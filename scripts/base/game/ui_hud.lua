-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren's HUD styles: data/frame.dat lists the styles (name, file, hidden, respond = picture width, facing =
-- 10 for the 10 player layouts) and each style file has a <frame> block (the box of one player: its picture, size,
-- columns per row, where the small face goes, the bar colours), <hp_bar>, <mp_bar> and <team_flag>. A value a style
-- does not give keeps the built-in one, which is what the classic HUD draws. Compatible with Lua 5.1/LuaJIT.
local mode_layout = require("base/game/mode_layout")
local data_text = require("base/game/data_text")
local constants = require("base/game/constants")
local ui_hud = {}

local list_path = "data/frame.dat"
-- May a style with this `hidden:` value be chosen? 0 always; others by game/unlock.allows (nothing when the game lacks it).
local function permitted(hidden)
    hidden = hidden or 0
    if hidden == 0 then return true end
    local ok, unlock = pcall(require, "base/game/unlock")
    return ok and type(unlock) == "table" and type(unlock.allows) == "function" and unlock.allows(hidden) == true
end
local classic_width = constants.screen.width

-- The classic HUD: 4 boxes of 198 x 54 per row, bars of 124 x 10 read from the BARS sheet at the `col_*` rows.
function ui_hud.default_style()
    return {frame_pic = "pe/frame", bars_pic = "pe/bars", frame_x = 0, frame_y = 0, frame_w = 198, frame_h = 54,
        small_x = 9, small_y = 7, row = 4, col_dhp = 30, col_hp = 20, col_bhp = 40, col_dmp = 10, col_mp = 0,
        hp_bar = {x = 57, y = 16, w = 124, h = 10}, mp_bar = {x = 57, y = 36, w = 124, h = 10},
        team_flag = {x = 5, y = 0}, centered = true}
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
    style.radar = ui_hud.parse_radar(text)
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
        if permitted(entry.hidden) and (entry.respond == nil or entry.respond == width) and (entry.facing or 8) == 8 then
            return entry
        end
    end
    return nil
end

-- The <radar> block of a style file (readme/frame dat.txt): the base picture and where it goes, the area the dots move
-- in, which object types and frame states show, and the dot pictures. nil when the block is missing, switched off
-- (`bound: 0`) or lacks its picture or size. Picture paths are lower case with forward slashes.
function ui_hud.parse_radar(text)
    local radar, inside = {types = {}, states = {}, team_pics = {}, type_pics = {}}, false
    for line in (text or ""):gmatch("[^\r\n]+") do
        local tag = line:match("^%s*<([%w_]+)>%s*$")
        if tag == "radar" then inside = true
        elseif tag == "radar_end" then break
        elseif inside then
            local key, value = line:match("^%s*([%w_]+)%s*:%s*(%S+)")
            if key then
                local number = tonumber(value)
                if key == "type" and number then radar.types[number] = true
                elseif key == "state" and number then radar.states[number] = true
                elseif key:match("^pic_team%d$") then radar.team_pics[tonumber(key:sub(-1))] = path_of(value)
                elseif key:match("^pic_type%d$") then radar.type_pics[tonumber(key:sub(-1))] = path_of(value)
                elseif key == "pic" or key == "pic_dead" or key == "pic_heal" or key == "pic_hidden" or key == "pic_clone" then
                    radar[key] = path_of(value)
                elseif number and radar[key] == nil then radar[key] = number end
            end
        end
    end
    if radar.bound ~= 1 or not radar.pic or not radar.width or not radar.height or radar.width < 1 or radar.height < 1 then return nil end
    radar.pic_x, radar.pic_y = radar.pic_x or 0, radar.pic_y or 0
    radar.start_x, radar.start_y = radar.start_x or radar.pic_x, radar.start_y or radar.pic_y
    radar.offset_x, radar.offset_y = radar.offset_x or 0, radar.offset_y or 0
    return radar
end

-- The picture of an object's dot: the team picture for a fighter (type 0), the type picture otherwise, the `dead` picture
-- for a fighter without hp. nil when the style has none.
function ui_hud.radar_icon(radar, kind, team, hp, flags)
    flags = flags or {}
    if flags.hidden and radar.pic_hidden then return radar.pic_hidden end
    if kind == 0 then
        if hp ~= nil and hp <= 0 and radar.pic_dead then return radar.pic_dead end
        if flags.clone and radar.pic_clone then return radar.pic_clone end
        if flags.healing and radar.pic_heal then return radar.pic_heal end
        team = math.floor(team or 1)
        -- The radar sheets have five team pictures. Once the stage enemies are team 6, team 5 is an ordinary team and the
        -- enemies take the fighter picture [BELUM PASTI: the original has no sixth team].
        if constants.teams.enemies > 5 and team >= constants.teams.enemies then
            return radar.type_pics[0] or radar.team_pics[5]
        end
        return radar.team_pics[math.max(1, math.min(5, team))] or radar.type_pics[0]
    end
    return radar.type_pics[kind]
end

-- Where the top left corner of a dot picture goes for an object at (x, z) on a stage `stage_width` wide whose z runs from
-- z_min to z_max: the dots move over the radar area less the offsets. [BELUM PASTI] the exact mapping of the original.
function ui_hud.radar_position(radar, x, z, stage_width, z_min, z_max)
    local across = math.max(0, radar.width - 2 * radar.offset_x)
    local down = math.max(0, radar.height - 2 * radar.offset_y)
    local fx = stage_width > 0 and math.max(0, math.min(1, x / stage_width)) or 0
    local fz = z_max > z_min and math.max(0, math.min(1, (z - z_min) / (z_max - z_min))) or 0
    return radar.start_x + math.floor(fx * across + 0.5), radar.start_y + math.floor(fz * down + 0.5)
end

local cache = {}
local function readable(path)
    local ok, bytes = pcall(engine.read_resource, path)
    return ok and bytes ~= nil
end

local names_cache
-- The style names of the game's data/frame.dat the player may choose from (not hidden, for 8 players), "Default" first.
-- {"Default"} alone when the game has no frame.dat.
function ui_hud.names()
    if names_cache then return names_cache end
    local names, seen = {"Default"}, {Default = true}
    local listing = data_text.read(list_path)
    for _, entry in ipairs(listing and ui_hud.list(listing) or {}) do
        if permitted(entry.hidden) and (entry.facing or 8) == 8 and entry.name and not seen[entry.name] then
            seen[entry.name] = true
            names[#names + 1] = entry.name
        end
    end
    names_cache = names
    return names
end

-- The HUD style of a battlefield layout and the style the player chose (`name`, "Default" or nil: the built-in HUD, which
-- is what data/frame/8/default.dat describes). A chosen style is read from data/frame.dat and its file; one the game does
-- not have, hidden, for another picture width or for 10 players keeps the built-in HUD. A picture the game does not have
-- keeps the built-in picture. `width` is the picture width (the classic 794 when nil).
function ui_hud.current(layout, width, name)
    local key = tostring(layout) .. ":" .. tostring(width) .. ":" .. tostring(name)
    if cache[key] then return cache[key] end
    local style
    if name and name ~= "Default" then
        local listing = data_text.read(list_path)
        local picture_width = width or classic_width
        local chosen
        for _, entry in ipairs(listing and ui_hud.list(listing) or {}) do
            if entry.name == name and permitted(entry.hidden) and (entry.facing or 8) == 8
               and (entry.respond == nil or entry.respond == picture_width) then
                chosen = entry
                break
            end
        end
        local text = chosen and data_text.read(chosen.file)
        if text and text:find("<frame>", 1, true) then
            style = ui_hud.parse(text)
            -- A style made for this exact width (`respond`) lays its boxes out across the whole picture (the 1018 style has
            -- its radar right of the 792 wide boxes); one without `respond` is classic sized and is centred.
            style.centered = chosen.respond == nil
            if style.frame_file and readable(style.frame_file) then style.frame_pic = style.frame_file end
            if style.bars_file and readable(style.bars_file) then style.bars_pic = style.bars_file end
            local radar = style.radar
            if radar then
                -- Only pictures the game has are drawn; without the base picture there is no radar.
                local function keep(path) if path and readable(path) then return path end end
                radar.pic = keep(radar.pic)
                for index, path in pairs(radar.team_pics) do radar.team_pics[index] = keep(path) end
                for index, path in pairs(radar.type_pics) do radar.type_pics[index] = keep(path) end
                for _, name in ipairs({"pic_dead", "pic_hidden", "pic_clone", "pic_heal"}) do radar[name] = keep(radar[name]) end
                radar.centered = chosen.respond == nil
                if not radar.pic then style.radar = nil end
            end
        end
    end
    style = style or ui_hud.default_style()
    cache[key] = style
    return style
end

-- Forgets the styles read so far (a host that reloads its game data, tests).
function ui_hud.reset() cache = {}; names_cache = nil end

return ui_hud
