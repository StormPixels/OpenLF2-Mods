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
    local list, current, given = {}, nil, false
    for line in (text or ""):gmatch("[^\r\n]+") do
        local tag = line:match("^%s*<([%w_]+)>")
        if tag == "mode_information" then
            current = {hidden = 0, respond = classic_width}
            given = false
        elseif tag == "mode_information_end" then
            if current and current.file then
                -- A block with a `width:` and no `respond:` (`width: 1333 height: 730`) answers to that width.
                if current.width and not given then current.respond = current.width end
                list[#list + 1] = current
            end
            current = nil
        elseif current then
            for key, value in line:gmatch("([%w_]+)%s*:%s*(%S+)") do
                if key == "file" then current.file = value:gsub("\\", "/"):lower()
                elseif key == "name" then current.name = value
                elseif key == "hidden" or key == "respond" or key == "width" or key == "height" then
                    local number = tonumber(value)
                    -- `width:` and `height:` are the picture's size in pixels (1 to 8192, the renderer's limit).
                    local sized = key == "width" or key == "height"
                    if number and (key == "hidden" or (number >= 1 and (not sized or number <= 8192))) then
                        current[key] = number
                        if key == "respond" then given = true end
                    end
                end
            end
        end
    end
    return list
end

-- The modes of the game's data/mode.dat in file order, cached ({} when the game has none). Each entry also gets `key` (the
-- value the "battlefield_layout" option stores: "mode:<file>", with "#2", "#3" ... for a file listed again) and `label`
-- (what the options page shows: its `name`, else the file's name).
local layout_prefix = "mode:"
local entries_cache
function ui_modes.entries()
    if entries_cache then return entries_cache end
    local listing = data_text.read(list_path)
    local list = listing and ui_modes.parse(listing) or {}
    local seen = {}
    for _, entry in ipairs(list) do
        local count = (seen[entry.file] or 0) + 1
        seen[entry.file] = count
        entry.key = layout_prefix .. entry.file .. (count > 1 and ("#" .. count) or "")
        entry.label = entry.name or entry.file:match("([^/]+)%.dat$") or entry.file
    end
    entries_cache = list
    return list
end

local function is_mode3(entry)
    return entry ~= nil and entry.file ~= nil and entry.file:match("mode3%.dat$") ~= nil
end

-- The key of a layout as it is now: "classic" and "expand" (built into the code), an entry's key of mode.dat, or nil when
-- the game has no such entry. The names older versions saved ("wide 1333", "wide 1018", "wide 1018 10P") are mapped to the
-- entry that is made for that picture.
function ui_modes.resolve(layout)
    if layout == "classic" or layout == "expand" then return layout end
    if type(layout) ~= "string" then return nil end
    local list = ui_modes.entries()
    for _, entry in ipairs(list) do
        if entry.key == layout then return entry.key end
    end
    local width = (layout == "wide 1333" and constants.screen.wide_width) or (layout == "wide 1018" and wide_1018_width) or nil
    if width then
        for _, entry in ipairs(list) do
            if entry.respond == width and not is_mode3(entry) then return entry.key end
        end
    elseif layout == "wide 1018 10P" then
        for _, entry in ipairs(list) do
            if is_mode3(entry) then return entry.key end
        end
    end
    return nil
end

-- The mode.dat entry of a layout; nil for classic, expand and a layout the game does not have.
local function entry_of(layout)
    local key = ui_modes.resolve(layout)
    if not key or key == "classic" or key == "expand" then return nil end
    for _, entry in ipairs(ui_modes.entries()) do
        if entry.key == key then return entry end
    end
    return nil
end
ui_modes.entry_of = entry_of

-- The mode file the menus, combo and kill display of a layout are read from: its own entry, and for classic and expand
-- (or a layout that is gone) the first mode made for the classic width (mode1.dat).
local function entry_for_layout(layout)
    return entry_of(layout) or ui_modes.for_width(ui_modes.entries(), classic_width)
end

-- The picture width a battlefield layout draws the menus on; nil for a layout this module does not know (and expand).
function ui_modes.layout_width(layout)
    if layout == "classic" then return classic_width end
    local entry = entry_of(layout)
    return entry and entry.respond or nil
end

-- Does the layout have ten player slots? (the mode of mode3.dat)
function ui_modes.is_ten(layout)
    return is_mode3(entry_of(layout))
end
-- How many player slots a layout has: 10 in the 10 player layout, 8 otherwise.
function ui_modes.slot_count(layout)
    return ui_modes.is_ten(layout) and 10 or 8
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

-- A wide layout's mode file when its own cannot be read.
local default_files = {[constants.screen.wide_width] = "data/mode/mode4.dat"}

-- May a `hidden:` value be used? 0 always; others by game/unlock.allows (nothing when the game lacks it).
local function permitted(hidden)
    hidden = hidden or 0
    if hidden == 0 then return true end
    local ok, unlock = pcall(require, "base/game/unlock")
    return ok and type(unlock) == "table" and type(unlock.allows) == "function" and unlock.allows(hidden) == true
end
local sources = {}
local combo_cache = {}   -- ui_modes.combo_settings, per layout
local kill_cache = {}    -- ui_modes.kill_settings, per layout
-- The mode file text of a battlefield layout and where it came from: "host" or "file" (the game's own file) or
-- "builtin" (the layout blocks that are part of OpenLF2, used when the game's file cannot be read; only for a 1018 wide
-- layout). nil in the classic layouts (the built-in menu stands) and when there is nothing to read.
function ui_modes.layout_text(layout)
    local width = ui_modes.layout_width(layout)
    if not width or width == classic_width then return nil end
    local entry = entry_of(layout)
    local ten = is_mode3(entry)
    if ten and not permitted(entry.hidden) then sources[layout] = false return nil end
    local text, source = ui_modes.text(entry)
    if not text and default_files[width] and not ten then text, source = ui_modes.text({file = default_files[width]}) end
    -- A file that is not a mode file (a wrong decode that still looks like text) is not used.
    if text and source == "file" and not text:find("<menu_control>", 1, true) then text = nil end
    if not text and width == wide_1018_width and not ten then text, source = require("base/game/mode2_builtin"), "builtin" end
    sources[layout] = source or false
    return text, source
end

-- The picture size mode.dat gives a layout's mode (`width:` and `height:` of its <mode_information> block, as LF2
-- Darkfiren reads it): width, height. Either is nil when the block lacks it, or when there is no block, no list or no
-- such layout: the caller keeps its built-in size then.
function ui_modes.layout_size(layout)
    local width = ui_modes.layout_width(layout)
    if not width then return nil, nil end
    local entry = entry_for_layout(layout)
    if not entry then return nil, nil end
    return entry.width, entry.height
end

-- Is the layout offered to the player? classic and expand always; a mode of mode.dat too, except the 10 player one while
-- its mode is locked or its file cannot be read.
local allowed_cache = {}   -- layout -> true or false
function ui_modes.layout_allowed(layout)
    local entry = entry_of(layout)
    if not entry then return layout == "classic" or layout == "expand" end
    if not is_mode3(entry) then return true end
    local allowed = allowed_cache[layout]
    if allowed == nil then
        allowed = ui_modes.text(entry) ~= nil
        allowed_cache[layout] = allowed
    end
    return allowed and permitted(entry.hidden)
end

-- What the "Battlefield layout" row offers: classic and expand (built into the code, so the game never has to have
-- a mode.dat), then every mode of the game's data/mode.dat in file order.
function ui_modes.layout_choices()
    local list = {"classic", "expand"}
    for _, entry in ipairs(ui_modes.entries()) do
        if ui_modes.layout_allowed(entry.key) then list[#list + 1] = entry.key end
    end
    return list
end

-- The text the options page shows for a layout: the name mode.dat gives the mode; nil for classic and expand (the caller
-- translates those).
function ui_modes.layout_label(layout)
    local entry = entry_of(layout)
    return entry and entry.label or nil
end

-- The layout a game starts with when nothing is saved yet: the first mode of mode.dat that may be chosen; classic when
-- the game has no mode.dat.
function ui_modes.default_layout()
    for _, entry in ipairs(ui_modes.entries()) do
        if ui_modes.layout_allowed(entry.key) then return entry.key end
    end
    return "classic"
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
    entries_cache = nil
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
    local entry = entry_for_layout(layout)
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
    local entry = entry_for_layout(layout)
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
            pics = block.pics, modes = modes, ids = ids, sound1 = block.sound1, sound2 = block.sound2, checkbox = block.bound == 1}
    end
    kill_cache[key] = settings
    return settings or nil
end

-- The values of a key written several times in a block (`mode: 2` and `mode: 3` of <menu_control>): the list in file order, {} when
-- the block or the key is missing. Comments (`;` and `#`) are cut.
function ui_modes.repeated(text, tag, key)
    local found, inside = {}, false
    for line in (text or ""):gmatch("[^\r\n]+") do
        local open = line:match("^%s*<([%w_]+)>")
        if open == tag then inside = true
        elseif open == tag .. "_end" or (open and open:sub(-4) == "_end") then inside = false
        elseif inside then
            local value = line:gsub("[;#].*$", ""):match("^%s*" .. key .. "%s*:%s*(-?%d+)")
            if value then found[#found + 1] = tonumber(value) end
        end
    end
    return found
end

return ui_modes
