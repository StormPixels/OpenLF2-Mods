// SPDX-License-Identifier: MIT
// Copyright (c) 2026 OpenLF2 contributors

#pragma once
#include "openlf2/ports/resources.hpp"
#include <cstdint>
#include <optional>
#include <string>
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

// LF2 Darkfiren: the window title from the text of data\system.dat: its top-level `name:` line (before any `<block>`),
// with `_` shown as a space (`Little_Fighter_2` -> `Little Fighter 2`), a `;comment` and surrounding white space
// dropped. nullopt when there is no usable name (missing, empty, longer than 100 characters, control characters),
// so the window keeps its own title.
std::optional<std::string> window_title_from_system_dat(std::string_view text);

// LF2 Darkfiren: the milliseconds between script frames from data\system.dat: `fps_value:` (normal, 33 in the
// original, accepted 10..100) and `fps_value_f5:` (the F5 fast mode, 3 in the original, accepted 1..100 and at most the
// normal value). A tag that is missing, not a number or out of range keeps the original's value, so original data
// and the shipped Darkfiren system.dat (33 and 3) schedule exactly as before. Only the top-level tags before the
// first `<block>` count.
struct FrameSteps {
    std::uint32_t normal = 33;
    std::uint32_t fast = 3;
};
FrameSteps frame_steps_from_system_dat(std::string_view text);
}
