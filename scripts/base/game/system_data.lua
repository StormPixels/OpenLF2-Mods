-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren's data\system.dat (interface I4): scalar settings and the id/state lists that switch behaviors
-- (armor_s, defend, hp_refill, id_locked, ...). Everything answers with the caller's default when the file or the
-- tag is missing, so original LF2 data behaves as before. Kept compatible with Lua 5.1/LuaJIT.
local sd_text = require("base/game/sd_text")
local system_data = {}

local max_entries = 100  -- every list of the readme holds up to 100 entries
local empty = {scalars = {}, lists = {}}
local parsed, settled = nil, false

-- Parses the text of system.dat into {scalars = {key = string}, lists = {name = {ids = set, states = set}}}.
function system_data.parse(text)
    local scan = sd_text.scan(text)
    local result = {scalars = scan.scalars, lists = {}}
    for _, block in ipairs(scan.blocks) do
        local list = result.lists[block.name]
        if not list then
            list = {ids = {}, states = {}, count = 0}
            result.lists[block.name] = list
        end
        for _, line in ipairs(block.lines) do
            for _, pair in ipairs(sd_text.pairs_of_line(line)) do
                local number = sd_text.int(pair[2])
                local target = pair[1] == "id" and list.ids or pair[1] == "state" and list.states or nil
                if number and target and list.count < max_entries then
                    target[number] = true
                    list.count = list.count + 1
                end
            end
        end
    end
    return result
end

-- Replaces the data (tests, hosts that already hold the text). nil forgets it so the next read loads again.
function system_data.set_text(text)
    parsed, settled = text and system_data.parse(text) or nil, text ~= nil
end

local function data()
    if settled then return parsed or empty end
    local text, message = sd_text.read("data/system.dat")
    if text then
        parsed, settled = system_data.parse(text), true
    elseif not sd_text.not_ready(message) then
        settled = true  -- no system.dat (original LF2): defaults for everything
    end
    return parsed or empty
end

-- A numeric tag such as `spark_w: 99` or `join: -1`; `default` when the tag is absent or not a number.
function system_data.number(key, default)
    local value = sd_text.int(data().scalars[key])
    if value == nil then return default end
    return value
end

-- A text tag such as `menu_bgm1: bgm\main.wma`; `default` when absent.
function system_data.string(key, default)
    local value = data().scalars[key]
    if value == nil or value == "" then return default end
    return value
end

-- The `id:` entries of a `<listname>` block as a set (number -> true); an empty set when the block is absent.
-- The set belongs to the module: callers must not change it.
function system_data.ids(listname)
    local list = data().lists[listname]
    return list and list.ids or {}
end

-- The `state:` entries of a `<listname>` block (armor_s, z_states) as a set; empty when absent.
function system_data.states(listname)
    local list = data().lists[listname]
    return list and list.states or {}
end

-- True once system.dat has been read (or found missing); false while the game data is not attached yet, so a
-- caller that must not settle on defaults too early can wait for it.
function system_data.loaded()
    data()
    return settled
end

-- Does system.dat carry the block at all? (id_locked: a missing block means nothing is locked by default.)
function system_data.has(listname)
    return data().lists[listname] ~= nil
end
return system_data
