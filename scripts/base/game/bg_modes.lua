-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren's background modes: the text of "game/bg_modes/<row>" (one mode per line, `key=value` pairs
-- separated by tabs, repeated keys such as respond joined with commas) and the layer filters a mode carries.
-- Kept compatible with Lua 5.1/LuaJIT.
local bg_modes = {}

-- Parses the resource text into a list of mode tables of strings; a line without a name is no mode.
function bg_modes.parse(text)
    local modes = {}
    for line in (text or ""):gmatch("[^\n]+") do
        local mode = {}
        for pair in line:gmatch("[^\t]+") do
            local key, value = pair:match("^([%w_]+)=(.*)$")
            if key then mode[key] = value end
        end
        if mode.name then modes[#modes + 1] = mode end
    end
    return modes
end

-- "0,2" -> {[0] = true, [2] = true}; nil when the mode has no such key.
local function value_set(text)
    if text == nil then return nil end
    local set = {}
    for item in text:gmatch("[^,]+") do
        local number = tonumber(item)
        if number then set[math.floor(number)] = true end
    end
    return set
end

-- The filters of a mode: `respond` chooses the background layers, `arest` the opoints. A filter is a set of the
-- values the mode lists, or nil (no filter, everything counts) when the mode does not carry the key. A layer or
-- opoint that has no value of its own has value 0, so a mode that lists 1 and 2 only leaves out the plain ones.
function bg_modes.filters(mode)
    return {respond = value_set(mode.respond), arest = value_set(mode.arest)}
end

-- True when the mode has a respond or arest key at all.
function bg_modes.has_filters(mode)
    return mode.respond ~= nil or mode.arest ~= nil
end

-- Does an item (layer.respond, opoint.arest) pass a filter set?
function bg_modes.passes(set, value)
    if set == nil then return true end
    return set[value or 0] == true
end

-- The filters of a background's first mode, which stands whenever no other mode was chosen (Random, Stage, a
-- background left without choosing). Nothing when the background has no modes or the row has none (Lee On Road).
function bg_modes.default_filters(row)
    if type(row) ~= "number" or row < 0 then return nil end
    local ok, text = pcall(engine.read_resource, "game/bg_modes/" .. row)
    if not ok then return nil end
    local first = bg_modes.parse(text)[1]
    return first and bg_modes.filters(first) or nil
end

return bg_modes
