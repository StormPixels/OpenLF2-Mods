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

namespace openlf2::object_data {
// Frames 0-998, as in the Darkfiren LF2 mod. 999 and 1000 keep their original meaning in `next:`.
inline constexpr std::int32_t frame_count = 999;
inline constexpr std::size_t max_sheets = 10;
// itr and bdy blocks per frame: 5 in LF2 2.0a, 100 in Darkfiren.
inline constexpr std::size_t max_frame_blocks = 100;
inline constexpr std::size_t max_object_points = 20;
inline constexpr std::size_t max_body_points = 5;
inline constexpr std::size_t max_frame_sounds = 20;
inline constexpr std::size_t max_header_list = 100;
inline constexpr std::size_t strength_entries = 10;
inline constexpr std::int32_t max_sheet_cells = 500;

// Darkfiren tags that LF2 2.0a lacks. They are kept as ordered key/value items and handed to
// scripts under the tag's own name, so a tag absent from the file is absent (nil) in Lua.
struct ExtraItem {
    enum class Kind : std::uint8_t { integer, list, text, groups };
    std::string key;
    Kind kind = Kind::integer;
    std::vector<std::int32_t> values; // one value for `integer`
    std::string text;
    std::vector<std::vector<std::int32_t>> groups; // `groups`: one entry per occurrence of the tag
};
using Extras = std::vector<ExtraItem>;

struct Rectangle {
    std::int32_t x = 0;
    std::int32_t y = 0;
    std::int32_t width = 0;
    std::int32_t height = 0;
};

struct SpriteSheet {
    std::string path;
    std::string declared_range; // The original ignores the text after `file`.
    std::int32_t first_picture = 0;
    std::int32_t cell_width = 0;  // w:
    std::int32_t cell_height = 0; // h:
    std::int32_t columns = 0;     // row: cells per image row
    std::int32_t rows = 0;        // col: number of image rows
};

// Shared 80-byte layout of itr blocks and weapon-strength entries.
struct Interaction {
    std::int32_t kind = 0;
    Rectangle area;
    std::int32_t dvx = 0;
    std::int32_t dvy = 0;
    std::int32_t fall = 0;
    std::int32_t arest = 0;
    std::int32_t vrest = 0;
    std::int32_t respond = 0;
    std::int32_t effect = 0;
    // catchingact fills both; pickingact writes [0] and pickedact writes [1].
    std::array<std::int32_t, 2> catching_actions{};
    std::array<std::int32_t, 2> caught_actions{};
    std::int32_t bdefend = 0;
    std::int32_t injury = 0;
    std::int32_t zwidth = 0;
    Extras extra; // Darkfiren-only fields (dvz, drain, poison, ...)
};

struct Body {
    std::int32_t kind = 0;
    Rectangle area;
    Extras extra; // zwidth, respond
};

struct ObjectPoint {
    std::int32_t kind = 0, x = 0, y = 0, action = 0, dvx = 0, dvy = 0, oid = 0, facing = 0;
    Extras extra;
};
struct BodyPoint {
    std::int32_t x = 0, y = 0;
    Extras extra; // w, h, rect, respond
};
struct CatchPoint {
    std::int32_t kind = 0, x = 0, y = 0;
    std::int32_t injury = 0; // also written by fronthurtact:
    std::int32_t cover = 0;  // also written by backhurtact:
    std::int32_t vaction = 0, aaction = 0, jaction = 0, daction = 0, taction = 0;
    std::int32_t throwvx = 0, throwvy = 0, hurtable = 0, decrease = 0, dircontrol = 0;
    // Not initialized by the original record constructor.
    std::optional<std::int32_t> throwinjury;
    std::optional<std::int32_t> throwvz;
    Extras extra;
};
struct WeaponPoint {
    std::int32_t kind = 0, x = 0, y = 0, weaponact = 0, attacking = 0, cover = 0;
    std::int32_t dvx = 0, dvy = 0, dvz = 0;
};

struct Frame {
    bool defined = false;
    std::string name;
    std::int32_t picture = 0;
    std::int32_t state = 0;
    std::int32_t wait = 0;
    std::int32_t next = 0;
    std::int32_t dvx = 0, dvy = 0, dvz = 0;
    std::int32_t center_x = 0, center_y = 0;
    std::int32_t mp = 0;
    // hit_a hit_d hit_j hit_Fa hit_Ua hit_Da hit_Fj hit_Uj hit_Dj hit_ja, in that order.
    std::array<std::int32_t, 10> hits{};
    std::optional<std::string> sound; // first of `sounds`
    // Up to 20 sound, 20 opoint and 5 bpoint blocks; opoint/bpoint above mirror element 0.
    std::vector<std::string> sounds;
    std::vector<ObjectPoint> opoints;
    std::vector<BodyPoint> bpoints;
    Extras extra; // dx, dy, dz, hp, chp, cmp, caught, loop, amount, shadow, bound, center_z, ...
    Extras hold;  // hold_a/d/j/f/b/uz/dz
    Extras hit_ext; // hit_f/b/uz/dz/g/Faj/Uaj/Daj and the raw pdk aliases
    std::optional<Extras> ppoint;
    ObjectPoint opoint;
    BodyPoint bpoint;
    CatchPoint cpoint;
    WeaponPoint wpoint;
    std::vector<Interaction> interactions;
    std::vector<Body> bodies;
    Rectangle interaction_bounds;
    Rectangle body_bounds;
};

struct WeaponStrength {
    bool referenced = false; // named by an entry: line
    std::optional<std::string> name; // stored in the previous entry's slot
    Interaction values;
};

// Header values without an original default are absent until the file sets them.
struct Movement {
    std::optional<std::int32_t> walking_frame_rate, running_frame_rate;
    std::optional<double> walking_speed, walking_speedz, running_speed, running_speedz;
    std::optional<double> heavy_walking_speed, heavy_walking_speedz;
    std::optional<double> heavy_running_speed, heavy_running_speedz;
    std::optional<double> jump_height, jump_distance, jump_distancez;
    std::optional<double> dash_height, dash_distance, dash_distancez;
    std::optional<double> rowing_height, rowing_distance;
};

// <weapon_piece>: `team` plus up to five numbered pieces.
struct WeaponPiece {
    Extras fields;
    std::array<std::optional<Extras>, 5> pieces;
};
// <pic>: `random`, `sound` and up to ten skins.
inline constexpr std::size_t max_skins = 10;
inline constexpr std::size_t max_commands = 10;
struct Skins {
    Extras fields;
    std::vector<Extras> entries;
};

// Display blocks (<hp_bar>, <minibar>, ...): the block's own tags plus its `layer:` records.
struct DisplayBlock {
    Extras fields;
    std::vector<Extras> layers;
};
inline constexpr std::size_t max_display_layers = 100; // minibar, bossbar and menu_face are tighter, see the parser
inline constexpr std::size_t max_stats_counts = 10;
inline constexpr std::size_t max_phase_ids = 100;
struct Display {
    std::optional<DisplayBlock> hp_bar, mp_bar, minibar, bossbar, effect, menu_face;
    std::optional<std::vector<Extras>> stats_count;
    std::optional<Extras> team_flag, name;
};

struct ObjectData {
    std::string name = "none";
    std::string head = "none";
    std::optional<std::string> small;
    Movement movement;
    Extras header; // Darkfiren <bmp_begin> tags
    std::optional<Extras> stats;  // <stats>
    std::optional<Extras> armor;  // <armor>
    std::optional<WeaponPiece> weapon_piece;
    std::vector<Extras> sound_list; // weapon <sound> (layout not documented, see parser)
    std::optional<Skins> skins;
    std::vector<Extras> command;  // <command>, up to ten entries
    std::optional<Extras> phase;  // <phase> (transformation grid)
    std::optional<Display> display;
    std::int32_t weapon_hp = 0;
    std::int32_t weapon_drop_hurt = 0;
    std::optional<std::string> weapon_hit_sound, weapon_drop_sound, weapon_broken_sound;
    std::vector<SpriteSheet> sheets;
    std::array<WeaponStrength, strength_entries> strengths{};
    std::vector<Frame> frames = std::vector<Frame>(frame_count);
    std::int32_t token_checksum = 0;
    // Recoverable quirks the original accepts silently, with line numbers.
    std::vector<std::string> diagnostics;
};

struct PictureCell {
    std::size_t sheet = 0;
    Rectangle source;
};

// Parses decoded text. Errors carry the 1-based line of the failing token.
Result<ObjectData> parse(std::string_view text);
// Reads a resource, decoding `.dat` files like the original, then parses it.
Result<ObjectData> load(const ResourceSource& resources, std::string_view path);
std::optional<PictureCell> find_picture(const ObjectData& data, std::int32_t picture);
// Script-facing table.
ScriptValue to_script_value(const ObjectData& data);
}
