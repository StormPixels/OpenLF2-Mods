// SPDX-License-Identifier: MIT
// Copyright (c) 2026 OpenLF2 contributors

#pragma once
#include "openlf2/ports/resources.hpp"
#include "openlf2/ports/compression.hpp"
#include <filesystem>
#include <array>
#include <map>
#include <memory>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace openlf2 {
// Supported LF2 v2.0a packages. Downloads continue to use the first variant.
inline constexpr std::string_view installer_name = "LF2_v2.0a.exe";
inline constexpr std::size_t installer_size = 29'586'263;
inline constexpr std::string_view alternate_installer_name = "lf2_v20a_Setup.exe";
inline constexpr std::size_t alternate_installer_size = 31'904'750;
inline constexpr std::array installer_names{installer_name, alternate_installer_name};
inline constexpr std::size_t installer_max_size = alternate_installer_size;
// Succeeds when `bytes` match a supported installer (size and SHA-256).
Result<void> identify_installer(std::span<const char> bytes);
class InstallerArchive final : public ResourceSource {
public:
    static Result<std::unique_ptr<InstallerArchive>> open(const std::filesystem::path& path,
                                                         const Decompressor& decompressor);
    InstallerArchive(Bytes bytes, const Decompressor& decompressor);
    Result<Bytes> read(std::string_view path) const override;
    [[nodiscard]] std::size_t file_count() const { return entries_.size(); }
    // Normalized virtual paths in lexical order.
    [[nodiscard]] std::vector<std::string> paths() const {
        std::vector<std::string> names;
        names.reserve(entries_.size());
        for (const auto& entry : entries_) names.push_back(entry.first);
        return names;
    }
private:
    struct Entry {
        std::size_t offset;
        std::size_t compressed_size;
        std::size_t decoded_size;
        Compression method;
    };
    Result<void> index();
    Result<void> unwrap_nsis();
    Result<void> index_nsis();
    Bytes bytes_;
    const Decompressor& decompressor_;
    std::map<std::string, Entry, std::less<>> entries_;
};
// An extracted (non-installer) LF2 v2.0a game folder, identified by its lf2.exe.
inline constexpr std::size_t folder_exe_size = 3'424'256;
// Succeeds when `source` holds the supported lf2.exe (size and SHA-256) and data/data.txt.
Result<void> identify_folder(const ResourceSource& source);
// Which rule set a game folder needs. `original`: LF2 v2.0a as released (lf2.exe matches). `original_modded`: the
// original engine layout with other data or another lf2.exe (NTSD, fan mods). `darkfiren`: LF2 Darkfiren, whose
// system.dat / resource.dat / lf2_exe/ replace what the original keeps in lf2.exe and hard-coded rules. `neora`: LF2 Neora
// (an engine modification: neora.dll next to its own executable, PDK.exe).
enum class GameKind { original, original_modded, darkfiren, neora };
struct GameProfile {
    GameKind kind = GameKind::original;
    std::string reason;  // the evidence that decided, for the log
};
std::string_view game_kind_name(GameKind kind);  // "original", "modded", "darkfiren", "neora"
class DirectoryArchive final : public ResourceSource {
public:
    DirectoryArchive() = default;
    static Result<std::unique_ptr<DirectoryArchive>> open(const std::filesystem::path& root);
    Result<Bytes> read(std::string_view path) const override;
    // Writes the file through a temporary file that replaces it, next to the existing file of that name or, for a
    // new file, next to the other files of its directory. The index is not changed (a new file is seen at the next
    // start). At most 1 MiB; an error when the directory is unknown.
    Result<void> write(std::string_view path, std::string_view text) const override;
    [[nodiscard]] std::size_t file_count() const { return files_.size(); }
    // The kind detected when the folder was opened (see detect_profile).
    [[nodiscard]] const GameProfile& profile() const { return profile_; }
    // The virtual name of the game's executable as found at open ("lf2.exe" itself, or the root .exe the folder holds
    // under another name: NTSD 2.4 P4tch3d.exe, DragonBallSuper.exe, ...); empty when the folder has none. It is also
    // readable as "lf2.exe", so everything that asks for that name gets the real executable.
    [[nodiscard]] const std::string& main_exe() const { return main_exe_; }
    // Decides the kind from the files alone. A file `game_kind.txt` holding original, modded or darkfiren forces the
    // answer; otherwise Darkfiren (both data/system.dat and data/resource.dat present, whatever the executable is called) wins,
    // then neora.dll in the folder's root (Neora), then lf2.exe: same size and SHA-256 as LF2 v2.0a is original, anything else (or none) is modded.
    [[nodiscard]] GameProfile detect_profile() const;
    // Normalized virtual paths in lexical order.
    [[nodiscard]] std::vector<std::string> paths() const {
        std::vector<std::string> names;
        names.reserve(files_.size());
        for (const auto& entry : files_) names.push_back(entry.first);
        return names;
    }
private:
    std::map<std::string, std::filesystem::path, std::less<>> files_;
    GameProfile profile_;
    std::string main_exe_;
    void alias_main_exe();
};
Result<Bytes> bitmap_resource(std::span<const char> executable, std::string_view name);
// The icon of a PE32 executable as a 24-bit BMP, drawn over `background` (0xRRGGBB) so no alpha is needed. A PNG-compressed
// or missing icon is an error; placeholder_icon is the picture to show instead (a 32x32 outline).
Result<Bytes> executable_icon(std::span<const char> executable, std::uint32_t background);
Bytes placeholder_icon(std::uint32_t background);
// The executable of a game folder that is not open: lf2.exe, else game_exe.txt's pick, else the largest root .exe that is
// no helper (the same choice DirectoryArchive makes); nothing when the folder has no .exe.
std::optional<std::filesystem::path> find_game_exe(const std::filesystem::path& folder);
// The recording key digits and version of any LF2 executable whose layout differs from v2.0a (LF2 Darkfiren):
// the one run of 1000+ ASCII digits in the file is the key, and the version is the u32 0x764 bytes before it.
Result<std::pair<std::string, std::int32_t>> scan_recording_constants(std::span<const char> executable);
// LF2 Neora: the Configuration Block of neora.dll (DLL/Main.asm) as text lines "key value": game_name is not included, the keys are
// win_width win_height shake_value slow_motion slow_power replay_switch battle_limit battle_step menu_picture_r unlock_teams f7_for_dead.
// The block is packed right after the two strings that follow the version text "Neora Engine v...". Empty when the DLL has no such
// text or a value is out of its sane range (another build of Neora), so the caller keeps its own defaults.
std::string neora_config_text(std::span<const char> dll);
// Initialized data of a PE32 executable at a virtual address (e.g. the original game's recording key).
Result<Bytes> executable_data(std::span<const char> executable, std::uint32_t address, std::size_t size);
}
