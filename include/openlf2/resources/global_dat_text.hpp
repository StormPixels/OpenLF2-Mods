// SPDX-License-Identifier: MIT
// Copyright (c) 2026 OpenLF2 contributors

#pragma once
#include "openlf2/ports/resources.hpp"
#include <optional>
#include <string_view>

namespace openlf2 {
// Largest decrypted text a "game/dat_text/..." or "game/mode_file/<k>" read may return.
inline constexpr std::size_t dat_text_limit = 1024 * 1024;
// LF2 Darkfiren: generic virtual sources that hand scripts the decrypted text of data files.
//   game/dat_text/<path>   the text of <path> (relative to the game root, '/' separated, case-insensitive; names
//                          ending in "dat" are decrypted like the original does). Fails when the file is
//                          missing, longer than dat_text_limit or not text.
//   game/mode_file/<k>     the text of data/mode/mode<k>.dat for k = 1..4; empty text when the game has no such
//                          file (like "game/mode_file"), an error for any other k.
// `normalized` must already be a virtual_path() result. Returns std::nullopt when it names neither source,
// so the caller continues with its other sources.
std::optional<Result<Bytes>> read_dat_text_resource(const ResourceSource& archive, std::string_view normalized);
}
