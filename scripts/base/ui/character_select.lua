-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local constants = require("base/game/constants")
local option_rows = constants.match_option_rows
local slot_phases = constants.character_slot_phases
local menus = constants.character_menus
local catalog = require("base/game/catalog")
local background = require("base/game/background")
local font = require("base/ui/font")
local i18n = require("base/i18n/i18n")
local sounds = require("base/game/sounds")
local controls = require("base/ui/controls")
local music = require("base/game/music")
local user_options = require("base/game/options")
local unlock = require("base/game/unlock")
local system_data = require("base/game/system_data")
local selection = {}
local idle_countdown = 150
local computer_phase, computer_team_phase, computer_done = slot_phases.computer_fighter, slot_phases.computer_team, slot_phases.computer_ready

-- LF2 Darkfiren's 8P super widescreen (mode4.dat): the eight slots stand in one row on CHARMENU3 (start_x 10,
-- 30 left of the classic 40) and every offset inside a slot stays as in the classic two rows of four.
-- The numbers below are what mode4.dat gives; selection.create takes the file's own (game/mode_layout.lua), so
-- these only stand when the file is missing or has no such tag.
local mode_layout = require("base/game/mode_layout")
local cost_rules = require("base/game/cost")
local stage_levels = require("base/game/stage_levels")
local menu_small = require("base/game/menu_small")
local ui_modes = require("base/game/ui_modes")
local object_data = require("base/game/object_data")
-- A fighter's data file is read once for everything the menu takes from it (skins, <phase>, <menu_face>).
local data_cache = {}
local function loaded_data(path)
    local entry = data_cache[path]
    if entry == nil then
        local ok, data = pcall(object_data.load, path)
        entry = {ok, data}
        data_cache[path] = entry
    end
    return entry[1], entry[2]
end
local layout_targets = {}
-- The options panel as LF2 Darkfiren draws it: the <menu_small> layers of mode4.dat (game/menu_small.lua).
local small_layers = {}
local small_modes = {}   -- <mode> of the mode file: {[layer] = {name, hex}} (difficulty, hitlag and TU names)
-- <misc> of mode4.dat: the music line (position, colours) and the small picture of the chosen background in its frame
-- (position, frame picture, on or off). 1142 is where the classic menu's music line lands in the wide picture.
local misc = {music_x = 1142, music_y = 3, music_title = 0x5a77d8, music_hint = 0x223fa0, frame_x = 531, frame_y = 4,
    small_x = 538, small_y = 11, show_small = 0, frame_pic = "sprite/ui/menu_clip2b.bmp", allow_defense = 0}
layout_targets.misc = misc
-- LF2 Darkfiren <time> of mode4.dat: the time limits (seconds) the wide options menu offers, and who wins.
local time_list, time_type = {}, 1
-- LF2 Darkfiren <cost> of mode4.dat: the pools the options menu offers and the prices (cost mode).
local cost_settings = {kind = 100, pools = {}, groups = {}}
local cost_in_mode   -- defined with the options panel below; the slot drawing needs it too
local cmb_known = {}
local per_row, shift, step_x, step_y = 4, 0, 153, 212
local ABSENT = -99999   -- "the file does not write this tag" (mode_layout.apply only takes a value of the type of the default)
local menu = {pic = "sprite/ui/charmenu3.bmp", x = 10, y = 33, row = 8, step_x = 153, step_y = 212,
    face_x = ABSENT, face_y = ABSENT, name_x = ABSENT, name_y = ABSENT, fighter_x = ABSENT, fighter_y = ABSENT, team_x = ABSENT, team_y = ABSENT,
    name_hide = ABSENT, bound = ABSENT, flag0 = "", flag1 = "", flag2 = "", flag3 = "", flag4 = "",
    -- cost mode (LF2 Darkfiren update 17): the price above a portrait (left x, y) and the backup mark of a team 1 to 5 member
    cost_x = ABSENT, cost_y = ABSENT, team_cmb_x = ABSENT, team_cmb_y = ABSENT,
    team1_cmb = "", team2_cmb = "", team3_cmb = "", team4_cmb = "", team5_cmb = ""}
-- The places of a slot's pictures and texts from its corner (x) and from its row (y): the classic menu's own, in the wide menu the
-- mode file's face_x, name_x, fighter_x, team_x (the place of the first slot on the screen: value - start_x + 40 from the corner,
-- as the corner is start_x - 40 from the classic one) and the y values as they are. A tag the file lacks keeps the classic place.
local places = {face_dx = 147, face_dy = 94, cost_dx = 180, cost_dy = 77, cmb_dx = 147, cmb_dy = 94, cmb = {}, name_dx = 177, name_y = 219, fighter_dx = 177, fighter_y = 241, team_dx = 167, team_y = 263,
    name_hide = false, same_allowed = true, flags = {}}
local function set_places(wide, modes)
    local function across(tag, default) local v = menu[tag] return (wide and type(v) == "number" and v ~= ABSENT) and v - menu.x + 40 or default end
    local function down(tag, default) local v = menu[tag] return (wide and type(v) == "number" and v ~= ABSENT) and v or default end
    places.face_dx, places.face_dy = across("face_x", 147), down("face_y", 94)
    -- cost_x is the left edge of the price text; unwritten, it is 33 right of the face and 17 above it (the update 17 default 180, 77)
    places.cost_dx, places.cost_dy = across("cost_x", places.face_dx + 33), down("cost_y", places.face_dy - 17)
    places.cmb_dx, places.cmb_dy = across("team_cmb_x", places.face_dx), down("team_cmb_y", places.face_dy)
    for team = 1, 5 do
        local path = wide and menu["team" .. team .. "_cmb"] or ""
        places.cmb[team] = path ~= "" and (path:gsub("\\", "/"):lower()) or nil
    end
    places.name_dx, places.name_y = across("name_x", 177), down("name_y", 219)
    places.fighter_dx, places.fighter_y = across("fighter_x", 177), down("fighter_y", 241)
    places.team_dx, places.team_y = across("team_x", 167), down("team_y", 263)
    places.name_hide = wide and menu.name_hide == 1
    -- `bound` 0: the same fighter may not be chosen twice (in the modes of the `mode:` lines, all without any); 1 or no tag: allowed.
    places.same_allowed = true
    if wide and menu.bound == 0 then
        local applies = not modes or #modes == 0
        for _, mode in ipairs(modes or {}) do if mode == places.mode then applies = true end end
        places.same_allowed = not applies
    end
    for team = 0, 4 do
        local path = wide and menu["flag" .. team] or ""
        places.flags[team] = path ~= "" and (path:gsub("\\", "/"):lower()) or nil
    end
end
layout_targets.menu = menu
local function origin(slot)
    return (slot % per_row) * step_x + shift, math.floor(slot / per_row) * step_y
end
local wide_known = {}
-- The wide menu needs the wide battlefield layout and a game that has the picture (LF2 Darkfiren).
-- Only the 1333 layout may do without a mode file (the built-in values are mode4.dat's); the other widths need theirs.
local function wide_wanted(width, mode_text)
    if not width then return false end
    if width ~= constants.screen.wide_width and not mode_text then return false end
    if wide_known[menu.pic] == nil then wide_known[menu.pic] = pcall(engine.read_resource, menu.pic) end
    -- The classic menu picture is in the game's resources, not always a file of its own: the classic layout draws it
    -- as pe/charmenu, and mode2.dat names the same picture.
    if not wide_known[menu.pic] and menu.pic:match("charmenu%.bmp$") then
        menu.pic = "pe/charmenu"
        if wide_known[menu.pic] == nil then wide_known[menu.pic] = pcall(engine.read_resource, menu.pic) end
    end
    return wide_known[menu.pic]
end
local function use_layout(state)
    if state.wide then per_row, shift, step_x, step_y = menu.row, menu.x - 40, menu.step_x, menu.step_y
    else per_row, shift, step_x, step_y = 4, 0, 153, 212 end
    places.mode = state.mode
    set_places(state.wide, state.menu_modes)
end
local function pressed(keys, key) return keys:find(key, 1, true) ~= nil end
-- What the wide menu adds to the classic 794 wide pictures: popup_gap is the extra width (for things at the right edge) and
-- state.dx, set while a popup is drawn, moves everything the helpers draw (a popup is laid out for 794 and sits in the middle).
local function popup_gap(state)
    if not state.wide then return 0 end
    return (state.width or constants.screen.wide_width) - constants.screen.width
end
local function image(state, path, x, y) state.display[#state.display + 1] = {"image", path, x + (state.dx or 0), y} end
-- With black as the transparent colour (the options panel rows).
local function keyed_image(state, path, x, y) state.display[#state.display + 1] = {"image", path, x + (state.dx or 0), y, true} end
local white, computer_red, option_blue = 0xffffff, 0xff9b9b, 0x9b9bff
local music_title, music_hint = 0x5a77d8, 0x223fa0
local count_greyed, count_box = 0x5068c0, 0x2f479f
-- The blinking text moves from `from` to `to` in 6 steps of the counter; `done` is the text of a confirmed choice. These are
-- the built-in colours (from (25, 70, 255) to (175, 220, 255), red and green stepping up by 30; white): selection.create sets
-- them again for each visit and takes the <TCo> block of the mode file (Hex1, Hex2, Hex3) over them.
local tco = {from = 0x1946ff, to = 0xafdcff, done = 0xffffff}
local function blink_color(state)
    local step, color = state.blink % 6, 0
    for _, shift in ipairs({65536, 256, 1}) do
        local a, b = math.floor(tco.from / shift) % 256, math.floor(tco.to / shift) % 256
        color = color + math.floor(a + (b - a) * step / 5 + 0.5) * shift
    end
    return color
end
local function text(state, value, x, y, color, background, align)
    state.display[#state.display + 1] = {"text", value, x + (state.dx or 0), y, color, background, align}
end
-- The name field below a slot. Translated text is centered in its black area; the original's bitmap text
-- starts at a fixed column, padded with spaces.
-- A text of a slot: its place is `offset` from the slot's corner and `y` (the name's by default), centred on `center` when a language
-- is active (the name and the fighter 30 pixels on from their x, the team 40 from its x).
local function slot_text(state, value, col, row, color, y, offset, center)
    local x = i18n.active() and col + (center or places.name_dx + 30)
    if x then text(state, i18n.tr(value):match("^%s*(.-)$"), x, y or row + places.name_y, color, nil, "center")
    else text(state, value, col + (offset or places.name_dx), y or row + places.name_y, color) end
end
local function sprite(state, path, rectangle, x, y, keyed)
    state.display[#state.display + 1] = {"sprite", path, rectangle, x + (state.dx or 0), y, keyed}
end
local function fill(state, x, y, width, height, gray)
    state.display[#state.display + 1] = {"fill", x + (state.dx or 0), y, width, height, gray}
end

-- LF2 Darkfiren's <random> of mode4.dat: the ids a random pick may give. Without it (and in the other menus) the
-- original's rule holds: the fighters before the enemies.
local function load_random_pool()
    local ok, text = pcall(engine.read_resource, "game/random_pool")
    local pool, count = {}, 0
    for id in (ok and text or ""):gmatch("%d+") do pool[tonumber(id)] = true; count = count + 1 end
    return count > 0 and pool or nil
end
local layout_defaults
local function reset_layout()
    if not layout_defaults then
        layout_defaults = {}
        for name, target in pairs(layout_targets) do
            local copy = {}
            for key, value in pairs(target) do copy[key] = value end
            layout_defaults[name] = copy
        end
        return
    end
    for name, copy in pairs(layout_defaults) do
        for key, value in pairs(copy) do layout_targets[name][key] = value end
    end
end
function selection.create(options)
    local previous = options.previous or {}
    local mode = assert(constants.modes[options.mode], "unknown character menu mode")
    local slots = {}
    for slot = 0, 9 do   -- ten slots exist; state.slot_count (8 or 10, by the layout) says how many are used
        -- Teams persist between visits except where the mode prescribes them.
        local team = previous.slots and previous.slots[slot] and previous.slots[slot].team or 0
        if mode == constants.modes.stage then team = constants.teams.player_one
        elseif mode == constants.modes.battle then team = math.floor(slot / 4) + 1 end
        slots[slot] = {phase = slot_phases.empty, fighter = 0, team = team, latched = true, ready = false}
    end
    -- Option values are globals in the original and keep their values between visits.
    local options = previous.options or {small_row = 1, hide_random = false, time_index = 0, cost_index = 0, item_drops = true, allow_transform = true, shuffle = false, row = option_rows.reroll, background = constants.background_rows.random, random_background = true,
        difficulty = 0, music = 0, stage_level = 0}
    -- mode4.dat's positions (only the wide layout draws with them); the built-in values come back first, so a file
    -- that lacks a tag (or is gone) leaves the built-in one.
    reset_layout()
    tco.from, tco.to, tco.done = 0x1946ff, 0xafdcff, white
    time_list, time_type = {}, 1
    cost_settings = {kind = 100, pools = {}, groups = {}}
    small_layers, small_modes = {}, {}
    local mode_text, mode_source
    local layout_name = user_options.current().battlefield_layout
    local width = user_options.wide_width(layout_name)
    if width then
        mode_text, mode_source = ui_modes.layout_text(layout_name)
        if mode_text then
            mode_layout.apply(mode_text, layout_targets)
            time_type, time_list = mode_layout.time_limits(mode_text)
            cost_settings = mode_layout.cost_settings(mode_text)
            -- `bound: 1` of <cost> (readme/mode dat.txt): the cost mode is on by default, with the first pool, in the modes the block names
            -- (`mode:` lines; all of them when it names none), until the player changes it. A menu that comes back keeps its choice.
            -- OpenLF2 option: the cost mode starts Off even when the mod's `bound: 1` asks for it.
            if false and not previous.options and cost_settings.bound == 1 and #cost_settings.pools > 0 then
                local listed = #cost_settings.modes == 0
                for _, listed_mode in ipairs(cost_settings.modes) do if listed_mode == mode then listed = true end end
                if listed then options.cost_index = 1 end
            end
            small_layers = menu_small.parse(mode_text)
            small_modes = menu_small.parse_modes(mode_text)
            local from, to, done = mode_layout.text_colors(mode_text)
            tco.from, tco.to, tco.done = from or tco.from, to or tco.to, done or tco.done
        end
    end
    local state = {mode = mode, fighters = catalog.load(), backgrounds = catalog.backgrounds(),
        slots = slots, menu = menus.human_slots, last_menu = menus.human_slots, options = options,
        countdown = idle_countdown, computers = previous.computers or -100,
        order = {}, cursor = 0, previous_random = false, blink = 0, display = {}, wide = wide_wanted(width, mode_text)}
    state.width = state.wide and width or nil
    -- The size mode.dat gives the chosen layout's mode (`width:` and `height:` of its <mode_information>), as LF2 Darkfiren
    -- reads it. Without one, or when a wide layout fell back to the classic menu, the built-in size stands.
    state.height = constants.screen.height
    if not width or state.wide then
        local file_width, file_height = ui_modes.layout_size(layout_name)
        if file_height then state.height = file_height end
        if state.wide and file_width then state.width = file_width end
    end
    state.menu_modes = state.wide and mode_text and ui_modes.repeated(mode_text, "menu_control", "mode") or nil
    -- <background> of the mode file (readme/mode dat.txt, "NEW image display at charmenu with d key"): D (defend) shows the picture `pic`
    -- at (x, y) for `bound` ticks (100 without it) while a player has not yet pressed A or J; another player pressing D shows it
    -- again. `transparency: 1` makes black clear. [BELUM PASTI] `respond` and `effect` (kept, not drawn differently).
    local hint = state.wide and mode_text and mode_layout.blocks(mode_text).background or nil
    if type(hint) == "table" and type(hint.pic) == "string" and hint.pic ~= "" then
        state.hint = {pic = hint.pic, x = type(hint.x) == "number" and hint.x or 0, y = type(hint.y) == "number" and hint.y or 0,
            ticks = type(hint.bound) == "number" and hint.bound > 0 and hint.bound or 100, transparency = hint.transparency == 1}
    end
    -- Ten player slots only in the 10 player layout, and only when it really drew (a layout that fell back is the classic menu).
    -- A championship has eight entrants whatever the layout: it keeps the eight slots in the 10 player layout.
    local championship = mode == constants.modes.championship or mode == constants.modes.team_championship
    state.slot_count = not championship and state.wide and user_options.slot_count and user_options.slot_count(layout_name) or 8
    -- The 10 player mode (mode3.dat) has no <grid_char>: no roster of faces, panel or taps (championship included).
    state.no_roster = state.wide and ui_modes.is_ten(layout_name) or nil
    -- LF2 Darkfiren shows the chosen background's preview at the top right in the 10 player layout too.
    if state.no_roster then misc.show_small = 1 end
    if mode == constants.modes.battle and state.slot_count == 10 then
        for slot = 0, 9 do slots[slot].team = math.floor(slot / 5) + 1 end   -- two sides of five
    end
    -- The player cannot read the log: a wide layout that is not drawn as chosen says so on the screen.
    if width and not state.wide then state.layout_note = "Wide " .. width .. ": layout files not found, classic menu"
    elseif width and mode_source == "builtin" then state.layout_note = "Wide " .. width .. ": built-in layout (mode2.dat not read)" end
    state.random_pool = state.wide and (ui_modes.random_pool(mode_text) or load_random_pool()) or nil
    return state
end

local function pick_fighter(state)
    local function candidates_for(pool, repeats)
        local list = {}
        for index, fighter in ipairs(state.fighters) do
            local allowed
            if pool then allowed = pool[fighter.id] and catalog.selectable(fighter)
            else allowed = fighter.id < constants.record_id_ranges.random_fighter_end_exclusive end
            if fighter.record >= 1 and allowed then
                local taken = false
                -- `repeats`: the same fighter may be picked twice (fewer fighters than slots, e.g. 10 players).
                for slot = 0, (state.slot_count or 8) - 1 do
                    if not repeats and state.slots[slot].fighter == index then taken = true end
                end
                if not taken then list[#list + 1] = index end
            end
        end
        return list
    end
    local candidates = state.random_pool and candidates_for(state.random_pool) or {}
    if #candidates == 0 then candidates = candidates_for(nil) end
    -- OpenLF2 change: with fewer fighters than slots (10 players) allow repeats instead of crashing.
    if #candidates == 0 and state.random_pool then candidates = candidates_for(state.random_pool, true) end
    if #candidates == 0 then candidates = candidates_for(nil, true) end
    -- The original would read an uninitialized candidate here.
    assert(#candidates > 0, "no fighter left for a random pick")
    return candidates[engine.random(#candidates) + 1]
end
local function resolve_random(state)
    for index = 0, (state.slot_count or 8) - 1 do state.slots[index].was_random = state.slots[index].fighter == 0 end
    for index = 0, (state.slot_count or 8) - 1 do
        local slot = state.slots[index]
        if slot.was_random then slot.fighter, slot.skin = pick_fighter(state), nil end
    end
end

-- Fighter 0 is Random; others index the catalog in file order.
-- LF2 Darkfiren skins (readme/dat file/skin system.txt): "D" (the defend key, letter "f") cycles the skins of the fighter
-- being chosen, in every mode but the championships. The skins come from the fighter's own data (record.data.skins, read
-- when a fighter is first asked for and remembered); a fighter with fewer than two skins or `random: 1` has nothing to
-- cycle. The choice is slot.skin (1..10) for the fighter slot.skin_for; the match gets it as options.slots[slot].skin
-- (game/st_spawn.lua turns it into value.pic_offset).
local skin_cache = {}
local function skins_of(fighter)
    if not fighter or type(fighter.path) ~= "string" then return nil end
    local cached = skin_cache[fighter.path]
    if cached == nil then
        local ok, data = loaded_data(fighter.path)
        local skins = ok and type(data) == "table" and data.skins or nil
        local count = 0
        if type(skins) == "table" then for index = 1, 10 do if skins[index] then count = index end end end
        cached = (count >= 2 and skins.random ~= 1) and {skins = skins, count = count} or false
        skin_cache[fighter.path] = cached
    end
    return cached or nil
end
-- The skin chosen for the fighter now in the slot (nil: the fighter's own look).
local function chosen_skin(slot)
    if slot.skin and slot.skin_for == slot.fighter then return slot.skin end
    return nil
end
-- The sound of changing the skin: `sound:` of the fighter's <skins> (readme/skin system.txt) when the game has that file, else
-- the menu's "join".
local sound_known = {}
local function play_file(state, path)
    if type(path) ~= "string" then return false end
    path = path:gsub("\\", "/"):lower()
    if path == "" then return false end
    if sound_known[path] == nil then sound_known[path] = pcall(engine.read_resource, path) end
    if not sound_known[path] then return false end
    state.direct_sounds = state.direct_sounds or {}
    state.direct_sounds[#state.direct_sounds + 1] = path
    return true
end
local function skin_sound(state, info)
    if not play_file(state, info.skins.sound) then sounds.direct(state, "join") end
end
local function next_skin(state, slot)
    if state.mode == constants.modes.championship or state.mode == constants.modes.team_championship then return end
    local info = skins_of(state.fighters[slot.fighter])
    if not info then return end
    slot.skin, slot.skin_for = (chosen_skin(slot) or 1) % info.count + 1, slot.fighter
    skin_sound(state, info)
end
local function skin_picture(fighter, slot, key)
    local index = chosen_skin(slot)
    local info = index and skins_of(fighter)
    local skin = info and info.skins[index]
    local path = skin and skin[key]
    if type(path) ~= "string" then return nil end
    return (path:gsub("\\", "/"):lower())
end

-- Changing the fighter forgets the skin (coming back to a fighter does not bring the old skin back).
-- `bound: 0` of <menu_control> (for the modes of its `mode:` lines): the same fighter may not be chosen by two slots, so the
-- stepping jumps over a fighter another slot has (Random, 0, is always free). Without the tag or with `bound: 1` anyone may be taken.
local function step_fighter(state, slot, direction)
    local position = slot.fighter
    for _ = 0, #state.fighters + 1 do
        position = catalog.step(state.fighters, position, direction)
        local taken = false
        if not places.same_allowed and position ~= 0 then
            for index = 0, state.slot_count - 1 do
                local other = state.slots[index]
                if other ~= slot and other and other.phase >= slot_phases.choosing_fighter and other.fighter == position then taken = true end
            end
        end
        if not taken then break end
    end
    slot.fighter, slot.skin = position, nil
end
local function next_fighter(state, slot) step_fighter(state, slot, 1) end
local function previous_fighter(state, slot) step_fighter(state, slot, -1) end

-- Extra pictures over a fighter's face in the menu (<menu_face> of its data, readme/dat file/menu face.txt, up to 30 layers): each
-- layer `pic` (source dx, dy; w x h) at (x, y) from the face picture's corner, `amount` copies `loop` pixels apart; `respond`
-- 0 both, 1 human, 2 computer slots; `transparency` 1 keys it; cc, c1, c2 blink it (hidden outside c1..c2 of every cc ticks).
-- `facing` is "no use" in the game's own table and is not read. [BELUM PASTI] the anchor (the face picture's corner).
local menu_face_cache = {}
local function menu_face_of(fighter)
    if not fighter or type(fighter.path) ~= "string" then return nil end
    local cached = menu_face_cache[fighter.path]
    if cached == nil then
        local ok, data = loaded_data(fighter.path)
        local display = ok and type(data) == "table" and type(data.display) == "table" and data.display.menu_face or nil
        cached = type(display) == "table" and type(display.layers) == "table" and #display.layers > 0 and display.layers or false
        menu_face_cache[fighter.path] = cached
    end
    return cached or nil
end
-- Cost mode: a computer marked as backup (key D while its team is chosen) shows its team's mark; it only counts when a human
-- is in the same team (team 1 to 5), as in the u17 exe (0x4607C0).
local function backup_marked(state, slot)
    if not slot.backup or slot.phase < computer_phase then return false end
    if slot.team < constants.teams.player_one or slot.team > constants.teams.player_five then return false end
    for index = 0, (state.slot_count or 8) - 1 do
        local other = state.slots[index]
        if other ~= slot and other.phase >= slot_phases.choosing_fighter and other.phase < computer_phase and other.team == slot.team then return true end
    end
    return false
end
-- `bound: N` of a layer (update log 21 December 2024, "to match the layer animation with the skin number selected"): the layer is
-- shown only while skin N is worn (the fighter's own look is skin 1); 0 or no tag: every skin. [BELUM PASTI] this reading.
local function draw_menu_face(state, slot, fighter, x0, y0)
    local layers = menu_face_of(fighter)
    if not layers then return end
    local human = slot.phase < computer_phase
    local skin_number = chosen_skin(slot) or 1
    for index = 1, math.min(#layers, 30) do
        local layer = layers[index]
        local wanted = layer.respond == 1 and human or layer.respond == 2 and not human or (layer.respond ~= 1 and layer.respond ~= 2)
        local period = type(layer.cc) == "number" and math.floor(layer.cc) or 0
        local shown = period <= 0 or ((state.frames or 0) % period >= (layer.c1 or 0) and (state.frames or 0) % period <= (layer.c2 or 0))
        local skin_ok = type(layer.bound) ~= "number" or layer.bound <= 0 or layer.bound == skin_number
        if wanted and shown and skin_ok and type(layer.pic) == "string" and type(layer.w) == "number" and layer.w >= 1 and type(layer.h) == "number" and layer.h >= 1 then
            local picture = layer.pic:gsub("\\", "/"):lower()
            local copies = type(layer.amount) == "number" and layer.amount >= 1 and math.floor(layer.amount) or 1
            local spacing = type(layer.loop) == "number" and layer.loop or layer.w
            for copy = 0, copies - 1 do
                sprite(state, picture, {layer.dx or 0, layer.dy or 0, layer.w, layer.h}, x0 + (layer.x or 0) + copy * spacing, y0 + (layer.y or 0), layer.transparency == 1)
            end
        end
    end
end

local function draw_fighter(state, slot, col, row, color)
    local fighter = state.fighters[slot.fighter]
    -- The eye of Reset Random (LF2 Darkfiren): a fighter that came from Random stays unseen until the match.
    if state.options and state.options.hide_random and slot.was_random then fighter = nil end
    local head = fighter and skin_picture(fighter, slot, "head")
    if head and not pcall(engine.read_resource, head) then head = nil end   -- a picture the game lacks keeps the fighter's own
    image(state, head or (fighter and fighter.portrait) or "pe/rface", col + places.face_dx, row + places.face_dy)
    draw_menu_face(state, slot, fighter, col + places.face_dx, row + places.face_dy)
    -- Cost mode: the backup mark of the team and the fighter's price ("Cost: $100") above its portrait. A fighter hidden
    -- behind Random shows no price.
    if state.wide and state.options and (state.options.cost_index or 0) > 0 and cost_in_mode(state.mode) then
        local mark = backup_marked(state, slot) and places.cmb[slot.team] or nil
        if mark then
            if cmb_known[mark] == nil then cmb_known[mark] = pcall(engine.read_resource, mark) end
            if cmb_known[mark] then image(state, mark, col + places.cmb_dx, row + places.cmb_dy) end
        end
        if fighter then
            -- fighter.record is only the number of the catalog record; the fighter's own `cost:` is read by the catalog
            local own = tonumber(fighter.cost)
            local price = own and own > 0 and own or cost_rules.price({groups = cost_settings.groups, default = cost_settings.kind}, fighter.id, nil)
            -- Left edge at cost_x and always light blue, whatever the slot's blinking colour (as in the u17 video).
            text(state, string.format("Cost: $%d", price), col + places.cost_dx, row + places.cost_dy, 0x6e8fff)
        end
    end
    slot_text(state, fighter and fighter.name or " Random", col, row, color, row + places.fighter_y, places.fighter_dx, places.fighter_dx + 30)
end
local flag_known = {}
-- team0_flag (independent) to team4_flag of <menu_control>: a picture in place of the text, at the place of the team text.
local function draw_team(state, slot, col, row, color)
    local flag = places.flags[slot.team == constants.teams.independent and 0 or slot.team]
    if flag then
        if flag_known[flag] == nil then flag_known[flag] = pcall(engine.read_resource, flag) end
        if flag_known[flag] then image(state, flag, col + places.team_dx, row + places.team_y) return end
    end
    if slot.team == constants.teams.independent then slot_text(state, "Independent", col, row, color, row + places.team_y, places.team_dx, places.team_dx + 40)
    else slot_text(state, "Team " .. slot.team, col, row, color, row + places.team_y, places.team_dx + 20, places.team_dx + 40) end
end

-- The last slot to pick a team may not join the side every other ready slot is on.
local function avoided_team(state, current)
    local avoid = -1
    for index = 0, (state.slot_count or 8) - 1 do
        local other = state.slots[index]
        if index ~= current and other.phase % 10 == slot_phases.ready then
            if other.team == constants.teams.independent then avoid = -2
            elseif avoid == -1 then avoid = other.team
            elseif avoid >= 0 and other.team ~= avoid then avoid = -2 end
        end
    end
    return avoid
end
local function normalize_team(state, slot, avoid)
    while slot.team == avoid or (state.mode == constants.modes.battle
           and (slot.team == constants.teams.independent or slot.team >= constants.teams.player_three)) do
        slot.team = (slot.team + 1) % constants.teams.enemies
    end
end
local function previous_team(state, slot, avoid)
    repeat
        slot.team = slot.team - 1
        if slot.team < 0 then slot.team = constants.teams.enemies - 1 end
    until slot.team ~= avoid and not (state.mode == constants.modes.battle
        and (slot.team == constants.teams.independent or slot.team > constants.teams.player_two))
end

-- A key press acts once per latch; returns whether the action should run now.
local function trigger(slot, allowed)
    local run = not slot.latched and allowed ~= false
    slot.latched = true
    return run
end

local function empty_slot(state, index, slot, keys, col, row, all_empty)
    if state.countdown == idle_countdown then
        image(state, state.blink % 5 < 3 and "pe/cma" or "pe/cma2", col + places.face_dx, row + places.face_dy)
    elseif state.countdown >= 0 then
        image(state, "pe/cm" .. (math.floor(state.countdown / 30) + 1), col + places.face_dx, row + places.face_dy)
    end
    if pressed(keys, "c") then
        if trigger(slot, state.last_menu == menus.human_slots) then
            slot.phase = slot_phases.choosing_fighter
            sounds.direct(state, "join")
        end
    elseif pressed(keys, "b") and all_empty then
        if trigger(slot) then
            state.leave = true
            sounds.direct(state, "cancel")
        end
    else
        slot.latched = false
    end
end


-- The transformation grid (<phase> of the character's data, readme/dat file/phase.txt): pressing A on a fighter that has one
-- opens a grid of the fighters whose ids the block lists (t0 ids; those the game has and that may be picked); the arrows
-- move, A takes the fighter and goes on as a plain confirm, J closes it, D changes the skin. Placed from the slot's corner:
-- the base picture `pic` at (pic_x, pic_y), the cells (small faces) from (start_x, start_y) every centerx and centery, `row`
-- rows, a box w by h of colour `rect` round the one chosen (`bound` 1 blinking, 2 steady); sound1 on opening, sound2 on closing.
--  respond  as `hidden` (game/unlock.allows): -1 the block is off, 0 always, 1 to 3 behind the cheat codes, 4 never, 10 to
--           1000 the saved keys. When it does not allow: the selection goes to `oid` (random without one) and A goes on
--           (works only when respond is not 0; an `oid` the game lacks: A goes on unchanged).
--  hidden   1: fighters whose own `hidden` (10 to 1000) is not met are shown too, in their `hidden_small`, and cannot be taken.
--  caughtact 1: the fighter chosen in the menu takes the first place of the grid.
--  pickedact 1: the cells show the small picture of the skin in use (`smallt`, else `small`, of that skin); D cycles it.
-- A cell shows the data's `smallt` (the small picture meant for this grid), else the `small` of the menu.
-- [BELUM PASTI] the anchor, the order of the cells (row by row), what `caughtact` and `pickedact` mean exactly (the readme
-- gives one line each), that locked cells are only shown, and the random of a missing `oid`.
local phase_cache = {}
local function phase_of(fighter)
    if not fighter or type(fighter.path) ~= "string" then return nil end
    local cached = phase_cache[fighter.path]
    if cached == nil then
        local ok, data = loaded_data(fighter.path)
        local block = ok and type(data) == "table" and data.phase or nil
        cached = type(block) == "table" and type(block.ids) == "table" and #block.ids > 0 and block or false
        phase_cache[fighter.path] = cached
    end
    return cached or nil
end
local function phase_allows(value)
    local unlock = require("base/game/unlock")
    if unlock.allows then return unlock.allows(value) end
    return value == nil or value <= 0 or (value <= 3 and unlock.flags.characters == 1)
end
local function header_of(fighter)
    local ok, data = loaded_data(fighter.path)
    return ok and type(data) == "table" and type(data.header) == "table" and data.header or {}
end
local function normal_path(path) return type(path) == "string" and path ~= "" and (path:gsub("\\", "/"):lower()) or nil end
local function open_phase_grid(state, slot)
    local block = phase_of(state.fighters[slot.fighter])
    if not block then return nil end
    local respond = block.respond or 0
    if respond == -1 then return nil end
    if not phase_allows(respond) then
        local target = 0
        if type(block.oid) == "number" then
            target = nil
            for position, fighter in ipairs(state.fighters) do
                if fighter.id == block.oid and catalog.selectable(fighter) then target = position break end
            end
        end
        if target == nil then return nil end
        return {redirect = target}
    end
    local cells, locked = {}, {}
    for _, id in ipairs(block.ids) do
        for position, fighter in ipairs(state.fighters) do
            if fighter.id == id then
                if catalog.selectable(fighter) then
                    local value = header_of(fighter).hidden
                    local held = type(value) == "number" and value >= 10 and value <= 1000 and not phase_allows(value)
                    if not held then cells[#cells + 1] = position
                    elseif block.hidden == 1 then cells[#cells + 1] = position; locked[#cells] = true end
                end
                break
            end
        end
    end
    if block.caughtact == 1 and slot.fighter > 0 then
        local reordered, reordered_locked = {slot.fighter}, {}
        for index, position in ipairs(cells) do
            if position ~= slot.fighter then
                reordered[#reordered + 1] = position
                reordered_locked[#reordered] = locked[index]
            end
        end
        cells, locked = reordered, reordered_locked
    end
    if #cells == 0 then return nil end
    -- `row` is the number of cells in a row: louis.dat has `row: 2` with two 40 x 45 cells side by side (centerx 45) in frame2.bmp
    -- (96 x 54); frame4.bmp (148 x 54) fits three, frame.bmp (198 x 54) four, frame3.bmp (96 x 105) two rows of two.
    return {block = block, cells = cells, locked = locked, cursor = 1, columns = math.max(1, math.floor(block.row or 1)),
        skin = chosen_skin(slot)}
end
local function confirm_after_phase(state, slot)
    slot.phase = state.mode == constants.modes.stage and slot_phases.ready or slot_phases.choosing_team
    sounds.direct(state, "join")
end
local function close_phase_grid(state, slot, take)
    local grid = slot.phase_grid
    slot.phase_grid = nil
    play_file(state, grid.block.sound2)
    if take then
        local position = grid.cells[grid.cursor]
        local info = skins_of(state.fighters[position])
        slot.fighter = position
        slot.skin = (grid.skin and info and info.count >= grid.skin) and grid.skin or nil
        slot.skin_for = slot.skin and position or nil
        confirm_after_phase(state, slot)
    else
        sounds.direct(state, "cancel")
    end
end
local function phase_grid_slot(state, slot, keys)
    local grid = slot.phase_grid
    local function move(delta)
        local target = grid.cursor + delta
        if target >= 1 and target <= #grid.cells then grid.cursor = target end
    end
    if pressed(keys, "r") then if trigger(slot) then move(1) end
    elseif pressed(keys, "l") then if trigger(slot) then move(-1) end
    elseif pressed(keys, "u") then if trigger(slot) then move(-grid.columns) end
    elseif pressed(keys, "d") then if trigger(slot) then move(grid.columns) end
    elseif pressed(keys, "c") then
        if trigger(slot) then
            if grid.locked[grid.cursor] then sounds.direct(state, "cancel") else close_phase_grid(state, slot, true) end
        end
    elseif pressed(keys, "b") then if trigger(slot) then close_phase_grid(state, slot, false) end
    elseif pressed(keys, "f") then
        if trigger(slot) and not grid.locked[grid.cursor] then
            local info = skins_of(state.fighters[grid.cells[grid.cursor]])
            if info and info.count > 1 then
                grid.skin = (grid.skin or 1) % info.count + 1
                skin_sound(state, info)
            end
        end
    else slot.latched = false end
end
local function cell_small(state, grid, position, held)
    local fighter = state.fighters[position]
    local header = header_of(fighter)
    if held then return normal_path(header.hidden_small) or fighter.small end
    if grid.block.pickedact == 1 and grid.skin then
        local info = skins_of(fighter)
        local entry = info and info.skins[grid.skin]
        local picture = entry and (normal_path(entry.smallt) or normal_path(entry.small))
        if picture then return picture end
    end
    return normal_path(header.smallt) or fighter.small
end
local function draw_phase_grid(state, slot, col, row)
    local grid = slot.phase_grid
    local block = grid.block
    local draw = block.transparency == 1 and keyed_image or image
    if type(block.pic) == "string" then draw(state, (block.pic:gsub("\\", "/"):lower()), col + (block.pic_x or 0), row + (block.pic_y or 0)) end
    for index, position in ipairs(grid.cells) do
        local x = col + (block.start_x or 0) + ((index - 1) % grid.columns) * (block.centerx or 0)
        local y = row + (block.start_y or 0) + math.floor((index - 1) / grid.columns) * (block.centery or 0)
        local small = cell_small(state, grid, position, grid.locked[index])
        if type(small) == "string" then keyed_image(state, small, x, y) end
        local box = block.bound
        if index == grid.cursor and (box == 2 or (box == 1 and state.blink % 5 < 3)) then
            local w, h = block.w or 0, block.h or 0
            local color = block.rect or 16777215
            local gray = math.floor((math.floor(color / 65536) % 256 + math.floor(color / 256) % 256 + color % 256) / 3)
            fill(state, x, y, w, 1, gray); fill(state, x, y + h - 1, w, 1, gray)
            fill(state, x, y, 1, h, gray); fill(state, x + w - 1, y, 1, h, gray)
        end
    end
end

local function fighter_slot(state, slot, keys, col, row)
    if slot.phase_grid then phase_grid_slot(state, slot, keys) return end
    if state.hint_until and (pressed(keys, "c") or pressed(keys, "b")) then state.hint_until = nil end   -- A or J closes the picture
    if state.hint and pressed(keys, "f") then state.hint_until = (state.frames or 0) + state.hint.ticks end
    if pressed(keys, "r") then
        if trigger(slot) then next_fighter(state, slot) end
    elseif pressed(keys, "l") then
        if trigger(slot) then previous_fighter(state, slot) end
    elseif pressed(keys, "u") then
        if trigger(slot) then slot.fighter, slot.skin = 0, nil end
    elseif pressed(keys, "f") then
        if trigger(slot) then next_skin(state, slot) end
    elseif pressed(keys, "c") then
        if trigger(slot) then
            local grid = open_phase_grid(state, slot)
            if grid and grid.redirect then
                if grid.redirect ~= slot.fighter then slot.fighter, slot.skin = grid.redirect, nil end
                confirm_after_phase(state, slot)
            elseif grid then
                slot.phase_grid = grid
                if not play_file(state, grid.block.sound1) then sounds.direct(state, "join") end
            else
                slot.phase = state.mode == constants.modes.stage and slot_phases.ready or slot_phases.choosing_team
                sounds.direct(state, "join")
            end
        end
    elseif pressed(keys, "b") then
        if trigger(slot) then
            slot.phase = slot_phases.empty
            sounds.direct(state, "cancel")
        end
    else
        slot.latched = false
    end
end

local function team_slot(state, index, slot, keys, col, row)
    local avoid = -1
    local ready = 0
    for other = 0, (state.slot_count or 8) - 1 do
        if state.slots[other].phase == slot_phases.ready then ready = ready + 1 end
    end
    if ready == (state.slot_count or 8) - 1 and (state.mode == constants.modes.versus or state.mode == constants.modes.battle) then
        avoid = avoided_team(state, index)
    end
    normalize_team(state, slot, avoid)
    draw_team(state, slot, col, row, blink_color(state))
    if state.mode == constants.modes.championship then
        -- Championship: Independent, with attack forced on; right/left still take priority.
        slot.team = constants.teams.independent
        slot.latched = false
        keys = keys .. "c"
    end
    if pressed(keys, "r") then
        if trigger(slot) then
            repeat
                repeat slot.team = (slot.team + 1) % constants.teams.enemies until slot.team ~= avoid
            until not (state.mode == constants.modes.battle
                and (slot.team == constants.teams.independent or slot.team > constants.teams.player_two))
        end
    elseif pressed(keys, "l") then
        if trigger(slot) then previous_team(state, slot, avoid) end
    elseif pressed(keys, "c") then
        if trigger(slot) then
            slot.phase = slot_phases.ready
            sounds.direct(state, "join")
        end
    elseif pressed(keys, "b") then
        if trigger(slot) then
            slot.phase = slot_phases.choosing_fighter
            sounds.direct(state, "cancel")
        end
    else
        slot.latched = false
    end
end

local function ready_slot(state, slot, keys)
    if state.menu ~= menus.human_slots then return false end
    if not pressed(keys, "b") then
        slot.latched = false
    elseif state.countdown == idle_countdown then
        if trigger(slot) then
            slot.phase = state.mode == constants.modes.stage and slot_phases.choosing_fighter or slot_phases.choosing_team
            sounds.direct(state, "cancel")
        end
    elseif trigger(slot) then
        return true
    end
    return false
end

local function slots_pass(state, held)
    local all_empty = false
    if state.menu == menus.human_slots then
        all_empty = true
        for index = 0, (state.slot_count or 8) - 1 do
            if state.slots[index].phase ~= slot_phases.empty then all_empty = false end
        end
    end
    local ready_count, idle_count, skip = 0, 0, false
    for index = 0, (state.slot_count or 8) - 1 do
        local slot = state.slots[index]
        local keys = held[index] or ""
        local col, row = origin(index)
        if places.name_hide then -- `name: 1` of <menu_control>: no name text
        elseif slot.phase < slot_phases.choosing_fighter then
            -- "Join?" blinks while the join screen runs; afterwards the empty slot shows dashes.
            if state.menu == menus.human_slots then slot_text(state, "   Join?", col, row, blink_color(state))
            else slot_text(state, "     ----", col, row, tco.done) end
        elseif slot.phase < computer_phase then slot_text(state, controls.name(index), col, row, tco.done)
        else slot_text(state, "Computer", col, row, computer_red) end
        if slot.phase == slot_phases.empty and state.menu == menus.human_slots then empty_slot(state, index, slot, keys, col, row, all_empty) end
        if slot.phase == slot_phases.choosing_fighter then
            draw_fighter(state, slot, col, row, blink_color(state))
            fighter_slot(state, slot, keys, col, row)
            -- Darkfiren places the grid from the top left corner of the fighter's portrait (the frame sits just above it).
            if slot.phase_grid then draw_phase_grid(state, slot, col + places.face_dx, row + places.face_dy) end
        end
        if slot.phase == slot_phases.choosing_team then
            draw_fighter(state, slot, col, row, tco.done)
            team_slot(state, index, slot, keys, col, row)
        end
        slot.ready = false
        if slot.phase == slot_phases.ready then
            draw_fighter(state, slot, col, row, tco.done)
            draw_team(state, slot, col, row, tco.done)
            if ready_slot(state, slot, keys) then skip = true end
            if slot.phase == slot_phases.ready then
                ready_count = ready_count + 1
                slot.ready = true
            end
        end
        if slot.phase == slot_phases.empty or slot.phase == slot_phases.ready then idle_count = idle_count + 1 end
    end
    local previous = state.countdown
    if ready_count < 1 or idle_count ~= (state.slot_count or 8) then
        state.countdown = idle_countdown
    else
        state.countdown = state.countdown - 1
        if skip then state.countdown = previous - 31 end
        if ready_count == (state.slot_count or 8) then state.countdown = 0 end
    end
end

-- <misc> `allow_defense: 1`: the computer count dialog is CMC2 with a Defense box (CMC2 is in resource.dat); the box sets the
-- armor of the computer fighters (100 = normal, steps of 50 up to 300 like the battle setup). Up and Down change it.
local cmc2_available
-- `allow_defense: 1` is read from <misc> of the mode file, or from system.dat (the newer Darkfiren puts it there). It is for the
-- versus and stage modes only (readme: "works in vs and stage mode only"); battle sets its defense in its own setup.
local function defense_dialog(state)
    if state.mode ~= constants.modes.versus and state.mode ~= constants.modes.stage then return false end
    if misc.allow_defense ~= 1 and system_data.number("allow_defense", 0) ~= 1 then return false end
    if cmc2_available == nil then cmc2_available = pcall(engine.read_resource, "pe/cmc2") end
    return cmc2_available
end
local function computer_count_menu(state, previous_menu)
    -- The dialog is laid out for the classic 794-wide picture; the wide menu moves it to the middle of its picture.
    local dx = state.wide and math.floor(((state.width or constants.screen.wide_width) - constants.screen.width) / 2 + 0.5) or 0
    local defense_on = defense_dialog(state)
    image(state, defense_on and "pe/cmc2" or "pe/cmc", 218 + dx, 215)
    if defense_on then
        state.options.computer_defense = state.options.computer_defense or constants.defense.normal
        local value = state.options.computer_defense
        text(state, string.format("x %d.%d", math.floor(value / 100), math.floor(value % 100 / 10)), 218 + dx + 232, 215 + 115, white)
    end
    local free, sides, teams = 0, 0, {}
    for index = 0, (state.slot_count or 8) - 1 do
        local slot = state.slots[index]
        if not slot.ready then free = free + 1
        elseif slot.team == constants.teams.independent or not teams[slot.team] then
            teams[slot.team] = true
            sides = sides + 1
        end
    end
    if free == 0 then state.menu = menus.options end
    local minimum = (sides < 2 and state.mode ~= constants.modes.stage) and 1 or 0
    if state.computers == -100 or state.computers < minimum or free < state.computers then
        state.computers = minimum
    end
    local accept = previous_menu == menus.computer_count
    for index = 0, (state.slot_count or 8) - 1 do
        local slot = state.slots[index]
        if slot.ready then
            local keys = state.held[index] or ""
            local auto = state.mode == constants.modes.championship or state.mode == constants.modes.team_championship
            if pressed(keys, "r") then
                if trigger(slot, accept) then
                    state.computers = state.computers + 1
                    if free < state.computers then state.computers = minimum end
                end
            elseif pressed(keys, "l") then
                if trigger(slot, accept) then
                    state.computers = state.computers - 1
                    if state.computers < minimum then state.computers = free end
                end
            elseif defense_on and (pressed(keys, "u") or pressed(keys, "d")) then
                if trigger(slot, accept) then
                    local step = pressed(keys, "u") and 50 or -50
                    local value = state.options.computer_defense + step
                    if value > constants.defense.maximum then value = constants.defense.normal end
                    if value < constants.defense.normal then value = constants.defense.maximum end
                    state.options.computer_defense = value
                    sounds.direct(state, "ok")
                end
            elseif pressed(keys, "c") or auto then
                if auto then
                    slot.latched = false
                    state.computers = free
                end
                if trigger(slot, accept) then
                    if not auto then sounds.direct(state, "ok") end
                    state.menu = menus.computer_slots
                    state.order, state.cursor = {}, 0
                    if state.computers == 0 then
                        state.options.row = option_rows.reroll
                        resolve_random(state)
                        state.menu = menus.options
                    else
                        for other = 0, (state.slot_count or 8) - 1 do
                            if not state.slots[other].ready and #state.order < state.computers then
                                state.order[#state.order + 1] = other
                                state.slots[other].phase = computer_phase
                            end
                        end
                    end
                    break
                end
            else
                slot.latched = false
            end
        end
    end
    -- The row of numbers is centred in the dialog: 8 numbers from x 280 in the classic layout; a layout of more than 8 slots
    -- (10 players) has 0 to the slot count, the 11 numbers of LF2 Darkfiren's dialog, which also leaves 0 to count as spectators.
    local slots_total = state.slot_count or 8
    local numbers = slots_total > 8 and slots_total + 1 or slots_total
    for number = 0, numbers - 1 do
        local x = 280 + number * 30 - (numbers - 8) * 15 + dx
        -- Digits the choice cannot reach (below the minimum, or more than the free slots) are greyed.
        local unavailable = number < minimum or free < number
        text(state, tostring(number), number >= 10 and x + 2 or x + 6, 286, unavailable and count_greyed or white)   -- no box: the dialog picture's own colour shows behind the digits
        -- system.dat `respond: 1`: the box around the chosen number blinks (update log 21 Feb 2023).
        local blink_on = system_data.number("respond", 0) ~= 1 or math.floor((state.frames or 0) / 8) % 2 == 0
        if state.computers == number and blink_on then
            fill(state, x, 283, 21, 1, 255)
            fill(state, x, 283, 1, 21, 255)
            fill(state, x, 303, 21, 1, 255)
            fill(state, x + 20, 283, 1, 21, 255)
        end
    end
end

-- Menu 2: ready human slots choose each computer's fighter, then its team.
local function computer_keys(state, previous_menu)
    local actions = {}
    if state.menu ~= menus.computer_slots then return actions end
    local accept = previous_menu == menus.computer_slots
    for index = 0, (state.slot_count or 8) - 1 do
        local slot = state.slots[index]
        if slot.ready then
            local keys = state.held[index] or ""
            if pressed(keys, "u") then actions.random = trigger(slot, accept) or actions.random
            elseif pressed(keys, "d") then slot.latched = true
            elseif pressed(keys, "f") then actions.backup = trigger(slot, accept) or actions.backup
            elseif pressed(keys, "r") then actions.next = trigger(slot, accept) or actions.next
            elseif pressed(keys, "l") then actions.previous = trigger(slot, accept) or actions.previous
            elseif pressed(keys, "c") then actions.confirm = trigger(slot, accept) or actions.confirm
            elseif pressed(keys, "b") then actions.back = trigger(slot, accept) or actions.back
            else slot.latched = false end
        end
    end
    return actions
end

local function advance_computer(state)
    local current = state.slots[state.order[state.cursor + 1]]
    current.phase = computer_done
    state.previous_random = current.fighter == 0
    state.cursor = state.cursor + 1
    if state.cursor < state.computers then
        state.slots[state.order[state.cursor + 1]].phase = computer_phase
        return false
    end
    resolve_random(state)
    state.options.row = option_rows.reroll
    state.menu = menus.options
    return true
end

local function computer_menu(state, previous_menu)
    local actions = computer_keys(state, previous_menu)
    for position = 1, state.computers do
        local index = state.order[position]
        local slot = state.slots[index]
        local col, row = origin(index)
        if slot.phase > computer_phase then draw_fighter(state, slot, col, row, computer_red) end
        if slot.phase > computer_team_phase then draw_team(state, slot, col, row, computer_red) end
    end
    local index = state.order[state.cursor + 1]
    local slot = index and state.slots[index]
    if slot and slot.phase == computer_phase then
        slot.backup = nil
        local col, row = origin(index)
        draw_fighter(state, slot, col, row, blink_color(state))
        if actions.next then next_fighter(state, slot) end
        if actions.previous then previous_fighter(state, slot) end
        if actions.random then slot.fighter = 0 end
        if state.previous_random then
            slot.fighter = 0
            state.previous_random = false
        end
        if actions.confirm then
            actions.confirm = false
            sounds.direct(state, "join")
            slot.phase = computer_team_phase
            if state.mode == constants.modes.stage and advance_computer(state) then return end
        end
        if actions.back then
            actions.back = false
            sounds.direct(state, "cancel")
            if state.cursor == 0 then
                state.menu = menus.computer_count
                for other = 0, (state.slot_count or 8) - 1 do
                    if state.slots[other].phase == computer_phase then state.slots[other].phase = slot_phases.empty end
                end
            else
                state.cursor = state.cursor - 1
                local previous = state.slots[state.order[state.cursor + 1]]
                previous.phase = (state.mode == constants.modes.stage or state.mode == constants.modes.championship)
                    and computer_phase or computer_team_phase
            end
        end
    end
    index = state.order[state.cursor + 1]
    slot = index and state.slots[index]
    if slot and slot.phase == computer_team_phase then
        local col, row = origin(index)
        local avoid = -1
        if state.cursor == state.computers - 1 and (state.mode == constants.modes.versus or state.mode == constants.modes.battle) then
            avoid = avoided_team(state, index)
        end
        normalize_team(state, slot, avoid)
        draw_team(state, slot, col, row)
        if actions.backup and cost_in_mode(state.mode) and state.mode == constants.modes.versus then
            -- Mark or unmark this computer as a backup (needs a human in its team).
            actions.backup = false
            slot.backup = not slot.backup or nil
            if slot.backup and not backup_marked(state, slot) then slot.backup = nil end
            sounds.direct(state, slot.backup and "join" or "cancel")
        end
        if actions.next then
            slot.team = (slot.team + 1) % constants.teams.enemies
            if slot.team == avoid then slot.team = (slot.team + 1) % constants.teams.enemies end
        end
        if actions.previous then previous_team(state, slot, avoid) end
        if state.mode == constants.modes.championship then
            slot.team = constants.teams.independent
            actions.confirm = true
        end
        if actions.confirm then
            sounds.direct(state, "join")
            if advance_computer(state) then return end
        end
        if actions.back then
            sounds.direct(state, "cancel")
            slot.phase = computer_phase
            state.previous_random = false
        end
    end
end

local options_sheet = "pe/menu_clip3"
local option_highlights = {
    [0] = {{407, 183, 126, 21}, 92, 16}, {{379, 206, 186, 21}, 64, 39}, {{355, 231, 235, 21}, 40, 64},
    {{330, 254, 279, 22}, 15, 87}, {{352, 278, 228, 22}, 37, 111}, {{416, 304, 111, 19}, 101, 137},
}
local difficulties = {[constants.difficulties.easy] = "Easy", [constants.difficulties.normal] = "Normal",
    [constants.difficulties.difficult] = "Difficult", [constants.difficulties.crazy] = "CRAZY!"}
local difficulty_layers = {[constants.difficulties.easy] = 1, [constants.difficulties.normal] = 2,
    [constants.difficulties.difficult] = 3, [constants.difficulties.crazy] = 4}
local music_names = {[0] = "Random", "Main Theme", "Stage 1", "Stage 2", "Stage 3", "Stage 4",
    "Stage 5", "Boss", "Final Boss"}
local function background_name(state, row)
    if row == constants.background_rows.random then return "Random" end
    local entry = state.backgrounds[row + 1]
    return entry and background.load(entry.path).name or ""
end

-- Next track number in the given direction: -1 (OFF), 0 (Random), then the tracks the unlock rules allow.
local function next_track(index, direction, count)
    local allowed = {}
    for _, number in ipairs(music.selectable()) do allowed[number] = true end
    for _ = 1, count + 2 do
        index = index + direction
        if index > count then index = -1 elseif index < -1 then index = count end
        if index <= 0 or allowed[index] then return index end
    end
    return index
end

local function music_option(state, left, right)
    local options = state.options
    local index = options.music
    local label
    if state.mode == constants.modes.stage then
        if left or right then index = index == -1 and 0 or -1 end
        label = index == -1 and "OFF" or "ON"
    else
        -- The list, its names and the hidden/unlock rules come from bgm.dat (music.tracks/names/selectable); without the
        -- file they are the original eight tracks.
        local count = #music.tracks
        if right then index = next_track(index, 1, count) end
        if left then index = next_track(index, -1, count) end
        if index == 0 then options.track = music.random_index() or engine.random(count) + 1
        elseif index > 0 then options.track = index
        else options.track = nil end
        music.selected = options.track and music.tracks[options.track] or nil
        local name = index > 0 and music.names[index] or nil
        label = index == -1 and "OFF" or (name and name ~= "" and name) or music_names[index] or tostring(index)
    end
    options.music = index
    if index == -1 then
        music.enabled = false
        music.stop()
    else
        music.enabled = true
    end
    -- Top right corner: in the wide menu it follows the right edge of the wider picture.
    -- The original draws the music line at the mode file's `music_x` as it stands (323 in mode2, mode3 and mode4 alike, measured on
    -- the 1018 wide game): no width is added, unlike `frame_x`. (The 1142 default already is the classic place in the 1333 picture.)
    local music_x = state.wide and misc.music_x or 603
    local music_y = state.wide and misc.music_y or 3
    text(state, i18n.tr("Music: %s", i18n.tr(label)), music_x, music_y, state.wide and misc.music_title or music_title)
    text(state, i18n.tr("(Press Left/Right to change)"), music_x, music_y + 17, state.wide and misc.music_hint or music_hint)
end

-- LF2 Darkfiren's <grid_bg> (mode4.dat): a panel at (180, 3) with the backgrounds one under the other, each a 212x109
-- picture every 135 pixels from (220, 15) with its name 250 to the right, four to a page. A tap on a picture chooses
-- that background; the keys move a cursor (up, down), choose (attack) or leave (jump). It replaces the cycling of the
-- Background row in the wide menu; Stage mode still cycles its stage there.
-- The 8P widescreen (mode2.dat) gives <grid_bg> as a strip instead: `centerx` above 0 lays the pictures in one row (three to a
-- page, the panel 790 x 185 like the stage list's), `centery` then being 0; step_x stays 0 for the vertical list above.
-- A file that gives `centerx` and `centery` both above 0 (with `row` pictures to a line) lays the list out in lines of pictures
-- instead, as many lines as the panel picture holds (the wide menus' 3 x 4 list), the lines scrolling with the cursor;
-- line_y is that centery (0 = not given), the names are centred on their picture.
local grid_bg = {panel_x = 180, panel_y = 3, panel_w = 500, panel_h = 542, x = 220, y = 15, w = 212, h = 109,
    step = 135, step_x = 0, line_y = 0, rows = 4, columns = 3, strip_w = 790, strip_h = 185, name_x = 250, name_y = 40,
    panel_pic = "sprite/ui/grid/box_bg.bmp", random_pic = "sprite/ui/grid/bg_grid_random.bmp"}
layout_targets.grid_bg = grid_bg
local grid_available = {}
local function grid_has(path)
    if grid_available[path] == nil then grid_available[path] = pcall(engine.read_resource, path) end
    return grid_available[path]
end
-- A picture path from a mode file (`UI\\bgmaps\\maps\\hkc.png`): the first spelling the game has (slashes forward, as written, then lower case).
local function existing_picture(path)
    if type(path) ~= "string" or not path:match("%S") then return nil end
    local plain = (path:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\\", "/"))
    if grid_has(plain) then return plain end
    if grid_has(plain:lower()) then return plain:lower() end
    return nil
end
-- The size of a BMP or PNG picture from its header (cached by path), nil when it cannot be read.
local picture_size_cache = {}
local function picture_size(path)
    local resource = existing_picture(path)
    if not resource then return nil, nil end
    if picture_size_cache[resource] == nil then
        local width, height = false, false
        local ok, data = pcall(engine.read_resource, resource)
        if ok and type(data) == "string" then
            if #data >= 24 and data:sub(2, 4) == "PNG" then
                local a, b, c, d, e, f, g, h = data:byte(17, 24)
                width = ((a * 256 + b) * 256 + c) * 256 + d
                height = ((e * 256 + f) * 256 + g) * 256 + h
            elseif #data >= 26 and data:sub(1, 2) == "BM" then
                local a, b, c, d, e, f, g, h = data:byte(19, 26)
                width = ((d * 256 + c) * 256 + b) * 256 + a
                height = ((h * 256 + g) * 256 + f) * 256 + e
                if height >= 2147483648 then height = 4294967296 - height end
            end
        end
        if width and height and width >= 1 and width < 8192 and height >= 1 and height < 8192 then
            picture_size_cache[resource] = {width, height}
        else
            picture_size_cache[resource] = false
        end
    end
    local size = picture_size_cache[resource]
    if size then return size[1], size[2] end
    return nil, nil
end
-- How many lines of cells (every `step_y` pixels from target.y) a grid panel's picture holds: the last line must end inside the
-- panel (a few pixels of its border may be passed); the screen's height stands in for a missing picture.
local function fitting_lines(target, step_y)
    local _, height = picture_size(target.panel_pic)
    local extent = math.max(target.h, target.name_y + 16)
    local room = target.panel_y + (height or constants.screen.height) - target.y - extent + 8
    return math.max(1, math.floor(room / step_y) + 1)
end
-- The picture a background's own .dat names with `small:` before its layers (bg/sys/grid/hkc.bmp for HK Coliseum), or nil.
local own_picture_cache = {}
local function background_own_picture(entry)
    if not entry then return nil end
    local cached = own_picture_cache[entry.path]
    if cached == nil then
        local ok, data = pcall(engine.read_background_data, entry.path)
        cached = ok and type(data) == "table" and existing_picture(data.small) or false
        own_picture_cache[entry.path] = cached
    end
    return cached or nil
end
-- Forward declaration: the chosen background's small picture is drawn behind the lists too (see options_menu).
local small_background
local function grid_picture(state, row)
    if row == constants.background_rows.random then return grid_bg.random_pic end
    local entry = state.backgrounds[row + 1]
    -- The background's own `small:` first, as the original list does; the path-derived stock picture is the fallback.
    local own = background_own_picture(entry)
    if own then return own end
    -- bg/sys/<name>/bg.dat has its picture in bg/sys/grid/<name>.bmp; the templates share temp.bmp.
    local folder = entry and entry.path:match("bg/sys/([^/]+)/") or "temp"
    return "bg/sys/grid/" .. folder .. ".bmp"
end
local function grid_cells(state)
    local cells = {constants.background_rows.random}
    for index = 0, #state.backgrounds - 1 do cells[#cells + 1] = index end
    return cells
end
local function grid_lines() return fitting_lines(grid_bg, grid_bg.line_y) end
local function grid_follow(grid)
    if grid_bg.step_x >= 1 then   -- the strip takes its page from the cursor, the lines follow it
        if grid_bg.line_y >= 1 then
            local lines = grid_lines()
            local line = math.floor((grid.cursor - 1) / grid_bg.columns)
            if line < grid.top then grid.top = line
            elseif line >= grid.top + lines then grid.top = line - lines + 1 end
        end
        return
    end
    if grid.cursor - 1 < grid.top then grid.top = grid.cursor - 1
    elseif grid.cursor - 1 >= grid.top + grid_bg.rows then grid.top = grid.cursor - grid_bg.rows end
end
local function open_grid(state)
    local cells = grid_cells(state)
    local current = state.options.random_background and constants.background_rows.random or state.options.background
    local cursor = 1
    for position, row in ipairs(cells) do if row == current then cursor = position; break end end
    state.grid = {cells = cells, cursor = cursor, top = 0}
    grid_follow(state.grid)
end
-- LF2 Darkfiren's background modes (data/bg/*.dat, found through data/bg_mode.dat) and <grid_bg_mode> (mode4.dat):
-- a panel at (1, 1) with the chosen background's modes, three to a line from (30, 10) every 260 by 135 pixels, each a
-- 212x109 picture with its name 25 to the right and 110 below. Choosing a background that has modes opens it at once;
-- leaving it keeps the first, plain mode. Of the tags a mode can carry, bound, weapon_drop, recmp, regen_hp,
-- regen_mp, hurtable, gain_mp_a and gain_mp_v work (the match reads them from state.bg_mode); a mode with any other effect is listed dimmed and cannot
-- be chosen yet. respond (background layers) and arest (opoints) work too, in every mode: they travel in the chosen
-- mode's `filters` (game/bg_modes.lua), and the first mode's filters stand when no other mode is chosen. fall and
-- wait (quests, team hp bars) are not done: the first mode keeps them as they are, any other mode with a value other
-- than 0 is listed dimmed.
local grid_mode = {panel_x = 1, panel_y = 1, panel_w = 790, panel_h = 547, x = 30, y = 10, w = 212, h = 109,
    step_x = 260, step_y = 135, columns = 3, lines = 4, name_x = 25, name_y = 110,
    panel_pic = "sprite/ui/grid/box_bgmode.bmp"}
layout_targets.grid_mode = grid_mode
local mode_effects = {bound = true, weapon_drop = true, recmp = true, regen_hp = true, regen_mp = true,
    hurtable = true, gain_mp_a = true, gain_mp_v = true,
    -- Applied through the chosen mode's area (game/bg_modes.lua): width and zboundary by game/background.lua, dvy by
    -- match.lua, centery by game/weapons.lua, attacking (the mode's damage percent) by game/combat.lua.
    width = true, zboundary = true, dvy = true, centery = true, attacking = true}
local mode_neutral = {name = true, hex = true, small = true, smallb = true, hidden = true, spark = true,
    bg_pause = true, cam_pause = true, id = true, oid = true, drop = true, etc_width = true, etc_mode = true,
    dicontrol = true}
-- Tags the round reads from the mode's area (bg_modes.area): they travel with the mode's filters, so they work in every mode.
local mode_area = {zcam = true, zcamera = true, shadow = true, shadowsize = true, start_frame = true, reserve = true,
    dx = true, dvx = true, dz = true, dvz = true, caught = true, caughtact = true, state = true, effect = true, kind = true,
    fronthurtact = true, backhurtact = true}
local mode_filters = {respond = true, arest = true, fall = true, wait = true}
local mode_filters_done = {respond = true, arest = true}
local bg_modes = require("base/game/bg_modes")
local mode_cache = {}
local function load_modes(row)
    if mode_cache[row] then return mode_cache[row] end
    local ok, text = pcall(engine.read_resource, "game/bg_modes/" .. row)
    local modes = bg_modes.parse(ok and text or "")
    for position, mode in ipairs(modes) do
        -- The tags that keep the mode from being chosen yet (shown under the grid). The first mode is the plain default, so it is
        -- always chosen; in another mode a tag that is not done does no harm when the first mode carries the very same value
        -- (a game that writes `wait: 1`, `bg_center: 1` or `effect: 1` in every mode), because then it changes nothing.
        local reasons = {}
        local first = modes[1]
        for key, value in pairs(mode) do
            local same = position == 1 or (first ~= nil and first[key] == value)
            if position == 1 or same or type(key) ~= "string" then
                -- nothing to report
            elseif mode_filters[key] then
                if not mode_filters_done[key] then
                    for item in value:gmatch("[^,]+") do
                        if tonumber(item) ~= 0 then reasons[#reasons + 1] = key; break end
                    end
                end
            elseif not mode_effects[key] and not mode_neutral[key] and not mode_area[key] then
                reasons[#reasons + 1] = key
            end
        end
        table.sort(reasons)
        mode.unsupported = reasons
        mode.supported = #reasons == 0
        mode.title = (mode.name:gsub("<boss>", ""):gsub("_", " "):gsub("^%s+", ""):gsub("%s+$", ""))
        local effects = {}
        for key in pairs(mode_effects) do
            local number = tonumber(mode[key])
            if number and number ~= 0 then effects[key] = number end
        end
        -- The first mode's filters are the default, so choosing it needs no filters of its own. Any other mode brings
        -- its own when it has some, or when the first mode has (a mode without respond/arest lets everything
        -- through, which must not fall back to the first mode's filters).
        if position > 1 and (bg_modes.has_filters(mode) or bg_modes.has_filters(modes[1])) then
            effects.filters = bg_modes.filters(mode, modes[1])
        end
        mode.effects = next(effects) and effects or nil
    end
    mode_cache[row] = modes
    return modes
end
-- May a `hidden:` value be used? game/unlock.allows (cheat codes and the saved keys); a host without it keeps the old rule.
local function allows(hidden)
    if unlock.allows then return unlock.allows(hidden) end
    return hidden == nil or hidden <= 0 or (hidden <= 3 and unlock.flags.characters == 1)
end

-- The modes the player may see: those whose hidden value is allowed; the first always.
local function visible_modes(row)
    local list = {}
    for position, mode in ipairs(load_modes(row)) do
        local hidden = tonumber(mode.hidden) or 0
        if position == 1 or allows(hidden) then list[#list + 1] = mode end
    end
    return list
end
local function mode_follow(grid)
    local line = math.floor((grid.cursor - 1) / grid_mode.columns)
    if line < grid.top then grid.top = line
    elseif line >= grid.top + grid_mode.lines then grid.top = line - grid_mode.lines + 1 end
end
local function open_mode_grid(state, row, modes)
    state.mode_grid = {row = row, cells = modes, cursor = 1, top = 0}
end
local function mode_choose(state, mode)
    if not mode.supported then return false end
    state.options.bg_mode = mode.effects
    state.options.bg_mode_title = mode.title
    state.options.bg_mode_small = mode.small   -- the preview follows the chosen mode's `small:`
    sounds.direct(state, "ok")
    state.mode_grid = nil
    return true
end
local function grid_choose(state, row)
    state.options.random_background = row == constants.background_rows.random
    state.options.background = row
    state.options.bg_mode = nil
    state.options.bg_mode_title = nil
    state.options.bg_mode_small = nil
    sounds.direct(state, "ok")
    state.grid = nil
    -- A background of the catalog may have modes to choose from; Random has none.
    if row >= 0 and row < constants.background_rows.random then
        local modes = visible_modes(row)
        if #modes > 1 then open_mode_grid(state, row, modes) end
    end
end
-- The background list as a strip (grid_bg.step_x above 0, the 8P widescreen): one row of three pictures, the page following
-- the cursor; left and right (also up and down) move, attack chooses, jump leaves, a tap chooses a picture or, outside the
-- panel, closes the list.
local function grid_strip_popup(state, previous_menu)
    local grid, held = state.grid, state.held
    local columns = grid_bg.columns
    local function inside(x, y, left, top, width, height) return x >= left and x < left + width and y >= top and y < top + height end
    local first = math.floor((grid.cursor - 1) / columns) * columns
    if held.click and held.pointer_x and held.pointer_x >= 0 and held.pointer_y and held.pointer_y >= 0 then
        local px, py = held.pointer_x - (state.dx or 0), held.pointer_y
        for column = 0, columns - 1 do
            local row = grid.cells[first + column + 1]
            local x = grid_bg.x + column * grid_bg.step_x
            if row and inside(px, py, x, grid_bg.y, grid_bg.w, grid_bg.name_y + 16) then
                grid_choose(state, row)
                return
            end
        end
        if not inside(px, py, grid_bg.panel_x, grid_bg.panel_y, grid_bg.strip_w, grid_bg.strip_h) then
            state.grid = nil
            return
        end
    end
    local keys = {}
    local accept = previous_menu == menus.options
    for index = 0, (state.slot_count or 8) - 1 do
        local slot = state.slots[index]
        if slot.ready then
            local keys_held = state.held[index] or ""
            local key
            for _, candidate in ipairs({"l", "r", "u", "d", "c", "b"}) do
                if pressed(keys_held, candidate) then key = candidate; break end
            end
            if key then keys[key] = trigger(slot, accept) or keys[key]
            else slot.latched = false end
        end
    end
    if keys.l or keys.u then grid.cursor = math.max(1, grid.cursor - 1) end
    if keys.r or keys.d then grid.cursor = math.min(#grid.cells, grid.cursor + 1) end
    first = math.floor((grid.cursor - 1) / columns) * columns
    if keys.b then state.grid = nil; return end
    if keys.c then grid_choose(state, grid.cells[grid.cursor]); return end
    image(state, grid_bg.panel_pic, grid_bg.panel_x, grid_bg.panel_y)
    local chosen = state.options.random_background and constants.background_rows.random or state.options.background
    for column = 0, columns - 1 do
        local position = first + column + 1
        local row = grid.cells[position]
        if row then
            local x, y = grid_bg.x + column * grid_bg.step_x, grid_bg.y
            local picture = grid_picture(state, row)
            if grid_has(picture) then image(state, picture, x, y) end
            local gray = row == chosen and 255 or (position == grid.cursor and 140 or nil)
            if gray then
                fill(state, x - 2, y - 2, grid_bg.w + 4, 2, gray)
                fill(state, x - 2, y + grid_bg.h, grid_bg.w + 4, 2, gray)
                fill(state, x - 2, y - 2, 2, grid_bg.h + 4, gray)
                fill(state, x + grid_bg.w, y - 2, 2, grid_bg.h + 4, gray)
            end
            text(state, background_name(state, row), x + grid_bg.name_x, y + grid_bg.name_y, white)
        end
    end
end

-- The background list as lines of pictures (grid_bg.step_x and line_y above 0): `row` pictures to a line, as many lines as the
-- panel picture holds, the lines scrolling with the cursor. Left and right move a picture, up and down a line, attack chooses,
-- jump leaves, a tap chooses a picture or, outside the panel, closes the list. The names are centred on their picture.
local function grid_lines_popup(state, previous_menu)
    local grid, held = state.grid, state.held
    local columns, lines = grid_bg.columns, grid_lines()
    local function inside(x, y, left, top, width, height) return x >= left and x < left + width and y >= top and y < top + height end
    if held.click and held.pointer_x and held.pointer_x >= 0 and held.pointer_y and held.pointer_y >= 0 then
        local px, py = held.pointer_x - (state.dx or 0), held.pointer_y
        for line = 0, lines - 1 do
            for column = 0, columns - 1 do
                local row = grid.cells[(grid.top + line) * columns + column + 1]
                local x, y = grid_bg.x + column * grid_bg.step_x, grid_bg.y + line * grid_bg.line_y
                if row and inside(px, py, x, y, grid_bg.w, grid_bg.h) then
                    grid_choose(state, row)
                    return
                end
            end
        end
        local panel_w, panel_h = picture_size(grid_bg.panel_pic)
        if not inside(px, py, grid_bg.panel_x, grid_bg.panel_y, panel_w or grid_bg.strip_w, panel_h or constants.screen.height) then
            state.grid = nil
            return
        end
    end
    local keys = {}
    local accept = previous_menu == menus.options
    for index = 0, (state.slot_count or 8) - 1 do
        local slot = state.slots[index]
        if slot.ready then
            local keys_held = state.held[index] or ""
            local key
            for _, candidate in ipairs({"u", "d", "l", "r", "c", "b"}) do
                if pressed(keys_held, candidate) then key = candidate; break end
            end
            if key then keys[key] = trigger(slot, accept) or keys[key]
            else slot.latched = false end
        end
    end
    local count = #grid.cells
    if keys.u then grid.cursor = math.max(1, grid.cursor - columns) end
    if keys.d then grid.cursor = math.min(count, grid.cursor + columns) end
    if keys.l then grid.cursor = math.max(1, grid.cursor - 1) end
    if keys.r then grid.cursor = math.min(count, grid.cursor + 1) end
    grid_follow(grid)
    if keys.b then state.grid = nil; return end
    if keys.c then grid_choose(state, grid.cells[grid.cursor]); return end
    image(state, grid_bg.panel_pic, grid_bg.panel_x, grid_bg.panel_y)
    local chosen = state.options.random_background and constants.background_rows.random or state.options.background
    for line = 0, lines - 1 do
        for column = 0, columns - 1 do
            local position = (grid.top + line) * columns + column + 1
            local row = grid.cells[position]
            if row then
                local x, y = grid_bg.x + column * grid_bg.step_x, grid_bg.y + line * grid_bg.line_y
                local picture = grid_picture(state, row)
                if grid_has(picture) then image(state, picture, x, y) end
                local gray = row == chosen and 255 or (position == grid.cursor and 140 or nil)
                if gray then
                    fill(state, x - 2, y - 2, grid_bg.w + 4, 2, gray)
                    fill(state, x - 2, y + grid_bg.h, grid_bg.w + 4, 2, gray)
                    fill(state, x - 2, y - 2, 2, grid_bg.h + 4, gray)
                    fill(state, x + grid_bg.w, y - 2, 2, grid_bg.h + 4, gray)
                end
                text(state, background_name(state, row), x + math.floor(grid_bg.w / 2), y + grid_bg.name_y, white, nil, "center")
            end
        end
    end
end

local function grid_popup(state, previous_menu)
    if grid_bg.step_x >= 1 and grid_bg.line_y >= 1 then return grid_lines_popup(state, previous_menu) end
    if grid_bg.step_x >= 1 then return grid_strip_popup(state, previous_menu) end
    local grid, held = state.grid, state.held
    local last_top = math.max(0, #grid.cells - grid_bg.rows)
    local scrollable = #grid.cells > grid_bg.rows
    local function inside(x, y, left, top, width, height) return x >= left and x < left + width and y >= top and y < top + height end
    if held.click and held.pointer_x and held.pointer_x >= 0 and held.pointer_y and held.pointer_y >= 0 then
        local px, py = held.pointer_x - (state.dx or 0), held.pointer_y
        for line = 0, grid_bg.rows - 1 do
            local row = grid.cells[grid.top + line + 1]
            if row and inside(px, py, grid_bg.x, grid_bg.y + line * grid_bg.step, grid_bg.w, grid_bg.h) then
                grid_choose(state, row)
                return
            end
        end
        if scrollable and inside(px, py, 600, 8, 80, 26) then
            grid.top = math.max(0, grid.top - grid_bg.rows)
            grid.cursor = math.max(grid.top + 1, math.min(grid.cursor, grid.top + grid_bg.rows))
        elseif scrollable and inside(px, py, 590, 506, 90, 28) then
            grid.top = math.min(last_top, grid.top + grid_bg.rows)
            grid.cursor = math.max(grid.top + 1, math.min(grid.cursor, grid.top + grid_bg.rows))
        elseif not inside(px, py, grid_bg.panel_x, grid_bg.panel_y, grid_bg.panel_w, grid_bg.panel_h) then
            state.grid = nil
            return
        end
    end
    local keys = {}
    local accept = previous_menu == menus.options
    for index = 0, (state.slot_count or 8) - 1 do
        local slot = state.slots[index]
        if slot.ready then
            local keys_held = state.held[index] or ""
            local key
            for _, candidate in ipairs({"u", "d", "c", "b"}) do
                if pressed(keys_held, candidate) then key = candidate; break end
            end
            if key then keys[key] = trigger(slot, accept) or keys[key]
            else slot.latched = false end
        end
    end
    if keys.u then grid.cursor = math.max(1, grid.cursor - 1) end
    if keys.d then grid.cursor = math.min(#grid.cells, grid.cursor + 1) end
    grid_follow(grid)
    if keys.b then state.grid = nil; return end
    if keys.c then grid_choose(state, grid.cells[grid.cursor]); return end
    image(state, grid_bg.panel_pic, grid_bg.panel_x, grid_bg.panel_y)
    local chosen = state.options.random_background and constants.background_rows.random or state.options.background
    for line = 0, grid_bg.rows - 1 do
        local position = grid.top + line + 1
        local row = grid.cells[position]
        if row then
            local x, y = grid_bg.x, grid_bg.y + line * grid_bg.step
            local picture = grid_picture(state, row)
            if grid_has(picture) then image(state, picture, x, y) end
            local gray = row == chosen and 255 or (position == grid.cursor and 140 or nil)
            if gray then
                fill(state, x - 2, y - 2, grid_bg.w + 4, 2, gray)
                fill(state, x - 2, y + grid_bg.h, grid_bg.w + 4, 2, gray)
                fill(state, x - 2, y - 2, 2, grid_bg.h + 4, gray)
                fill(state, x + grid_bg.w, y - 2, 2, grid_bg.h + 4, gray)
            end
            text(state, background_name(state, row), x + grid_bg.name_x, y + grid_bg.name_y, white)
        end
    end
    if scrollable then
        text(state, "Up", 620, 14, option_blue)
        text(state, "Down", 612, 512, option_blue)
    end
end

local function mode_popup(state, previous_menu)
    local grid, held = state.mode_grid, state.held
    local function inside(x, y, left, top, width, height) return x >= left and x < left + width and y >= top and y < top + height end
    if held.click and held.pointer_x and held.pointer_x >= 0 and held.pointer_y and held.pointer_y >= 0 then
        local px, py = held.pointer_x - (state.dx or 0), held.pointer_y
        local hit
        for line = 0, grid_mode.lines - 1 do
            for column = 0, grid_mode.columns - 1 do
                local position = (grid.top + line) * grid_mode.columns + column + 1
                local x, y = grid_mode.x + column * grid_mode.step_x, grid_mode.y + line * grid_mode.step_y
                if grid.cells[position] and inside(px, py, x, y, grid_mode.w, grid_mode.name_y + 16) then hit = position end
            end
        end
        if hit then
            grid.cursor = hit
            if mode_choose(state, grid.cells[hit]) then return end
        elseif not inside(px, py, grid_mode.panel_x, grid_mode.panel_y, grid_mode.panel_w, grid_mode.panel_h) then
            state.mode_grid = nil
            return
        end
    end
    local keys = {}
    local accept = previous_menu == menus.options
    for index = 0, (state.slot_count or 8) - 1 do
        local slot = state.slots[index]
        if slot.ready then
            local keys_held = state.held[index] or ""
            local key
            for _, candidate in ipairs({"u", "d", "l", "r", "c", "b"}) do
                if pressed(keys_held, candidate) then key = candidate; break end
            end
            if key then keys[key] = trigger(slot, accept) or keys[key]
            else slot.latched = false end
        end
    end
    local count = #grid.cells
    if keys.u then grid.cursor = math.max(1, grid.cursor - grid_mode.columns) end
    if keys.d then grid.cursor = math.min(count, grid.cursor + grid_mode.columns) end
    if keys.l then grid.cursor = math.max(1, grid.cursor - 1) end
    if keys.r then grid.cursor = math.min(count, grid.cursor + 1) end
    mode_follow(grid)
    if keys.b then state.mode_grid = nil; return end
    if keys.c and mode_choose(state, grid.cells[grid.cursor]) then return end
    image(state, grid_mode.panel_pic, grid_mode.panel_x, grid_mode.panel_y)
    local chosen = state.options.bg_mode
    for line = 0, grid_mode.lines - 1 do
        for column = 0, grid_mode.columns - 1 do
            local position = (grid.top + line) * grid_mode.columns + column + 1
            local mode = grid.cells[position]
            if mode then
                local x, y = grid_mode.x + column * grid_mode.step_x, grid_mode.y + line * grid_mode.step_y
                -- A cell shows the mode's `smallb:` when it has one, else the background's own `small:` (its grid picture,
                -- bg/sys/grid/<n>.bmp). A mode's `small:` is the preview picture (small_background), not this one.
                local picture = existing_picture(mode.smallb) or grid_picture(state, grid.row)
                if picture and grid_has(picture) then image(state, picture, x, y) end
                local gray = ((chosen == mode.effects and (chosen ~= nil or position == 1)) and 255)
                    or (position == grid.cursor and 140 or nil)
                if gray then
                    fill(state, x - 2, y - 2, grid_mode.w + 4, 2, gray)
                    fill(state, x - 2, y + grid_mode.h, grid_mode.w + 4, 2, gray)
                    fill(state, x - 2, y - 2, 2, grid_mode.h + 4, gray)
                    fill(state, x + grid_mode.w, y - 2, 2, grid_mode.h + 4, gray)
                end
                text(state, mode.title, x + grid_mode.name_x, y + grid_mode.name_y, mode.supported and white or 0x808098)
            end
        end
    end
    -- Why the mode under the cursor cannot be chosen: the tags of its file that are not done yet.
    local under = grid.cells[grid.cursor]
    if under and not under.supported and under.unsupported and #under.unsupported > 0 then
        text(state, "Not supported yet: " .. table.concat(under.unsupported, ", "):sub(1, 90), grid_mode.panel_x + 12,
            grid_mode.panel_y + grid_mode.panel_h - 20, 0xffb060)
    end
end

-- LF2 Darkfiren's stage list (data/stage.dat) and <grid_stage> (mode4.dat): a panel at (1, 140) with the levels in one
-- row, three at a time, from (25, 180) every 260 pixels, each a 212x109 picture (the level's `small`) with its name below.
-- A tap on a level chooses it; left and right move, attack chooses, jump leaves. Hidden levels follow the cheat code.
-- A file whose <grid_stage> gives `centery` above 0 (the wide menus: `row: 3`, `centery: 135`, the panel BOX_BGMODE at (1, 1))
-- lays the levels in lines instead, as many as the panel picture holds (four for 547 pixels), like the mode list: up and down
-- move a line, the lines scroll with the cursor. step_y stays 0 for the built-in single row.
local grid_stage = {panel_x = 1, panel_y = 140, panel_w = 790, panel_h = 185, x = 25, y = 180, w = 212, h = 109,
    step_x = 260, step_y = 0, columns = 3, name_x = 25, name_y = 110, panel_pic = "sprite/ui/grid/box_stage.bmp"}
layout_targets.grid_stage = grid_stage
-- Lines of levels the popup draws and the height of its panel (the click area): one line of 185 pixels unless the file asks
-- for lines with `centery`; then the panel picture's height (the screen's when the picture is missing).
local function stage_panel_height()
    if grid_stage.step_y < 1 then return grid_stage.panel_h end
    local _, height = picture_size(grid_stage.panel_pic)
    return height or constants.screen.height
end
local function stage_lines()
    if grid_stage.step_y < 1 then return 1 end
    return fitting_lines(grid_stage, grid_stage.step_y)
end
local function stage_follow(grid)
    local lines = stage_lines()
    local line = math.floor((grid.cursor - 1) / grid_stage.columns)
    if lines == 1 or line < grid.top then grid.top = line
    elseif line >= grid.top + lines then grid.top = line - lines + 1 end
end
local stage_data_cache
local function stage_data()
    if stage_data_cache == nil then
        local ok, data = pcall(engine.read_stage_data, "data/stage.dat")
        stage_data_cache = ok and data or false
    end
    return stage_data_cache or nil
end
-- The level list replaces the original's group counter only when the game has one and this is Stage mode.
local function levels_wanted(state)
    return state.mode == constants.modes.stage and stage_levels.active(stage_data())
end
local function stage_cells()
    return stage_levels.visible(stage_data(), allows)
end
local function open_stage_grid(state)
    local cells = stage_cells()
    local cursor = 1
    for position, info in ipairs(cells) do
        if info.id == math.floor(state.options.stage_level / 10) then cursor = position end
    end
    if #cells == 0 then return end
    state.stage_grid = {cells = cells, cursor = cursor, top = 0}
    stage_follow(state.stage_grid)
end
local function stage_choose(state, info)
    state.options.stage_level = info.id * 10
    sounds.direct(state, "ok")
    state.stage_grid = nil
end
local function stage_popup(state, previous_menu)
    local grid, held = state.stage_grid, state.held
    local function inside(x, y, left, top, width, height) return x >= left and x < left + width and y >= top and y < top + height end
    local lines, columns = stage_lines(), grid_stage.columns
    if held.click and held.pointer_x and held.pointer_x >= 0 and held.pointer_y and held.pointer_y >= 0 then
        local px, py = held.pointer_x - (state.dx or 0), held.pointer_y
        for line = 0, lines - 1 do
            for column = 0, columns - 1 do
                local info = grid.cells[(grid.top + line) * columns + column + 1]
                local x, y = grid_stage.x + column * grid_stage.step_x, grid_stage.y + line * grid_stage.step_y
                if info and inside(px, py, x, y, grid_stage.w, grid_stage.name_y + 16) then
                    stage_choose(state, info)
                    return
                end
            end
        end
        if not inside(px, py, grid_stage.panel_x, grid_stage.panel_y, grid_stage.panel_w, stage_panel_height()) then
            state.stage_grid = nil
            return
        end
    end
    local keys = {}
    local accept = previous_menu == menus.options
    for index = 0, (state.slot_count or 8) - 1 do
        local slot = state.slots[index]
        if slot.ready then
            local keys_held = state.held[index] or ""
            local key
            for _, candidate in ipairs({"u", "d", "l", "r", "c", "b"}) do
                if pressed(keys_held, candidate) then key = candidate; break end
            end
            if key then keys[key] = trigger(slot, accept) or keys[key]
            else slot.latched = false end
        end
    end
    local count = #grid.cells
    if lines > 1 then   -- the single row has nothing above or below
        if keys.u then grid.cursor = math.max(1, grid.cursor - columns) end
        if keys.d then grid.cursor = math.min(count, grid.cursor + columns) end
    end
    if keys.l then grid.cursor = math.max(1, grid.cursor - 1) end
    if keys.r then grid.cursor = math.min(count, grid.cursor + 1) end
    stage_follow(grid)
    if keys.b then state.stage_grid = nil; return end
    if keys.c then stage_choose(state, grid.cells[grid.cursor]); return end
    image(state, grid_stage.panel_pic, grid_stage.panel_x, grid_stage.panel_y)
    local chosen = math.floor(state.options.stage_level / 10)
    for line = 0, lines - 1 do
        for column = 0, columns - 1 do
            local position = (grid.top + line) * columns + column + 1
            local info = grid.cells[position]
            if info then
                local x, y = grid_stage.x + column * grid_stage.step_x, grid_stage.y + line * grid_stage.step_y
                local picture = (info.small or ""):gsub("\\", "/"):lower()
                if picture ~= "" and grid_has(picture) then image(state, picture, x, y) end
                local gray = info.id == chosen and 255 or (position == grid.cursor and 140 or nil)
                if gray then
                    fill(state, x - 2, y - 2, grid_stage.w + 4, 2, gray)
                    fill(state, x - 2, y + grid_stage.h, grid_stage.w + 4, 2, gray)
                    fill(state, x - 2, y - 2, 2, grid_stage.h + 4, gray)
                    fill(state, x + grid_stage.w, y - 2, 2, grid_stage.h + 4, gray)
                end
                text(state, info.name, x + grid_stage.name_x, y + grid_stage.name_y, info.boss == 1 and computer_red or white)
            end
        end
    end
end

-- The three popups (background list, mode list, stage list) are laid out for 794 pixels: in the wide menu they sit in the middle
-- of the wider picture (drawing and pointer both).
local function centered_popup(state, popup, previous_menu)
    state.dx = math.floor(popup_gap(state) / 2 + 0.5)
    local result = popup(state, previous_menu)
    state.dx = 0
    return result
end
local grid_popup_body, mode_popup_body, stage_popup_body = grid_popup, mode_popup, stage_popup
grid_popup = function(state, previous_menu) return centered_popup(state, grid_popup_body, previous_menu) end
mode_popup = function(state, previous_menu) return centered_popup(state, mode_popup_body, previous_menu) end
stage_popup = function(state, previous_menu) return centered_popup(state, stage_popup_body, previous_menu) end

-- What attack does on a row of the options menu (the classic panel's rows, then the extra rows).
-- LF2 Darkfiren's options panel (<menu_small> of mode4.dat, game/menu_small.lua): picture rows stacked from the top
-- left, the selected one lit by its highlight picture, values written into the boxes the pictures leave.
local function small_menu_wanted(state)
    local first = small_layers[1]
    return state.wide and first ~= nil and first.small ~= nil and grid_has(first.small)
end
local function background_has_modes(state)
    local row = state.options.background
    if state.options.random_background or row == constants.background_rows.random then return false end
    return #visible_modes(row) > 1
end
-- Layer 6 (`more-options`, mode3.dat) is the "Open/Close Extra Settings" row: `small` is its Open picture, `smallb` the Close one
-- (`head` and `smallc` the lit ones). The layers marked `kind: 1` (7 to 12: background mode, time, cost, drops, TU mode, Exit)
-- are shown only while it is open. mode4.dat has no `kind` and a layer 6 that is never shown, so its rows are always there.
local extra_toggle = 6
-- The original game (checked on its screenshot): while the extra settings are OPEN the row reads "Close Extra Settings", which
-- is `smallb` (`smallc` lit); while they are closed it reads "Open Extra Settings", which is `small` (`head` lit). The readme's
-- "small ... if settings is on" does not mean that. true would swap the two (it showed "Open" while open in OpenLF2).
local extra_on_uses_small = false
local hitlag_steps = 5   -- hitlag modes 0 (normal) and -1 to -5 (readme/hitlag mode.txt); `D` (defend) on the difficulty row cycles them
local small_forced = {[7] = true, [8] = true}
-- The `mode:` lines of <cost> name the game modes that have the cost mode (none named: all of them).
function cost_in_mode(mode)
    local list = cost_settings.modes
    if not list or #list == 0 then return true end
    for _, listed in ipairs(list) do if listed == mode then return true end end
    return false
end
local function small_rows(state)
    local stage_mode = state.mode == constants.modes.stage
    local skip = {[8] = not stage_mode and #time_list == 0, [9] = stage_mode or #cost_settings.pools == 0 or not cost_in_mode(state.mode)}
    return menu_small.rows(small_layers, state.mode, allows, small_forced, skip, state.options.extra_open), stage_mode,
        not stage_mode and background_has_modes(state)
end
local function small_disabled(number, stage_mode, has_modes)
    return (number == 7 and (stage_mode or not has_modes)) or (number == 8 and stage_mode)
end

local function option_action(state, context, row, extras)
    local options = state.options
    sounds.direct(state, "ok")
    if row == option_rows.start then
        if state.mode == constants.modes.versus then music.play_selected() end
        -- The flow reads selection.match_options(state) to build the match.
        context.action("start_match")
    elseif row == option_rows.difficulty then
        options.difficulty = options.difficulty - 1
        local unlocked = require("base/game/unlock").flags.characters
        if (options.difficulty < constants.difficulties.difficult and unlocked == 0)
           or options.difficulty < constants.difficulties.crazy then
            options.difficulty = constants.difficulties.easy
        end
    elseif row > option_rows.exit and extras[row - option_rows.exit] then
        extras[row - option_rows.exit].action()
    elseif row == option_rows.exit then
        context.action("title")
    elseif row == option_rows.reselect then
        for index = 0, (state.slot_count or 8) - 1 do
            local slot = state.slots[index]
            slot.phase = slot_phases.empty
            slot.latched = true
            if slot.was_random then slot.fighter = 0 end
        end
        state.countdown = idle_countdown
        state.menu = menus.human_slots
    elseif row == option_rows.background then
        if levels_wanted(state) then
            open_stage_grid(state)
        elseif state.mode == constants.modes.stage then
            options.stage_level = (options.stage_level + 10) % 60
        elseif state.wide then
            open_grid(state)
        else
            options.random_background = false
            if options.background == constants.background_rows.random then options.background = 0
            else
                options.background = options.background + 1
                if options.background == #state.backgrounds then
                    options.background = constants.background_rows.random
                    options.random_background = true
                end
            end
        end
    elseif row == option_rows.reroll then
        for index = 0, (state.slot_count or 8) - 1 do
            local slot = state.slots[index]
            if slot.was_random then slot.fighter, slot.skin = pick_fighter(state), nil end
        end
    end
end

local function small_menu(state, previous_menu, context)
    local options = state.options
    -- The extra settings start closed; the choice is kept from then on.
    if options.extra_open == nil then options.extra_open = false end
    options.time_index = math.min(options.time_index or 0, #time_list)
    options.cost_index = math.min(options.cost_index or 0, #cost_settings.pools)
    if options.random_background then options.background = constants.background_rows.random end
    local rows, stage_mode, has_modes = small_rows(state)
    local cost_on = options.cost_index > 0
    if stage_mode then options.stage_level = options.stage_level - options.stage_level % 10 end
    -- The selected row must exist and be usable.
    local present = false
    for _, row in ipairs(rows) do
        if row.layer == options.small_row and not small_disabled(row.layer, stage_mode, has_modes) then present = true end
    end
    if not present then options.small_row = 1 end
    local sub_count = cost_on and 3 or 2
    options.sub_row = math.min(options.sub_row or 1, sub_count)
    for _, row in ipairs(rows) do
        local number, layer = row.layer, small_layers[row.layer]
        local x, y = layer.x or 3, row.y
        local selected = options.small_row == number
        local color = menu_small.colour(layer.hex) or option_blue
        local base, light = layer.small, layer.head
        if number == 4 and stage_mode then base, light = layer.smallb or base, layer.smallc or light
        elseif number == 7 and stage_mode then base, light = layer.smallc or base, nil
        elseif number == 7 and not has_modes then base, light = layer.smallb or base, nil
        elseif number == 8 and stage_mode then base, light = layer.smallb or base, nil
        elseif number == 10 then base, light = (cost_on and layer.head) or layer.smalld or layer.head, nil
        elseif number == extra_toggle and (options.extra_open == true) ~= extra_on_uses_small then base, light = layer.smallb or base, layer.smallc or light end
        if base then keyed_image(state, base, x, y) end
        if selected and light then keyed_image(state, light, x, y) end
        -- Layer 6's check box (`smalld` at `dx`, `y + dy`, or at `fy`), drawn while the extra settings are on.
        if number == extra_toggle and options.extra_open and layer.smalld and layer.dx then
            keyed_image(state, layer.smalld, layer.dx, layer.fy or (y + (layer.dy or 0)))
        end
        if number == 3 and options.hide_random and layer.smallb then keyed_image(state, layer.smallb, layer.dx or 0, layer.dy or 0)
        elseif number == 4 then
            if stage_mode then
                local level = math.floor(options.stage_level / 10)
                local info = levels_wanted(state) and stage_levels.level(stage_data(), level)
                text(state, info and info.name or (level < 5 and tostring(level + 1) or "Survival"), layer.next or 107, layer.dy or 91, color)
            else
                text(state, background_name(state, options.background), layer.dx or 174, layer.dy or 91, color)
            end
        elseif number == 5 then
            -- The name and colour come from the mode file's <mode> (layers 1 to 4: easy, normal, difficult, crazy); the
            -- built-in names stay for a file without it. `fy` is a fixed y that wins over `dy`.
            local entry = small_modes[difficulty_layers[options.difficulty]]
            text(state, entry and entry.name or difficulties[options.difficulty] or "", layer.dx or 174,
                layer.fy or (y + (layer.dy or 4)), entry and menu_small.colour(entry.hex) or option_blue)
            -- The hitlag mode (<mode> layers 6 to 10 for -1 to -5) at (`dvx`, `dvy`), not moved by the row loop.
            local hitlag = options.hitlag or 0
            local hitlag_entry = hitlag < 0 and small_modes[5 - hitlag]
            if hitlag_entry then
                text(state, hitlag_entry.name, layer.dvx or 271, layer.dvy or 37, menu_small.colour(hitlag_entry.hex) or option_blue)
            end
        elseif number == 7 and not small_disabled(7, stage_mode, has_modes) then
            local modes = visible_modes(options.background)
            text(state, options.bg_mode_title or (modes[1] and modes[1].title) or "", layer.dx or 174, layer.fy or (y + (layer.dy or 5)), color)
        elseif number == 8 and not stage_mode then
            local limit = time_list[options.time_index]
            text(state, limit and string.format("%d:%02d", math.floor(limit / 60), limit % 60) or "Off", layer.dx or 174, layer.fy or (y + (layer.dy or 5)), color)
        elseif number == 9 then
            if cost_on then
                if layer.smallb then keyed_image(state, layer.smallb, layer.dvx or 108, y + (layer.dvy or 8)) end
                text(state, tostring(cost_settings.pools[options.cost_index]), layer.dx or 188, layer.fy or (y + (layer.dy or 8)), color)
                if options.shuffle and layer.smallb then keyed_image(state, layer.smallb, layer.next or 276, y + (layer.dvy or 8)) end
            end
        elseif number == 10 then
            local mark = layer.smallp
            if mark then
                local top = layer.fy or (y + (layer.dy or 8))
                if options.item_drops ~= false then keyed_image(state, mark, layer.dx or 65, top) end
                if options.allow_transform ~= false then keyed_image(state, mark, layer.dvx or 151, top) end
                if cost_on and options.shuffle then keyed_image(state, mark, layer.next or 276, top) end
            end
            if selected then
                local focus = ({layer.small, layer.smallb, layer.smallc})[options.sub_row]
                if focus then keyed_image(state, focus, x, y) end
            end
        end
    end
    -- Not drawn: a layer's `pic` (with `pickedact`, `centerx`, `centery`). Release R24 drew it for the selected row, but the
    -- 10 player file (mode3.dat) gives every layer a `pic` that is a leftover picture (pause.bmp, demo.bmp, davis_f.bmp,
    -- julian_s.bmp ...) and the row would show it over the panel (PAUSE, DEMO and fighter faces popping up). LF2 Darkfiren
    -- does not show them. The keys are still parsed by game/menu_small.lua.
    -- The TU mode's state sits in a black box at the Fight! row (layer 11's `dx`, `fy`), while layer 11's own row is shown;
    -- with `caughtact: 1` it is always there (the extra settings closed too), as long as the layer may show in this mode.
    local tu = small_layers[11]
    local tu_shown = false
    for _, row in ipairs(rows) do if row.layer == 11 then tu_shown = true end end
    if tu and not tu_shown and tu.caughtact == 1 then
        tu_shown = menu_small.shown(tu, state.mode, allows, true, 11)
    end
    if tu and tu_shown then
        local box_x, box_y = (tu.dx or 271), (tu.fy or 17)
        fill(state, box_x - 3, box_y - 2, 29, 15, 0)
        text(state, options.tu1 and "1tu" or "2tu", box_x, box_y, white)
    end
    -- The preview frame sits behind the background and mode lists (the original draws the list over it).
    if state.wide and (state.grid or state.mode_grid) then small_background(state) end
    if state.grid then return grid_popup(state, previous_menu) end
    if state.mode_grid then return mode_popup(state, previous_menu) end
    if state.stage_grid then return stage_popup(state, previous_menu) end

    local keys = {}
    local accept = previous_menu == menus.options
    for index = 0, (state.slot_count or 8) - 1 do
        local slot = state.slots[index]
        if slot.ready then
            local held = state.held[index] or ""
            local key
            for _, candidate in ipairs({"u", "d", "r", "l", "c", "b", "f"}) do
                if pressed(held, candidate) then key = candidate; break end
            end
            if key then keys[key] = trigger(slot, accept) or keys[key]
            else slot.latched = false end
        end
    end
    local function move(step)
        local position
        for index, row in ipairs(rows) do if row.layer == options.small_row then position = index end end
        position = position or 1
        for _ = 1, #rows do
            position = (position - 1 + step) % #rows + 1
            local layer = rows[position].layer
            if not small_disabled(layer, stage_mode, has_modes) then options.small_row = layer; return end
        end
    end
    if keys.u then move(-1) end
    if keys.d then move(1) end
    music_option(state, keys.l, keys.r)
    local number = options.small_row
    local layer9_j = small_layers[9] and small_layers[9].caughtact == 1
    if keys.b then
        if number == 3 then options.hide_random = not options.hide_random; sounds.direct(state, "ok")
        -- J goes back through the values that A steps forward: difficulty, time limit, cost pool. (The random respawn that
        -- layer 9's `caughtact: 1` gave J is still on the sub row of layer 10.)
        elseif number == 5 then
            local unlocked = require("base/game/unlock").flags.characters
            options.difficulty = options.difficulty + 1
            if options.difficulty > constants.difficulties.easy then
                options.difficulty = unlocked == 0 and constants.difficulties.difficult or constants.difficulties.crazy
            end
            sounds.direct(state, "ok")
        elseif number == 8 and not stage_mode then
            options.time_index = (options.time_index - 1) % (#time_list + 1); sounds.direct(state, "ok")
        elseif number == 9 then
            options.cost_index = (options.cost_index - 1) % (#cost_settings.pools + 1); sounds.direct(state, "ok")
        elseif number == 10 then options.sub_row = options.sub_row % sub_count + 1; sounds.direct(state, "ok") end
    end
    -- `D` (defend) on the difficulty row: the hitlag mode 0, -1 ... -5 (readme/hitlag mode.txt).
    if keys.f and number == 5 then
        options.hitlag = -(((-(options.hitlag or 0)) + 1) % (hitlag_steps + 1))
        sounds.direct(state, "ok")
    end
    if not keys.c then return end
    if number == 1 then option_action(state, context, option_rows.start, {})
    elseif number == 2 then option_action(state, context, option_rows.reselect, {})
    elseif number == 3 then option_action(state, context, option_rows.reroll, {})
    elseif number == 4 then option_action(state, context, option_rows.background, {})
    elseif number == 5 then option_action(state, context, option_rows.difficulty, {})
    elseif number == 12 then option_action(state, context, option_rows.exit, {})
    elseif number == extra_toggle then
        sounds.direct(state, "ok")
        options.extra_open = not options.extra_open
    elseif number == 7 and has_modes then
        sounds.direct(state, "ok")
        open_mode_grid(state, options.background, visible_modes(options.background))
    elseif number == 8 and not stage_mode then
        sounds.direct(state, "ok")
        options.time_index = (options.time_index + 1) % (#time_list + 1)
    elseif number == 9 then
        sounds.direct(state, "ok")
        options.cost_index = (options.cost_index + 1) % (#cost_settings.pools + 1)
    elseif number == 10 then
        sounds.direct(state, "ok")
        if options.sub_row == 1 then options.item_drops = options.item_drops == false
        elseif options.sub_row == 2 then options.allow_transform = options.allow_transform == false
        elseif cost_on then options.shuffle = not options.shuffle end
    elseif number == 11 then
        sounds.direct(state, "ok")
        options.tu1 = not options.tu1
    end
end

local function options_menu(state, previous_menu, context)
    local options = state.options
    if small_menu_wanted(state) then return small_menu(state, previous_menu, context) end
    sprite(state, options_sheet, {348, 0, 304, 156}, 3, 3, false)
    sprite(state, options_sheet, {348, 156, 304, 10}, 3, 159, true)
    -- The extra rows under the options panel (LF2 Darkfiren's <menu_small> layers 8 to 10): time limit, cost pool, item
    -- drops, transform, respawn shuffle. They exist in the wide layout, not in Stage mode, and only where mode4.dat
    -- offers the choices (time limits, cost pools).
    local extras = {}
    if state.wide and state.mode ~= constants.modes.stage then
        options.time_index = math.min(options.time_index or 0, #time_list)
        options.cost_index = math.min(options.cost_index or 0, #cost_settings.pools)
        if #time_list > 0 then
            extras[#extras + 1] = {label = "Time limit:", value = function()
                local limit = time_list[options.time_index]
                return limit and string.format("%d:%02d", math.floor(limit / 60), limit % 60) or "Off"
            end, action = function() options.time_index = (options.time_index + 1) % (#time_list + 1) end}
        end
        if #cost_settings.pools > 0 and cost_in_mode(state.mode) then
            extras[#extras + 1] = {label = "Cost pool:", value = function()
                return options.cost_index > 0 and tostring(cost_settings.pools[options.cost_index]) or "Off"
            end, action = function() options.cost_index = (options.cost_index + 1) % (#cost_settings.pools + 1) end}
        end
        extras[#extras + 1] = {label = "Item drops:", value = function() return options.item_drops == false and "Off" or "On" end,
            action = function() options.item_drops = options.item_drops == false end}
        extras[#extras + 1] = {label = "Transform:", value = function() return options.allow_transform == false and "Off" or "On" end,
            action = function() options.allow_transform = options.allow_transform == false end}
        if #cost_settings.pools > 0 and cost_in_mode(state.mode) then
            extras[#extras + 1] = {label = "Respawn shuffle:", value = function() return options.shuffle and "On" or "Off" end,
                action = function() options.shuffle = not options.shuffle end}
        end
    end
    -- TU mode (LF2 Darkfiren, <menu_small> layer 11): 1tu reads the keys every time unit instead of every second one,
    -- for smoother input. It is offered in every mode of the wide layout.
    if state.wide then
        extras[#extras + 1] = {label = "TU mode:", value = function() return options.tu1 and "1tu" or "2tu" end,
            action = function() options.tu1 = not options.tu1 end}
    end
    local last_row = option_rows.exit + #extras
    if options.row > last_row then options.row = option_rows.start end
    local highlight = option_highlights[options.row]
    if highlight then sprite(state, options_sheet, highlight[1], highlight[2], highlight[3], false) end
    for position, extra in ipairs(extras) do
        local y = 175 + 20 * (position - 1)
        local color = options.row == option_rows.exit + position and white or option_blue
        text(state, extra.label, 15, y, color)
        text(state, extra.value(), 150, y, color)
    end
    if options.random_background then options.background = constants.background_rows.random end
    if state.mode == constants.modes.stage then
        options.stage_level = options.stage_level - options.stage_level % 10
        sprite(state, options_sheet, {330, 363, 279, 22}, 15, 87, false)
        if options.row == option_rows.background then sprite(state, options_sheet, {330, 332, 279, 22}, 15, 87, false) end
        local level = math.floor(options.stage_level / 10)
        if levels_wanted(state) then
            local info = stage_levels.level(stage_data(), level)
            text(state, info and info.name or tostring(level), 174, 91, option_blue)
        elseif level < 5 then text(state, tostring(level + 1), 194, 91, option_blue)
        else text(state, "Survival", 174, 91, option_blue) end
    else
        text(state, background_name(state, options.background), 174, 91, option_blue)
    end
    text(state, difficulties[options.difficulty] or "", 174, 115, option_blue)
    -- The preview frame sits behind the background and mode lists (the original draws the list over it).
    if state.wide and (state.grid or state.mode_grid) then small_background(state) end
    if state.grid then return grid_popup(state, previous_menu) end
    if state.mode_grid then return mode_popup(state, previous_menu) end
    if state.stage_grid then return stage_popup(state, previous_menu) end

    local keys = {}
    local accept = previous_menu == menus.options
    for index = 0, (state.slot_count or 8) - 1 do
        local slot = state.slots[index]
        if slot.ready then
            local held = state.held[index] or ""
            local key
            for _, candidate in ipairs({"u", "d", "r", "l", "c"}) do
                if pressed(held, candidate) then key = candidate; break end
            end
            if key then
                keys[key] = trigger(slot, accept) or keys[key]
            else
                -- Jump neither acts nor releases the latch here.
                slot.latched = pressed(held, "b")
            end
        end
    end
    if keys.u then
        options.row = options.row - 1
        if options.row < 0 then options.row = last_row end
    end
    if keys.d then options.row = (options.row + 1) % (last_row + 1) end
    music_option(state, keys.l, keys.r)
    if not keys.c then return end
    option_action(state, context, options.row, extras)
end

function selection.reset_all(state)
    for index = 0, (state.slot_count or 8) - 1 do
        local slot = state.slots[index]
        slot.phase = slot_phases.empty
        slot.latched = true
        if slot.was_random then slot.fighter = 0 end
    end
    state.countdown = idle_countdown
    state.menu, state.last_menu = menus.human_slots, menus.human_slots
    state.display = {}
    return state
end

function selection.resume_options(state, outcome)
    if outcome and outcome.stage_level then state.options.stage_level = outcome.stage_level end
    for index = 0, (state.slot_count or 8) - 1 do state.slots[index].latched = true end
    state.menu, state.last_menu = menus.options, menus.options
    state.display = {}
    return state
end

-- Match setup for base/game/match: human slots are joined (1-10), computers 11 and up.
function selection.match_options(state)
    local slots = {}
    for index = 0, (state.slot_count or 8) - 1 do
        local slot = state.slots[index]
        if slot.phase >= slot_phases.choosing_fighter and slot.phase <= slot_phases.computer_fighter - 1 then
            slots[index] = {kind = "human", fighter = slot.fighter, team = slot.team, random = slot.was_random, skin = chosen_skin(slot)}
        elseif slot.phase >= slot_phases.computer_fighter then
            slots[index] = {kind = "computer", fighter = slot.fighter, team = slot.team, random = slot.was_random, skin = chosen_skin(slot),
                backup = backup_marked(state, slot) or nil}
        end
    end
    return {mode = state.mode, difficulty = state.options.difficulty, background = state.options.background,
        stage_level = state.options.stage_level,
        time_limit = state.wide and state.mode ~= constants.modes.stage and (state.options.time_index or 0) > 0
            and time_list[state.options.time_index] or nil, time_type = time_type,
        cost = state.wide and state.mode ~= constants.modes.stage and cost_in_mode(state.mode) and (state.options.cost_index or 0) > 0 and
            {pool = cost_settings.pools[state.options.cost_index], kind = cost_settings.kind, groups = cost_settings.groups,
                randoms = cost_settings.randoms, team = cost_settings.team, y = cost_settings.y, dy = cost_settings.dy} or nil,
        no_item_drops = state.wide and state.mode ~= constants.modes.stage and state.options.item_drops == false or nil,
        no_transform = state.wide and state.mode ~= constants.modes.stage and state.options.allow_transform == false or nil,
        respawn_shuffle = state.wide and state.mode ~= constants.modes.stage and cost_in_mode(state.mode) and (state.options.cost_index or 0) > 0
            and state.options.shuffle or nil,
        tu1 = state.wide and state.options.tu1 == true or nil,
        -- The Defense box of the computer count dialog (`allow_defense`): the armor of the computer fighters.
        computer_defense = defense_dialog(state) and (state.options.computer_defense or constants.defense.normal) ~= constants.defense.normal
            and state.options.computer_defense or nil,
        -- [BELUM TERHUBUNG] the hitlag mode (0, -1 ... -5) is chosen and carried to the match; combat does not read it yet.
        hitlag = state.wide and (state.options.hitlag or 0) ~= 0 and state.options.hitlag or nil,
        bg_mode = state.mode ~= constants.modes.stage and not state.options.random_background and state.options.bg_mode or nil,
        fighters = state.fighters, backgrounds = state.backgrounds, slots = slots}
end

-- The roster of the wide menu (mode4.dat's <grid_char>): every selectable fighter as a 40x45 face, 21 to a row from
-- (45, 320) every 60 by 66 pixels, under a panel at (22, 294). A tap on a face gives it to the first slot that is
-- choosing a fighter; a fighter a slot has chosen is framed and labelled with who has it.
local roster = {x = 45, y = 320, columns = 21, step_x = 60, step_y = 66, width = 40, height = 45,
    human_x = 12, human_y = 46, com_x = 7, com_y = 46, panel_x = 22, panel_y = 294,
    panel_pic = "sprite/ui/grid/box_char2.bmp", small_pic = "sprite/ui/grid/rface_small.bmp"}
layout_targets.roster = roster
local function roster_cell(position)
    return roster.x + (position % roster.columns) * roster.step_x,
        roster.y + math.floor(position / roster.columns) * roster.step_y
end
local function roster_fighters(state)
    local cells = {0}
    for index, fighter in ipairs(state.fighters) do
        if catalog.listed(fighter) then cells[#cells + 1] = index end
    end
    return cells
end
local function roster_panel(state)
    -- A game whose mode file has no <grid_char> (and no sprite/ui/grid/box_char2.bmp) has no roster panel: a missing
    -- picture is skipped, not asked of the host (which stops the app on it).
    if grid_has(roster.panel_pic) then image(state, roster.panel_pic, roster.panel_x, roster.panel_y) end
end
local function roster_pass(state, held)
    local cells = roster_fighters(state)
    -- A tap picks for the first slot that is choosing a fighter.
    if held and held.click and held.pointer_x and held.pointer_x >= 0 and held.pointer_y and held.pointer_y >= 0 then
        for position, fighter_index in ipairs(cells) do
            local x, y = roster_cell(position - 1)
            if held.pointer_x >= x and held.pointer_x < x + roster.step_x - 10
               and held.pointer_y >= y and held.pointer_y < y + roster.height + 16 then
                for index = 0, (state.slot_count or 8) - 1 do
                    local slot = state.slots[index]
                    if slot.phase == slot_phases.choosing_fighter then
                        slot.fighter = fighter_index
                        sounds.direct(state, "ok")
                        break
                    end
                end
                break
            end
        end
    end
    local owners = {}
    for index = 0, (state.slot_count or 8) - 1 do
        local slot = state.slots[index]
        if slot.phase >= slot_phases.choosing_fighter and not (state.options.hide_random and slot.was_random) then
            local computer = slot.phase >= computer_phase
            owners[slot.fighter] = {computer = computer, label = computer and "COM" or ("P" .. (index + 1)),
                color = computer and computer_red or white, gray = computer and 160 or 255}
        end
    end
    for position, fighter_index in ipairs(cells) do
        local x, y = roster_cell(position - 1)
        local fighter = state.fighters[fighter_index]
        local face = fighter and fighter.small or roster.small_pic
        if fighter or grid_has(face) then image(state, face, x, y) end
        local owner = owners[fighter_index]
        if owner then
            fill(state, x - 1, y - 1, roster.width + 2, 1, owner.gray)
            fill(state, x - 1, y + roster.height, roster.width + 2, 1, owner.gray)
            fill(state, x - 1, y - 1, 1, roster.height + 2, owner.gray)
            fill(state, x + roster.width, y - 1, 1, roster.height + 2, owner.gray)
            text(state, owner.label, x + (owner.computer and roster.com_x or roster.human_x),
                y + (owner.computer and roster.com_y or roster.human_y), owner.color)
        end
    end
end

-- <misc> `background_small`: the chosen background's small map picture (bg/sys/map/<name>.bmp) in a frame next to the
-- music line; Random shows sprite/ui/bg_random.bmp. Stage mode has no single background to show.
small_background = function(state)
    state.small_frame = state.frames   -- drawn in this update (see selection.update)
    if misc.show_small ~= 1 or state.mode == constants.modes.stage then return end
    local row = state.options.background
    local picture
    if state.options.random_background or row == constants.background_rows.random then
        -- Random shows BG_RANDOM, line 8 of resource.dat (sprite\\UI\\BG_RANDOM.bmp), as "pe/bg_random". The `small:` of <grid_bg>
        -- (BG_GRID_RANDOM) is the thumbnail of the background list, not this preview, so it is no longer used here.
        picture = "pe/bg_random"
        if not grid_has(picture) then picture = existing_picture("UI/BG_RANDOM.png") or "sprite/ui/bg_random.bmp" end
    else
        local entry = state.backgrounds[row + 1]
        picture = "bg/sys/map/" .. (entry and entry.path:match("bg/sys/([^/]+)/") or "temp") .. ".bmp"
    end
    -- The preview is the `small:` of the chosen background mode, else of the background's first mode; without either, the
    -- picture derived from the path above.
    if not (state.options.random_background or row == constants.background_rows.random) and row >= 0 and row < constants.background_rows.random then
        local wanted = existing_picture(state.options.bg_mode_small)
        if not wanted then
            for _, mode in ipairs(load_modes(row)) do
                wanted = existing_picture(mode.small)
                if wanted then break end
            end
        end
        if wanted then picture = wanted end
    end
    if not grid_has(picture) then return end
    -- The mode files give the classic top right corner (x 531 of 794); in a wider picture it follows the right edge.
    local gap = popup_gap(state)
    -- BG_FRAME (260 x 144 in the game) is the frame of the preview and the background's picture (BG_RANDOM: 246 x 127) sits 7 pixels in.
    -- The mode's `pic` (MENU_CLIP2b, 704 x 353) is a sheet of menu pictures, not a frame: it is not drawn here. The resource is
    -- looked for as a file and, as the original keeps it, in the game's resources (resource.dat).
    for _, base in ipairs({existing_picture("UI/BG_FRAME.png") or "ui/bg_frame.png", "sprite/ui/bg_frame.bmp", "pe/bg_frame"}) do
        if grid_has(base) then image(state, base, misc.frame_x + gap, misc.frame_y) break end
    end
    image(state, picture, misc.small_x + gap, misc.small_y)
end

function selection.update(state, held, context)
    state.display = {}
    state.held = held
    state.leave = false
    state.blink = (state.blink + 1) % 30
    state.frames = (state.frames or 0) + 1
    local previous_menu = state.menu
    use_layout(state)
    fill(state, 0, 0, state.wide and (state.width or constants.screen.wide_width) or constants.screen.width, state.height or constants.screen.height, 0)
    if state.wide then
        if not state.no_roster then roster_panel(state) end
        image(state, menu.pic, menu.x, menu.y)
    else
        image(state, "pe/charmenu", 40, 33)
    end
    slots_pass(state, held)
    if state.wide and not state.no_roster then roster_pass(state, held) end
    if state.layout_note then text(state, state.layout_note, 6, (state.height or constants.screen.height) - 14, 0xffd34c) end
    if state.hint and state.hint_until and (state.frames or 0) < state.hint_until then
        local draw = state.hint.transparency and keyed_image or image
        draw(state, state.hint.pic, state.hint.x, state.hint.y)
    end
    state.last_menu = state.menu
    if state.menu == menus.computer_count then computer_count_menu(state, previous_menu) end
    if state.menu == menus.computer_slots or state.menu == menus.options then computer_menu(state, previous_menu) end
    if state.countdown < 1 and state.menu == menus.human_slots then state.menu = menus.computer_count end
    if state.leave then context.action("title") end
    if state.menu == menus.options and state.mode ~= constants.modes.battle then
        options_menu(state, previous_menu, context)
        -- With the menu panel and the music line, not before: the chosen background's small picture.
        -- A list opened by this very press was not there when the options menu drew its frame, so the picture must still be
        -- drawn this update or it (and its frame) would blink for one frame.
        if state.wide and (not (state.grid or state.mode_grid) or state.small_frame ~= state.frames) then small_background(state) end
    elseif state.menu == menus.options and previous_menu ~= menus.options then
        context.action("battle_setup")
    end
    for _, sound in ipairs(sounds.flush(state)) do context.sound(sound.resource, sound.volume, sound.pan) end
end

-- The picture the screen is drawn on (updated by draw); flow.lua puts the status line at its bottom edge.
selection.view = {width = constants.screen.width, height = constants.screen.height}
function selection.draw(state, context)
    local view_width = state.wide and (state.width or constants.screen.wide_width) or constants.screen.width
    local view_height = state.height or constants.screen.height
    selection.view.width, selection.view.height = view_width, view_height
    context.viewport(view_width, view_height, 0, 0, 0)
    for _, command in ipairs(state.display) do
        if command[1] == "image" then context.image(command[2], command[3], command[4], command[5] == true)
        elseif command[1] == "sprite" then
            context.sprite(command[2], command[3], command[4], command[5], command[6])
        elseif command[1] == "text" then font.gdi(context, command[2], command[3], command[4], command[5], command[6], command[7])
        elseif command[1] == "fill" then
            context.fill(command[2], command[3], command[4], command[5], command[6], command[6], command[6])
        end
    end
end
-- Headless traces: menu, countdown and each slot's phase:fighter:team.
function selection.describe(state)
    local slots = {}
    for index = 0, (state.slot_count or 8) - 1 do
        local slot = state.slots[index]
        slots[#slots + 1] = string.format("%d:%d:%d", slot.phase, slot.fighter, slot.team)
    end
    return string.format("menu=%d countdown=%d slots=%s", state.menu, state.countdown, table.concat(slots, ","))
end
return selection
