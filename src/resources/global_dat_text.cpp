// SPDX-License-Identifier: MIT
// Copyright (c) 2026 OpenLF2 contributors

#include "openlf2/resources/global_dat_text.hpp"
#include "openlf2/resources/data_file.hpp"
#include <string>

namespace openlf2 {
std::optional<Result<Bytes>> read_dat_text_resource(const ResourceSource& archive, std::string_view normalized) {
    constexpr std::string_view text_prefix = "game/dat_text/";
    constexpr std::string_view mode_prefix = "game/mode_file/";
    if (normalized.starts_with(text_prefix)) {
        const auto target = normalized.substr(text_prefix.size());
        if (target.empty()) return Result<Bytes>(fail(ErrorCode::format, "game/dat_text needs a file path"));
        // The archive never contains "game/..." names, so a nested "game/dat_text/game/dat_text/x" simply fails.
        return read_data_text(archive, target, dat_text_limit);
    }
    if (normalized.starts_with(mode_prefix)) {
        const auto number = normalized.substr(mode_prefix.size());
        if (number.size() != 1 || number.front() < '1' || number.front() > '4') {
            return Result<Bytes>(fail(ErrorCode::format, "game/mode_file/<k> needs k in 1..4"));
        }
        const std::string file = "data/mode/mode" + std::string(number) + ".dat";
        auto text = read_data_text(archive, file, dat_text_limit);
        if (!text) return Result<Bytes>(Bytes());
        return text;
    }
    return std::nullopt;
}

std::optional<std::string> window_title_from_system_dat(std::string_view text) {
    constexpr std::size_t longest = 100;
    std::size_t position = 0;
    while (position <= text.size()) {
        auto end = text.find('\n', position);
        if (end == std::string_view::npos) end = text.size();
        auto line = text.substr(position, end - position);
        position = end + 1;
        while (!line.empty() && (line.front() == ' ' || line.front() == '\t')) line.remove_prefix(1);
        if (!line.empty() && line.front() == '<') break;  // the top-level tags end at the first block
        if (!line.starts_with("name")) continue;
        auto rest = line.substr(4);
        while (!rest.empty() && (rest.front() == ' ' || rest.front() == '\t')) rest.remove_prefix(1);
        if (rest.empty() || rest.front() != ':') continue;
        rest.remove_prefix(1);
        if (const auto comment = rest.find(';'); comment != std::string_view::npos) rest = rest.substr(0, comment);
        std::string title(rest);
        while (!title.empty() && (title.back() == ' ' || title.back() == '\t' || title.back() == '\r')) title.pop_back();
        std::size_t start = 0;
        while (start < title.size() && (title[start] == ' ' || title[start] == '\t')) ++start;
        title.erase(0, start);
        if (title.empty() || title.size() > longest) return std::nullopt;
        for (auto& character : title) {
            if (static_cast<unsigned char>(character) < 32 || character == 127) return std::nullopt;
            if (character == '_') character = ' ';
        }
        return title;
    }
    return std::nullopt;
}
}
