-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren's mode list (data/mode/mode.dat) and the mode file each battlefield layout draws its menus with.
-- Every <mode_information> block names a mode (`name`), its file (`file`), `hidden` and the window width it is made
-- for (`respond`, 794 when absent). The text of a mode file comes from the generic resource game/dat_text/<path>;
-- only mode4.dat has the older game/mode_file as a fallback. Compatible with Lua 5.1/LuaJIT.
local constants = require("base/game/constants")
local mode_layout = require("base/game/mode_layout")
local data_text = require("base/game/data_text")
local ui_modes = {}

local list_path = "data/mode.dat"
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
    if layout == "wide 1018" or layout == "wide 1018 10P" then return wide_1018_width end
    return nil
end

-- The first mode of the list made for `width`. `hidden` is left aside: the player chose the layout.
function ui_modes.for_width(list, width)
    for _, entry in ipairs(list or {}) do
        if entry.respond == width then return entry end
    end
    return nil
end

-- The text of a mode file and where it came from ("host", "file"), or nil. mode4.dat also falls back on the older
-- game/mode_file resource.
function ui_modes.text(entry)
    if not entry or not entry.file then return nil end
    local text, source = data_text.read(entry.file)
    if text then return text, source end
    if entry.file:match("mode4%.dat$") then
        local ok, legacy = pcall(engine.read_resource, "game/mode_file")
        if ok and type(legacy) == "string" and legacy ~= "" then return legacy, "host" end
    end
    return nil
end

-- A wide layout's mode file when mode.dat does not name one that fits (or cannot be read).
local default_files = {[constants.screen.wide_width] = "data/mode/mode4.dat", [wide_1018_width] = "data/mode/mode2.dat"}

local ten_player_layout = "wide 1018 10P"
-- May a `hidden:` value be used? 0 always; others by game/unlock.allows (nothing when the game lacks it).
local function permitted(hidden)
    hidden = hidden or 0
    if hidden == 0 then return true end
    local ok, unlock = pcall(require, "base/game/unlock")
    return ok and type(unlock) == "table" and type(unlock.allows) == "function" and unlock.allows(hidden) == true
end
-- The mode of a layout in mode.dat's list: the one made for its width, but the 10 player layout takes mode3.dat.
local function entry_for(layout, list, width)
    if layout == ten_player_layout then
        for _, entry in ipairs(list or {}) do
            if entry.file and entry.file:match("mode3%.dat$") then return entry end
        end
        return nil
    end
    return ui_modes.for_width(list, width)
end
local sources = {}
local combo_cache = {}   -- ui_modes.combo_settings, per layout
local kill_cache = {}    -- ui_modes.kill_settings, per layout
-- The mode file text of a battlefield layout and where it came from: "host" or "file" (the game's own file) or
-- "builtin" (the layout blocks that are part of OpenLF2, used when the game's file cannot be read; only for the 1018
-- layout). nil in the classic layouts (the built-in menu stands) and when there is nothing to read.
function ui_modes.layout_text(layout)
    local width = ui_modes.layout_width(layout)
    if not width or width == classic_width then return nil end
    local listing = data_text.read(list_path)
    local entry = entry_for(layout, listing and ui_modes.parse(listing) or nil, width)
    if layout == ten_player_layout and (not entry or not permitted(entry.hidden)) then sources[layout] = false return nil end
    local text, source = ui_modes.text(entry)
    if not text and default_files[width] and layout ~= ten_player_layout then text, source = ui_modes.text({file = default_files[width]}) end
    -- A file that is not a mode file (a wrong decode that still looks like text) is not used.
    if text and source == "file" and not text:find("<menu_control>", 1, true) then text = nil end
    if not text and width == wide_1018_width and layout ~= ten_player_layout then text, source = require("base/game/mode2_builtin"), "builtin" end
    sources[layout] = source or false
    return text, source
end

-- Is the layout offered to the player? Every layout is, except the 10 player one while its mode is locked or the game
-- has no mode3.dat.
local allowed_cache = {}   -- layout -> the mode entry whose file can be read, or false
function ui_modes.layout_allowed(layout)
    if layout ~= ten_player_layout then return true end
    local entry = allowed_cache[layout]
    if entry == nil then
        local listing = data_text.read(list_path)
        local found = entry_for(layout, listing and ui_modes.parse(listing) or nil, wide_1018_width)
        entry = found and ui_modes.text(found) and found or false
        allowed_cache[layout] = entry
    end
    return entry ~= false and permitted(entry.hidden)
end

-- "host", "file", "builtin" or nil: where the layout's mode text comes from (remembered by layout_text; read once for a
-- layout it has not seen). For the notice on the options page.
function ui_modes.layout_source(layout)
    if sources[layout] == nil then ui_modes.layout_text(layout) end
    return sources[layout] or nil
end

-- Forgets what layout_source knows and the files decoded (tests, a host that reloads the game data).
function ui_modes.reset()
    sources = {}
    combo_cache = {}
    kill_cache = {}
    allowed_cache = {}
    data_text.reset()
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
        times = tonumber(block.times), respond = tonumber(block.respond), bound = tonumber(block.bound),
        facing = tonumber(block.facing), caughtact = tonumber(block.caughtact), effect = tonumber(block.effect)}
end

-- What the combo display of a battlefield layout needs: the <combo> block of the mode file that layout is made for
-- (classic and expand: mode1.dat, the 794 wide mode; wide layouts: their own), as {pic, w, h, offset_x, offset_y, times,
-- name} with defaults filled in; nil when the mode has no <combo>, switched it off (`bound: 0`) or names no picture.
function ui_modes.combo_settings(layout)
    local key = tostring(layout)
    if combo_cache[key] ~= nil then return combo_cache[key] or nil end
    local width = ui_modes.layout_width(layout) or classic_width
    local listing = data_text.read(list_path)
    local entry = entry_for(layout, listing and ui_modes.parse(listing) or nil, width)
    local text = entry and ui_modes.text(entry) or nil
    local block = text and ui_modes.combo(text) or nil
    local settings = false
    if block and block.bound ~= 0 and block.pic and block.pic ~= "" then
        settings = {pic = block.pic, w = block.w or 15, h = block.h or 15, offset_x = block.offset_x or 0, offset_y = block.offset_y or 0,
            times = block.times or 30, name = (block.name and block.name ~= "") and block.name or "%d_hit", facing = block.facing or 1}
    end
    combo_cache[key] = settings
    return settings or nil
end

-- The kill display (readme/mode dat.txt, "CUSTOM NAME DISPLAY OF WHO KILLED WHOM"): the first <bmp_begin> block of a mode file.
-- `mode` and `id` may repeat (the game modes it shows in, at most 20 excluded object ids), which mode_layout.blocks (first value
-- of a key only) cannot give, so the block is read here line by line. Picture and sound names come back with "/" and lower case.
-- nil when the file has no such block.
local kill_numbers = {"bound", "respond", "times", "loop", "y", "x", "dx", "dvx", "arest", "vrest", "caughtact", "catchingact",
    "pickedact", "pickingact", "transparency"}
function ui_modes.kill_board(text)
    local inside, found = false, nil
    for line in (text or ""):gmatch("[^\r\n]+") do
        local tag = line:match("^%s*<([%w_]+)>%s*$")
        if tag == "bmp_begin" and not found then inside, found = true, {modes = {}, ids = {}, pics = {}}
        elseif tag == "bmp_end" and inside then break
        elseif inside then
            local key, value = line:match("^%s*([%w_]+)%s*:%s*(.-)%s*$")
            if key then
                local number = tonumber(value:match("^(-?%d+)"))
                if key == "mode" then
                    if number then found.modes[#found.modes + 1] = number end
                elseif key == "id" then
                    if number and #found.ids < 20 then found.ids[#found.ids + 1] = number end
                elseif key:match("^pic_type[0-6]$") or key == "sound1" or key == "sound2" then
                    local name = value:gsub("%s*;.*$", ""):gsub("\\", "/"):lower()
                    if name ~= "" then
                        if key:sub(1, 3) == "pic" then found.pics[tonumber(key:sub(-1))] = name else found[key] = name end
                    end
                elseif found[key] == nil and number then
                    for _, known in ipairs(kill_numbers) do if known == key then found[key] = number end end
                end
            end
        end
    end
    return found
end

-- What the kill display of a battlefield layout needs, from the mode file of that layout (classic and expand: mode1.dat, as the
-- combo): nil when the file has no block or `bound: 0`; otherwise {times, loop, max_rows, y, x, dx, dvx, arest, vrest, attacker_name,
-- victim_name, attacker_back, victim_back, transparent, pics = {[0..6] = path}, modes = {[mode] = true} or nil (every mode),
-- ids = {[id] = true}, sound1, sound2}. [BELUM PASTI] `respond` (no comment in the readme) is taken as the most entries shown
-- at once (5 when absent).
function ui_modes.kill_settings(layout)
    local key = tostring(layout)
    if kill_cache[key] ~= nil then return kill_cache[key] or nil end
    local width = ui_modes.layout_width(layout) or classic_width
    local listing = data_text.read(list_path)
    local entry = entry_for(layout, listing and ui_modes.parse(listing) or nil, width)
    local text = entry and ui_modes.text(entry) or nil
    local block = text and ui_modes.kill_board(text) or nil
    local settings = false
    if block and block.bound ~= 0 then
        local modes, ids = nil, {}
        if #block.modes > 0 then modes = {} for _, mode in ipairs(block.modes) do modes[mode] = true end end
        for _, id in ipairs(block.ids) do ids[id] = true end
        settings = {times = block.times or 70, loop = block.loop or 40, max_rows = (block.respond and block.respond > 0) and block.respond or 5,
            y = block.y or 0, x = block.x or 0, dx = block.dx or 0, dvx = block.dvx or 0, arest = block.arest == 1, vrest = block.vrest == 1,
            attacker_name = block.caughtact == 1, victim_name = block.catchingact == 1,
            attacker_back = block.pickedact == 1, victim_back = block.pickingact == 1, transparent = block.transparency == 1,
            pics = block.pics, modes = modes, ids = ids, sound1 = block.sound1, sound2 = block.sound2}
    end
    kill_cache[key] = settings
    return settings or nil
end

return ui_modes
