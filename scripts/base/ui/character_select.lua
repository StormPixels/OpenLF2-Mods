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
local selection = {}
local idle_countdown = 150
local computer_phase, computer_team_phase, computer_done = slot_phases.computer_fighter, slot_phases.computer_team, slot_phases.computer_ready

-- LF2 Darkfiren's 8P super widescreen (mode4.dat): the eight slots stand in one row on CHARMENU3 (start_x 10,
-- 30 left of the classic 40) and every offset inside a slot stays as in the classic two rows of four.
-- The numbers below are what mode4.dat gives; selection.create takes the file's own (game/mode_layout.lua), so
-- these only stand when the file is missing or has no such tag.
local mode_layout = require("base/game/mode_layout")
local layout_targets = {}
local per_row, shift, step_x, step_y = 4, 0, 153, 212
local menu = {pic = "sprite/ui/charmenu3.bmp", x = 10, y = 33, row = 8, step_x = 153, step_y = 212}
layout_targets.menu = menu
local function origin(slot)
    return (slot % per_row) * step_x + shift, math.floor(slot / per_row) * step_y
end
local wide_known = {}
-- The wide menu needs the wide battlefield layout and a game that has the picture (LF2 Darkfiren).
local function wide_wanted()
    if user_options.current().battlefield_layout ~= user_options.wide_layout then return false end
    if wide_known[menu.pic] == nil then wide_known[menu.pic] = pcall(engine.read_resource, menu.pic) end
    return wide_known[menu.pic]
end
local function use_layout(state)
    if state.wide then per_row, shift, step_x, step_y = menu.row, menu.x - 40, menu.step_x, menu.step_y
    else per_row, shift, step_x, step_y = 4, 0, 153, 212 end
end
local function pressed(keys, key) return keys:find(key, 1, true) ~= nil end
local function image(state, path, x, y) state.display[#state.display + 1] = {"image", path, x, y} end
local white, computer_red, option_blue = 0xffffff, 0xff9b9b, 0x9b9bff
local music_title, music_hint = 0x5a77d8, 0x223fa0
local count_greyed, count_box = 0x5068c0, 0x2f479f
-- Red and green step up by 30 every 6th of the counter, from (25, 70); blue stays full.
local function blink_color(state)
    local step = state.blink % 6
    return (step * 30 + 0x19) * 65536 + (step * 30 + 0x46) * 256 + 0xff
end
local function text(state, value, x, y, color, background, align)
    state.display[#state.display + 1] = {"text", value, x, y, color, background, align}
end
-- The name field below a slot. Translated text is centered in its black area; the original's bitmap text
-- starts at a fixed column, padded with spaces.
local function slot_text(state, value, col, row, color, y, offset)
    local x = i18n.active() and col + 207
    if x then text(state, i18n.tr(value):match("^%s*(.-)$"), x, y or row + 219, color, nil, "center")
    else text(state, value, col + (offset or 177), y or row + 219, color) end
end
local function sprite(state, path, rectangle, x, y, keyed)
    state.display[#state.display + 1] = {"sprite", path, rectangle, x, y, keyed}
end
local function fill(state, x, y, width, height, gray)
    state.display[#state.display + 1] = {"fill", x, y, width, height, gray}
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
    for slot = 0, 7 do
        -- Teams persist between visits except where the mode prescribes them.
        local team = previous.slots and previous.slots[slot].team or 0
        if mode == constants.modes.stage then team = constants.teams.player_one
        elseif mode == constants.modes.battle then team = math.floor(slot / 4) + 1 end
        slots[slot] = {phase = slot_phases.empty, fighter = 0, team = team, latched = true, ready = false}
    end
    -- Option values are globals in the original and keep their values between visits.
    local options = previous.options or {row = option_rows.reroll, background = constants.background_rows.random, random_background = true,
        difficulty = 0, music = 0, stage_level = 0}
    -- mode4.dat's positions (only the wide layout draws with them); the built-in values come back first, so a file
    -- that lacks a tag (or is gone) leaves the built-in one.
    reset_layout()
    if user_options.current().battlefield_layout == user_options.wide_layout then
        local ok, text = pcall(engine.read_resource, "game/mode_file")
        if ok and text then mode_layout.apply(text, layout_targets) end
    end
    local state = {mode = mode, fighters = catalog.load(), backgrounds = catalog.backgrounds(),
        slots = slots, menu = menus.human_slots, last_menu = menus.human_slots, options = options,
        countdown = idle_countdown, computers = previous.computers or -100,
        order = {}, cursor = 0, previous_random = false, blink = 0, display = {}, wide = wide_wanted()}
    state.random_pool = state.wide and load_random_pool() or nil
    return state
end

local function pick_fighter(state)
    local function candidates_for(pool)
        local list = {}
        for index, fighter in ipairs(state.fighters) do
            local allowed
            if pool then allowed = pool[fighter.id] and catalog.selectable(fighter)
            else allowed = fighter.id < constants.record_id_ranges.random_fighter_end_exclusive end
            if fighter.record >= 1 and allowed then
                local taken = false
                for slot = 0, 7 do
                    if state.slots[slot].fighter == index then taken = true end
                end
                if not taken then list[#list + 1] = index end
            end
        end
        return list
    end
    local candidates = state.random_pool and candidates_for(state.random_pool) or {}
    if #candidates == 0 then candidates = candidates_for(nil) end
    -- The original would read an uninitialized candidate here.
    assert(#candidates > 0, "no fighter left for a random pick")
    return candidates[engine.random(#candidates) + 1]
end
local function resolve_random(state)
    for index = 0, 7 do state.slots[index].was_random = state.slots[index].fighter == 0 end
    for index = 0, 7 do
        local slot = state.slots[index]
        if slot.was_random then slot.fighter = pick_fighter(state) end
    end
end

-- Fighter 0 is Random; others index the catalog in file order.
local function next_fighter(state, slot) slot.fighter = catalog.step(state.fighters, slot.fighter, 1) end
local function previous_fighter(state, slot) slot.fighter = catalog.step(state.fighters, slot.fighter, -1) end

local function draw_fighter(state, slot, col, row, color)
    local fighter = state.fighters[slot.fighter]
    image(state, fighter and fighter.portrait or "pe/rface", col + 147, row + 94)
    slot_text(state, fighter and fighter.name or " Random", col, row, color, row + 241)
end
local function draw_team(state, slot, col, row, color)
    if slot.team == constants.teams.independent then slot_text(state, "Independent", col, row, color, row + 263, 167)
    else slot_text(state, "Team " .. slot.team, col, row, color, row + 263, 187) end
end

-- The last slot to pick a team may not join the side every other ready slot is on.
local function avoided_team(state, current)
    local avoid = -1
    for index = 0, 7 do
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
        slot.team = (slot.team + 1) % 5
    end
end
local function previous_team(state, slot, avoid)
    repeat
        slot.team = slot.team - 1
        if slot.team < 0 then slot.team = constants.teams.player_four end
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
        image(state, state.blink % 5 < 3 and "pe/cma" or "pe/cma2", col + 147, row + 94)
    elseif state.countdown >= 0 then
        image(state, "pe/cm" .. (math.floor(state.countdown / 30) + 1), col + 147, row + 94)
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

local function fighter_slot(state, slot, keys)
    if pressed(keys, "r") then
        if trigger(slot) then next_fighter(state, slot) end
    elseif pressed(keys, "l") then
        if trigger(slot) then previous_fighter(state, slot) end
    elseif pressed(keys, "u") then
        if trigger(slot) then slot.fighter = 0 end
    elseif pressed(keys, "c") then
        if trigger(slot) then
            slot.phase = state.mode == constants.modes.stage and slot_phases.ready or slot_phases.choosing_team
            sounds.direct(state, "join")
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
    for other = 0, 7 do
        if state.slots[other].phase == slot_phases.ready then ready = ready + 1 end
    end
    if ready == 7 and (state.mode == constants.modes.versus or state.mode == constants.modes.battle) then
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
                repeat slot.team = (slot.team + 1) % 5 until slot.team ~= avoid
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
        for index = 0, 7 do
            if state.slots[index].phase ~= slot_phases.empty then all_empty = false end
        end
    end
    local ready_count, idle_count, skip = 0, 0, false
    for index = 0, 7 do
        local slot = state.slots[index]
        local keys = held[index] or ""
        local col, row = origin(index)
        if slot.phase < slot_phases.choosing_fighter then
            -- "Join?" blinks while the join screen runs; afterwards the empty slot shows dashes.
            if state.menu == menus.human_slots then slot_text(state, "   Join?", col, row, blink_color(state))
            else slot_text(state, "     ----", col, row, white) end
        elseif slot.phase < computer_phase then slot_text(state, controls.name(index), col, row, white)
        else slot_text(state, "Computer", col, row, computer_red) end
        if slot.phase == slot_phases.empty and state.menu == menus.human_slots then empty_slot(state, index, slot, keys, col, row, all_empty) end
        if slot.phase == slot_phases.choosing_fighter then
            draw_fighter(state, slot, col, row, blink_color(state))
            fighter_slot(state, slot, keys)
        end
        if slot.phase == slot_phases.choosing_team then
            draw_fighter(state, slot, col, row, white)
            team_slot(state, index, slot, keys, col, row)
        end
        slot.ready = false
        if slot.phase == slot_phases.ready then
            draw_fighter(state, slot, col, row, white)
            draw_team(state, slot, col, row, white)
            if ready_slot(state, slot, keys) then skip = true end
            if slot.phase == slot_phases.ready then
                ready_count = ready_count + 1
                slot.ready = true
            end
        end
        if slot.phase == slot_phases.empty or slot.phase == slot_phases.ready then idle_count = idle_count + 1 end
    end
    local previous = state.countdown
    if ready_count < 1 or idle_count ~= 8 then
        state.countdown = idle_countdown
    else
        state.countdown = state.countdown - 1
        if skip then state.countdown = previous - 31 end
        if ready_count == 8 then state.countdown = 0 end
    end
end

local function computer_count_menu(state, previous_menu)
    -- The dialog is laid out for the classic 794-wide picture; the wide menu moves it to the middle of its picture.
    local dx = state.wide and math.floor((constants.screen.wide_width - constants.screen.width) / 2 + 0.5) or 0
    image(state, "pe/cmc", 218 + dx, 215)
    local free, sides, teams = 0, 0, {}
    for index = 0, 7 do
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
    for index = 0, 7 do
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
                        for other = 0, 7 do
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
    for number = 0, 7 do
        local x = 280 + number * 30 + dx
        -- Digits the choice cannot reach (below the minimum, or more than the free slots) are greyed.
        local unavailable = number < minimum or free < number
        text(state, tostring(number), x + 6, 286, unavailable and count_greyed or white, count_box)
        if state.computers == number then
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
    for index = 0, 7 do
        local slot = state.slots[index]
        if slot.ready then
            local keys = state.held[index] or ""
            if pressed(keys, "u") then actions.random = trigger(slot, accept) or actions.random
            elseif pressed(keys, "d") then slot.latched = true
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
                for other = 0, 7 do
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
        if actions.next then
            slot.team = (slot.team + 1) % 5
            if slot.team == avoid then slot.team = (slot.team + 1) % 5 end
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
local music_names = {[0] = "Random", "Main Theme", "Stage 1", "Stage 2", "Stage 3", "Stage 4",
    "Stage 5", "Boss", "Final Boss"}
local function background_name(state, row)
    if row == constants.background_rows.lee_on_road then return "Lee On Road" end
    if row == constants.background_rows.random then return "Random" end
    local entry = state.backgrounds[row + 1]
    return entry and background.load(entry.path).name or ""
end

local function music_option(state, left, right)
    local options = state.options
    local index = options.music
    local label
    if state.mode == constants.modes.stage then
        if left or right then index = index == -1 and 0 or -1 end
        label = index == -1 and "OFF" or "ON"
    else
        if right then index = index + 1 end
        if index > 8 then index = -1 end
        if left then index = index - 1 end
        if index < -1 then index = 8 end
        if index == 0 then options.track = engine.random(8) + 1
        elseif index > 0 then options.track = index
        else options.track = nil end
        music.selected = options.track and music.tracks[options.track] or nil
        label = index == -1 and "OFF" or music_names[index]
    end
    options.music = index
    if index == -1 then
        music.enabled = false
        music.stop()
    else
        music.enabled = true
    end
    -- Top right corner: in the wide menu it follows the right edge of the wider picture.
    local right_edge = state.wide and constants.screen.wide_width - constants.screen.width or 0
    text(state, i18n.tr("Music: %s", i18n.tr(label)), 603 + right_edge, 3, music_title)
    text(state, i18n.tr("(Press Left/Right to change)"), 603 + right_edge, 20, music_hint)
end

-- LF2 Darkfiren's <grid_bg> (mode4.dat): a panel at (180, 3) with the backgrounds one under the other, each a 212x109
-- picture every 135 pixels from (220, 15) with its name 250 to the right, four to a page. A tap on a picture chooses
-- that background; the keys move a cursor (up, down), choose (attack) or leave (jump). It replaces the cycling of the
-- Background row in the wide menu; Stage mode still cycles its stage there.
local grid_bg = {panel_x = 180, panel_y = 3, panel_w = 500, panel_h = 542, x = 220, y = 15, w = 212, h = 109,
    step = 135, rows = 4, name_x = 250, name_y = 40, panel_pic = "sprite/ui/grid/box_bg.bmp",
    random_pic = "sprite/ui/grid/bg_grid_random.bmp"}
layout_targets.grid_bg = grid_bg
local grid_available = {}
local function grid_has(path)
    if grid_available[path] == nil then grid_available[path] = pcall(engine.read_resource, path) end
    return grid_available[path]
end
local function grid_picture(state, row)
    if row == constants.background_rows.random then return grid_bg.random_pic end
    local folder = "lor"
    if row ~= constants.background_rows.lee_on_road then
        local entry = state.backgrounds[row + 1]
        -- bg/sys/<name>/bg.dat has its picture in bg/sys/grid/<name>.bmp; the templates share temp.bmp.
        folder = entry and entry.path:match("bg/sys/([^/]+)/") or "temp"
    end
    return "bg/sys/grid/" .. folder .. ".bmp"
end
local function grid_cells(state)
    local cells = {constants.background_rows.random, constants.background_rows.lee_on_road}
    for index = 0, #state.backgrounds - 1 do cells[#cells + 1] = index end
    return cells
end
local function grid_follow(grid)
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
    hurtable = true, gain_mp_a = true, gain_mp_v = true}
local mode_neutral = {name = true, hex = true, small = true, smallb = true, hidden = true, spark = true,
    bg_pause = true, cam_pause = true, id = true, oid = true, drop = true, etc_width = true, etc_mode = true,
    dicontrol = true}
local mode_filters = {respond = true, arest = true, fall = true, wait = true}
local mode_filters_done = {respond = true, arest = true}
local bg_modes = require("base/game/bg_modes")
local mode_cache = {}
local function load_modes(row)
    if mode_cache[row] then return mode_cache[row] end
    local ok, text = pcall(engine.read_resource, "game/bg_modes/" .. row)
    local modes = bg_modes.parse(ok and text or "")
    for position, mode in ipairs(modes) do
        local supported = true
        for key, value in pairs(mode) do
            if mode_filters[key] then
                if position > 1 and not mode_filters_done[key] then
                    for item in value:gmatch("[^,]+") do
                        if tonumber(item) ~= 0 then supported = false end
                    end
                end
            elseif not mode_effects[key] and not mode_neutral[key] then
                supported = false
            end
        end
        mode.supported = supported
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
            effects.filters = bg_modes.filters(mode)
        end
        mode.effects = next(effects) and effects or nil
    end
    mode_cache[row] = modes
    return modes
end
-- The modes the player may see: those with hidden 1 to 3 once the cheat is in, hidden 4 never; the first always.
local function visible_modes(row)
    local list = {}
    for position, mode in ipairs(load_modes(row)) do
        local hidden = tonumber(mode.hidden) or 0
        if position == 1 or hidden == 0 or (hidden <= 3 and unlock.flags.characters == 1) then list[#list + 1] = mode end
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
    sounds.direct(state, "ok")
    state.mode_grid = nil
    return true
end
local function grid_choose(state, row)
    state.options.random_background = row == constants.background_rows.random
    state.options.background = row
    state.options.bg_mode = nil
    sounds.direct(state, "ok")
    state.grid = nil
    -- A background of the catalog may have modes to choose from; Random and Lee On Road have none.
    if row >= 0 and row < constants.background_rows.lee_on_road then
        local modes = visible_modes(row)
        if #modes > 1 then open_mode_grid(state, row, modes) end
    end
end
local function grid_popup(state, previous_menu)
    local grid, held = state.grid, state.held
    local last_top = math.max(0, #grid.cells - grid_bg.rows)
    local scrollable = #grid.cells > grid_bg.rows
    local function inside(x, y, left, top, width, height) return x >= left and x < left + width and y >= top and y < top + height end
    if held.click and held.pointer_x and held.pointer_x >= 0 and held.pointer_y and held.pointer_y >= 0 then
        local px, py = held.pointer_x, held.pointer_y
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
    for index = 0, 7 do
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
        local px, py = held.pointer_x, held.pointer_y
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
    for index = 0, 7 do
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
                local picture = (mode.smallb or ""):gsub("\\", "/")
                if grid_has(picture) then image(state, picture, x, y) end
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
end

local function options_menu(state, previous_menu, context)
    local options = state.options
    sprite(state, options_sheet, {348, 0, 304, 156}, 3, 3, false)
    sprite(state, options_sheet, {348, 156, 304, 10}, 3, 159, true)
    local highlight = option_highlights[options.row]
    sprite(state, options_sheet, highlight[1], highlight[2], highlight[3], false)
    if options.random_background then options.background = constants.background_rows.random end
    if state.mode == constants.modes.stage then
        options.stage_level = options.stage_level - options.stage_level % 10
        sprite(state, options_sheet, {330, 363, 279, 22}, 15, 87, false)
        if options.row == option_rows.background then sprite(state, options_sheet, {330, 332, 279, 22}, 15, 87, false) end
        local level = math.floor(options.stage_level / 10)
        if level < 5 then text(state, tostring(level + 1), 194, 91, option_blue)
        else text(state, "Survival", 174, 91, option_blue) end
    else
        text(state, background_name(state, options.background), 174, 91, option_blue)
    end
    text(state, difficulties[options.difficulty] or "", 174, 115, option_blue)
    if state.grid then return grid_popup(state, previous_menu) end
    if state.mode_grid then return mode_popup(state, previous_menu) end

    local keys = {}
    local accept = previous_menu == menus.options
    for index = 0, 7 do
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
        if options.row < 0 then options.row = option_rows.exit end
    end
    if keys.d then options.row = (options.row + 1) % (option_rows.exit + 1) end
    music_option(state, keys.l, keys.r)
    if not keys.c then return end
    sounds.direct(state, "ok")
    if options.row == option_rows.start then
        if state.mode == constants.modes.versus then music.play_selected() end
        -- The flow reads selection.match_options(state) to build the match.
        context.action("start_match")
    elseif options.row == option_rows.difficulty then
        options.difficulty = options.difficulty - 1
        local unlocked = require("base/game/unlock").flags.characters
        if (options.difficulty < constants.difficulties.difficult and unlocked == 0)
           or options.difficulty < constants.difficulties.crazy then
            options.difficulty = constants.difficulties.easy
        end
    elseif options.row == option_rows.exit then
        context.action("title")
    elseif options.row == option_rows.reselect then
        for index = 0, 7 do
            local slot = state.slots[index]
            slot.phase = slot_phases.empty
            slot.latched = true
            if slot.was_random then slot.fighter = 0 end
        end
        state.countdown = idle_countdown
        state.menu = menus.human_slots
    elseif options.row == option_rows.background then
        if state.mode == constants.modes.stage then
            options.stage_level = (options.stage_level + 10) % 60
        elseif state.wide then
            open_grid(state)
        else
            options.random_background = false
            if options.background == constants.background_rows.random then options.background = constants.background_rows.lee_on_road
            elseif options.background == constants.background_rows.lee_on_road then options.background = 0
            else
                options.background = options.background + 1
                if options.background == #state.backgrounds then
                    options.background = constants.background_rows.random
                    options.random_background = true
                end
            end
        end
    elseif options.row == option_rows.reroll then
        for index = 0, 7 do
            local slot = state.slots[index]
            if slot.was_random then slot.fighter = pick_fighter(state) end
        end
    end
end

function selection.reset_all(state)
    for index = 0, 7 do
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
    for index = 0, 7 do state.slots[index].latched = true end
    state.menu, state.last_menu = menus.options, menus.options
    state.display = {}
    return state
end

-- Match setup for base/game/match: human slots are joined (1-10), computers 11 and up.
function selection.match_options(state)
    local slots = {}
    for index = 0, 7 do
        local slot = state.slots[index]
        if slot.phase >= slot_phases.choosing_fighter and slot.phase <= slot_phases.computer_fighter - 1 then
            slots[index] = {kind = "human", fighter = slot.fighter, team = slot.team}
        elseif slot.phase >= slot_phases.computer_fighter then
            slots[index] = {kind = "computer", fighter = slot.fighter, team = slot.team}
        end
    end
    return {mode = state.mode, difficulty = state.options.difficulty, background = state.options.background,
        stage_level = state.options.stage_level,
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
        if catalog.selectable(fighter) then cells[#cells + 1] = index end
    end
    return cells
end
local function roster_panel(state)
    image(state, roster.panel_pic, roster.panel_x, roster.panel_y)
end
local function roster_pass(state, held)
    local cells = roster_fighters(state)
    -- A tap picks for the first slot that is choosing a fighter.
    if held and held.click and held.pointer_x and held.pointer_x >= 0 and held.pointer_y and held.pointer_y >= 0 then
        for position, fighter_index in ipairs(cells) do
            local x, y = roster_cell(position - 1)
            if held.pointer_x >= x and held.pointer_x < x + roster.step_x - 10
               and held.pointer_y >= y and held.pointer_y < y + roster.height + 16 then
                for index = 0, 7 do
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
    for index = 0, 7 do
        local slot = state.slots[index]
        if slot.phase >= slot_phases.choosing_fighter then
            local computer = slot.phase >= computer_phase
            owners[slot.fighter] = {computer = computer, label = computer and "COM" or ("P" .. (index + 1)),
                color = computer and computer_red or white, gray = computer and 160 or 255}
        end
    end
    for position, fighter_index in ipairs(cells) do
        local x, y = roster_cell(position - 1)
        local fighter = state.fighters[fighter_index]
        local face = fighter and fighter.small or roster.small_pic
        image(state, face, x, y)
        local owner = owners[fighter_index]
        if owner then
            fill(state, x - 1, y - 1, roster.width + 2, 1, owner.gray)
            fill(state, x - 1, y + roster.height, roster.width + 2, 1, owner.gray)
            fill(state, x - 1, y - 1, 1, roster.height + 2, owner.gray)
            fill(state, x + roster.width, y - 1, 1, roster.height + 2, owner.gray)
            text(state, owner.label, x + (owner.computer and roster.com_x or roster.human_x),
                y + (owner.computer and roster.com_y or roster.human_y), owner.color)
        else
            text(state, fighter and fighter.name or "Random", x, y + roster.human_y, option_blue)
        end
    end
end

function selection.update(state, held, context)
    state.display = {}
    state.held = held
    state.leave = false
    state.blink = (state.blink + 1) % 30
    local previous_menu = state.menu
    use_layout(state)
    fill(state, 0, 0, state.wide and constants.screen.wide_width or constants.screen.width, constants.screen.height, 0)
    if state.wide then
        roster_panel(state)
        image(state, menu.pic, menu.x, menu.y)
    else
        image(state, "pe/charmenu", 40, 33)
    end
    slots_pass(state, held)
    if state.wide then roster_pass(state, held) end
    state.last_menu = state.menu
    if state.menu == menus.computer_count then computer_count_menu(state, previous_menu) end
    if state.menu == menus.computer_slots or state.menu == menus.options then computer_menu(state, previous_menu) end
    if state.countdown < 1 and state.menu == menus.human_slots then state.menu = menus.computer_count end
    if state.leave then context.action("title") end
    if state.menu == menus.options and state.mode ~= constants.modes.battle then
        options_menu(state, previous_menu, context)
    elseif state.menu == menus.options and previous_menu ~= menus.options then
        context.action("battle_setup")
    end
    for _, sound in ipairs(sounds.flush(state)) do context.sound(sound.resource, sound.volume, sound.pan) end
end

function selection.draw(state, context)
    context.viewport(state.wide and constants.screen.wide_width or constants.screen.width, constants.screen.height, 0, 0, 0)
    for _, command in ipairs(state.display) do
        if command[1] == "image" then context.image(command[2], command[3], command[4], false)
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
    for index = 0, 7 do
        local slot = state.slots[index]
        slots[#slots + 1] = string.format("%d:%d:%d", slot.phase, slot.fighter, slot.team)
    end
    return string.format("menu=%d countdown=%d slots=%s", state.menu, state.countdown, table.concat(slots, ","))
end
return selection
