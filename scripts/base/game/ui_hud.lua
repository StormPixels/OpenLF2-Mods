-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren's HUD styles: data/frame.dat lists the styles (name, file, hidden, respond = picture width, facing =
-- 10 for the 10 player layouts) and each style file has a <frame> block (the box of one player: its picture, size,
-- columns per row, where the small face goes, the bar colours), <hp_bar>, <mp_bar> and <team_flag>. A value a style
-- does not give keeps the built-in one, which is what the classic HUD draws. Compatible with Lua 5.1/LuaJIT.
local mode_layout = require("base/game/mode_layout")
local ui_hud = {}

local list_path = "game/dat_text/data/frame.dat"

-- The classic HUD: 4 boxes of 198 x 54 per row, bars of 124 x 10 read from the BARS sheet at the `col_*` rows.
function ui_hud.default_style()
    return {frame_pic = "pe/frame", bars_pic = "pe/bars", frame_x = 0, frame_y = 0, frame_w = 198, frame_h = 54,
        small_x = 9, small_y = 7, row = 4, col_dhp = 30, col_hp = 20, col_bhp = 40, col_dmp = 10, col_mp = 0,
        hp_bar = {x = 57, y = 16, w = 124, h = 10}, mp_bar = {x = 57, y = 36, w = 124, h = 10},
        team_flag = {x = 5, y = 0}}
end

local function path_of(value)
    return type(value) == "string" and value:gsub("\\", "/"):lower() or nil
end

-- A style from the text of its file, on top of the built-in one. A bar or box size below 1 is ignored.
function ui_hud.parse(text)
    local style, blocks = ui_hud.default_style(), mode_layout.blocks(text)
    local frame = blocks.frame
    if frame then
        for _, key in ipairs({"frame_x", "frame_y", "small_x", "small_y", "col_dhp", "col_hp", "col_bhp", "col_dmp", "col_mp"}) do
            if type(frame[key]) == "number" then style[key] = frame[key] end
        end
        for _, key in ipairs({"frame_w", "frame_h", "row"}) do
            if type(frame[key]) == "number" and frame[key] >= 1 then style[key] = frame[key] end
        end
        style.frame_file, style.bars_file = path_of(frame.frame), path_of(frame.bars)
    end
    for _, name in ipairs({"hp_bar", "mp_bar"}) do
        local block = blocks[name]
        if block then
            for _, key in ipairs({"x", "y", "w", "h"}) do
                local value = block[key]
                if type(value) == "number" and ((key ~= "w" and key ~= "h") or value >= 1) then style[name][key] = value end
            end
        end
    end
    local flag = blocks.team_flag
    if flag then
        if type(flag.team_flag_x) == "number" then style.team_flag.x = flag.team_flag_x end
        if type(flag.team_flag_y) == "number" then style.team_flag.y = flag.team_flag_y end
    end
    return style
end

-- {{name =, file = "data/frame/8/default.dat", hidden =, respond =, facing =}, ...} of data/frame.dat. The keys of an
-- entry may stand on the <frame_information> line itself (`respond: 1018 hidden: 1`).
function ui_hud.list(text)
    local list, current = {}, nil
    for line in (text or ""):gmatch("[^\r\n]+") do
        local tag, rest = line:match("^%s*<([%w_]+)>(.*)$")
        if tag == "frame_information_end" then
            if current and current.file then list[#list + 1] = current end
            current = nil
        elseif tag == "frame_information" then
            current = {hidden = 0}
        end
        if current then
            for key, value in (rest or line):gmatch("([%w_]+)%s*:%s*(%S+)") do
                if key == "file" then current.file = path_of(value)
                elseif key == "name" then current.name = value
                elseif key == "hidden" or key == "respond" or key == "facing" then
                    current[key] = tonumber(value) or current[key]
                end
            end
        end
    end
    return list
end

-- The style a picture of `width` pixels shows by default: the first listed style that is not hidden, is made for no
-- width or this one, and is for 8 players (`facing` 10 marks the 10 player styles).
function ui_hud.pick(list, width)
    for _, entry in ipairs(list or {}) do
        if (entry.hidden or 0) == 0 and (entry.respond == nil or entry.respond == width) and (entry.facing or 8) == 8 then
            return entry
        end
    end
    return nil
end

local cache = {}
local function readable(path)
    local ok, bytes = pcall(engine.read_resource, path)
    return ok and bytes ~= nil
end

-- The HUD style of a battlefield layout: the built-in one in the classic layout, else the default style of
-- data/frame.dat for that width (the built-in one when the game has none). A picture the game does not have keeps the
-- built-in picture. `width` is the picture width.
function ui_hud.current(layout, width)
    local key = tostring(layout) .. ":" .. tostring(width)
    if cache[key] then return cache[key] end
    local style
    if layout ~= "classic" and layout ~= "expand" and width then
        local ok, listing = pcall(engine.read_resource, list_path)
        local entry = ok and ui_hud.pick(ui_hud.list(listing), width) or nil
        local ok_file, text = false, nil
        if entry then ok_file, text = pcall(engine.read_resource, "game/dat_text/" .. entry.file) end
        if ok_file and type(text) == "string" then
            style = ui_hud.parse(text)
            if style.frame_file and readable(style.frame_file) then style.frame_pic = style.frame_file end
            if style.bars_file and readable(style.bars_file) then style.bars_pic = style.bars_file end
        end
    end
    style = style or ui_hud.default_style()
    cache[key] = style
    return style
end

-- Forgets the styles read so far (a host that reloads its game data, tests).
function ui_hud.reset() cache = {} end

return ui_hud
