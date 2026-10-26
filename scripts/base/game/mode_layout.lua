-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren's mode4.dat as a layout: the text of "game/mode_file" is read for the blocks whose positions and
-- sizes the character menu draws with (<menu_control>, <grid_char>, <grid_bg>, <grid_bg_mode>). A value the file
-- does not give, or gives in the wrong form, leaves the built-in one in place. Compatible with Lua 5.1/LuaJIT.
local mode_layout = {}

-- {tag = {key = value}}: the first block of each tag, the first line of each key. Numbers become numbers; the
-- `pic` and `small` paths are lower case with forward slashes, as the game's resources are named.
function mode_layout.blocks(text)
    local blocks, current = {}, nil
    for line in (text or ""):gmatch("[^\r\n]+") do
        local tag = line:match("^%s*<([%w_]+)>%s*$")
        if tag then
            if tag:sub(-4) == "_end" then current = nil
            elseif blocks[tag] == nil then current = {}; blocks[tag] = current
            else current = nil end
        elseif current then
            local key, value = line:match("^%s*([%w_]+)%s*:%s*(.-)%s*$")
            if key and current[key] == nil then
                if key == "pic" or key == "small" then
                    value = value:gsub("\\", "/"):lower()
                else
                    value = tonumber(value:match("^(-?%d+)")) or value
                end
                current[key] = value
            end
        end
    end
    return blocks
end

-- target key <- block key, per target table of the menu; keys that must be at least 1 are listed apart.
local maps = {
    menu = {tag = "menu_control", pic = "pic", x = "start_x", y = "start_y", row = "row", step_x = "centerx", step_y = "centery"},
    roster = {tag = "grid_char", panel_pic = "pic", small_pic = "small", panel_x = "pic_x", panel_y = "pic_y",
        x = "start_x", y = "start_y", columns = "row", step_x = "centerx", step_y = "centery", width = "w", height = "h",
        human_x = "human_x", human_y = "human_y", com_x = "com_x", com_y = "com_y"},
    grid_bg = {tag = "grid_bg", panel_pic = "pic", random_pic = "small", panel_x = "pic_x", panel_y = "pic_y",
        x = "start_x", y = "start_y", w = "w", h = "h", step = "centery", name_x = "name_x", name_y = "name_y"},
    grid_mode = {tag = "grid_bg_mode", panel_pic = "pic", panel_x = "pic_x", panel_y = "pic_y",
        x = "start_x", y = "start_y", w = "w", h = "h", step_x = "centerx", step_y = "centery", columns = "row",
        name_x = "name_x", name_y = "name_y"},
}
local at_least_one = {row = true, columns = true, w = true, h = true, width = true, height = true, step = true,
    step_x = true, step_y = true}

-- Overwrites the built-in values of targets = {menu = t, roster = t, grid_bg = t, grid_mode = t} (tables the
-- caller owns) with what the text gives. Returns how many values were taken.
function mode_layout.apply(text, targets)
    local blocks, taken = mode_layout.blocks(text), 0
    for name, map in pairs(maps) do
        local target, block = targets[name], blocks[map.tag]
        if target and block then
            for to, from in pairs(map) do
                local value = block[from]
                if to ~= "tag" and value ~= nil and type(value) == type(target[to]) and
                   not (type(value) == "number" and at_least_one[to] and value < 1) then
                    target[to] = value
                    taken = taken + 1
                end
            end
        end
    end
    return taken
end

return mode_layout
