-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local constants = require("base/game/constants")
local record_kinds = constants.record_kinds
local match = require("base/game/match")
local background = require("base/game/background")
local object_data = require("base/game/object_data")
local font = require("base/ui/font")
local i18n = require("base/i18n/i18n")
local sounds = require("base/game/sounds")
local rumble = require("base/game/rumble")
local controls = require("base/ui/controls")
local options = require("base/game/options")
local user_options = options   -- screen.create() has a parameter named options
local ui_hud = require("base/game/ui_hud")
local ui_modes = require("base/game/ui_modes")
-- The HUD, pause picture and mode line are laid out for the classic 794 wide picture. In LF2 Darkfiren's super
-- widescreen layout the picture is 1333 wide: wide_gap() is the extra width (for things at the right corner) and
-- wide_center() half of it (for things in the middle). Both are 0 in the classic layout.
local function wide_gap()
    local width = options.wide_width(options.current().battlefield_layout)
    if width then
        return width - constants.screen.width
    end
    return 0
end
local function wide_center() return math.floor(wide_gap() / 2 + 0.5) end
-- Blinking of a layer (cc, c1, c2 as in a background layer): hidden outside c1..c2 of every cc ticks; shown always without cc.
local function layer_shown(layer, tick)
    local period = type(layer.cc) == "number" and math.floor(layer.cc) or 0
    if period <= 0 then return true end
    local phase = math.floor(tick or 0) % period
    return phase >= (layer.c1 or 0) and phase <= (layer.c2 or 0)
end
-- `respond` of a layer: 0 both, 1 human only, 2 computer only (readme/dat file/menu face.txt).
local function layer_for(layer, human)
    if layer.respond == 1 then return human == true elseif layer.respond == 2 then return human ~= true end
    return true
end
-- Where a stage or battle command (game/stage.lua, game/battle.lua: written for 794 pixels) goes in a wider picture. The top rows
-- (y < 200: the team lines at y 110 and 133) keep the left ones (x < 200) in place, move the middle ones (x < 400: the stage
-- title) to the middle and the right ones to the right edge; the banners lower down (the stage clear and GO pictures) go to the
-- middle, except the GO arrow at the right edge (x >= 600). [BELUM PASTI] the thresholds; they read the classic coordinates, so
-- they only serve a command without an anchor.
local function stage_dx(x, y, anchor)
    local gap = wide_gap()
    if gap == 0 then return 0 end
    -- The command's own anchor (the last element: "L", "C" or "R", from game/stage.lua and game/battle.lua) wins over the guess.
    if anchor == "L" then return 0 elseif anchor == "C" then return wide_center() elseif anchor == "R" then return gap end
    if y < 200 then
        if x < 200 then return 0 elseif x < 400 then return wide_center() end
        return gap
    end
    return x >= 600 and gap or wide_center()
end
local screen = {}
-- The canvas the battle is drawn on: 794, 1018 or 1333 wide and 550 up to 1000 high. Updated by screen.draw; the status line
-- texts (mode, FPS, volume) sit at its bottom edge, so flow.lua reads it as well.
screen.view = {width = constants.screen.width, height = constants.screen.height}
local replay_lines, mode_line

-- options: see base/game/match create().
-- The picture width a wide layout runs the simulation's background modes on (`width: -1` stands for it): 1333 or 1018 for
-- those layouts, nil (the classic 794) otherwise. Set before every match is created; idempotent (game/background.lua).
local function set_window_width()
    if background.set_window_width then
        background.set_window_width(user_options.wide_width(user_options.current().battlefield_layout))
    end
end

function screen.create(options)
    set_window_width()
    local state = {match = match.create(options)}
    local snapshots, next_snapshot = {{items = {}}, {items = {}}}, 1
    state.match.capture = function(current)
        local snapshot = screen.snapshot(current, snapshots[next_snapshot])
        next_snapshot = 3 - next_snapshot
        return snapshot
    end
    return state
end

local spark_frames = {}
for frame = 1, 4 do
    spark_frames[frame] = {0x66 * frame, 0, 0x66, 0x50}
    spark_frames[frame + 10] = {0x66 * frame, 0x80, 0x66, 0x50}
    spark_frames[frame + 5] = {0x3d * frame, 0x50, 0x3d, 0x30}
    spark_frames[frame + 15] = {0x3d * frame, 0xd0, 0x3d, 0x30}
end

-- LF2 Darkfiren stores hit sparks in a regular grid: one block is spark_w x spark_h (system.dat) followed by a
-- one pixel separator, five blocks per row, frames numbered row by row. "game/spark_block" holds "w h", or nothing
-- for the original's irregular sheet.
local spark_block, spark_block_read
local function spark_block_size()
    if not spark_block_read then
        spark_block_read = true
        local ok, text = pcall(engine.read_resource, "game/spark_block")
        local width, height = (ok and text or ""):match("^(%d+)%s+(%d+)")
        if width then spark_block = {tonumber(width), tonumber(height)} end
    end
    return spark_block
end

local function spark_source(frame)
    local block = spark_block_size()
    if not block then return spark_frames[frame] end
    local column, row = frame % 5, math.floor(frame / 5)
    -- Like the original, column 0 is never drawn.
    if column == 0 then return nil end
    return {column * (block[1] + 1), row * (block[2] + 1), block[1], block[2]}
end

local function advance_sparks(list, drawn)
    local count = 0
    local block = spark_block_size()
    -- Sparks are centred on their block: half of 102x80 and 61x48 in the original sheet.
    local big_left, big_up, small_left, small_up = 0x33, 0x28, 0x1e, 0x18
    if block then
        big_left, big_up = math.floor(block[1] / 2), math.floor(block[2] / 2)
        small_left, small_up = big_left, big_up
    end
    local position = 1
    while position <= #list do
        local spark = list[position]
        local timer = spark.timer
        local frame, left, up
        if timer < 5 then frame, left, up = timer, big_left, big_up
        elseif timer >= 10 and timer < 15 then frame, left, up = timer - 5, small_left, small_up
        elseif timer >= 20 and timer < 29 then frame, left, up = math.floor((timer - 20) / 2) + 10, big_left, big_up
        elseif timer >= 30 and timer < 39 then frame, left, up = math.floor((timer - 30) / 2) + 15, small_left, small_up end
        if frame then
            count = count + 1
            local entry = drawn[count] or {}
            entry.frame, entry.x, entry.y = frame, spark.x - left, spark.y - up
            drawn[count] = entry
            spark.timer = timer + 1
        elseif position == #list then
            list[position] = nil
        end
        position = position + 1
    end
    for index = count + 1, #drawn do drawn[index] = nil end
    return drawn
end

-- Who killed whom (the kill display of the mode file, ui_modes.kill_settings). value.fx.killed_by (AI 3) counts the kills of a
-- victim per killer slot and value.fx.last_killer names the slot of the last killing blow; neither says when it happened, so
-- the snapshot watches each character's total: a rise of it is one new kill. Events are shared by both snapshot buffers and
-- never change once made. A total that falls (fx.reset between rounds, a slot given to another record) is only a new base.
-- [BELUM PASTI] `fx.last_killer_type` (0..6, the kind of the object that struck; nil until AI 3 sets it) picks pic_type<n>.
local kill_tracker = {}
local kill_max_events, kill_max_age = 12, 1200
-- The kill display's sounds (sound1 when a team 1 member dies, sound2 when a stage enemy does; stage mode only): the path goes
-- into the match's direct sound queue (as sounds.direct does), which sounds.flush plays in the same tick.
local kill_sound_known = {}
local function kill_sound(state, event)
    if state.mode ~= constants.modes.stage then return end
    local settings = ui_modes.kill_settings(options.current().battlefield_layout)
    if not settings or (settings.modes and not settings.modes[state.mode]) then return end
    if settings.ids[event.victim_id or -1] or settings.ids[event.killer_id or -1] then return end
    local path = event.victim_team == 1 and settings.sound1 or event.victim_team == constants.teams.enemies and settings.sound2 or nil
    if not path then return end
    if kill_sound_known[path] == nil then kill_sound_known[path] = pcall(engine.read_resource, path) end
    if kill_sound_known[path] then
        state.direct_sounds = state.direct_sounds or {}
        state.direct_sounds[#state.direct_sounds + 1] = path
    end
end
local function track_kill(tracker, state, index, value, clock)
    local fx = value.fx
    local by = type(fx) == "table" and fx.killed_by or nil
    if type(by) ~= "table" or value.record.kind ~= record_kinds.character then tracker.seen[index] = nil return end
    local total = 0
    for _, count in pairs(by) do if type(count) == "number" then total = total + count end end
    local seen = tracker.seen[index]
    if seen and seen.record == value.record and total > seen.total and type(fx.last_killer) == "number" then
        local killer = state.items[fx.last_killer]
        local kind = type(fx.last_killer_type) == "number" and fx.last_killer_type >= 0 and fx.last_killer_type <= 6 and math.floor(fx.last_killer_type) or 0
        tracker.events[#tracker.events + 1] = {born = clock, victim = index, victim_id = value.record.id, victim_team = value.team,
            killer = fx.last_killer, killer_id = killer and killer.record and killer.record.id or nil, killer_team = killer and killer.team or nil, kind = kind}
        kill_sound(state, tracker.events[#tracker.events])
    end
    tracker.seen[index] = {record = value.record, total = total}
end

function screen.snapshot(state, snapshot)
    snapshot = snapshot or {items = {}}
    local order, count = snapshot.items, 0
    local tracker = kill_tracker
    local clock = type(state.elapsed) == "number" and state.elapsed or 0
    if tracker.state ~= state or clock < (tracker.clock or 0) then
        tracker.state, tracker.seen, tracker.events = state, {}, {}
    end
    tracker.clock = clock
    for index = 0, constants.item_slots - 1 do
        local value = state.items[index]
        if value then
            count = count + 1
            local entry = order[count] or {sparks = {}}
            entry.index, entry.record, entry.frame = index, value.record, value.frame
            entry.x, entry.y, entry.z, entry.facing = value.x_int, value.y_int, value.z_int, value.facing
            entry.blink, entry.hit_lag, entry.draw_offset = value.blink, value.hit_lag, value.draw_offset
            entry.pic_offset, entry.weapon, entry.team = value.pic_offset, value.weapon, value.team
            entry.hp, entry.max_hp, entry.human = value.hp, value.max_hp, value.human
            entry.dark_hp, entry.mp = value.dark_hp, value.mp   -- minibar bars
            entry.floor_y = type(value.floor_y) == "number" and value.floor_y or 0   -- the platform plane under it (shadow)
            -- Combo counter (value.fx.combo hits in a row, value.fx.combo_age ticks since the last one; AI 3).
            local fx = value.fx
            entry.combo = type(fx) == "table" and fx.combo or 0
            entry.combo_age = type(fx) == "table" and fx.combo_age or 0
            entry.combo_victim = type(fx) == "table" and type(fx.combo_victim) == "number" and fx.combo_victim or nil
            entry.over_combo, entry.over_combo_age = nil, nil
            entry.lives = value.lives
            track_kill(tracker, state, index, value, clock)
            -- I10: state 20/21 hide the object. The frame tag center_z corrects the z the drawing order uses by
            -- (center_z - 20000), or by (center_z - 200000) in the 100000..299999 range (Darkfiren: "the object with the
            -- smallest z is drawn first", so 10000 puts it behind everything, 29999 in front). It is a drawing order
            -- only: the picture stays where it is. Entries are reused, so every field is set on every snapshot.
            local frame = value.record.frame and value.record.frame(value.frame)
            local priority = frame and frame.center_z
            local correction = 0
            if type(priority) == "number" then
                if priority >= 10000 and priority <= 29999 then correction = priority - 20000
                elseif priority >= 100000 and priority <= 299999 then correction = priority - 200000 end
            end
            entry.invisible = value.st ~= nil and value.st.invisible == true
            -- Radar pictures: a hidden object (value.st.hidden, AI 2), a clone (value.st.clone, copied from value.fx.clone) and a
            -- fighter that is healing (the same test as the HUD bar's flash). nil-safe: absent fields count as false.
            entry.hidden = value.st ~= nil and value.st.hidden == true
            entry.clone = value.st ~= nil and value.st.clone == true
            entry.healing = (value.regen_timer ~= nil and math.floor(value.regen_timer / constants.healing.timer_base) == 1)
                or (value.heal_timer ~= nil and value.heal_timer > 0)            entry.depth = value.z_int + correction
            advance_sparks(value.sparks, entry.sparks)
            order[count] = entry
        end
    end
    for index = count + 1, #order do order[index] = nil end
    -- Keep the original slot order for equal depths.
    for index = 2, count do
        local entry, position = order[index], index
        while position > 1 and entry.depth < order[position - 1].depth do
            order[position] = order[position - 1]
            position = position - 1
        end
        order[position] = entry
    end
    -- Combo facing 0 (above the victim): the victim of a running combo (fx.combo_victim, AI 3; nil without it) carries its hits.
    for index = 1, count do
        local attacker = order[index]
        if type(attacker.combo) == "number" and attacker.combo >= 2 and attacker.combo_victim then
            for other = 1, count do
                local victim = order[other]
                if victim.index == attacker.combo_victim then
                    if not victim.over_combo or (attacker.combo_age or 0) < victim.over_combo_age then
                        victim.over_combo, victim.over_combo_age = attacker.combo, attacker.combo_age or 0
                    end
                    break
                end
            end
        end
    end
    local events = tracker.events
    while #events > kill_max_events or (events[1] and clock - events[1].born > kill_max_age) do table.remove(events, 1) end
    snapshot.kills, snapshot.kill_clock = events, clock
    snapshot.etc_width = type(state.bg_area) == "table" and state.bg_area.etc_width or nil
    snapshot.boss_slot = type(state.stage_run) == "table" and state.stage_run.boss_slot or nil
    snapshot.camera, snapshot.shake = state.camera, state.shake
    snapshot.time_left = state.time_limit and math.max(0, state.time_limit * 30 - state.elapsed) or state.stage_clock
    snapshot.time_row = state.stage_clock and 16 or 0
    if state.cost then
        snapshot.cost_pool = snapshot.cost_pool or {}
        for team, left in pairs(state.cost.pool) do snapshot.cost_pool[team] = left end
    else
        snapshot.cost_pool = nil
    end
    snapshot.paused, snapshot.stage = nil, nil
    return snapshot
end

function screen.update(state, held, context)
    screen.kill_toggle(state, held)
    local result = match.step(state.match, held)
    if result == "leave" then
        -- F4 in Championship or during a replay: the game state becomes 10, the title.
        context.action("title")
        return
    end
    if result == "replay_error" then
        context.action("replay_error")
        return
    end
    for _, sound in ipairs(sounds.flush(state.match)) do context.sound(sound.resource, sound.volume, sound.pan) end
    -- Rumble (OpenLF2 extension): a landed hit on a local player's slot rumbles their controller,
    -- or device haptics when slot 1 is reading the on-screen touch gamepad.
    local rumble_enabled = options.current().rumble
    for _, event in ipairs(rumble.flush(state.match)) do
        if rumble_enabled then
            local set = controls.current().sets[event.item_index + 1]
            if set and set.device and set.device >= constants.input_devices.controller_one then
                context.rumble("gamepad", set.device - constants.input_devices.controller_one, event.strength)
            elseif set and set.device == constants.input_devices.keyboard and event.item_index == 0 and held.touch_active then
                context.rumble("phone", 0, event.strength)
            end
        end
    end
    if result == "finished" then
        context.action("round_over")
        return
    end
    state.view = state.match.last_snapshot
end

local function bold_text(context, text, x, y)
    for _, offset in ipairs({{-1, 1}, {-1, 0}, {0, 1}, {0, 0}}) do font.draw(context, text, x + offset[1], y + offset[2]) end
end
local function wrapped_text(context, text, x, y, lines)
    local line = 0
    for part in (text .. "\n"):gmatch("([^\n]*)\n") do
        repeat
            if line >= lines then return end
            bold_text(context, part:sub(1, 64), x, y + line * 16)
            part = part:sub(65)
            line = line + 1
        until part == ""
    end
end
local function clock(frames)
    local seconds = math.floor((frames + 15) / 30)
    if seconds < 3600 then return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60) end
    return string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 3600 % 60)
end
replay_lines = function(context, current)
    local replay = current.replay
    local y = current.mode == constants.modes.battle and 0x9b or 0x85
    if replay.author ~= "<No name>" then
        bold_text(context, "Author:", 10, y)
        bold_text(context, replay.author:sub(1, 64), 0x4b, y)
        y = y + 0x16
    end
    if replay.info ~= "<No info>" then
        bold_text(context, "  Info:", 10, y)
        wrapped_text(context, replay.info, 0x4b, y, 4)
    end
    bold_text(context, clock(current.elapsed) .. " / " .. clock(replay.total_time), 5, screen.view.height - 40)
end
local mode_text = ""
mode_line = function(context, current, replaying)
    local names = {
        [constants.modes.versus] = "VS mode ",
        [constants.modes.championship] = "1 on 1 ",
        [constants.modes.team_championship] = "2 on 2 ",
        [constants.modes.battle] = "Battle mode "}
    local base
    if current.mode == constants.modes.stage then
        base = math.floor((current.stage_run and current.stage_run.id or 0) / 10) == 5 and "Survival Stage " or "Stage mode "
    else
        base = names[current.mode]
    end
    if base then
        local suffixes = {[0] = "(Difficult)", [1] = "(Normal)", [2] = "(Easy)", [-1] = "(CRAZY!)"}
        -- `base` ends with a space; its parts are translated one by one.
        mode_text = i18n.tr(base:sub(1, -2)) .. " " .. i18n.tr(suffixes[current.difficulty] or "")
    end
    if mode_text ~= "" then bold_text(context, mode_text, screen.view.width - 4 - font.width(mode_text), screen.view.height - (replaying and 40 or 19)) end
end

local words_known = {}
local function label_font(team)
    if team >= constants.teams.player_one and team < constants.teams.enemies then
        local sheet = "pe/words" .. team
        if team > constants.teams.player_four then
            -- A team the original did not have: its letter sheet may not exist in the game's resources.
            if words_known[sheet] == nil then words_known[sheet] = pcall(engine.read_resource, sheet) end
            if not words_known[sheet] then return "pe/words0" end
        end
        return sheet
    end
    return "pe/words0"
end
local function glyphs(context, sheet, text, x, y, advance)
    for position = 1, #text do
        local code = text:byte(position)
        context.sprite(sheet, {(code % 16) * 16, math.floor(code / 16) * 16 + 1, 8, 16},
            x + (position - 1) * advance, y, true)
    end
end

-- The original passes COLORREF values (0xBBGGRR) to its text routine; font.gdi takes 0xRRGGBB.
local function colorref(value)
    return value % 256 * 65536 + math.floor(value / 256) % 256 * 256 + math.floor(value / 65536)
end

-- The minibar of a fighter (record.display.minibar, `<minibar>` of its dat): layers drawn under the character, in file
-- order. A layer without a type is a picture (the frame), type 1 is the hp bar, 2 the dark hp, 3 the mp (a bar `max`
-- wide in value, 500 by default); `facing: 1` fills from the right. `team:` lists and `respond` choose who and which mode
-- it is for (team table of readme/dat file/minibar.txt: 1-4 teams, 5 stage enemies, 10-13 player independent, 20-27
-- computer independent; respond 0 versus, 1 stage). Not done: types 4 and 5 (fusion time), `effect`, `cc`/`c1`/`c2`,
-- `bound`/`centerx`. [BELUM PASTI] the anchor: x from the character's centre, y from the ground line (z).
local minibar_mode = 0
local function minibar_code(entry)
    if entry.team == constants.teams.enemies then return 5 end
    if entry.team == constants.teams.independent then
        if entry.index < 10 then return 10 + entry.index end
        if entry.index >= 20 and entry.index <= 27 then return entry.index end
        return nil
    end
    if entry.team >= 1 and entry.team <= 4 then return entry.team end
    return nil
end
local function minibar_for(layer, code)
    if layer.teams and #layer.teams > 0 then
        local found = false
        for _, team in ipairs(layer.teams) do if team == code then found = true end end
        if not found then return false end
    end
    if type(layer.respond) == "number" and layer.respond ~= minibar_mode then return false end
    return true
end
local function draw_minibar(context, entry, camera, shake)
    local display = entry.record.display
    local block = type(display) == "table" and display.minibar or nil
    local layers = block and block.layers
    if type(layers) ~= "table" then return end
    local code = minibar_code(entry)
    for _, layer in ipairs(layers) do
        if type(layer.pic) == "string" and type(layer.w) == "number" and layer.w >= 1 and type(layer.h) == "number" and layer.h >= 1
           and minibar_for(layer, code) then
            local width = layer.w
            local kind = layer.type
            if kind == 1 or kind == 2 or kind == 3 then
                local value = kind == 1 and entry.hp or kind == 2 and entry.dark_hp or entry.mp
                local full = type(layer.max) == "number" and layer.max > 0 and layer.max or constants.points.full
                width = math.max(0, math.min(layer.w, math.floor(layer.w * (value or 0) / full)))
            elseif kind ~= nil then
                width = 0   -- types 4 and 5 are not drawn yet
            end
            if width > 0 then
                local dx = layer.dx or 0
                local x = entry.draw_offset + entry.x - camera + shake + (layer.x or 0)
                if layer.facing == 1 and width < layer.w then
                    x, dx = x + layer.w - width, dx + layer.w - width
                end
                context.sprite(layer.pic:gsub("\\", "/"):lower(), {dx, layer.dy or 0, width, layer.h}, x, entry.z + (layer.y or 0), layer.transparency == 1)
            end
        end
    end
end

-- The combo display (<combo> of the mode file, readme/mode dat.txt): "N_hit" (`name`, %d = the hits) written with the
-- picture as a 16 x 16 grid of blocks w x h by character code, above the attacker, for `times` ticks after the last hit.
-- [BELUM PASTI] from two hits on, the anchor (centred over the head, `offset_y` upwards, `offset_x` to the right) and
-- `facing: 0` (above the victim; not drawn).
local combo_settings
local combo_known = {}
local function draw_combo(context, entry, frame, camera, shake)
    local settings = combo_settings
    if not settings or (settings.facing ~= 1 and settings.facing ~= 0) then return end
    -- facing 1: above the attacker (its own count); facing 0: above the victim (the count of the combo on it).
    local hits, age = entry.combo, entry.combo_age or 0
    if settings.facing == 0 then hits, age = entry.over_combo, entry.over_combo_age or 0 end
    if type(hits) ~= "number" or hits < 2 or age >= settings.times then return end
    if combo_known[settings.pic] == nil then combo_known[settings.pic] = pcall(engine.read_resource, settings.pic) end
    if not combo_known[settings.pic] then return end
    local text = (settings.name:gsub("%%d", tostring(math.floor(hits))))
    local x = entry.draw_offset + entry.x - camera + shake + settings.offset_x - math.floor(#text * settings.w / 2)
    local y = entry.z - frame.center_y + entry.y - settings.offset_y
    for position = 1, #text do
        local code = text:byte(position)
        context.sprite(settings.pic, {(code % 16) * settings.w, math.floor(code / 16) * settings.h, settings.w, settings.h},
            x + (position - 1) * settings.w, y, true)
    end
end

-- The kill display: one row per recent kill, `loop` pixels apart from `y` down, oldest first, each shown `times` ticks. A row is the
-- attacker's name (x), a picture by the kind of the killing object (dx) and the victim's name (dvx). A name is the player label
-- (as over the head: "P1", "Com"), with the character's name after it when caughtact / catchingact are 1, in the team's font when
-- arest / vrest are 1; pickedact / pickingact write it backwards, here: ending at x. [BELUM PASTI] all positions and anchors,
-- the picture's vertical place (same y as the text), `respond` as the row limit, backwards = right aligned, and that the host
-- draws the PNG pictures (sprite\\kill\\*.png). The sounds are played where the kill is noticed (kill_sound).
local fighter_names
local function character_name(id)
    if not fighter_names then
        fighter_names = {}
        local ok, catalog = pcall(require, "base/game/catalog")
        local ok_list, list = false, nil
        if ok and type(catalog) == "table" and type(catalog.load) == "function" then ok_list, list = pcall(catalog.load) end
        if ok_list and type(list) == "table" then
            for _, fighter in ipairs(list) do fighter_names[fighter.id] = (tostring(fighter.name):gsub("_", " ")) end
        end
    end
    return fighter_names[id]
end
local kill_pic_known = {}
local function kill_text(index, id, with_name)
    local label = index < constants.player_slots and controls.name(index) or "Com"
    local name = with_name and id and character_name(id) or nil
    return name and (label .. " " .. name) or label
end
local function draw_kill_board(context, view, current)
    local settings = ui_modes.kill_settings(options.current().battlefield_layout)
    if not settings or not view.kills or #view.kills == 0 then return end
    if settings.modes and not settings.modes[current.mode] then return end
    local visible = {}
    for _, event in ipairs(view.kills) do
        local age = (view.kill_clock or 0) - event.born
        if age >= 0 and age < settings.times and not settings.ids[event.victim_id or -1] and not settings.ids[event.killer_id or -1] then
            visible[#visible + 1] = event
        end
    end
    for first = 1, #visible - settings.max_rows do table.remove(visible, 1) end
    for row, event in ipairs(visible) do
        local y = settings.y + (row - 1) * settings.loop
        local pic = settings.pics[event.kind] or settings.pics[0]
        if pic then
            if kill_pic_known[pic] == nil then kill_pic_known[pic] = pcall(engine.read_resource, pic) end
            if kill_pic_known[pic] then context.image(pic, settings.dx, y, settings.transparent) end
        end
        local attacker = kill_text(event.killer, event.killer_id, settings.attacker_name)
        local victim = kill_text(event.victim, event.victim_id, settings.victim_name)
        local attacker_x = settings.attacker_back and settings.x - #attacker * 9 or settings.x
        local victim_x = settings.victim_back and settings.dvx - #victim * 9 or settings.dvx
        glyphs(context, settings.arest and event.killer_team and label_font(event.killer_team) or "pe/words0", attacker, attacker_x, y, 9)
        glyphs(context, settings.vrest and event.victim_team and label_font(event.victim_team) or "pe/words0", victim, victim_x, y, 9)
    end
end

local draw_blood
-- Blood (frame tag bpoint, readme/frame/bpoint.txt; up to five per frame in frame.bpoints, frame.bpoint = the first): a point with
-- x > 0 drops blood once the HP is below `respond` percent of the maximum (point.respond, else the object's <stats> bleed_hp, else
-- the classic third). Plain old data (x and y only) keeps the 1x3 red picture of pe/bars; with w, h, rect or rect32 it is a filled
-- rectangle (width 1 and height 3 where one is absent). rect is RGB565 as in a background layer (the engine converts that for a
-- layer, here it is done the same way); rect32 is 24 bit RGB (the upper byte is dropped, as in background.lua) and wins when both
-- are written; red (0xF800) when neither. The parser leaves a tag out of the table when the file does not write it.
-- [BELUM PASTI] a rectangle wider than 1 facing left covers the mirrored pixels; respond or bleed_hp of 0 mean "not written"; the
-- parser has no rect32 for bpoint yet (bpoint_tags in object_data.cpp), it is read when it appears.
local function blood_colour(point)
    local color
    if type(point.rect32) == "number" then
        color = point.rect32 % 16777216
    else
        local value = (type(point.rect) == "number" and point.rect or 0xF800) % 65536
        local red, green, blue = math.floor(value / 2048) % 32, math.floor(value / 32) % 64, value % 32
        color = (((red * 0x200 + green) * 0x80 + blue) * 8 + 0x070707) % 16777216
    end
    return math.floor(color / 65536), math.floor(color / 256) % 256, color % 256
end
local function blood_hp(entry, point)
    local percent = point.respond
    if type(percent) ~= "number" or percent <= 0 then
        local data = entry.record.data
        local stats = type(data) == "table" and data.stats or nil
        percent = type(stats) == "table" and stats.bleed_hp or nil
    end
    if type(percent) == "number" and percent > 0 then return math.floor(entry.max_hp * percent / 100) end
    return math.floor(entry.max_hp / 3)
end
draw_blood = function(context, entry, frame, camera, shake)
    local right = entry.facing == constants.facings.right
    for _, point in ipairs(frame.bpoints or {frame.bpoint}) do
        if point.x > 0 and entry.hp < blood_hp(entry, point) then
            local offset = right and point.x - frame.center_x or frame.center_x - point.x
            local y = point.y - frame.center_y + entry.z + entry.y
            local custom = point.w or point.h or point.rect or point.rect32
            if custom then
                local width = type(point.w) == "number" and point.w > 0 and point.w or 1
                local height = type(point.h) == "number" and point.h > 0 and point.h or 3
                local x = offset + entry.draw_offset + entry.x - camera + shake - (right and 0 or width - 1)
                local red, green, blue = blood_colour(point)
                context.fill(x, y, width, height, red, green, blue)
            else
                context.sprite("pe/bars", {0, 20, 1, 3}, offset + entry.draw_offset + entry.x - camera + shake, y, false)
            end
        end
    end
end

local function draw_item(context, stage, view, entry, bounds, lighting)
    local frame = entry.record.frame(entry.frame)
    local blink = math.abs(entry.blink)
    local camera = view.camera
    local casts_shadow = entry.weapon >= 0 and frame.state ~= constants.frame_states.vanishing_ball
       and frame.state ~= constants.frame_states.team_order_marker
       and entry.record.id ~= constants.object_ids.firzen_ball
       and entry.record.id ~= constants.object_ids.bat_ball
       and entry.blink > -70 and blink % 4 < 2 and frame.shadow ~= 1
    if casts_shadow and stage.shadow and not lighting.projected_shadows then
        local width, height = stage.shadow_size[1] or 0, stage.shadow_size[2] or 0
        local shadow = stage.shadow:gsub("\\", "/"):lower()
        -- The shadow lies on the platform the object stands on (value.floor_y, negative = above the ground; 0 on the ground).
        context.image(shadow, entry.draw_offset + entry.x - camera - math.floor(width / 2),
            entry.z + (entry.floor_y or 0) - math.floor(height / 2), true)
    end
    local shake = entry.hit_lag < 0 and view.shake * 6 - 3 or 0
    local visible = blink % 4 < 2 and entry.blink > -25 and not entry.invisible
    local on_screen = frame.state == constants.frame_states.team_order_marker
    local resource, source = object_data.picture(entry.record.data, entry.frame, entry.pic_offset)
    if visible and resource and not frame.undefined then
        local y = entry.z - frame.center_y + entry.y
        local x
        if entry.facing == constants.facings.right then x = entry.draw_offset - frame.center_x + entry.x - camera + shake
        else x = frame.center_x + entry.draw_offset + entry.x - camera + shake - source[3] end
        if on_screen then
            -- Order markers stay on the screen: the classic one, or the whole window in the widescreen layout.
            -- The width of the message box: the mode's etc_width (state.bg_area.etc_width, AI 5), 80 without it.
            local etc_width = type(view.etc_width) == "number" and view.etc_width > 0 and math.floor(view.etc_width) or 80
            if bounds then x = math.max(bounds.left, math.min(x, bounds.right - etc_width))
            else x = math.max(0, math.min(x, constants.screen.width - etc_width)) end
        end
        -- A sprite far outside the picture (an opoint with y 20000 sends an object far below the screen) is skipped, not
        -- handed to the host: Darkfiren allows such positions, the draw commands only hold +-8192.
        if math.abs(x) > 8192 or math.abs(y) > 8192 then
            -- nothing to draw
        elseif (lighting.character_shading or lighting.projected_shadows) and not on_screen then
            local kind = entry.record.kind
            local physical = kind == record_kinds.light_item or kind == record_kinds.heavy_item
                or kind == record_kinds.baseball or kind == record_kinds.drink
            context.world_sprite(resource, source, x, y, entry.facing ~= constants.facings.right,
                entry.z, lighting.light_azimuth, lighting.light_elevation,
                lighting.character_shading and kind == record_kinds.character,
                lighting.projected_shadows and (casts_shadow or physical), lighting.shadow_blur, lighting.shadow_opacity)
        else
            -- Frame tags `amount` and `loop`: the picture is repeated `amount` times, `loop` pixels apart
            -- [BELUM PASTI: modelled on the background layers; the spacing is the picture width when loop is absent].
            local copies = type(frame.amount) == "number" and frame.amount > 1 and math.min(frame.amount, 64) or 1
            local spacing = type(frame.loop) == "number" and frame.loop ~= 0 and frame.loop or source[3]
            for copy = 0, copies - 1 do
                local shift = entry.facing == constants.facings.right and copy * spacing or -copy * spacing
                context.sprite(resource, source, x + shift, y, true, entry.facing ~= constants.facings.right)
            end
        end
    end
    if visible and not on_screen then draw_blood(context, entry, frame, camera, shake) end
    if entry.lives > 1 then
        -- Remaining lives ("x2"; two digits at most) above the head, in the default font, unclamped.
        local text = entry.lives < 10 and ("x" .. entry.lives)
            or ("x" .. math.floor(entry.lives / 10) % 10 .. entry.lives % 10)
        glyphs(context, "pe/words0", text, entry.draw_offset + entry.x - camera - math.floor(#text * 9 / 2),
            entry.z - frame.center_y + entry.y - 7, 9)
    end
    local is_character = entry.record.kind == record_kinds.character
    local label, sheet
    if entry.index < 20 or (entry.team ~= constants.teams.enemies and is_character) then
        -- Items 0..9 are the player slots (ten in the 10 player layout), 10..19 the computers picked in the menu.
        label = entry.index < constants.player_slots and controls.name(entry.index) or "Com"
        sheet = label_font(entry.team)
    elseif is_character and entry.team == constants.teams.enemies
           and (entry.record.id < constants.record_id_ranges.enemy_character_first
           or entry.record.id > constants.record_id_ranges.enemy_character_last or entry.record.id == constants.fighter_ids.bat) then
        -- Bosses and other enemy characters in slots 20+ (WORDS5 sheet).
        label, sheet = "Com", "pe/words5"
    end
    if label and entry.blink > -25 and frame.bound ~= 1 then
        local length = #label
        local x = entry.draw_offset + entry.x - camera - math.floor(length * 9 / 2)
        if bounds then
            x = math.max(bounds.left, math.min(x, bounds.right - length * 9))
        else
            if x < 0 then x = 0 end
            if x > constants.screen.width - length * 9 then x = constants.screen.width - length * 9 end
        end
        glyphs(context, sheet, label, x, entry.z + 3, 9)
    end
    if entry.blink > -25 and not entry.invisible then
        draw_minibar(context, entry, camera, shake)
        draw_combo(context, entry, frame, camera, shake)
    end
    for _, spark in ipairs(entry.sparks) do
        local source = spark_source(spark.frame)
        -- Frames 0, 5, 10 and 15 are never given a rectangle (assumed empty; see docs).
        if source then context.sprite("pe/spark", source, entry.draw_offset + spark.x - camera, spark.y, true) end
    end
end

-- The classic HUD, for a host or a test that has no game/ui_hud (the same numbers as ui_hud.default_style()).
local fallback_hud = {frame_pic = "pe/frame", bars_pic = "pe/bars", frame_x = 0, frame_y = 0, frame_w = 198, frame_h = 54,
    small_x = 9, small_y = 7, row = 4, col_dhp = 30, col_hp = 20, col_bhp = 40, col_dmp = 10, col_mp = 0,
    hp_bar = {x = 57, y = 16, w = 124, h = 10}, mp_bar = {x = 57, y = 36, w = 124, h = 10}, team_flag = {x = 5, y = 0}}

-- A bar of the fighter's own <hp_bar>/<mp_bar> (record.display) when it gives a position and a width, else the style's.
local function bar_of(value, name, style)
    local display = value.record.display
    local own = type(display) == "table" and display[name] or nil
    -- Only the plain horizontal bar (type 1, or none given) is drawn from it; other types are [BELUM PASTI] and keep the style's.
    if type(own) == "table" and (own.type == nil or own.type == 1) and type(own.x) == "number"
       and type(own.y) == "number" and type(own.w) == "number" and own.w >= 1 then
        return {x = own.x, y = own.y, w = own.w, h = type(own.h) == "number" and own.h >= 1 and own.h or style[name].h}
    end
    return style[name]
end

-- Earthquake (frame state 5XXYY, game/st_camera.lua): match.st.quake_x/quake_y are pixel offsets, zero when no frame asks
-- for one. The arena (background, objects, sparks) moves by them: positive x to the right, positive y down; the HUD, the
-- stage commands and the pause picture stay.
local function quake_offsets(current)
    local st = current.st
    if type(st) ~= "table" then return 0, 0 end
    local function clamp(value)
        if type(value) ~= "number" or value ~= value then return 0 end
        return math.max(-50, math.min(50, math.floor(value)))
    end
    return clamp(st.quake_x), clamp(st.quake_y)
end
local shifted_calls = {"viewport", "overlay", "render_area", "clip", "sound", "rumble", "music", "speed", "render_filter",
    "text_input", "replay_drop", "fullscreen", "action"}
-- `context` with every drawing call moved by (dx, dy).
local function shifted(context, dx, dy)
    local moved = {}
    for _, name in ipairs(shifted_calls) do moved[name] = context[name] end
    function moved.sprite(resource, source, x, y, ...) return context.sprite(resource, source, x + dx, y + dy, ...) end
    function moved.world_sprite(resource, source, x, y, mirrored, ground_y, ...)
        return context.world_sprite(resource, source, x + dx, y + dy, mirrored, ground_y and ground_y + dy, ...)
    end
    function moved.image(resource, x, y, ...) return context.image(resource, x + dx, y + dy, ...) end
    function moved.icon(resource, x, y, ...) return context.icon(resource, x + dx, y + dy, ...) end
    function moved.fill(x, y, ...) return context.fill(x + dx, y + dy, ...) end
    function moved.text(text, x, y, ...) return context.text(text, x + dx, y + dy, ...) end
    return moved
end

-- The radar of a HUD style (frame.dat <radar>): the base picture, a dot per object of the listed types and frame states
-- (pictures by team or type), blinking while `fall` says the fighter is down or invincible, and the camera outline.
-- The boss bar (<bossbar> of the boss's data file, readme/dat file/bossbar.txt; stage mode only): the layers are drawn on the
-- screen at their x and y. The boss is `state.stage_run.boss_slot` (AI 5, nil when none; read into snapshot.boss_slot). Layers
-- without a type are plain pictures; type 1 (hp), 2 (dhp) and 3 (mp) are bars of w pixels filled by the value over `max`
-- (the boss's maximum hp for 1 and 2, 500 for 3 when `max` is not written), `facing: 1` empties it towards the right edge, as
-- the minibar. Types 4 and 5 are not drawn; cc, c1, c2 blink a layer. In a wider picture the bar sits in the
-- middle. [BELUM PASTI] who is shown when there are several bosses (the first), that it stays until the boss leaves the
-- game (also at 0 HP), and `max`.
local function draw_bossbar(context, view, current)
    local slot = view.boss_slot
    if current.mode ~= constants.modes.stage or type(slot) ~= "number" then return end
    local boss
    for _, entry in ipairs(view.items) do if entry.index == slot then boss = entry break end end
    local display = boss and boss.record.display
    local block = type(display) == "table" and display.bossbar or nil
    local layers = block and block.layers
    if type(layers) ~= "table" then return end
    context = wide_center() ~= 0 and shifted(context, wide_center(), 0) or context
    for _, layer in ipairs(layers) do
        if layer_shown(layer, view.kill_clock) and type(layer.pic) == "string" and type(layer.w) == "number" and layer.w >= 1
           and type(layer.h) == "number" and layer.h >= 1 then
            local width, kind = layer.w, layer.type
            if kind == 1 or kind == 2 or kind == 3 then
                local value = kind == 1 and boss.hp or kind == 2 and boss.dark_hp or boss.mp
                local full = type(layer.max) == "number" and layer.max > 0 and layer.max or (kind == 3 and constants.points.full or boss.max_hp)
                width = math.max(0, math.min(layer.w, math.floor(layer.w * (value or 0) / math.max(1, full))))
            elseif kind ~= nil then
                width = 0
            end
            if width > 0 then
                local x, dx = layer.x or 0, layer.dx or 0
                if layer.facing == 1 and width < layer.w then x, dx = x + layer.w - width, dx + layer.w - width end
                context.sprite(layer.pic:gsub("\\", "/"):lower(), {dx, layer.dy or 0, width, layer.h}, x, layer.y or 0, layer.transparency == 1)
            end
        end
    end
end

local function draw_radar(context, view, current, radar, center, picture_width)
    local shift = radar.centered and center or 0
    context.image(radar.pic, radar.pic_x + shift, radar.pic_y, false)
    local stage = current.stage or {}
    local stage_width = stage.width or constants.screen.width
    local bounds = stage.zboundary or {}
    local z_min, z_max = bounds[1] or 0, bounds[2] or 0
    for _, entry in ipairs(view.items) do
        local record = entry.record
        local frame = record.frame and record.frame(entry.frame)
        local shown = frame and (radar.states[frame.state] or (entry.hidden and radar.pic_hidden))
        if radar.types[record.kind] and shown and not entry.invisible
           and not (radar.fall == 1 and entry.blink and entry.blink > 0 and entry.blink % 4 >= 2) then
            local picture = ui_hud.radar_icon(radar, record.kind, entry.team, entry.hp,
                {hidden = entry.hidden, clone = entry.clone, healing = entry.healing})
            if picture then
                local x, y = ui_hud.radar_position(radar, entry.x, entry.z, stage_width, z_min, z_max)
                context.image(picture, x + shift, y, true)
            end
        end
    end
    if radar.cover == 1 then
        -- The camera outline: the window's share of the stage across the radar area.
        local across = math.max(0, radar.width - 2 * radar.offset_x)
        local window = picture_width
        local left = radar.start_x + shift + math.floor(math.max(0, math.min(1, (view.camera or 0) / math.max(1, stage_width))) * across + 0.5)
        local size = math.max(2, math.min(across, math.floor(window / math.max(1, stage_width) * across + 0.5)))
        local top, height = radar.start_y, math.max(2, radar.height - 2 * radar.offset_y)
        local rect = radar.rect or 16777215
        local red, green, blue = math.floor(rect / 65536) % 256, math.floor(rect / 256) % 256, rect % 256
        context.fill(left, top, size, 1, red, green, blue)
        context.fill(left, top + height - 1, size, 1, red, green, blue)
        context.fill(left, top, 1, height, red, green, blue)
        context.fill(left + size - 1, top, 1, height, red, green, blue)
    end
end

-- The small face of a fighter: the one of the skin it wears (record.data.skins[i].small where the skin's offset is the
-- fighter's pic_offset), else the character's own. A picture the game lacks keeps the character's own.
local skin_small_known = {}
local function small_face(value)
    local own = value.record.data.small
    local skins = value.record.data.skins
    if type(skins) ~= "table" or not value.pic_offset or value.pic_offset == 0 then return own end
    for index = 1, 10 do
        local skin = skins[index]
        if skin and skin.offset == value.pic_offset and type(skin.small) == "string" then
            local path = skin.small:gsub("\\", "/"):lower()
            if skin_small_known[path] == nil then skin_small_known[path] = pcall(engine.read_resource, path) end
            return skin_small_known[path] and skin.small or own
        end
    end
    return own
end

-- Custom counters and effect pictures of the HUD panel of a fighter (record.display, readme/dat file/stats count.txt and
-- effect.txt). Both are placed from the top left corner of the fighter's HUD panel. [BELUM PASTI] that anchor.
-- stats_count (up to 10 `count`s): the number of `type` (the types below; right aligned at x, `facing: 1` left aligned),
-- at most `max`, in the letters of `pic` 0..5 (pe/words<pic>, 0 without it); `respond: 1` only when function keys were used
-- (cheat_lock > 0). Types 18 and 19 write "current/total" (hp, mp) and ignore max, pic and facing; type 14 ignores max and
-- facing. Sources (AI 3): 9 `blink`, 10 `timer_b0`, 11 `merge_timer`, 12 `fx.armor.hp` (else the data's armor hp), 13
-- `fx.armor.timer`, 14 `<stats> defend` (else `value.armor`) [BELUM PASTI which], 15 `fx.deaths` (R27 AI 3; 0 without it).
-- 38 `fx.hits` (hits made; 0 until the first). Types the game has no value for are not drawn: 30 to 37 (rage, unlimited,
-- unassigned timers).
-- effect (up to 100 layers): the picture (source x, y = dx, dy; w x h) while the status `type` is on: -1 none, 0..5 poison of
-- that type, 6 poison, 7 weak, 8 manacle, 9 delay, 10 confus, 11 join, 12 mimic, 13 bound, 14 facing; 15 to 20 (rage,
-- unlimited) are not drawn yet. `bound: 1` shortens it with the timer (`max` 999 by default) as `facing` says: 0 from
-- the right, 1 from the left, 2 from the bottom, 3 from the top. `respond` 1 human, 2 computer only; cc, c1, c2 blink it.
local status_names = {poison = 21, weak = 22, manacle = 23, delay = 24, confus = 25, join = 26, mimic = 27, bound = 28, facing = 29}
local status_by_effect = {[6] = "poison", [7] = "weak", [8] = "manacle", [9] = "delay", [10] = "confus", [11] = "join", [12] = "mimic",
    [13] = "bound", [14] = "facing"}
local function status_timer(value, name)
    local extra = value.fx
    local bag = type(extra) == "table" and type(extra.status) == "table" and extra.status[name] or nil
    if type(bag) == "table" then bag = bag.timer end
    return type(bag) == "number" and bag > 0 and math.floor(bag) or 0
end
local function count_value(value, kind)
    if kind == 1 then return value.hp elseif kind == 2 then return value.dark_hp elseif kind == 3 then return value.mp
    elseif kind == 4 then return value.damage_dealt elseif kind == 5 then return value.hp_spent elseif kind == 6 then return value.mp_spent
    elseif kind == 7 then return value.kills elseif kind == 8 then return value.pickings elseif kind == 16 then return value.max_hp
    elseif kind == 17 then return constants.points.full elseif kind == 20 then return value.lives
    elseif kind == 9 then return value.blink            -- invincible time (the blink counter)
    elseif kind == 10 then return value.timer_b0        -- fall points
    elseif kind == 11 then return value.merge_timer     -- fusion time (the rest before a new fusion once apart)
    elseif kind == 12 or kind == 13 then
        local armor = type(value.fx) == "table" and value.fx.armor or nil
        local data = type(value.record.data) == "table" and value.record.data.armor or nil
        if kind == 12 then return type(armor) == "table" and armor.hp or type(data) == "table" and data.hp or 0 end
        return type(armor) == "table" and armor.timer or 0   -- -1 (no recovery) shows as 0
    elseif kind == 14 then
        local stats = type(value.record.data) == "table" and value.record.data.stats or nil
        if type(stats) == "table" and type(stats.defend) == "number" and stats.defend > 0 then return stats.defend end
        return type(value.armor) == "number" and value.armor > 0 and value.armor or 0
    elseif kind == 15 then return type(value.fx) == "table" and value.fx.deaths or 0
    elseif kind == 38 then return type(value.fx) == "table" and value.fx.hits or 0 end   -- hits made (AI 3, R29)
    for name, number in pairs(status_names) do if number == kind then return status_timer(value, name) end end
    return nil
end
local function draw_stats_count(context, state, value, column, row)
    local counts = type(value.record.display) == "table" and value.record.display.stats_count or nil
    if type(counts) ~= "table" then return end
    for index = 1, math.min(#counts, 10) do
        local count = counts[index]
        if type(count) == "table" and type(count.x) == "number" and type(count.y) == "number" and (count.respond ~= 1 or (state.cheat_lock or 0) > 0) then
            local text, right
            if count.type == 18 or count.type == 19 then
                local now, total = count.type == 18 and value.hp or value.mp, count.type == 18 and value.max_hp or constants.points.full
                if type(now) == "number" and type(total) == "number" then text, right = math.max(0, math.floor(now)) .. "/" .. math.floor(total), true end
            else
                local number = count_value(value, count.type)
                if type(number) == "number" then
                    local top = type(count.max) == "number" and count.max >= 0 and count.max or 999
                    -- Type 14 (defense) ignores max and facing (readme).
                    if count.type == 14 then top = math.huge end
                    text, right = tostring(math.max(0, math.min(math.floor(number), top))), count.type == 14 or count.facing ~= 1
                end
            end
            if text then
                local sheet = "pe/words0"
                if count.type ~= 18 and count.type ~= 19 and type(count.pic) == "number" and count.pic >= 0 and count.pic <= 5 then
                    sheet = "pe/words" .. math.floor(count.pic)
                end
                glyphs(context, sheet, text, column + count.x - (right and #text * 9 or 0), row + count.y, 9)
            end
        end
    end
end
local function effect_on(value, kind)
    if type(kind) ~= "number" then return 0 end
    if kind >= 0 and kind <= 5 then
        local extra = value.fx
        local poison = type(extra) == "table" and type(extra.status) == "table" and extra.status.poison or nil
        if type(poison) == "table" and poison.kind == kind and type(poison.timer) == "number" and poison.timer > 0 then return math.floor(poison.timer) end
        return 0
    end
    local name = status_by_effect[kind]
    return name and status_timer(value, name) or 0
end
local function draw_effects(context, value, column, row, tick)
    local block = type(value.record.display) == "table" and value.record.display.effect or nil
    local layers = type(block) == "table" and block.layers or nil
    if type(layers) ~= "table" then return end
    for _, layer in ipairs(layers) do
        local timer = effect_on(value, layer.type)
        if timer > 0 and layer_for(layer, value.human) and layer_shown(layer, tick) and type(layer.pic) == "string"
           and type(layer.w) == "number" and layer.w >= 1 and type(layer.h) == "number" and layer.h >= 1 then
            local width, height = layer.w, layer.h
            local x, y, dx, dy = column + (layer.x or 0), row + (layer.y or 0), layer.dx or 0, layer.dy or 0
            if layer.bound == 1 then
                local full = type(layer.max) == "number" and layer.max > 0 and layer.max or 999
                local share = math.min(timer, full) / full
                local way = layer.facing or 0
                if way == 0 or way == 1 then
                    width = math.max(0, math.floor(layer.w * share))
                    if way == 1 then x, dx = x + layer.w - width, dx + layer.w - width end
                elseif way == 2 or way == 3 then
                    height = math.max(0, math.floor(layer.h * share))
                    if way == 3 then y, dy = y + layer.h - height, dy + layer.h - height end
                end
            end
            if width > 0 and height > 0 then
                context.sprite(layer.pic:gsub("\\", "/"):lower(), {dx, dy, width, height}, x, y, layer.transparency == 1)
            end
        end
    end
end

-- The nickname of a fighter in its HUD panel (<name> of the data file, readme/dat file/name.txt): `respond` 2 shows it in
-- offline and online games, 1 only online (this game has no network play: not shown), 0 or none never; at (name_x, name_y)
-- from the panel's corner, in the team's letters when `team` is 1. The nickname is the player label of the slot ("P1", as
-- over the head) and "Com" for a computer fighter. [BELUM PASTI] the anchor (panel corner), the font and the text (no
-- nickname setting exists), and `team` is not in AI 1's tag list yet (read when it appears).
local function draw_nickname(context, value, own_slot, slot, column, row)
    local block = type(value.record.display) == "table" and value.record.display.name or nil
    if type(block) ~= "table" or block.respond ~= 2 or type(block.name_x) ~= "number" or type(block.name_y) ~= "number" then return end
    local text = own_slot and controls.name(slot) or "Com"
    glyphs(context, block.team == 1 and label_font(value.team) or "pe/words0", text, column + block.name_x, row + block.name_y, 9)
end

local function draw_status(context, state, style)
    style = style or fallback_hud
    for slot = 0, (style.slots or 8) - 1 do
        local row = math.floor(slot / style.row) * style.frame_h + style.frame_y
        local column = style.frame_x + (slot % style.row) * style.frame_w + (style.centered == false and 0 or wide_center())
        context.image(style.frame_pic, column, row, false)
        local value = state.items[slot] or state.items[slot + 10]
        if value then
            local small = small_face(value)
            if small then context.image(small:gsub("\\", "/"):lower(), column + style.small_x, row + style.small_y, false) end
            if value.hp > 0 then
                local hp_bar, mp_bar = bar_of(value, "hp_bar", style), bar_of(value, "mp_bar", style)
                local function bar(source_y, width, geometry)
                    if width > 0 then context.sprite(style.bars_pic, {0, source_y, width, geometry.h}, column + geometry.x, row + geometry.y, false) end
                end
                -- 124 pixels is the full bar of the classic HUD; another width scales it.
                local function filled(amount, geometry) return math.floor(amount * 31 / 125 * (geometry.w / 124)) end
                bar(style.col_dhp, filled(value.dark_hp, hp_bar), hp_bar)
                bar(style.col_hp, filled(value.hp, hp_bar), hp_bar)
                -- Healing (milk, regeneration): the bar flashes every other tick of the 12-tick counter.
                if (math.floor(value.regen_timer / constants.healing.timer_base) == 1 or value.heal_timer > 0) and state.counter_12 % 2 == 0 then
                    bar(style.col_bhp, filled(value.hp, hp_bar), hp_bar)
                end
                bar(style.col_dmp, mp_bar.w, mp_bar)
                bar(style.col_mp, filled(math.min(value.mp, constants.points.full), mp_bar), mp_bar)
            end
            local own_flag = type(value.record.display) == "table" and value.record.display.team_flag or nil
            local flag = type(own_flag) == "table" and type(own_flag.x) == "number" and type(own_flag.y) == "number" and own_flag or style.team_flag
            glyphs(context, label_font(value.team), string.char(254), column + flag.x, row + flag.y, 8)
            draw_stats_count(context, state, value, column, row)
            draw_effects(context, value, column, row, state.elapsed)
            draw_nickname(context, value, state.items[slot] ~= nil, slot, column, row)
        end
    end
end

local function draw_scoreboard(context, current)
    local counter = current.round_counter
    if counter < 101 or counter >= constants.round_counters.finished then return end
    -- Eight player slots, ten in the 10 player layout (items 8 and 9, or 18 and 19 for computers).
    local slot_total = options.slot_count and options.slot_count(options.current().battlefield_layout) or 8
    local players = 0
    for slot = 0, slot_total - 1 do
        if current.items[slot] or current.items[slot + 10] then players = players + 1 end
    end
    local players_alive = false
    for index = 0, constants.item_slots - 1 do
        local value = current.items[index]
        if value and value.hp > 0 and value.record.kind == record_kinds.character
           and value.team > constants.teams.independent
           and value.team < constants.teams.active_end_exclusive
           and value.team ~= constants.teams.enemies then
            players_alive = true
        end
    end
    local battle_run = current.battle_run
    -- Ten rows would pass the screen (10 * 45 + 93 = 543, with the battle lines 588): the rows then come closer, overlapping the
    -- padding of the row pictures a little, to fit in 530. [BELUM PASTI] how much a row picture may be covered (down to 30).
    local fixed = battle_run and 138 or 93
    local step = 45
    if players * 45 + fixed > 530 then step = math.max(30, math.floor((530 - fixed) / players)) end
    local height = players * step + fixed
    local top = math.floor((530 - height) / 2)
    local row_y = top + 16
    context.image("pe/score_board1", 150, top, false)
    for slot = 0, slot_total - 1 do
        local index = current.items[slot] and slot or slot + 10
        local value = current.items[index]
        if value then
            row_y = row_y + step
            context.image("pe/score_board2", 150, row_y, false)
            local small = small_face(value)
            if small then context.image(small:gsub("\\", "/"):lower(), 165, row_y, false) end
            local label = index < 10 and ("P" .. (index + 1) .. " ") or "Com"
            glyphs(context, label_font(value.team), label, 206, row_y + 15, 9)
            font.gdi(context, tostring(value.kills), 271, row_y + 15, colorref(0xaaaaff))
            font.gdi(context, tostring(value.damage_dealt), 326, row_y + 15, colorref(0xaaaaff))
            font.gdi(context, tostring(value.hp_spent), 390, row_y + 15, colorref(0xaaf0f0))
            font.gdi(context, tostring(value.mp_spent), 454, row_y + 15, colorref(0xaaf0f0))
            font.gdi(context, tostring(value.pickings), 527, row_y + 15, colorref(0xaaf5aa))
            local result
            if current.mode == constants.modes.stage then
                if not players_alive then result = "pe/lose_dead"
                else result = value.hp < 1 and "pe/win_dead" or "pe/win_alive" end
            elseif current.winner >= 0 then
                if current.winner == value.team then
                    result = value.hp < 1 and "pe/win_dead" or "pe/win_alive"
                else
                    result = "pe/lose_dead"
                end
            end
            if result then context.image(result, 571, row_y + 15, false) end
        end
    end
    local footer = top + players * step + 61
    if battle_run then
        context.image("pe/score_board4", 150, footer, false)
        context.image("pe/score_board3", 150, footer + 45, false)
        font.gdi(context, tostring(battle_run.deaths[1]), 243, footer + 23, colorref(0xffafaf))
        font.gdi(context, tostring(battle_run.deaths[2]), 483, footer + 23, colorref(0xafafff))
        font.gdi(context, tostring(battle_run.damage[1]), 323, footer + 23, colorref(0xffafaf))
        font.gdi(context, tostring(battle_run.damage[2]), 563, footer + 23, colorref(0xafafff))
    else
        context.image("pe/score_board3", 150, footer, false)
    end
    local seconds = math.floor((current.elapsed + 15) / 30)
    local text
    if seconds < 3600 then text = string.format("%02d : %02d", math.floor(seconds / 60), seconds % 60)
    else
        text = string.format("%02d : %02d : %02d", math.floor(seconds / 3600),
            math.floor(seconds % 3600 / 60), seconds % 3600 % 60)
    end
    font.gdi(context, text, 580, top + players * step + (battle_run and 112 or 67))
end

function screen.describe(state)
    local current = state.match
    local parts = {"frame=" .. current.frame_number, "background=" .. current.background_row,
        "camera=" .. current.camera, "round=" .. current.round_counter, "winner=" .. current.winner}
    if current.paused then parts[#parts + 1] = "paused" end
    if current.mode == constants.modes.demo then parts[#parts + 1] = current.random_game and "demo" or "demo_ending" end
    if current.cheat_lock > 0 then
        local counts = current.function_counts
        parts[#parts + 1] = string.format("fkeys=%d:%d,%d,%d,%d", current.cheat_lock, counts[6], counts[7],
            counts[8], counts[9])
    end
    local run = current.stage_run
    if run then
        parts[#parts + 1] = string.format("stage=%d phase=%d go=%d shutter=%d result=%d bound=%d width=%d", run.id,
            run.phase, run.go, run.shutter, run.result, current.stage_bound, current.stage.width or constants.screen.width)
    end
    for index = 0, constants.item_slots - 1 do
        local value = current.items[index]
        if value then
            -- Holding links are listed only when set, so plain items keep the short form.
            local held = value.weapon ~= constants.weapon_holder_codes.none and string.format(" weapon=%d link=%d", value.weapon,
                value.weapon > 0 and value.held_item or value.holder) or ""
            parts[#parts + 1] = string.format("item%d{id=%d frame=%d x=%.3f y=%.3f z=%.3f vx=%.3f vy=%.3f vz=%.3f hp=%d mp=%d facing=%d%s}",
                index, value.record.id, value.frame, value.x, value.y, value.z, value.vx, value.vy, value.vz,
                value.hp, value.mp, value.facing, held)
        end
    end
    return table.concat(parts, " ")
end

-- The unlock key (stage.dat `respond:`) the match just ended with, or nil: only a cleared stage earns one. The decision
-- belongs to game/stage.lua; nothing here judges a win. nil-safe when the game has no such function.
function screen.unlock_key(state)
    local ok, stage = pcall(require, "base/game/stage")
    if not ok or type(stage) ~= "table" or not stage.unlock_key then return nil end
    return stage.unlock_key(state.match)
end

function screen.outcome(state)
    local run = state.match.stage_run
    if not run then return {} end
    return {stage_level = run.id, auto_start = run.next_group, ending = run.ending}
end

-- The check box of the kill display (`bound: 1` in its block): while the game is paused a small box at the top right corner
-- turns the display on and off (the pause summary box of Darkfiren, whose content the readme does not give, is not made).
-- [BELUM PASTI] the place (top right corner), the size and the text.
local function kill_checkbox_place() return constants.screen.width + wide_gap() - 22, 6, 14 end
function screen.kill_toggle(state, held)
    local view = state.view
    if not (view and view.paused and type(held) == "table" and held.click and type(held.pointer_x) == "number" and type(held.pointer_y) == "number") then return false end
    local settings = ui_modes.kill_settings(options.current().battlefield_layout)
    if not settings or not settings.checkbox then return false end
    local x, y, size = kill_checkbox_place()
    if held.pointer_x >= x - 2 and held.pointer_x <= x + size + 2 and held.pointer_y >= y - 2 and held.pointer_y <= y + size + 2 then
        state.kill_hidden = not state.kill_hidden
        return true
    end
    return false
end
local function draw_kill_checkbox(context, state, view)
    if not view.paused then return end
    local settings = ui_modes.kill_settings(options.current().battlefield_layout)
    if not settings or not settings.checkbox then return end
    local x, y, size = kill_checkbox_place()
    context.fill(x - 1, y - 1, size + 2, size + 2, 0, 0, 0)
    context.fill(x, y, size, size, 200, 200, 200)
    context.fill(x + 1, y + 1, size - 2, size - 2, 40, 40, 40)
    if not state.kill_hidden then context.fill(x + 3, y + 3, size - 6, size - 6, 255, 255, 255) end
    font.gdi(context, i18n.tr("Kill list"), x - 62, y - 1, colorref(0xffffff))
end

function screen.draw(state, context, window_bounds)
    local view_width = constants.screen.width
    -- A background taller than the classic 550 is shown whole: the viewport takes its height and the platform scales it.
    local view_height = constants.screen.height
    if state.match and state.match.stage and background.view_height then view_height = background.view_height(state.match.stage) or view_height end
    local wide_picture = options.wide_width(options.current().battlefield_layout)
    if wide_picture then
        -- LF2 Darkfiren's widescreen: the picture is 1333 (or 1018) wide whatever the window; a window that is
        -- even wider shows more of the stage, and a narrower one is letterboxed by the platform. The simulation
        -- keeps its classic 794 wide view; the expanded battlefield below shows the rest.
        view_width = wide_picture
        window_bounds = {
            left = math.min(window_bounds and window_bounds.left or 0, 0),
            top = math.min(window_bounds and window_bounds.top or 0, 0),
            right = math.max(window_bounds and window_bounds.right or 0, view_width),
            bottom = math.max(window_bounds and window_bounds.bottom or 0, view_height)}
    end
    screen.view.width, screen.view.height = view_width, view_height
    context.viewport(view_width, view_height, 0, 0, 0)
    local view = state.view
    local current = state.match
    if not view then return end
    local bounds, passable_bounds, wide
    if window_bounds and (window_bounds.left < 0 or window_bounds.top < 0
            or window_bounds.right > constants.screen.width or window_bounds.bottom > view_height) then
        -- The stage's edges are the screen's edges: a window of the full screen width scrolls across the stage
        -- (slower than the game's camera, which follows the fighters on a 794 wide view) and always contains
        -- that classic view. Nothing is scaled and nothing slides in at the stage ends.
        local stage_width = current.stage.width or constants.screen.width
        local window_width = window_bounds.right - window_bounds.left
        -- The window scrolls across the part of the stage that is open, so that its edge is the screen's edge: the
        -- whole stage, or, in Stage mode, the current section (it grows step by step). Nothing is drawn beyond a
        -- section that is narrower than the window.
        local limit = stage_width
        if current.stage_bound >= window_width and current.stage_bound < limit then limit = current.stage_bound end
        local camera
        if stage_width > window_width and current.stage_bound > 0 and current.stage_bound < window_width then
            -- The open section is narrower than the window: all of it is shown, from its left edge.
            camera = 0
        elseif stage_width > window_width then
            camera = math.floor(math.min(view.camera, limit - constants.screen.width) * (limit - window_width) / (limit - constants.screen.width))
        else
            -- A stage narrower than the window is centred.
            camera = math.floor((stage_width - window_width) / 2)
        end
        if stage_width > window_width then
            -- The window moves smoothly when the section opens up, and always holds the classic 794 wide view.
            local previous = state.wide_camera
            if previous then camera = math.max(previous - 10, math.min(previous + 10, camera)) end
            camera = math.max(view.camera + constants.screen.width - window_width, math.min(view.camera, camera))
            camera = math.max(0, math.min(stage_width - window_width, camera))
            state.wide_camera = camera
        end
        wide = {left = window_bounds.left, right = window_bounds.right, camera = camera}
        -- World x is drawn at x - shift in viewport coordinates.
        local shift = camera - window_bounds.left
        local classic_right = view.camera + constants.screen.width - shift
        view = {camera = shift, items = view.items, paused = view.paused, shake = view.shake, stage = view.stage,
            time_left = view.time_left, time_row = view.time_row, cost_pool = view.cost_pool, kills = view.kills, kill_clock = view.kill_clock, etc_width = view.etc_width, boss_slot = view.boss_slot}
        -- Only matters for a stage narrower than the window.
        bounds = {left = math.max(window_bounds.left, -shift), right = math.min(window_bounds.right, stage_width - shift)}
        passable_bounds = {left = bounds.left, right = bounds.right}
        if current.stage_bound > 0 then
            -- Preserve the original picture; restrict only the extended area.
            passable_bounds.right = math.min(bounds.right, math.max(classic_right, current.stage_bound - shift))
        end
        context.render_area(window_bounds.left, window_bounds.top,
            window_bounds.right - window_bounds.left, window_bounds.bottom - window_bounds.top)
        context.clip(passable_bounds.left, window_bounds.top,
            passable_bounds.right - passable_bounds.left, window_bounds.bottom - window_bounds.top)
    end
    local quake_x, quake_y = quake_offsets(current)
    -- Vertical camera (match.camera_z, pixels, 0 or more; Darkfiren's zcam/zcamera for a background taller than the window):
    -- the whole arena (background, objects, sparks) moves up by that much; the HUD stays. nil-safe: no field, no move.
    local camera_z = type(current.camera_z) == "number" and current.camera_z == current.camera_z and math.max(0, math.floor(current.camera_z)) or 0
    local shift_y = quake_y - camera_z
    local arena = (quake_x ~= 0 or shift_y ~= 0) and shifted(context, quake_x, shift_y) or context
    if current.background_row == constants.background_rows.lee_on_road then
        background.paint_lee_on_road(arena, view.camera, bounds)
    else
        background.paint(arena, current.stage, current.view, view.camera, bounds, wide)
    end
    context.clip(passable_bounds and passable_bounds.left or 0, 128,
        passable_bounds and passable_bounds.right - passable_bounds.left or constants.screen.width, view_height - 128)
    local lighting = options.current()
    minibar_mode = current.mode == constants.modes.stage and 1 or 0
    combo_settings = ui_modes.combo_settings(options.current().battlefield_layout)
    for _, entry in ipairs(view.items) do
        draw_item(arena, current.stage, view, entry, passable_bounds, lighting)
    end
    context.clip()
    for _, command in ipairs(view.stage or {}) do
        if command[1] == "sprite" then context.sprite(command[2], command[3], command[4] + stage_dx(command[4], command[5], command[6]), command[5], true)
        elseif command[1] == "fill" then
            if bounds and command[2] == 0 and command[4] == constants.screen.width then
                -- Stage shutters cover the whole window, including blocked scenery.
                context.clip(window_bounds.left, window_bounds.top,
                    window_bounds.right - window_bounds.left, window_bounds.bottom - window_bounds.top)
                context.fill(window_bounds.left, command[3],
                    window_bounds.right - window_bounds.left, command[5], 0, 0, 0)
                context.clip()
            else
                context.fill(command[2], command[3], command[4], command[5], 0, 0, 0)
            end
        elseif command[1] == "text" then font.gdi(context, command[2], command[3] + stage_dx(command[3], command[4], command[6] or (type(command[5]) == "string" and command[5] or nil)), command[4], type(command[5]) == "number" and colorref(command[5]) or nil)
        elseif command[1] == "caption" then
            -- Outlined bitmap text in a team font (the original's four-way offset draw).
            local caption_x = command[3] + stage_dx(command[3], command[4], command[6])
            for _, offset in ipairs({{-1, 1}, {-1, 0}, {0, 1}, {0, 0}}) do
                glyphs(context, "pe/words" .. command[5], command[2], caption_x + offset[1], command[4] + offset[2], 8)
            end
        end
    end
    do
        local layout = options.current().battlefield_layout
        local style = ui_hud.current(layout, options.wide_width(layout), options.current().hud_style)
        draw_status(context, current, style)
        if style and style.radar then draw_radar(context, view, current, style.radar, wide_center(), options.wide_width(layout) or constants.screen.width) end
    end
    if not state.kill_hidden then draw_kill_board(context, view, current) end
    draw_kill_checkbox(context, state, view)
    draw_bossbar(context, view, current)
    if view.time_left then
        -- The time limit's clock: the time left, in the middle under the HP frames.
        local seconds = math.ceil(view.time_left / 30)
        local clock_text = string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
        bold_text(context, clock_text, 0x18d + wide_center() - math.floor(font.width(clock_text) / 2), 0x6e + (view.time_row or 0))
    end
    if view.cost_pool then
        -- LF2 Darkfiren's cost mode: what each team has left, one line per team under the clock.
        local teams = {}
        for team in pairs(view.cost_pool) do teams[#teams + 1] = team end
        table.sort(teams)
        for line, team in ipairs(teams) do
            local label = string.format("%s %d: %d", team >= 10 and "P" or "Team", team >= 10 and team - 9 or team, view.cost_pool[team])
            bold_text(context, label, 0x18d + wide_center() - math.floor(font.width(label) / 2), 0x6e + 14 * line)
        end
    end
    if view.paused then
        context.image("pe/pause", 360 + wide_center(), 288, true)
        return
    end
    -- After the end loop: the demo's exit hint and DEMO picture, or the function-key line (GDI
    -- text; font.gdi stands in).
    if current.random_game then
        font.gdi(context, i18n.tr("Press F4 or 'Attack' to exit"), 0x262 + wide_gap(), 0x6e, 0x7d7d7d)
        font.gdi(context, "http://www.LittleFighter.com", 5, 0x6e, 0xc8c8c8)
        context.image("pe/demo", 0x168 + wide_center(), 0x120, true)
    elseif current.cheat_lock == 1 then
        local counts = current.function_counts
        local text = i18n.tr("Function Keys Used:    F6: %d time(s)    F7: %d time(s)    F8: %d time(s)    F9: %d time(s)",
            counts[6], counts[7], counts[8], counts[9])
        if current.mode == constants.modes.stage then
            context.fill(0, 128, constants.screen.width + wide_gap(), 21, 0, 0, 0)
            font.gdi(context, text, 0, 129)
        else
            font.gdi(context, text, 0, 109)
        end
    elseif current.cheat_lock == 2 then
        font.gdi(context, i18n.tr("Function Keys Locked"), 0, 109)
    end
    -- The summary is laid out for 794 pixels and sits in the middle of a wider picture.
    draw_scoreboard(wide_center() ~= 0 and shifted(context, wide_center(), 0) or context, current)
    local replaying = current.replay and not current.replay_ended
    if replaying then
        -- The strip ends at the right edge (67 + 725 of 794): in a wider picture it moves with it. [BELUM PASTI]
        context.sprite("pe/menu_clip4", {2, 586, 725, 12}, 0x43 + wide_gap(), 0x216, false)
        if current.replay_status then replay_lines(context, current) end
    end
    mode_line(context, current, replaying)
end

return screen
