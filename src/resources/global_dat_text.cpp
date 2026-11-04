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
}
