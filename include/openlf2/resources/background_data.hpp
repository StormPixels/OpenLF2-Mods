// SPDX-License-Identifier: MIT
// Copyright (c) 2026 OpenLF2 contributors

#pragma once

#include "openlf2/core/result.hpp"
#include "openlf2/core/script_value.hpp"
#include "openlf2/ports/resources.hpp"
#include <array>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace openlf2::background_data {
// LF2 Darkfiren raised the layer limit from 30 to 1000 and allows 50 opoints per background.
inline constexpr std::size_t max_layers = 1000;
inline constexpr std::size_t max_opoints = 50;

struct Layer {
    std::string path;              // loaded for every layer, including filled ones
    std::int32_t transparency = 0; // non-zero: source color key
    std::int32_t width = 0;        // parallax width; fill width for colored layers
    std::int32_t x = 0;
    std::int32_t y = 0;
    std::int32_t height = 0;       // fill height
    std::int32_t color = 0;        // 0x00RRGGBB fill before the painter's remap; 0 = bitmap
    std::int32_t loop = 0;         // repeat step; 0 draws once
    std::int32_t cc = 0;           // animation period; 0 = always visible
    std::int32_t c1 = 0;           // first visible counter value
    std::int32_t c2 = 0;           // last visible counter value
    std::int32_t respond = 0;      // LF2 Darkfiren: drawn only when the background mode lists this value
    std::int32_t state = 0;        // LF2 Darkfiren: 0 always, 1 only when the round starts, 2 only when it ends
};

// LF2 Darkfiren `opoint:` ... `opoint_end:` of a background: an object put on the stage when the round begins.
// `arest` plays the part of a layer's `respond`: the background mode must list it for the opoint to be used.
struct Opoint {
    std::int32_t oid = 0;
    std::int32_t action = 0;
    std::int32_t x = 0;
    std::int32_t y = 0;
    std::int32_t z = 0;
    std::int32_t dvx = 0;
    std::int32_t dvy = 0;
    std::int32_t dvz = 0;
    std::int32_t facing = 0;
    std::int32_t team = 0;
    std::optional<std::int32_t> hp;  // absent: the object's own value (500 by default)
    std::optional<std::int32_t> mp;
    std::int32_t effect = 0;         // blinking time; 0 = none
    std::int32_t arest = 0;
};

inline constexpr std::size_t max_team_frames = 50;
inline constexpr std::size_t max_quests = 5;

// LF2 Darkfiren `frame:` ... `frame_end:` of a background: one image of a team HP bar (readme background.txt).
// `type` 0 frame, 1 hp bar, 2 dark hp bar; `facing` 0 fills left to right, 1 right to left; `respond` is read and kept; the
// background mode's `wait:` must list the frame's `wait` for it to show; `effect`, `cc`, `c1`, `c2` animate it like a layer; `wait` is read
// and kept (its meaning is not documented).
struct TeamFrame {
    std::string path;
    std::int32_t team = 0;
    std::int32_t type = 0;
    std::int32_t x = 0;
    std::int32_t y = 0;
    std::int32_t w = 0;
    std::int32_t h = 0;
    std::int32_t dx = 0;
    std::int32_t dy = 0;
    std::int32_t facing = 0;
    std::int32_t respond = 0;
    std::int32_t wait = 0;
    std::int32_t effect = 0;
    std::int32_t cc = 0;
    std::int32_t c1 = 0;
    std::int32_t c2 = 0;
};

// LF2 Darkfiren `quest:` ... `quest_end:` of a background (up to 5): a goal checked in loops.
struct Quest {
    std::string sound;        // played when the goal is reached
    std::int32_t type = 0;    // 1 kill, 2 total attack, 3 mp usage, 4 hp lost
    std::int32_t respond = 0; // 1..12: what the reward is
    std::int32_t amount = 0;
    std::int32_t start = 0;   // first check, in units of 1/30 s
    std::int32_t recover = 0; // time between checks, in units
    std::int32_t times = 0;   // number of checks
    std::int32_t bound = 0;   // game mode: 0 vs, 1 stage, 4 battle
    std::int32_t fall = 0;    // the quest runs only in a background mode whose `fall:` lists this value
    std::int32_t next = 0;    // what the goal grows by after each reward
};

// Values the original never resets are absent until the file sets them.
struct Background {
    std::optional<std::string> name; // display form: 29 characters, underscores as spaces
    std::optional<std::int32_t> width;
    std::array<std::optional<std::int32_t>, 2> zboundary;
    std::array<std::int32_t, 2> perspective{};
    std::optional<std::string> shadow;
    std::array<std::optional<std::int32_t>, 2> shadow_size;
    std::vector<Layer> layers;
    std::vector<Opoint> opoints;
    std::vector<TeamFrame> team_frames;
    std::vector<Quest> quests;
    std::int32_t token_checksum = 0;
    std::vector<std::string> diagnostics;
};

// `rect:` conversion of an RGB565 value, biased by +0x070707.
std::int32_t convert_rgb565(std::int32_t value);
Result<Background> parse(std::string_view text);
Result<Background> load(const ResourceSource& resources, std::string_view path);
// Script-facing table.
ScriptValue to_script_value(const Background& background);
}
