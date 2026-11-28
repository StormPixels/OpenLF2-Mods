-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- One place for the settings that differ between the kinds of game folder (see base/game/game_kind.lua):
--   shared    what every kind uses unless its own table says otherwise;
--   original  LF2 v2.0a as released;
--   modded    the original engine layout with other data or another lf2.exe (NTSD, fan mods);
--   darkfiren LF2 Darkfiren (system.dat, resource.dat).
-- A script asks game_profile.get("key") instead of keeping its own constant, so adding a rule for one kind is one line
-- in `kinds` and nothing else. A key a kind does not list falls back to `shared`; a key nobody lists is nil.
-- Kept compatible with Lua 5.1/LuaJIT.
local game_kind = require("base/game/game_kind")
local game_profile = {}

local shared = {
    -- Recording page of launch.lua: false is the vanilla MENU_CLIP6 sheet (704 x 312, e-mail field, "recorded" page),
    -- true the compact sheet of the Darkfiren pack (794 x 264, no e-mail field).
    compact_sheet = false,
    -- Match height (background.view_height): a background whose far zboundary is at most classic_far uses
    -- classic_view_height, a taller one tall_view_height. Equal heights make every background classic.
    classic_far = 550,
    classic_view_height = 550,
    tall_view_height = 730,
}

local kinds = {
    -- Original LF2: every background fits the classic 550 high picture.
    original = {tall_view_height = 550},
    -- Original plus mods (e.g. Naruto: The Setting Dawn): the vanilla sheet, and tall backgrounds use 730.
    modded = {},
    -- Darkfiren: its compact recording sheet; tall backgrounds use 730.
    darkfiren = {compact_sheet = true},
}

-- "original", "modded" or "darkfiren".
function game_profile.kind() return game_kind.name() end

-- The value of `key` for the opened game, or `default` when neither the kind nor `shared` has it.
function game_profile.get(key, default)
    local own = kinds[game_kind.name()]
    local value = own and own[key]
    if value == nil then value = shared[key] end
    if value == nil then return default end
    return value
end

return game_profile
