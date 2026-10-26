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

namespace openlf2::stage_data {
// The original has 60 stages (6 groups of 10). LF2 Darkfiren numbers a stage level_id * 10 + the id inside the
// level's file, with up to 20 levels.
inline constexpr std::size_t max_stages = 200;
inline constexpr std::size_t max_phases = 100;
inline constexpr std::size_t max_entries = 60;

enum class EntryKind : std::int32_t { normal = 0, soldier = 1, boss = 2 };

// Defaults are the values `id:` of a stage writes into all of its phases and entries.
struct Entry {
    std::int32_t id = -1;
    std::int32_t x = 500; // also set to bound + 80 by every later `bound:` of the phase
    std::int32_t hp = 500;
    std::int32_t times = 1; // `<soldier>` sets 50
    std::int32_t reserve = 0;
    std::int32_t join = 0;
    std::int32_t join_reserve = 0;
    std::int32_t act = 9;
    std::int32_t y = 0;
    double ratio = 0.0;
    EntryKind kind = EntryKind::normal;
    // LF2 Darkfiren tags; absent (nullopt / 0) keeps the original's behaviour.
    std::optional<std::int32_t> team;  // `team:` -1 independent, 1 to 5
    std::optional<std::int32_t> mp;
    std::optional<std::int32_t> z;
    std::optional<std::int32_t> fx;    // fixed x, wins over x
    std::int32_t pic = 0;              // skin offset
};

struct Phase {
    std::int32_t bound = -1;
    std::string music;
    std::int32_t when_clear_goto_phase = -1;
    std::int32_t when_clear_goto_stage = -1;  // LF2 Darkfiren: level_id * 10 + id of the stage to go to
    std::int32_t time = -1;                   // LF2 Darkfiren: seconds of the phase, -1 none
    std::vector<Entry> entries; // entries opened by `id:`, in file order
};

struct Stage {
    std::vector<Phase> phases; // phase count as the original's +2000 field
    // LF2 Darkfiren, between `id:` and the first `<phase>`.
    std::string name;                // `stage_1-1`, `Survival_Stage:_%d` (underscores are spaces)
    bool boss = false;               // `<boss>`: the name is red
    std::int32_t bg = -1;            // row of the background list; -1: not given (the first)
    std::int32_t end = 0;            // last stage of a level: 1 credits, 2 back to the character menu
    std::int32_t next = 0;           // 1: go on without waiting for the computer fighters
    std::int32_t type = 0;           // 1: survival features
    std::int32_t ptype = 0;          // 1: a phase ends when its enemies are gone
    std::int32_t xpos = 360;         // x of the stage name
    std::int32_t facing = 0;         // 1: the stage goes from right to left
    std::int32_t mode = 0;           // background mode
    std::int32_t respond = 0;        // 1-3: area beyond the bound blacked out
    std::int32_t hex = -1;           // colour of the name
};

// LF2 Darkfiren's data/stage.dat: a list of levels, each with the file of its stages.
struct Level {
    std::int32_t id = 0;
    std::string name;       // underscores are spaces
    std::string file;
    std::string pic;
    std::string small;
    bool boss = false;      // `<boss>`: the name is red
    std::int32_t hex = -1;
    std::int32_t hidden = 0;
    std::int32_t respond = 0;
    std::optional<std::int32_t> bound;
    std::int32_t facing = 0;   // number of fighters the level needs
    std::int32_t effect = 0;   // 1: the same fighter twice is not allowed
    std::vector<std::int32_t> oids;
};

struct StageList {
    // Stages the file never defines keep the original's phase count -1 (absent here).
    std::array<std::optional<Stage>, max_stages> stages;
    std::vector<Level> levels;  // empty for the original's stage.dat
    std::vector<std::string> diagnostics;
};

Result<StageList> parse(std::string_view text);
Result<StageList> load(const ResourceSource& resources, std::string_view path);
// Script-facing table.
ScriptValue to_script_value(const StageList& list);
}
