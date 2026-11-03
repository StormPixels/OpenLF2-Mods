-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren's mode list (data/mode/mode.dat) and the mode file each battlefield layout draws its menus with.
-- Every <mode_information> block names a mode (`name`), its file (`file`), `hidden` and the window width it is made
-- for (`respond`, 794 when absent). The text of a mode file comes from the generic resource game/dat_text/<path>;
-- only mode4.dat has the older game/mode_file as a fallback. Compatible with Lua 5.1/LuaJIT.
local constants = require("base/game/constants")
local mode_layout = require("base/game/mode_layout")
local ui_modes = {}

local list_path = "game/dat_text/data/mode/mode.dat"
local classic_width = constants.screen.width
-- LF2 Darkfiren's 8P widescreen (mode2.dat, `respond: 1018` in mode.dat).
local wide_1018_width = 1018

-- {{name =, file = "data/mode/mode4.dat" (lower case, forward slashes), hidden =, respond =}, ...} in file order.
-- Several `key: value` pairs may share a line, as in `name: mode#2   hidden: 0   respond: 1018`; a block without a
-- `file` is dropped. A value is the first word after the colon (names with spaces are not supported).
function ui_modes.parse(text)
    local list, current = {}, nil
    for line in (text or ""):gmatch("[^\r\n]+") do
        local tag = line:match("^%s*<([%w_]+)>")
        if tag == "mode_information" then
            current = {hidden = 0, respond = classic_width}
        elseif tag == "mode_information_end" then
            if current and current.file then list[#list + 1] = current end
            current = nil
        elseif current then
            for key, value in line:gmatch("([%w_]+)%s*:%s*(%S+)") do
                if key == "file" then current.file = value:gsub("\\", "/"):lower()
                elseif key == "name" then current.name = value
                elseif key == "hidden" or key == "respond" then
                    local number = tonumber(value)
                    if number and (key == "hidden" or number >= 1) then current[key] = number end
                end
            end
        end
    end
    return list
end

-- The picture width a battlefield layout draws the menus on; nil for a layout this module does not know.
function ui_modes.layout_width(layout)
    if layout == "classic" then return classic_width end
    if layout == "wide 1333" then return constants.screen.wide_width end
    if layout == "wide 1018" then return wide_1018_width end
    return nil
end

-- The first mode of the list made for `width`. `hidden` is left aside: the player chose the layout.
function ui_modes.for_width(list, width)
    for _, entry in ipairs(list or {}) do
        if entry.respond == width then return entry end
    end
    return nil
end

-- The text of a mode file, or nil. mode4.dat falls back on the game/mode_file resource.
function ui_modes.text(entry)
    if not entry or not entry.file then return nil end
    local ok, text = pcall(engine.read_resource, "game/dat_text/" .. entry.file)
    if ok and type(text) == "string" and text ~= "" then return text end
    if entry.file:match("mode4%.dat$") then
        ok, text = pcall(engine.read_resource, "game/mode_file")
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    return nil
end

-- The mode file text of a battlefield layout: nil in the classic layout (the built-in menu stands) and for a layout
-- without a mode. Without game/dat_text the wide 1333 layout still gets mode4.dat from game/mode_file.
function ui_modes.layout_text(layout)
    local width = ui_modes.layout_width(layout)
    if not width or width == classic_width then return nil end
    local ok, listing = pcall(engine.read_resource, list_path)
    local entry = ok and ui_modes.for_width(ui_modes.parse(listing), width) or nil
    if not entry and width == constants.screen.wide_width then entry = {file = "data/mode/mode4.dat"} end
    return ui_modes.text(entry)
end

-- The ids of the <random> block of a mode file (the fighters a random pick may give), as a set; nil when empty.
function ui_modes.random_pool(text)
    local pool, count, inside = {}, 0, false
    for line in (text or ""):gmatch("[^\r\n]+") do
        local tag = line:match("^%s*<([%w_]+)>")
        if tag == "random" then inside = true
        elseif tag == "random_end" then break
        elseif inside then
            local id = tonumber(line:match("^%s*id%s*:%s*(%d+)"))
            if id then pool[id] = true; count = count + 1 end
        end
    end
    return count > 0 and pool or nil
end

-- The <name> block of a mode file: the mode's title (`name`) with the position (`x`, `y`) it is drawn at and its two
-- colours (`hexf` text, `hexb` shadow, as 0xRRGGBB numbers); nil without the block. Read only: nothing draws it yet.
function ui_modes.title(text)
    -- mode_layout.blocks turns a value that starts with digits ("8P_normal_mode") into a number, so the title is
    -- read from the lines directly.
    local block, inside = {}, false
    for line in (text or ""):gmatch("[^\r\n]+") do
        local tag = line:match("^%s*<([%w_]+)>%s*$")
        if tag == "name" and next(block) == nil then inside = true
        elseif tag then inside = false
        elseif inside then
            local key, value = line:match("^%s*([%w_]+)%s*:%s*(.-)%s*$")
            if key and block[key] == nil then block[key] = value end
        end
    end
    if not block.name or block.name == "" then return nil end
    return {name = block.name, x = tonumber(block.x) or 0, y = tonumber(block.y) or 0,
        hexf = tonumber(block.hexf), hexb = tonumber(block.hexb)}
end

-- The <combo> block: the hit counter picture `pic` (digits of w x h), where it goes (`offset_x`, `offset_y`) and for how
-- long (`times` ticks, from `respond` hits); nil without the block. Read only: the match has no combo counter yet.
function ui_modes.combo(text)
    local block = mode_layout.blocks(text).combo
    if not block then return nil end
    return {name = block.name, pic = block.pic and tostring(block.pic):gsub("^%s+", ""):gsub("\\", "/"):lower() or nil,
        w = tonumber(block.w), h = tonumber(block.h), offset_x = tonumber(block.offset_x), offset_y = tonumber(block.offset_y),
        times = tonumber(block.times), respond = tonumber(block.respond)}
end

return ui_modes
