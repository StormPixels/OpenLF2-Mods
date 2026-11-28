-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- Tipe game 4: LF2 Neora (an engine modification: neora.dll next to its own executable PDK.exe; detected by neora.dll).
-- Only what differs from the shared settings of base/game/tipe_game.lua.
-- The Configuration Block of neora.dll (DLL/Main.asm) is read from the game's own DLL (resource "game/neora_config", see
-- neora_config_text in src/resources/installer.cpp), so a Neora mod that changed a value is followed; `fallback` is what Neora ships.
-- Only what OpenLF2 has a counterpart for is used.
local loaded

local function config()
    if loaded then return loaded end
    loaded = {}
    local ok, text = pcall(function() return engine.read_resource("game/neora_config") end)
    if ok and type(text) == "string" then
        for key, value in text:gmatch("([%a_]+) (%-?%d+)") do loaded[key] = tonumber(value) end
    end
    return loaded
end

-- tipe game setting = the DLL's number of that name (Neora's own name on the right).
local numbers = {
    slow_motion = "slow_motion",          -- slow motion at the end of a round
    slow_power = "slow_power",
    battle_defense_max = "battle_limit",  -- Battle mode defense limit, tenths of a percent (the original stops at 300)
    battle_defense_step = "battle_step",  -- one key press (the original steps 50)
    shake_value = "shake_value",          -- the shake of a hit
}
-- tipe game setting = the DLL's 0/1 flag.
local flags = {
    f7_after_round = "f7_for_dead",       -- F7 after the round has ended, as in LF2 1.9
    unlock_teams = "unlock_teams",        -- team choice in Stage mode
}
local fallback = {
    compact_sheet = true,  -- PDK.exe's MENU_CLIP6 is the compact 794 x 264 sheet
    slow_motion = 1, slow_power = 65, battle_defense_max = 1000, battle_defense_step = 100, shake_value = 3,
    f7_after_round = true, unlock_teams = true,
}

-- The game's Lua has no setmetatable (scripts/runtime/bootstrap.lua gives scripts a fixed set of functions), so the settings
-- are not a table with __index: `settings` stays empty and `setting(key)` is asked by tipe_game.get instead.
local function setting(key)
    local block = config()
    if numbers[key] and block[numbers[key]] ~= nil then return block[numbers[key]] end
    if flags[key] and block[flags[key]] ~= nil then return block[flags[key]] == 1 end
    return fallback[key]
end

return {
    id = 4,
    kind = "neora",
    name = "LF2 Neora",
    settings = {},
    setting = setting,
}
