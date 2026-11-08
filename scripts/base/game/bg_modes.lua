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

-- The tags of a mode that change the background's area or the round's start: `shadow`, `shadowsize`, `dicontrol`, `start_frame`, `reserve`,
-- `dx`, `dvx`, `dz`, `dvz` (the round's start and control, read by the round) and `width` (the battlefield's width,
-- -1 = the window width), `zboundary` ("near far"), `dvy` (the start height of every fighter, below 0), `centery`
-- (the height weapons, criminals and battle-mode armies drop from, below 0) and `attacking` (the damage percent
-- of every hit, 0 or more). Returns nil when the mode carries none of them. A value the readme does not allow
-- (a dvy or centery of 0 or more, a negative attacking, a zboundary without two numbers) is dropped.
function bg_modes.area(mode)
    if mode == nil then return nil end
    local area = {}
    local width = tonumber(mode.width)
    if width and (width == -1 or width > 0) then area.width = math.floor(width) end
    local near, far = tostring(mode.zboundary or ""):match("^%s*(-?%d+)[%s,]+(-?%d+)")
    if near then area.zboundary = {tonumber(near), tonumber(far)} end
    local dvy = tonumber(mode.dvy)
    if dvy and dvy < 0 then area.dvy = math.floor(dvy) end
    local centery = tonumber(mode.centery)
    if centery and centery < 0 then area.centery = math.floor(centery) end
    local attacking = tonumber(mode.attacking)
    if attacking and attacking >= 0 then area.attacking = math.floor(attacking) end
    -- `shadow` (the image) and `shadowsize` ("width height") take priority over the bg.dat's own.
    if type(mode.shadow) == "string" and mode.shadow:match("%S") then area.shadow = (mode.shadow:gsub("^%s+", ""):gsub("%s+$", "")) end
    local shadow_width, shadow_height = tostring(mode.shadowsize or ""):match("^%s*(%d+)[%s,]+(%d+)")
    if shadow_width then area.shadow_size = {tonumber(shadow_width), tonumber(shadow_height)} end
    -- Round start and control tags: whole numbers, nil when the mode has none. `dicontrol` is 0 (vanilla) or 1 (pdk).
    for _, key in ipairs({"start_frame", "reserve", "dx", "dvx", "dz", "dvz"}) do
        local number = tonumber(mode[key])
        if number then area[key] = math.floor(number) end
    end
    local control = tonumber(mode.dicontrol)
    if control == 0 or control == 1 then area.dicontrol = control end
    return next(area) and area or nil
end

-- The filters of a mode: `respond` chooses the background layers, `arest` the opoints. A filter is a set of the
-- values the mode lists, or nil (no filter, everything counts) when the mode does not carry the key. A layer or
-- opoint that has no value of its own has value 0, so a mode that lists 1 and 2 only leaves out the plain ones.
-- `area` (see bg_modes.area) travels with them: background.filtered applies its width and zboundary, and the
-- round reads the rest as state.bg_area.
function bg_modes.filters(mode)
    return {respond = value_set(mode.respond), arest = value_set(mode.arest), wait = value_set(mode.wait),
        fall = value_set(mode.fall), area = bg_modes.area(mode)}
end

-- True when the mode has a respond or arest key, or one of the area tags, at all.
function bg_modes.has_filters(mode)
    return mode.respond ~= nil or mode.arest ~= nil or mode.wait ~= nil or mode.fall ~= nil or bg_modes.area(mode) ~= nil
end

-- The percent every hit's damage is scaled to (`attacking`); 100 when the mode has none.
function bg_modes.damage_percent(area)
    return area and area.attacking or 100
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

-- `hurtable` (mode tag): 1 lets a team hit its own members, 2 makes every hit do no damage, 3 is both.
function bg_modes.friendly_fire(mode) return mode ~= nil and (mode.hurtable or 0) % 2 == 1 end
function bg_modes.no_damage(mode) return mode ~= nil and (mode.hurtable or 0) >= 2 end

-- `gain_mp_a` / `gain_mp_v`: the percent of a hit's injury that becomes MP for the attacker and for the victim
-- (characters only, the MP may pass 500). Returns the two amounts, rounded down.
function bg_modes.mp_gain(mode, attacker_is_character, victim_is_character, injury)
    if not mode or injury <= 0 then return 0, 0 end
    local attacker_gain = attacker_is_character and mode.gain_mp_a and math.floor(injury * mode.gain_mp_a / 100) or 0
    local victim_gain = victim_is_character and mode.gain_mp_v and math.floor(injury * mode.gain_mp_v / 100) or 0
    return attacker_gain, victim_gain
end

return bg_modes
