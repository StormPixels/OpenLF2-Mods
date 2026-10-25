// SPDX-License-Identifier: MIT
// Copyright (c) 2026 OpenLF2 contributors

#pragma once
#include "openlf2/ports/resources.hpp"
#include "openlf2/ports/compression.hpp"
#include <filesystem>
#include <array>
#include <map>
#include <memory>
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
class DirectoryArchive final : public ResourceSource {
public:
    DirectoryArchive() = default;
    static Result<std::unique_ptr<DirectoryArchive>> open(const std::filesystem::path& root);
    Result<Bytes> read(std::string_view path) const override;
    [[nodiscard]] std::size_t file_count() const { return files_.size(); }
    // Normalized virtual paths in lexical order.
    [[nodiscard]] std::vector<std::string> paths() const {
        std::vector<std::string> names;
        names.reserve(files_.size());
        for (const auto& entry : files_) names.push_back(entry.first);
        return names;
    }
private:
    std::map<std::string, std::filesystem::path, std::less<>> files_;
};
Result<Bytes> bitmap_resource(std::span<const char> executable, std::string_view name);
// The recording key digits and version of any LF2 executable whose layout differs from v2.0a (LF2 Darkfiren):
// the one run of 1000+ ASCII digits in the file is the key, and the version is the u32 0x764 bytes before it.
Result<std::pair<std::string, std::int32_t>> scan_recording_constants(std::span<const char> executable);
// Initialized data of a PE32 executable at a virtual address (e.g. the original game's recording key).
Result<Bytes> executable_data(std::span<const char> executable, std::uint32_t address, std::size_t size);
}
