-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren's <menu_small> (mode files): the options panel of the character menu as a stack of picture rows,
-- one per layer: layer N draws its `small` picture (the row) at (x, y) and, when selected, its `head` picture
-- (the highlight) over it; the next visible layer starts h pixels lower. Numbers are absolute screen positions.
-- This module reads the layers and works out which rows show and where; character_select draws and runs them.
-- Compatible with Lua 5.1/LuaJIT.
local menu_small = {}

local path_keys = {small = true, head = true, smallb = true, smallc = true, smalld = true, smallp = true, pic = true, pic2 = true}

-- {[layer number] = {small=, head=, ..., x=, y=, h=, dx=, dy=, dvx=, dvy=, fy=, next=, hex=, hidden=, kind=, caughtact=,
-- modes = {[game mode] = true} or nil}} for the first <menu_small> block of the text.
function menu_small.parse(text)
    local layers, inside, current = {}, false, nil
    for line in (text or ""):gmatch("[^\r\n]+") do
        line = line:gsub("#.*", "")
        local tag = line:match("^%s*<([%w_]+)>%s*$")
        if tag == "menu_small" then inside = true
        elseif tag == "menu_small_end" then break
        elseif inside then
            local number = line:match("^%s*layer%s*:%s*(%d+)")
            if number then
                current = {}
                layers[tonumber(number)] = current
            elseif line:match("^%s*layer_end") then
                current = nil
            elseif current then
                for key, value in line:gmatch("([%w_]+)%s*:%s*(%S+)") do
                    if key == "mode" then
                        current.modes = current.modes or {}
                        local mode = tonumber(value)
                        if mode then current.modes[mode] = true end
                    elseif path_keys[key] then
                        current[key] = value:gsub("\\", "/"):lower()
                    else
                        current[key] = tonumber(value) or current[key]
                    end
                end
            end
        end
    end
    return layers
end

-- Is the layer shown? hidden 4 and the lock values (10 and up) never; 1 to 3 once the cheat code is in. A layer
-- that lists game modes is shown in those only. `game_mode`: 0 versus, 1 stage, 2 and 3 championships, 4 battle, 5 demo.
function menu_small.shown(layer, game_mode, cheat)
    if not layer or not (layer.small or layer.head) then return false end
    local hidden = layer.hidden or 0
    if hidden ~= 0 and not (hidden >= 1 and hidden <= 3 and cheat) then return false end
    if layer.kind == 1 then return false end   -- "more settings" is not offered
    if layer.modes and not layer.modes[game_mode] then return false end
    return true
end

-- The rows to draw, top to bottom: {layer = n, y = top of the row}. `forced` lists layer numbers that stay in as
-- disabled rows although their modes do not list this game mode (the time limit in Stage mode, for instance);
-- `skip` lists layer numbers to leave out whatever else.
function menu_small.rows(layers, game_mode, cheat, forced, skip)
    local numbers = {}
    for number in pairs(layers) do numbers[#numbers + 1] = number end
    table.sort(numbers)
    local rows, y = {}, nil
    for _, number in ipairs(numbers) do
        local layer = layers[number]
        local show = menu_small.shown(layer, game_mode, cheat)
        if not show and forced and forced[number] and layer.small then
            local hidden = layer.hidden or 0
            show = hidden == 0 or (hidden >= 1 and hidden <= 3 and cheat)
        end
        if show and skip and skip[number] then show = false end
        if show then
            y = y or layers[1] and layers[1].y or layer.y or 3
            rows[#rows + 1] = {layer = number, y = y}
            y = y + (layer.h or 0)
        end
    end
    return rows
end

-- Windows colour (blue * 65536 + green * 256 + red) to 0xRRGGBB.
function menu_small.colour(value)
    if not value then return nil end
    return (value % 256) * 65536 + (math.floor(value / 256) % 256) * 256 + math.floor(value / 65536) % 256
end

return menu_small
