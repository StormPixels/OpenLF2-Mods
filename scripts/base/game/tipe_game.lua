-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- Tipe game: what the opened game folder needs, one numbered file per type in base/game/types/.
--   Tipe game 1  LF2 original         types/tipe_game_1.lua
--   Tipe game 2  LF2 original + mod   types/tipe_game_2.lua
--   Tipe game 3  LF2 Darkfiren        types/tipe_game_3.lua
--   Tipe game 4  LF2 Neora            types/tipe_game_4.lua
-- `shared` below is what every tipe game uses; a type's file lists only what differs ("edit tipe game N" = edit that one
-- file). A script asks tipe_game.get("key", default): the opened type's value, else the shared one, else the default.
--
-- A new tipe game 5 takes four steps (as tipe game 4, Neora, did):
--   1. a file types/tipe_game_5.lua like the others (id = 5, kind = "<name>", name, settings);
--   2. list it in `types` below and in scripts/base/package.manifest;
--   3. teach the host to detect it: GameKind and DirectoryArchive::detect_profile (src/resources/installer.cpp), whose
--      kind name is the `kind` of the file;
--   4. add settings only for what differs from `shared`.
-- Kept compatible with Lua 5.1/LuaJIT.
local game_kind = require("base/game/game_kind")
local tipe_game = {}

local shared = {
    -- Recording page of launch.lua: false is the vanilla MENU_CLIP6 sheet (704 x 312, e-mail field, "recorded" page),
    -- true the compact sheet of the Darkfiren pack (794 x 264, no e-mail field).
    compact_sheet = false,
    -- Match height (background.view_height): a background whose far zboundary is at most classic_far uses
    -- classic_view_height, a taller one tall_view_height. Equal heights make every background classic.
    classic_far = 550,
    classic_view_height = 550,
    tall_view_height = 730,
    -- Slow motion at the end of a round (milliseconds added per frame, see speed.lua). 0 = off. LF2 Darkfiren's system.dat
    -- `slow_motion:` / `slow_power:` tags win over these when the game has them; an engine without such tags (Neora keeps
    -- them in its DLL config block) takes the type's value.
    slow_motion = 0,
    slow_power = 65,
    -- Battle mode defense of a side (battle_setup.lua), in tenths of a percent: the limit and the step of one key press.
    battle_defense_max = 300,
    battle_defense_step = 50,
    -- F7 (heal all) also works after the round has ended (match.lua function_keys).
    f7_after_round = false,
}

-- Every tipe game, by number.
local types = {
    require("base/game/tipe_game_1"),
    require("base/game/tipe_game_2"),
    require("base/game/tipe_game_3"),
    require("base/game/tipe_game_4"),
}

-- The tipe game with this number, or nil.
function tipe_game.by_id(id)
    for _, entry in ipairs(types) do
        if entry.id == id then return entry end
    end
    return nil
end

-- The tipe game of the opened game. A kind no file names is treated as the original (tipe game 1).
function tipe_game.current()
    local kind = game_kind.name()
    for _, entry in ipairs(types) do
        if entry.kind == kind then return entry end
    end
    return types[1]
end

function tipe_game.id() return tipe_game.current().id end
function tipe_game.name() return tipe_game.current().name end

-- The value of `key` for the opened game: its tipe game's own, else the shared one, else `default`.
function tipe_game.get(key, default)
    local value = tipe_game.current().settings[key]
    if value == nil then value = shared[key] end
    if value == nil then return default end
    return value
end

return tipe_game
