// SPDX-License-Identifier: MIT
// Copyright (c) 2026 OpenLF2 contributors

#include "openlf2/resources/installer.hpp"
#include "openlf2/resources/data_file.hpp"
#include "openlf2/resources/global_dat_text.hpp"
#include "openlf2/core/binary.hpp"
#include "openlf2/core/files.hpp"
#include "openlf2/ports/digest.hpp"
#include <algorithm>
#include <cstdio>
#include <optional>

namespace openlf2 {
namespace {
std::size_t overlay_offset(const BinaryView& file) {
    if (file.text(0, 2) != "MZ") throw FormatError("missing DOS header");
    const std::size_t pe = file.u32(0x3c);
    if (file.text(pe, 4) != std::string("PE\0\0", 4)) throw FormatError("missing PE header");
    const std::size_t sections = pe + 24 + file.u16(pe + 20);
    const auto count = file.u16(pe + 6);
    file.slice(sections, std::size_t{count} * 40);
    std::size_t overlay = 0;
    for (std::size_t index = 0; index < count; ++index) {
        const auto section = sections + index * 40;
        const std::size_t offset = file.u32(section + 20), size = file.u32(section + 16);
        file.slice(offset, size);
        overlay = std::max(overlay, offset + size);
    }
    return overlay;
}
struct NsisHeader {
    Bytes bytes;
    std::size_t data_offset;
    std::size_t instructions;
    std::size_t count;
    std::size_t strings;
    std::size_t strings_size;
};
NsisHeader nsis_header(std::span<const char> bytes, const Decompressor& decompressor) {
    const BinaryView file(bytes);
    const auto overlay = overlay_offset(file);
    // These two pinned packages use a customized NSIS 2 header and opcodes.
    constexpr std::array<std::uint32_t, 4> signature{0x5ac8fd16, 0x0fa48c1d, 0xac86f46d, 0x3c8cf36f};
    for (std::size_t i = 0; i < signature.size(); ++i) {
        if (file.u32(overlay + i * 4) != signature[i]) throw FormatError("missing LF2 NSIS signature");
    }
    if (file.u32(overlay + 20) != bytes.size() - overlay || file.u32(overlay + 24) != 0) {
        throw FormatError("invalid LF2 NSIS package bounds");
    }
    const auto compressed = file.u32(overlay + 28);
    if (!(compressed & 0x80000000u)) throw FormatError("uncompressed LF2 NSIS header");
    const std::size_t size = compressed & 0x7fffffffu;
    auto decoded = decompressor.decode(Compression::nsis_deflate, file.slice(overlay + 32, size), file.u32(overlay + 16));
    if (!decoded) throw FormatError(decoded.error().message);
    const BinaryView header(*decoded);
    const std::size_t count = header.u32(40), instructions = header.u32(44);
    const std::size_t strings = header.u32(60), strings_end = header.u32(52);
    if (count > 4096 || strings_end < strings) throw FormatError("invalid LF2 NSIS header blocks");
    header.slice(instructions, count * 28);
    header.slice(strings, strings_end - strings);
    return {std::move(*decoded), overlay + 32 + size, instructions, count, strings, strings_end - strings};
}
std::string nsis_string(const NsisHeader& header, std::size_t offset) {
    if (offset >= header.strings_size) throw FormatError("LF2 NSIS string outside table");
    const auto bytes = BinaryView(header.bytes).slice(header.strings + offset, header.strings_size - offset);
    const auto end = std::ranges::find(bytes, '\0');
    if (end == bytes.end()) throw FormatError("unterminated LF2 NSIS string");
    return {bytes.begin(), end};
}
struct NsisBlock { std::size_t offset; std::size_t size; Compression method; };
NsisBlock nsis_block(std::span<const char> bytes, const NsisHeader& header, std::size_t offset) {
    const BinaryView file(bytes);
    if (offset > bytes.size() - header.data_offset) throw FormatError("LF2 NSIS file outside payload");
    const auto position = header.data_offset + offset;
    const auto flags = file.u32(position);
    const std::size_t size = flags & 0x7fffffffu;
    file.slice(position + 4, size);
    return {position + 4, size, flags & 0x80000000u ? Compression::nsis_deflate : Compression::stored};
}
}
Result<void> identify_installer(std::span<const char> bytes) {
    if (bytes.size() != installer_size && bytes.size() != alternate_installer_size) {
        return fail(ErrorCode::unsupported, "installer is " + std::to_string(bytes.size()) +
            " bytes; supported LF2 v2.0a installers are " + std::to_string(installer_size) +
            " or " + std::to_string(alternate_installer_size) + " bytes");
    }
    auto digest = sha256(bytes);
    if (!digest) return std::unexpected(digest.error());
    const auto expected = bytes.size() == installer_size
        ? "540c485547e234b0d09595f54d067aafd7176092c308aca61868f3cbc03030e1"
        : "2d9629fa1ca67d636c595842aafeb563603b97de4c8530d0bcb7641ad717e9ee";
    if (*digest != expected) {
        return fail(ErrorCode::unsupported, "installer does not match supported LF2 v2.0a SHA-256");
    }
    return {};
}
InstallerArchive::InstallerArchive(Bytes bytes, const Decompressor& decompressor)
    : bytes_(std::move(bytes)), decompressor_(decompressor) {}

Result<std::unique_ptr<InstallerArchive>> InstallerArchive::open(
    const std::filesystem::path& path, const Decompressor& decompressor) {
    auto bytes = read_file(path, installer_max_size);
    if (!bytes) return std::unexpected(bytes.error());
    auto identified = identify_installer(*bytes);
    if (!identified) return std::unexpected(identified.error());
    auto archive = std::make_unique<InstallerArchive>(std::move(*bytes), decompressor);
    if (archive->bytes_.size() == alternate_installer_size) {
        auto unwrapped = archive->unwrap_nsis();
        if (!unwrapped) return std::unexpected(unwrapped.error());
        auto indexed = archive->index_nsis();
        if (!indexed) return std::unexpected(indexed.error());
        return archive;
    }
    auto indexed = archive->index();
    if (!indexed) return std::unexpected(indexed.error());
    return archive;
}

Result<void> InstallerArchive::unwrap_nsis() {
    try {
        const auto header = nsis_header(bytes_, decompressor_);
        const BinaryView commands(header.bytes);
        std::optional<Bytes> host;
        for (std::size_t i = 0; i < header.count; ++i) {
            const auto command = header.instructions + i * 28;
            if (commands.u32(command) != 36 ||
                nsis_string(header, commands.u32(command + 8)) != "\xfd\x9a\x80\\hostsetup.exe") continue;
            if (host) throw FormatError("duplicate LF2 NSIS host package");
            const auto block = nsis_block(bytes_, header, commands.u32(command + 12));
            auto decoded = decompressor_.decode(block.method, BinaryView(bytes_).slice(block.offset, block.size), 30'799'229);
            if (!decoded) return std::unexpected(decoded.error());
            host = std::move(*decoded);
        }
        if (!host) throw FormatError("missing LF2 NSIS host package");
        auto digest = sha256(*host);
        if (!digest) return std::unexpected(digest.error());
        if (*digest != "a3e8de6e7a17f40956a2b7dcee7cd53a5c17fbd0c41a7bf68b87ff199a185e08") {
            throw FormatError("LF2 NSIS host package SHA-256 mismatch");
        }
        bytes_ = std::move(*host);
        return {};
    } catch (const FormatError& error) { return fail(ErrorCode::format, error.what()); }
}

Result<void> InstallerArchive::index_nsis() {
    try {
        const auto header = nsis_header(bytes_, decompressor_);
        const BinaryView commands(header.bytes);
        std::optional<std::string> directory;
        for (std::size_t i = 0; i < header.count; ++i) {
            const auto command = header.instructions + i * 28;
            const auto opcode = commands.u32(command);
            // Read only file declarations under $INSTDIR. No installer commands,
            // plugins, toolbar files, registry operations or executables are run.
            if (opcode == 34 && commands.u32(command + 8) == 1) {
                auto path = nsis_string(header, commands.u32(command + 4));
                directory.reset();
                if (path.starts_with("\xfd\x95\x80")) {
                    path.erase(0, 3);
                    if (path.starts_with('\\')) path.erase(0, 1);
                    if (path.empty()) directory = "";
                    else {
                        auto normalized = virtual_path(path);
                        if (!normalized) return std::unexpected(normalized.error());
                        directory = *normalized + "/";
                    }
                }
            } else if (opcode == 36 && directory) {
                const auto filename = nsis_string(header, commands.u32(command + 8));
                if (filename.starts_with('\xfd')) continue;
                auto path = virtual_path(*directory + filename);
                if (!path) return std::unexpected(path.error());
                const auto block = nsis_block(bytes_, header, commands.u32(command + 12));
                const auto decoded = block.method == Compression::stored ? block.size : 0;
                if (!entries_.emplace(*path, Entry{block.offset, block.size, decoded, block.method}).second) {
                    throw FormatError("duplicate LF2 NSIS filename: " + *path);
                }
            }
        }
        if (!entries_.contains("lf2.exe") || !entries_.contains("data/data.txt")) throw FormatError("incomplete LF2 NSIS game files");
        return {};
    } catch (const FormatError& error) { return fail(ErrorCode::format, error.what()); }
}

Result<void> InstallerArchive::index() {
    try {
        const BinaryView file(bytes_);
        if (file.text(0, 2) != "MZ") throw FormatError("missing DOS header");
        const std::size_t pe = file.u32(0x3c);
        file.slice(pe, 24);
        file.slice(pe, 24 + std::size_t{file.u16(pe + 20)});
        if (file.text(pe, 4) != std::string("PE\0\0", 4)) throw FormatError("missing PE header");
        const auto section_count = file.u16(pe + 6);
        const std::size_t sections = pe + 24 + file.u16(pe + 20);
        file.slice(sections, std::size_t{section_count} * 40);
        std::size_t overlay = 0;
        for (std::size_t index = 0; index < section_count; ++index) {
            const auto section = sections + index * 40;
            const std::size_t offset = file.u32(section + 20);
            const std::size_t size = file.u32(section + 16);
            file.slice(offset, size);
            overlay = std::max(overlay, offset + size);
        }
        if (file.text(overlay, 6) != "wwgT)H") throw FormatError("missing installer signature");
        std::size_t cursor = overlay + 6;
        std::size_t payload = 0;
        std::size_t payload_size = 0;
        Bytes table;
        while (cursor < bytes_.size()) {
            const auto id = file.u16(cursor);
            const auto flags = file.u16(cursor + 2);
            const std::size_t size = file.u32(cursor + 4);
            const auto body = cursor + 8;
            if (id == 0x7f7f) {
                if (flags != 0 || file.u32(body) != size) throw FormatError("invalid payload header");
                payload = body + 4;
                payload_size = size;
                file.slice(payload, size);
                if (payload + size != bytes_.size()) throw FormatError("payload does not end at EOF");
                break;
            }
            file.slice(body, size);
            if (flags != 1 || size < 5) throw FormatError("unsupported metadata record");
            if (id == 0x143a) {
                if (!table.empty()) throw FormatError("duplicate file table");
                auto decoded = decompressor_.decode(static_cast<Compression>(file.u8(body + 4)),
                    file.slice(body + 5, size - 5), file.u32(body));
                if (!decoded) return std::unexpected(decoded.error());
                table = std::move(*decoded);
            }
            cursor = body + size;
        }
        if (payload == 0 || table.empty()) throw FormatError("missing payload or file table");
        const BinaryView records(table);
        const auto count = records.u32(0);
        if (count > 4096) throw FormatError("excessive file-table count");
        cursor = 4;
        for (std::uint32_t index = 0; index < count; ++index) {
            const std::size_t size = records.u16(cursor);
            if (size < 4) throw FormatError("short file-table record");
            const BinaryView record(records.slice(cursor, size));
            const auto kind = record.u16(2);
            if (kind == 0) {
                if (size < 63) throw FormatError("short file record");
                const auto name_bytes = record.slice(62, size - 62);
                const auto terminator = std::ranges::find(name_bytes, '\0');
                if (terminator == name_bytes.end()) throw FormatError("unterminated filename");
                auto name = virtual_path(std::string(name_bytes.begin(), terminator));
                if (!name) return std::unexpected(name.error());
                const std::size_t offset = record.u32(6);
                const std::size_t compressed = record.u32(10);
                const std::size_t decoded = record.u32(18);
                if (compressed < 1 || offset > payload_size || compressed > payload_size - offset ||
                    decoded > 64 * 1024 * 1024) throw FormatError("invalid indexed file bounds");
                const auto method = static_cast<Compression>(file.u8(payload + offset));
                if (method != Compression::stored && method != Compression::zlib && method != Compression::bzip2) {
                    throw FormatError("unsupported installer compression method");
                }
                if (!entries_.emplace(*name, Entry{payload + offset + 1, compressed - 1, decoded, method}).second) {
                    throw FormatError("duplicate normalized filename: " + *name);
                }
            } else if (kind != 2 || index != 0) throw FormatError("unsupported file-table record kind");
            cursor += size;
        }
        if (cursor != table.size()) throw FormatError("trailing file-table bytes");
        return {};
    } catch (const FormatError& error) { return fail(ErrorCode::format, error.what()); }
}

Result<Bytes> InstallerArchive::read(std::string_view path) const {
    auto normalized = virtual_path(path);
    if (!normalized) return std::unexpected(normalized.error());
    const auto entry = entries_.find(*normalized);
    if (entry == entries_.end()) return fail(ErrorCode::io, "installer resource missing: " + *normalized);
    const auto& location = entry->second;
    const BinaryView view(bytes_);
    auto result = decompressor_.decode(location.method,
        view.slice(location.offset, location.compressed_size), location.decoded_size);
    if (!result) result.error().message = *normalized + ": " + result.error().message;
    return result;
}

namespace {
constexpr std::string_view folder_exe_sha256 =
    "12dfa00f6b767508612550e9ab27ab74b4201ff4cb9ff31d068925924eab8fc5";
constexpr std::size_t folder_file_limit = 64 * 1024 * 1024;
}

// The folder's lf2.exe is no longer required to be the original LF2 v2.0a: its size and SHA-256 are only logged.
Result<void> identify_folder(const ResourceSource& source) {
    // lf2.exe is optional: LF2 Darkfiren keeps its bitmaps as files, and lf2_exe/ (tools/extract_lf2_exe.py) holds the rest.
    if (auto exe = source.read("lf2.exe")) {
        const bool same_size = exe->size() == folder_exe_size;
        auto digest = sha256(*exe);
        const bool same_digest = digest && *digest == folder_exe_sha256;
        std::fprintf(stderr, "[folder] lf2.exe is %zu bytes (LF2 v2.0a: %s), SHA-256 %s; size and hash are not enforced\n",
            static_cast<std::size_t>(exe->size()), same_size ? "same size" : "different size",
            same_digest ? "matches LF2 v2.0a" : "differs from LF2 v2.0a");
    } else {
        std::fprintf(stderr, "[folder] no lf2.exe; bitmaps come from resource.dat and lf2_exe/\n");
    }
    // data.txt may be renamed by system.dat `data:` (LF2 Darkfiren); the default name still counts.
    std::string data_path = "data/data.txt";
    if (const auto system_dat = read_data_text(source, "data/system.dat", 1024 * 1024)) {
        data_path = data_path_from_system_dat(std::string_view(reinterpret_cast<const char*>(system_dat->data()), system_dat->size()));
    }
    auto data = source.read(data_path);
    if (!data && data_path != "data/data.txt") data = source.read("data/data.txt");
    if (!data) return std::unexpected(data.error());
    return {};
}

std::string neora_config_text(std::span<const char> dll) {
    const std::string_view all(dll.data(), dll.size());
    const auto at = all.find("Neora Engine v");
    if (at == std::string_view::npos) return {};
    // version text, NUL, game window name, NUL, then 35 packed bytes: dd width, dd height, db shake, db slow_motion, dd slow_power,
    // db replay_switch, dd battle_limit, dd battle_step, dd Menu_Picture_R, dd Unlock_Teams, dd F7_for_dead.
    const auto name_start = all.find('\0', at);
    if (name_start == std::string_view::npos) return {};
    const auto name_end = all.find('\0', name_start + 1);
    if (name_end == std::string_view::npos || name_end - name_start > 100) return {};
    constexpr std::size_t block = 35;
    const std::size_t first = name_end + 1;
    if (first + block > all.size()) return {};
    const auto byte = [&](std::size_t offset) { return static_cast<std::uint32_t>(static_cast<unsigned char>(all[first + offset])); };
    const auto dword = [&](std::size_t offset) { return byte(offset) | byte(offset + 1) << 8 | byte(offset + 2) << 16 | byte(offset + 3) << 24; };
    const std::uint32_t width = dword(0), height = dword(4), shake = byte(8), slow = byte(9), power = dword(10), replay = byte(14);
    const std::uint32_t limit = dword(15), step = dword(19), menu_r = dword(23), unlock = dword(27), f7 = dword(31);
    if (width < 100 || width > 10000 || height < 100 || height > 10000 || shake > 100 || slow > 1 || power > 1000 || replay > 1 ||
        limit < 100 || limit > 100000 || step < 1 || step > 100000 || menu_r > 1 || unlock > 1 || f7 > 1) return {};
    std::string text;
    const auto line = [&](const char* key, std::uint32_t value) { text += std::string(key) + " " + std::to_string(value) + "\n"; };
    line("win_width", width); line("win_height", height); line("shake_value", shake); line("slow_motion", slow); line("slow_power", power);
    line("replay_switch", replay); line("battle_limit", limit); line("battle_step", step); line("menu_picture_r", menu_r);
    line("unlock_teams", unlock); line("f7_for_dead", f7);
    return text;
}

std::string_view game_kind_name(GameKind kind) {
    switch (kind) {
    case GameKind::original: return "original";
    case GameKind::original_modded: return "modded";
    case GameKind::darkfiren: return "darkfiren";
    case GameKind::neora: return "neora";
    }
    return "original";
}

// Finds the game's executable when the folder has no lf2.exe and makes it readable as "lf2.exe". In order: a file
// game_exe.txt naming a root .exe; else the largest root .exe that is not a helper (unins*, *lobby*, *setup*, ...).
void DirectoryArchive::alias_main_exe() {
    if (files_.contains("lf2.exe")) { main_exe_ = "lf2.exe"; return; }
    if (const auto named = files_.find("game_exe.txt"); named != files_.end()) {
        if (auto text = read_file(named->second, 256)) {
            std::string wanted(text->data(), text->size());
            while (!wanted.empty() && static_cast<unsigned char>(wanted.back()) <= 32) wanted.pop_back();
            std::size_t first = 0;
            while (first < wanted.size() && static_cast<unsigned char>(wanted[first]) <= 32) ++first;
            if (const auto virt = virtual_path(std::string_view(wanted).substr(first))) {
                const auto exe = files_.find(*virt);
                if (exe != files_.end() && virt->ends_with(".exe")) {
                    main_exe_ = *virt;
                    files_.emplace("lf2.exe", exe->second);
                    return;
                }
            }
        }
    }
    const auto is_helper = [](std::string_view file) {
        for (const std::string_view word : {"unins", "lobby", "setup", "redist", "update", "launcher", "config", "crash"}) {
            if (file.find(word) != std::string_view::npos) return true;
        }
        return false;
    };
    std::string best;
    std::filesystem::path best_path;
    std::uintmax_t best_size = 0;
    for (const auto& [file, location] : files_) {
        if (file.find('/') != std::string::npos || !file.ends_with(".exe") || is_helper(file)) continue;
        std::error_code size_error;
        const auto size = std::filesystem::file_size(location, size_error);
        if (size_error) continue;
        if (best.empty() || size > best_size) { best = file; best_path = location; best_size = size; }
    }
    if (best.empty()) return;
    main_exe_ = best;
    files_.emplace("lf2.exe", best_path);
}

std::optional<std::filesystem::path> find_game_exe(const std::filesystem::path& folder) {
    std::error_code error;
    std::filesystem::directory_iterator entries(folder, error);
    if (error) return std::nullopt;
    std::map<std::string, std::filesystem::path> exes;  // lower-case name -> path
    std::optional<std::filesystem::path> named;          // game_exe.txt
    for (const auto& entry : entries) {
        std::error_code entry_error;
        if (!entry.is_regular_file(entry_error) || entry_error) continue;
        auto name = entry.path().filename().string();
        for (auto& c : name) { if (c >= 'A' && c <= 'Z') c = static_cast<char>(c + ('a' - 'A')); }
        if (name == "game_exe.txt") named = entry.path();
        if (name.ends_with(".exe")) exes.emplace(name, entry.path());
    }
    if (const auto lf2 = exes.find("lf2.exe"); lf2 != exes.end()) return lf2->second;
    if (named) {
        if (auto text = read_file(*named, 256)) {
            std::string wanted(text->data(), text->size());
            while (!wanted.empty() && static_cast<unsigned char>(wanted.back()) <= 32) wanted.pop_back();
            std::size_t first = 0;
            while (first < wanted.size() && static_cast<unsigned char>(wanted[first]) <= 32) ++first;
            wanted.erase(0, first);
            for (auto& c : wanted) { if (c >= 'A' && c <= 'Z') c = static_cast<char>(c + ('a' - 'A')); }
            if (const auto exe = exes.find(wanted); exe != exes.end()) return exe->second;
        }
    }
    std::optional<std::filesystem::path> best;
    std::uintmax_t best_size = 0;
    for (const auto& [file, location] : exes) {
        bool helper = false;
        for (const std::string_view word : {"unins", "lobby", "setup", "redist", "update", "launcher", "config", "crash"}) {
            if (file.find(word) != std::string::npos) helper = true;
        }
        if (helper) continue;
        std::error_code size_error;
        const auto size = std::filesystem::file_size(location, size_error);
        if (size_error) continue;
        if (!best || size > best_size) { best = location; best_size = size; }
    }
    return best;
}

GameProfile DirectoryArchive::detect_profile() const {
    // 1. The owner's word: game_kind.txt (original | modded | darkfiren).
    if (const auto forced = files_.find("game_kind.txt"); forced != files_.end()) {
        if (auto text = read_file(forced->second, 256)) {
            std::string word;
            for (const char c : std::string_view(text->data(), text->size())) {
                if (c >= 'A' && c <= 'Z') word += static_cast<char>(c + ('a' - 'A'));
                else if (c >= 'a' && c <= 'z') word += c;
            }
            if (word == "darkfiren") return {GameKind::darkfiren, "game_kind.txt says darkfiren"};
            if (word == "neora") return {GameKind::neora, "game_kind.txt says neora"};
            if (word == "original") return {GameKind::original, "game_kind.txt says original"};
            if (word == "modded" || word == "mod") return {GameKind::original_modded, "game_kind.txt says modded"};
        }
    }
    // 2. LF2 Darkfiren: data/system.dat AND data/resource.dat, files the original never has. The name of the
    // executable plays no part here.
    if (files_.contains("data/system.dat") && files_.contains("data/resource.dat")) {
        return {GameKind::darkfiren, "data/system.dat and data/resource.dat present"};
    }
    // 3. LF2 Neora: its engine modification, neora.dll, next to the executable.
    if (files_.contains("neora.dll")) return {GameKind::neora, "neora.dll present"};
    // 4. The original engine layout: lf2.exe decides between untouched and modified.
    const auto exe_file = files_.find("lf2.exe");
    if (exe_file == files_.end()) return {GameKind::original_modded, "no lf2.exe and no Darkfiren files"};
    auto exe = read_file(exe_file->second, folder_file_limit);
    if (!exe) return {GameKind::original_modded, "lf2.exe cannot be read"};
    if (exe->size() != folder_exe_size) {
        return {GameKind::original_modded, "game exe is " + std::to_string(exe->size()) + " bytes, LF2 v2.0a lf2.exe is " +
                std::to_string(folder_exe_size)};
    }
    auto digest = sha256(*exe);
    if (!digest || *digest != folder_exe_sha256) return {GameKind::original_modded, "lf2.exe SHA-256 differs from LF2 v2.0a"};
    return {GameKind::original, "lf2.exe is LF2 v2.0a"};
}

Result<std::unique_ptr<DirectoryArchive>> DirectoryArchive::open(const std::filesystem::path& root) {
    std::error_code ec;
    if (!std::filesystem::is_directory(root, ec)) {
        return fail(ErrorCode::io, "LF2 folder not found: " + root.string());
    }
    auto archive = std::make_unique<DirectoryArchive>();
    const std::filesystem::recursive_directory_iterator end;
    for (std::filesystem::recursive_directory_iterator it(root, ec); !ec && it != end; it.increment(ec)) {
        std::error_code entry_ec;
        if (!it->is_regular_file(entry_ec) || entry_ec) continue;
        const auto relative = std::filesystem::relative(it->path(), root, entry_ec);
        if (entry_ec) continue;
        auto path = virtual_path(relative.generic_string());
        if (!path) continue;  // names that cannot be normalized are not game resources
        archive->files_.emplace(*path, it->path());  // first file wins if names differ only by case
    }
    if (ec) return fail(ErrorCode::io, "cannot list LF2 folder: " + ec.message());
    archive->alias_main_exe();
    auto identified = identify_folder(*archive);
    if (!identified) return std::unexpected(identified.error());
    // A folder is not proof of complete assets: data/ and sprite/ must hold files, and every file that
    // data.txt lists (`file: data\\x.dat`) must exist.
    std::string missing;
    for (const std::string_view prefix : {"data/", "sprite/"}) {
        const auto first = archive->files_.lower_bound(prefix);
        if (first == archive->files_.end() || !first->first.starts_with(prefix)) missing += std::string(prefix) + " (empty) ";
    }
    std::string data_path = "data/data.txt";
    if (const auto system_dat = read_data_text(*archive, "data/system.dat", 1024 * 1024)) {
        data_path = data_path_from_system_dat(std::string_view(reinterpret_cast<const char*>(system_dat->data()), system_dat->size()));
    }
    auto data_text = read_data_text(*archive, data_path, 4 * 1024 * 1024);
    if (!data_text && data_path != "data/data.txt") data_text = read_data_text(*archive, "data/data.txt", 4 * 1024 * 1024);
    std::size_t missing_files = 0;
    if (data_text) {
        const std::string_view text(data_text->data(), data_text->size());
        std::size_t at = 0;
        while ((at = text.find("file:", at)) != std::string_view::npos) {
            at += 5;
            while (at < text.size() && (text[at] == ' ' || text[at] == '\t')) ++at;
            std::size_t stop = at;
            while (stop < text.size() && text[stop] != ' ' && text[stop] != '\t' && text[stop] != '\r' && text[stop] != '\n') ++stop;
            const auto listed = virtual_path(text.substr(at, stop - at));
            at = stop;
            if (!listed || archive->files_.contains(*listed)) continue;
            if (++missing_files <= 3) missing += *listed + " ";
        }
    }
    if (missing_files > 3) missing += "(+" + std::to_string(missing_files - 3) + " more) ";
    if (!missing.empty()) return fail(ErrorCode::io, "LF2 assets incomplete, missing: " + missing);
    archive->profile_ = archive->detect_profile();
    std::fprintf(stderr, "[folder] %s: kind %s (%s), exe %s\n", root.filename().string().c_str(),
        std::string(game_kind_name(archive->profile_.kind)).c_str(), archive->profile_.reason.c_str(),
        archive->main_exe_.empty() ? "none" : archive->main_exe_.c_str());
    return archive;
}

Result<void> DirectoryArchive::write(std::string_view path, std::string_view text) const {
    constexpr std::size_t write_limit = 1024 * 1024;
    if (text.size() > write_limit) return fail(ErrorCode::limit, "game file text exceeds 1 MiB");
    auto normalized = virtual_path(path);
    if (!normalized) return std::unexpected(normalized.error());
    const auto slash = normalized->rfind('/');
    const std::string directory_name = slash == std::string::npos ? std::string() : normalized->substr(0, slash);
    const std::string file_name = slash == std::string::npos ? *normalized : normalized->substr(slash + 1);
    std::filesystem::path directory;
    std::string name = file_name;
    if (const auto existing = files_.find(*normalized); existing != files_.end()) {
        directory = existing->second.parent_path();
        name = existing->second.filename().string();  // keep the file's own letter case
    } else {
        // A new file goes next to the other files of its virtual directory.
        for (const auto& entry : files_) {
            const auto other = entry.first.rfind('/');
            const std::string other_directory = other == std::string::npos ? std::string() : entry.first.substr(0, other);
            if (other_directory == directory_name) { directory = entry.second.parent_path(); break; }
        }
        if (directory.empty()) return fail(ErrorCode::io, "no directory known for " + *normalized);
    }
    return replace_file(directory, name, std::span<const char>(text.data(), text.size()));
}
Result<Bytes> DirectoryArchive::read(std::string_view path) const {
    auto normalized = virtual_path(path);
    if (!normalized) return std::unexpected(normalized.error());
    const auto file = files_.find(*normalized);
    if (file == files_.end()) {
        std::fprintf(stderr, "[folder] MISSING %s\n", normalized->c_str());
        return fail(ErrorCode::io, "folder resource missing: " + *normalized);
    }
    std::fprintf(stderr, "[folder] read %s\n", normalized->c_str());
    auto result = read_file(file->second, folder_file_limit);
    if (!result) {
        std::fprintf(stderr, "[folder] FAILED %s: %s\n", normalized->c_str(), result.error().message.c_str());
        result.error().message = *normalized + ": " + result.error().message;
    }
    return result;
}
}
