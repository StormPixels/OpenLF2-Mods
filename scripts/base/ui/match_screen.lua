-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local constants = require("base/game/constants")
local record_kinds = constants.record_kinds
local match = require("base/game/match")
local background = require("base/game/background")
local wide_menu = require("base/ui/wide_menu")
local object_data = require("base/game/object_data")
local font = require("base/ui/font")
local i18n = require("base/i18n/i18n")
local sounds = require("base/game/sounds")
local rumble = require("base/game/rumble")
local controls = require("base/ui/controls")
local navigation = require("base/ui/navigation")
local options = require("base/game/options")
local user_options = options   -- screen.create() has a parameter named options
local ui_hud = require("base/game/ui_hud")
local ui_modes = require("base/game/ui_modes")
local system_data = require("base/game/system_data")
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
-- The display blocks (<hp_bar>, <minibar>, <bossbar>, <team_flag>, ...) of a fighter: the host puts them in the object data
-- (record.data.display); the record itself carries only id, kind, data, movement and frames.
local function display_of(record)
    if type(record) ~= "table" then return nil end
    if type(record.display) == "table" then return record.display end
    local data = record.data
    if type(data) == "table" and type(data.display) == "table" then return data.display end
    return nil
end
-- Blinking of a layer (cc, c1, c2 as in a background layer): hidden outside c1..c2 of every cc ticks; shown always without cc.
local function layer_shown(layer, tick)
    local period = type(layer.cc) == "number" and math.floor(layer.cc) or 0
    if period <= 0 then return true end
    local phase = math.floor(tick or 0) % period
    return phase >= (layer.c1 or 0) and phase <= (layer.c2 or 0)
end
-- `effect: N` of a minibar or bossbar layer (LF2 Darkfiren): the layer is only drawn while the hp is below N percent of the maximum.
local function effect_ok(layer, hp, max_hp)
    if type(layer.effect) ~= "number" then return true end
    return (hp or 0) * 100 < layer.effect * math.max(1, max_hp or 1)
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
-- PAUSE.bmp and DEMO.bmp are 84 x 23: the game puts them at x 360 (the middle would be 355); in a wider picture they are put in its middle.
local function centered_x()
    if wide_gap() == 0 then return 0x168 end
    return math.floor((constants.screen.width + wide_gap() - 84) / 2)
end
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
            -- <bmp_begin> `bound` (readme "new in bmp part"): 1 no name text for this object, 2 its clones show its name, not "Com".
            local function header_bound(thing)
                local data = thing and thing.record and thing.record.data
                local header = type(data) == "table" and data.header or nil
                return type(header) == "table" and header.bound or 0
            end
            local owner = type(value.owner) == "number" and value.owner ~= index and state.items[value.owner] or nil
            entry.name_bound = header_bound(value)
            entry.owner_index = owner and value.owner or nil
            entry.owner_name_bound = header_bound(owner)
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
    snapshot.names_kind = type(state.bg_area) == "table" and state.bg_area.names or nil -- the mode's `kind`
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

local control_window_update   -- defined with the control window further down
function screen.update(state, held, context)
    -- The control window (`Change controls`) owns the input and freezes the match while it is open.
    if state.control_window then
        control_window_update(state, held, context)
        return
    end
    screen.pause_toggle(state, held)
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
-- computer independent; respond: the modes, see minibar_for). Not done: types 4 and 5 (fusion time). `bound: 1` keeps the layer inside the visible area, `centerx` then being the margin to its edges (minibar_x). OpenLF2 change: `cc`/`c1`/`c2` blink, `effect` (hp below N percent) and, without `bound`, `centerx` (x offset) are done. [BELUM PASTI] the anchor: x from the character's centre, y from the ground line (z).
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
    -- `respond` names the modes of the layer (0 vs, 1 stage, 2 1on1, 3 2on2, 4 battle, 5 demo: the values of constants.modes); it may be
    -- written several times (up to 20), AI 1 hands those over as layer.responds (R10), layer.respond being the last.
    if type(layer.responds) == "table" and #layer.responds > 0 then
        local found = false
        for _, mode in ipairs(layer.responds) do if mode == minibar_mode then found = true end end
        if not found then return false end
    elseif type(layer.respond) == "number" and layer.respond ~= minibar_mode then return false end
    return true
end
-- The x of a layer. `bound: 1` (readme "dat file/minibar.txt"): the image is shown in the visible area, like the etc messages, and
-- `centerx` is the gap kept to the edges of the background (the window in a wide layout); without `bound`, `centerx` is a plain
-- x offset (OpenLF2 change, see above). `width` is the layer's w, 0 for a whole picture of unknown size.
local function minibar_x(entry, layer, camera, shake, bounds, width)
    local x = entry.draw_offset + entry.x - camera + shake + (layer.x or 0)
    if layer.bound == 1 then
        local margin = layer.centerx or 0
        local left = (bounds and bounds.left or 0) + margin
        local right = (bounds and bounds.right or constants.screen.width) - margin - (width or 0)
        if x > right then x = right end
        if x < left then x = left end
        return x
    end
    return x + (layer.centerx or 0)
end
local function draw_minibar(context, entry, frame, camera, shake, tick, bounds)
    -- OpenLF2 change: `y` counts upwards from the top of the current sprite (z - center_y + y), so a layer with y 16 sits above the
    -- head as in the LF2 Darkfiren screenshot; before it counted downwards from the ground line (under the feet).
    -- [BELUM PASTI] the anchor: top of the sprite, taken from one screenshot of the original (bar about 85-95 px over the feet).
    local top = entry.z + (entry.y or 0) - ((frame and frame.center_y) or 0)
    local display = display_of(entry.record)
    local block = type(display) == "table" and display.minibar or nil
    local layers = block and block.layers
    if type(layers) ~= "table" then return end
    local code = minibar_code(entry)
    for _, layer in ipairs(layers) do
        if type(layer.pic) == "string" and layer.type == nil and not (type(layer.w) == "number" and layer.w >= 1 and type(layer.h) == "number" and layer.h >= 1)
           and minibar_for(layer, code) and layer_shown(layer, tick) and effect_ok(layer, entry.hp, entry.max_hp) then
            -- OpenLF2 change: a picture layer (no type) without w and h is the whole picture (the frame), as in the original.
            local x = minibar_x(entry, layer, camera, shake, bounds, 0)
            context.image(layer.pic:gsub("\\", "/"):lower(), x, top - (layer.y or 0), layer.transparency == 1)
        elseif type(layer.pic) == "string" and type(layer.w) == "number" and layer.w >= 1 and type(layer.h) == "number" and layer.h >= 1
           and minibar_for(layer, code) and layer_shown(layer, tick) and effect_ok(layer, entry.hp, entry.max_hp) then
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
                -- centerx: extra x offset (LF2 Darkfiren example: frame x -41 w 81, bars x -41 w 77 centerx 2 = centred in the frame).
                local x = minibar_x(entry, layer, camera, shake, bounds, layer.w)
                if layer.facing == 1 and width < layer.w then
                    x, dx = x + layer.w - width, dx + layer.w - width
                end
                context.sprite(layer.pic:gsub("\\", "/"):lower(), {dx, layer.dy or 0, width, layer.h}, x, top - (layer.y or 0), layer.transparency == 1)
            end
        end
    end
end

-- The combo display (<combo> of the mode file, readme/mode dat.txt): "N_hit" (`name`, %d = the hits) written with the
-- picture as a 16 x 16 grid of blocks by character code, above the attacker, for `times` ticks after the last hit. A block is
-- w x h with a 1 pixel line (green in combo_hits.bmp) at its right and bottom edge, so the grid runs every w + 1 by h + 1.
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
        context.sprite(settings.pic, {(code % 16) * (settings.w + 1), math.floor(code / 16) * (settings.h + 1), settings.w, settings.h},
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
-- The width of a PNG (bytes 17 to 20, big endian) or BMP (bytes 19 to 22, little endian) picture from its file; nil when unknown.
local kill_pic_width = {}
local function picture_width(pic)
    if kill_pic_width[pic] == nil then
        local width = false
        local ok, data = pcall(engine.read_resource, pic)
        if ok and type(data) == "string" then
            if #data >= 24 and data:sub(2, 4) == "PNG" then
                local a, b, c, d = data:byte(17, 20)
                width = ((a * 256 + b) * 256 + c) * 256 + d
            elseif #data >= 22 and data:sub(1, 2) == "BM" then
                local a, b, c, d = data:byte(19, 22)
                width = ((d * 256 + c) * 256 + b) * 256 + a
            end
        end
        kill_pic_width[pic] = (width and width >= 1 and width < 4096) and width or false
    end
    return kill_pic_width[pic] or nil
end
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
        local attacker = kill_text(event.killer, event.killer_id, settings.attacker_name)
        local victim = kill_text(event.victim, event.victim_id, settings.victim_name)
        local attacker_x = settings.attacker_back and settings.x - #attacker * 9 or settings.x
        local victim_x = settings.victim_back and settings.dvx - #victim * 9 or settings.dvx
        if pic then
            if kill_pic_known[pic] == nil then kill_pic_known[pic] = pcall(engine.read_resource, pic) end
            if kill_pic_known[pic] then
                -- Centred between the end of the attacker's name and the start of the victim's name (it covered the attacker's
                -- name at `dx`); at `dx` as the file says when the picture's width cannot be read.
                local width = picture_width(pic)
                local at = width and math.floor((attacker_x + #attacker * 9 + victim_x - width) / 2) or settings.dx
                context.image(pic, at, y, settings.transparent)
            end
        end
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
            -- Plain blood is a 1x3 red rectangle (the colour of blood_colour: red 0xF800 when nothing is written).
            -- It used to be cut from the bitmap resource pe/bars; when a game has no bars.bmp (LF2 Darkfiren without
            -- lf2.exe) that read failed and closed the game at the first drop of blood, so it is filled instead.
            local width = type(point.w) == "number" and point.w > 0 and point.w or 1
            local height = type(point.h) == "number" and point.h > 0 and point.h or 3
            local x = offset + entry.draw_offset + entry.x - camera + shake - (right and 0 or width - 1)
            local red, green, blue = blood_colour(point)
            context.fill(x, y, width, height, red, green, blue)
        end
    end
end

-- The itr and bdy boxes of an object (system.dat `<frame> bound: 1`, system_data.hitboxes): thin rectangles in the colour of the
-- part, only for the objects whose team, kind, id and frame state the part lists (a list it lacks allows all).
local hitbox_settings
local function hitbox_allows(part, kind, entry, frame)
    if not part then return false end
    if next(part.kind) ~= nil and not part.kind[kind] then return false end
    if next(part.team) ~= nil and not part.team[entry.team] then return false end
    if next(part.type) ~= nil and not part.type[entry.record.kind] then return false end
    if next(part.id) ~= nil and not part.id[entry.record.id] then return false end
    if next(part.state) ~= nil and not part.state[frame.state] then return false end
    return true
end
local function draw_hitbox_list(context, part, list, entry, frame, camera, shake)
    if type(list) ~= "table" then return end
    local red, green, blue = math.floor(part.color / 65536) % 256, math.floor(part.color / 256) % 256, part.color % 256
    for _, area in ipairs(list) do
        if type(area.x) == "number" and type(area.width) == "number" and area.width > 0 and area.height > 0
           and hitbox_allows(part, area.kind, entry, frame) then
            local x
            if entry.facing == constants.facings.right then x = area.x + entry.x - frame.center_x
            else x = frame.center_x + entry.x - area.width - area.x end
            x = x + entry.draw_offset - camera + shake
            local y = area.y + entry.z + entry.y - frame.center_y
            context.fill(x, y, area.width, 1, red, green, blue)
            context.fill(x, y + area.height - 1, area.width, 1, red, green, blue)
            context.fill(x, y, 1, area.height, red, green, blue)
            context.fill(x + area.width - 1, y, 1, area.height, red, green, blue)
        end
    end
end
local function draw_hitboxes(context, entry, frame, camera, shake)
    local settings = hitbox_settings
    if not settings then return end
    draw_hitbox_list(context, settings.itr, frame.interactions, entry, frame, camera, shake)
    draw_hitbox_list(context, settings.bdy, frame.bodies, entry, frame, camera, shake)
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
    if hitbox_settings and not on_screen then draw_hitboxes(context, entry, frame, camera, shake) end
    if entry.lives > 1 and not (view.names_kind and view.names_kind >= 3) then
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
    -- Clones of an object whose <bmp_begin> has `bound: 2` carry the name of the owner (its player name, "Com" for a computer).
    if is_character and entry.owner_name_bound == 2 and entry.owner_index and entry.name_bound ~= 1 then
        label = entry.owner_index < constants.player_slots and controls.name(entry.owner_index) or "Com"
        sheet = sheet or label_font(entry.team)
    end
    -- <bmp_begin> `bound: 1`: this object never shows a name, human or computer.
    if entry.name_bound == 1 then label = nil end
    -- The mode's `kind` (LF2 Darkfiren): 1 and 3 hide the names of computers that were not picked in the menu, 2 and 4 the names of
    -- the players too (the computers of the menu keep theirs); 3 and 4 hide the reserve ("x2") above the head as well.
    if label and view.names_kind then
        local human = entry.index < constants.player_slots
        if (human and (view.names_kind == 2 or view.names_kind == 4)) or (not human and entry.index >= 20) then label = nil end
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
        draw_minibar(context, entry, frame, camera, shake, view.kill_clock, bounds)
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
    local display = display_of(value.record)
    local own = type(display) == "table" and display[name] or nil
    -- Only the plain horizontal bar (type 1, or none given) is drawn from it; other types are [BELUM PASTI] and keep the style's.
    if type(own) == "table" and (own.type == nil or own.type == 1 or own.type == 2 or (own.type == 3 and name == "hp_bar")) and type(own.x) == "number"
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
    local display = boss and display_of(boss.record)
    local block = type(display) == "table" and display.bossbar or nil
    local layers = block and block.layers
    if type(layers) ~= "table" then return end
    context = wide_center() ~= 0 and shifted(context, wide_center(), 0) or context
    for _, layer in ipairs(layers) do
        if layer_shown(layer, view.kill_clock) and effect_ok(layer, boss.hp, boss.max_hp) and type(layer.pic) == "string"
           and layer.type == nil and not (type(layer.w) == "number" and layer.w >= 1 and type(layer.h) == "number" and layer.h >= 1) then
            -- OpenLF2 change: a picture layer (no type) without w and h is the whole picture (the frame).
            context.image(layer.pic:gsub("\\", "/"):lower(), (layer.x or 0) + (layer.centerx or 0), layer.y or 0, layer.transparency == 1)
        elseif layer_shown(layer, view.kill_clock) and effect_ok(layer, boss.hp, boss.max_hp) and type(layer.pic) == "string"
           and type(layer.w) == "number" and layer.w >= 1 and type(layer.h) == "number" and layer.h >= 1 then
            local width, kind = layer.w, layer.type
            if kind == 1 or kind == 2 or kind == 3 then
                local value = kind == 1 and boss.hp or kind == 2 and boss.dark_hp or boss.mp
                local full = type(layer.max) == "number" and layer.max > 0 and layer.max or (kind == 3 and constants.points.full or boss.max_hp)
                width = math.max(0, math.min(layer.w, math.floor(layer.w * (value or 0) / math.max(1, full))))
            elseif kind ~= nil then
                width = 0
            end
            if width > 0 then
                local x, dx = (layer.x or 0) + (layer.centerx or 0), layer.dx or 0
                if layer.facing == 1 and width < layer.w then x, dx = x + layer.w - width, dx + layer.w - width end
                context.sprite(layer.pic:gsub("\\", "/"):lower(), {dx, layer.dy or 0, width, layer.h}, x, layer.y or 0, layer.transparency == 1)
            end
        end
    end
end

local function draw_radar(context, view, current, radar, center, picture_width)
    local shift = center  -- decided by hud_shifts
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

-- R35: the small face of the status box (the frame of the HUD) only. `smallb` is the alternate small picture used there (readme "skin system.txt":
-- "smallb - alternate small image at framebox"; the developer on Discord: it is like `small:` but only for the framebox, and a tag that is not
-- written falls back to `small:`, so a bigger `small:` does not disturb the scoreboard and the championship menus, which keep `small`).
-- The skin worn (record.data.skins[i].smallb where the skin's offset is the fighter's pic_offset), else the header's `smallb`
-- (record.data.header.smallb) for the default look, else the usual small face. [BELUM PASTI] a worn skin without its own `smallb` uses its own
-- `small` and not the header's `smallb`. A picture the game lacks falls back to the usual small face.
local function readable_picture(path_text)
    local path = path_text:gsub("\\", "/"):lower()
    if skin_small_known[path] == nil then skin_small_known[path] = pcall(engine.read_resource, path) end
    return skin_small_known[path]
end
local function framebox_face(value)
    local data = value.record.data
    local skins, offset = data.skins, value.pic_offset
    if type(skins) == "table" and offset and offset ~= 0 then
        for index = 1, 10 do
            local skin = skins[index]
            if skin and skin.offset == offset then
                if type(skin.smallb) == "string" and readable_picture(skin.smallb) then return skin.smallb end
                return small_face(value)
            end
        end
        return small_face(value)
    end
    local header = data.header
    local own = type(header) == "table" and header.smallb
    if type(own) == "string" and readable_picture(own) then return own end
    return small_face(value)
end
screen.framebox_face = framebox_face -- exported for the tests

-- Custom counters and effect pictures of the HUD panel of a fighter (record.display, readme/dat file/stats count.txt and
-- effect.txt). Both are placed from the top left corner of the fighter's HUD panel. [BELUM PASTI] that anchor.
-- stats_count (up to 10 `count`s): the number of `type` (the types below; it starts at x and runs to the right; `facing: 1` ends at x and runs to the left, as the
-- frame pictures of cui1 to cui3 and Wcuiv1 lay their number boxes out; the readme says it the other way round),
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
    elseif kind == 38 then
        -- The running combo, the number of the "N_hit" display: shown with that display and gone when it ends (the combo
        -- resets); nothing below 2 hits (as for the display). Not the total of hits made (fx.hits).
        local fx = type(value.fx) == "table" and value.fx or nil
        local hits, age = fx and fx.combo, fx and fx.combo_age or 0
        if type(hits) ~= "number" or hits < 2 then return nil end
        if combo_settings and type(combo_settings.times) == "number" and age >= combo_settings.times then return nil end
        return hits
    end
    for name, number in pairs(status_names) do if number == kind then return status_timer(value, name) end end
    return nil
end
local function draw_stats_count(context, state, value, column, row, counts, hp_bar, mp_bar)
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
                    text, right = tostring(math.max(0, math.min(math.floor(number), top))), count.type == 14 or count.facing == 1
                end
            end
            if text then
                local sheet = "pe/words0"
                if count.type ~= 18 and count.type ~= 19 and type(count.pic) == "number" and count.pic >= 0 and count.pic <= 5 then
                    sheet = "pe/words" .. math.floor(count.pic)
                end
                -- `loop` is the distance between two letters (8 or 9; ignored by the types 14, 18 and 19, which use 9).
                local advance = count.type ~= 14 and count.type ~= 18 and count.type ~= 19 and type(count.loop) == "number" and count.loop >= 1 and count.loop or 9
                local left = column + count.x - (right and #text * advance or 0)
                -- OpenLF2 change: the "now/total" numbers (types 18 and 19) are centred in their own bar (hp_bar / mp_bar of the
                -- fighter or the style) whatever their length; x and y of the count are ignored.
                local bar = count.type == 18 and hp_bar or count.type == 19 and mp_bar or nil
                local top = row + count.y
                if bar and type(bar.x) == "number" and type(bar.w) == "number" then
                    left = column + bar.x + math.floor((bar.w - #text * advance) / 2)
                    -- Vertically too: the ink of the digits (not the 16 high cell) is centred on the bar.
                    local rows = type(bar.y) == "number" and type(bar.h) == "number" and font.digit_rows() or nil
                    if rows then top = row + bar.y + math.floor((bar.h - (rows[2] - rows[1] + 1)) / 2) - rows[1] end
                end
                glyphs(context, sheet, text, left, top, advance)
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
local function draw_effects(context, value, column, row, tick, layers)
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
local function draw_nickname(context, value, own_slot, slot, column, row, block)
    if type(block) ~= "table" or block.respond ~= 2 or type(block.name_x) ~= "number" or type(block.name_y) ~= "number" then return end
    local text = own_slot and controls.name(slot) or "Com"
    glyphs(context, block.team == 1 and label_font(value.team) or "pe/words0", text, column + block.name_x, row + block.name_y, 9)
end

-- Where the HUD's boxes and radar go in a wide picture. A style whose radar sits right of the boxes was made for that picture (four
-- boxes of 198 and a radar: 1018 wide) and is one block: boxes and radar move together, centred as a whole (0 when the picture is
-- as wide as the block). Any other style keeps the classic placement: boxes centred unless the style says not, the radar by its
-- own `centered`. Returns the shift of the boxes and the shift of the radar.
local function hud_shifts(style)
    local boxes = style.centered == false and 0 or wide_center()
    local radar = style.radar
    local radar_shift = radar and radar.centered and wide_center() or 0
    if radar and style.centered ~= false and (radar.pic_x or 0) >= (style.frame_x or 0) + (style.row or 4) * (style.frame_w or 198) - 1 then
        local width = options.wide_width(options.current().battlefield_layout) or constants.screen.width
        local content = radar.pic_x + (wide_menu.picture_width(radar.pic) or radar.width or 0)
        boxes = math.max(0, math.floor((width - content) / 2 + 0.5))
        radar_shift = boxes
    elseif radar and style.centered ~= false and options.wide_width(options.current().battlefield_layout) then
        -- A radar that starts inside the row of boxes (frame.dat of a 1016 wide HUD: boxes 0..792, radar from 681) was made to
        -- stand right of them in a wide picture: the radar is pushed to the end of the row and the two are centred as one block,
        -- instead of the boxes being centred alone and the radar covering the last one. The classic 794 picture keeps its overlap.
        local first = style.frame_x or 0
        local row_end = first + (style.row or 4) * (style.frame_w or 198)
        local radar_x = radar.pic_x or 0
        if radar_x > first and radar_x < row_end - 1 then
            local push = row_end - radar_x
            local width = options.wide_width(options.current().battlefield_layout)
            local content = radar_x + push + (wide_menu.picture_width(radar.pic) or radar.width or 0)
            boxes = math.max(0, math.floor((width - content) / 2 + 0.5))
            radar_shift = boxes + push
        end
    end
    return boxes, radar_shift
end

local function draw_status(context, state, style)
    style = style or fallback_hud
    local boxes_shift = hud_shifts(style)
    for slot = 0, (style.slots or 8) - 1 do
        local row = math.floor(slot / style.row) * style.frame_h + style.frame_y
        local column = style.frame_x + (slot % style.row) * style.frame_w + boxes_shift
        local value = state.items[slot] or state.items[slot + 10]
        -- A character's own `frame:` and `bars:` (<bmp_begin>, readme "new in bmp part.txt") replace the style's pictures in its box; the
        -- placement and the bar colour rows still come from the style. A picture the game lacks falls back to the style's.
        local frame_pic, bars_pic = style.frame_pic, style.bars_pic
        if value then
            local header = value.record.data.header
            if type(header) == "table" then
                if type(header.frame) == "string" and readable_picture(header.frame) then frame_pic = header.frame:gsub("\\", "/"):lower() end
                if type(header.bars) == "string" and readable_picture(header.bars) then bars_pic = header.bars:gsub("\\", "/"):lower() end
            end
        end
        context.image(frame_pic, column, row, false)
        if value then
            local small = framebox_face(value)
            if small then context.image(small:gsub("\\", "/"):lower(), column + style.small_x, row + style.small_y, false) end
            local hp_bar, mp_bar = bar_of(value, "hp_bar", style), bar_of(value, "mp_bar", style)
            if value.hp > 0 then
                local function bar(source_y, width, geometry)
                    if width > 0 then context.sprite(bars_pic, {0, source_y, width, geometry.h}, column + geometry.x, row + geometry.y, false) end
                end
                -- 124 pixels is the full bar of the classic HUD; another width scales it.
                local function filled(amount, geometry) return math.floor(amount * 31 / 125 * (geometry.w / 124)) end
                bar(style.col_dhp, filled(value.dark_hp, hp_bar), hp_bar)
                local own_hp = display_of(value.record)
                own_hp = type(own_hp) == "table" and own_hp.hp_bar or nil
                local hp_animation = nil
                if type(own_hp) == "table" and own_hp.type == 3 and type(own_hp.layers) == "table" and #own_hp.layers > 0 then hp_animation = own_hp
                elseif style.hp_bar.type == 3 and type(style.hp_bar.layers) == "table" and #style.hp_bar.layers > 0 then hp_animation = style.hp_bar end
                if type(own_hp) == "table" and own_hp.type == 2 then
                    -- <hp_bar> type 2 (readme "hpbar.txt": rgb bar based on colour, hp only): one solid colour that goes green, yellow, red as
                    -- the hp falls (the HUD of the video "RGB Bars (green => yellow => red)"). [BELUM PASTI] the exact curve: linear in two halves.
                    local width = filled(value.hp, hp_bar)
                    if width > 0 then
                        local ratio = math.max(0, math.min(1, value.hp / constants.points.full))
                        local red = math.min(255, math.floor(2 * (1 - ratio) * 255))
                        local green = math.min(255, math.floor(2 * ratio * 255))
                        context.fill(column + hp_bar.x, row + hp_bar.y, width, hp_bar.h, red, green, 0)
                    end
                elseif hp_animation then
                    -- <hp_bar> type 3 (readme "hpbar.txt"): the bar is read from the bars picture at (dx, dy) of each layer, a layer shown only
                    -- in c1..c2 of every cc ticks (so two layers swap), while the hp is below `effect` percent (always when it is missing or
                    -- 100 or more); otherwise, or when no layer is shown, the usual bar. [BELUM PASTI] how `effect: 1xx` of the notes reads.
                    local percent = value.hp * 100 / constants.points.full
                    local drawn = false
                    if hp_animation.effect == nil or hp_animation.effect >= 100 or percent < hp_animation.effect then
                        local width = filled(value.hp, hp_bar)
                        for _, layer in ipairs(hp_animation.layers) do
                            if width > 0 and layer_shown(layer, state.elapsed) then
                                context.sprite(bars_pic, {layer.dx or 0, layer.dy or 0, width, hp_bar.h}, column + hp_bar.x, row + hp_bar.y, false)
                                drawn = true
                            end
                        end
                    end
                    if not drawn then bar(style.col_hp, filled(value.hp, hp_bar), hp_bar) end
                else
                    bar(style.col_hp, filled(value.hp, hp_bar), hp_bar)
                end
                -- Healing (milk, regeneration): the bar flashes every other tick of the 12-tick counter.
                if (math.floor(value.regen_timer / constants.healing.timer_base) == 1 or value.heal_timer > 0) and state.counter_12 % 2 == 0 then
                    bar(style.col_bhp, filled(value.hp, hp_bar), hp_bar)
                end
                -- <mp_bar> type 3 (readme "mpbar.txt"): 10 vertical bars of `w` x `h` read from the bars picture at (dx, dy), one for every 50 mp,
                -- `loop` pixels apart; `facing: 1` fills from the right. The frame picture holds the empty slots. [BELUM PASTI] the partial
                -- bar is drawn narrower, `amount` layers are not used.
                local own_mp = display_of(value.record)
                own_mp = type(own_mp) == "table" and own_mp.mp_bar or nil
                if type(own_mp) == "table" and own_mp.type == 3 and type(own_mp.x) == "number" and type(own_mp.y) == "number" then
                    local width, height = own_mp.w or 6, own_mp.h or 10
                    local pitch = own_mp.loop or width
                    local mana = math.min(math.max(value.mp, 0), constants.points.full)
                    for index = 0, 9 do
                        local part = math.min(50, mana - index * 50)
                        if part <= 0 then break end
                        local pixels = math.max(1, math.floor(width * part / 50))
                        local slot_x = own_mp.facing == 1 and (own_mp.x + (9 - index) * pitch + width - pixels) or (own_mp.x + index * pitch)
                        context.sprite(bars_pic, {own_mp.dx or 0, own_mp.dy or 0, pixels, height}, column + slot_x, row + own_mp.y, false)
                    end
                elseif type(own_mp) == "table" and own_mp.type == 4 and type(own_mp.x) == "number" and type(own_mp.y) == "number" then
                    -- <mp_bar> type 4 (readme "mpbar.txt"): 2 layers of 5 vertical bars, one bar for every 50 mp, `mp` fixed at 250 per layer; the
                    -- second layer (read `h` rows lower) covers the first one from 251 mp. The rest as type 3. [BELUM PASTI] the layer offset.
                    local width, height = own_mp.w or 6, own_mp.h or 10
                    local pitch = own_mp.loop or width
                    local mana = math.min(math.max(value.mp, 0), constants.points.full)
                    local layers = (type(own_mp.amount) == "number" and own_mp.amount >= 1) and own_mp.amount or 2
                    local layer = math.min(mana > 250 and 1 or 0, layers - 1)
                    local function segments(index, amount)
                        for number = 0, 4 do
                            local part = math.min(50, amount - number * 50)
                            if part <= 0 then break end
                            local pixels = math.max(1, math.floor(width * part / 50))
                            local slot_x = own_mp.facing == 1 and (own_mp.x + (4 - number) * pitch + width - pixels) or (own_mp.x + number * pitch)
                            context.sprite(bars_pic, {own_mp.dx or 0, (own_mp.dy or 0) + index * height, pixels, height}, column + slot_x, row + own_mp.y, false)
                        end
                    end
                    if layer > 0 then segments(0, 250) end
                    segments(layer, mana - layer * 250)
                elseif type(own_mp) == "table" and own_mp.type == 2 then
                    -- <mp_bar> type 2 (readme "mpbar.txt"): `amount` layers of `h` rows read from the bars picture at (dx, dy + layer * h); the layer
                    -- changes every `mp` (100 by default), so 1..100 mp fills layer 1, 101..200 fills layer 2 over a full layer 1, and so on;
                    -- beyond the last layer the last one stays. [BELUM PASTI] the way a new layer grows over the previous one.
                    local step = (type(own_mp.mp) == "number" and own_mp.mp >= 1) and own_mp.mp or 100
                    local layers = (type(own_mp.amount) == "number" and own_mp.amount >= 1) and own_mp.amount or 1
                    local mana = math.min(math.max(value.mp, 0), constants.points.full)
                    if mana > 0 then
                        local layer = math.min(math.ceil(mana / step) - 1, layers - 1)
                        local function layer_row(index, pixels)
                            if pixels > 0 then
                                context.sprite(bars_pic, {own_mp.dx or 0, (own_mp.dy or 0) + index * mp_bar.h, pixels, mp_bar.h},
                                    column + mp_bar.x, row + mp_bar.y, false)
                            end
                        end
                        if layer > 0 then layer_row(layer - 1, mp_bar.w) end
                        local part = math.min(1, (mana - layer * step) / step)
                        layer_row(layer, math.floor(mp_bar.w * part))
                    end
                else
                    bar(style.col_dmp, mp_bar.w, mp_bar)
                    bar(style.col_mp, filled(math.min(value.mp, constants.points.full), mp_bar), mp_bar)
                end
            end
            local own_display = display_of(value.record)
            local own_flag = own_display and own_display.team_flag or nil
            local flag = type(own_flag) == "table" and type(own_flag.x) == "number" and type(own_flag.y) == "number" and own_flag or style.team_flag
            glyphs(context, label_font(value.team), string.char(254), column + flag.x, row + flag.y, 8)
            -- A character's own blocks replace the style's (the HUD style file: ui_hud.parse).
            local own = own_display or {}
            draw_stats_count(context, state, value, column, row, own.stats_count or style.stats_count, hp_bar, mp_bar)
            draw_effects(context, value, column, row, state.elapsed, own.effect and own.effect.layers or style.effect)
            draw_nickname(context, value, state.items[slot] ~= nil, slot, column, row, own.name or style.name)
        end
    end
end

-- `summary` draws the same table in the middle of a round (the pause summary box): the numbers so far, no win or lose marks.
local function draw_scoreboard(context, current, summary)
    local counter = current.round_counter
    if not summary and (counter < 101 or counter >= constants.round_counters.finished) then return end
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
    -- The pictures are 61 (head) + 45 (row) * players + 32 (foot) high, 138 for the battle lines (80 + 45). Ten rows pass the 530 the
    -- table is centred in (543, with the battle lines 588): it then takes the whole 550 of the canvas (543 fits, top 3) and, if it
    -- still does not (battle: 588), the rows come closer to 41 (down to 30), overlapping the row pictures a little. [BELUM PASTI]
    local fixed = battle_run and 138 or 93
    local available = 530
    if players * 45 + fixed > available then available = constants.screen.height end
    local step = 45
    if players * 45 + fixed > available then step = math.max(30, math.floor((available - fixed) / players)) end
    local height = players * step + fixed
    local top = math.floor((available - height) / 2)
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
            if summary then result = nil
            elseif current.mode == constants.modes.stage then
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

-- The pause check boxes, top right (Darkfiren: "summary box is shown when the game is paused, click on the small checkbox in the top
-- right corner"): "Summary" turns the summary box (the score table so far) on and off; "Kill list" (only with `bound: 1` in the
-- kill display's block) the who-killed-whom display. [BELUM PASTI] the content of Darkfiren's summary box (the readme gives none: here
-- the table of the end of a round), the places, the size and the texts.
local function summary_possible(view, current) return view.paused and not (current or {}).random_game end
-- The boxes of the pause screen (LF2 Darkfiren video: a column at the right edge under the HUD, label left of a box only while the
-- pointer is on it). Order: Scoreboard, Change controls (`<misc> bound: 1`), Hit counter (`<combo> bound: 1`), Radar display (the
-- HUD style has a radar), Death counter (`<bmp_begin> bound: 1`). Rows that do not apply leave no gap.
local pause_labels = {summary = "Scoreboard", controls = "Change controls", combo = "Hit counter", radar = "Radar display", kill = "Death counter"}
local device_names = {[0] = "Keyboard", "Pad 1", "Pad 2", "Pad 3", "Pad 4"}
local function pad_possible(view, current)
    current = current or {}
    return view.paused and not current.random_game and not current.replay and ui_modes.misc_control(options.current().battlefield_layout)
end
local function pause_layout(view, current)
    current = current or {}
    local layout = options.current().battlefield_layout
    -- The exe (routine 0x459370 draws, 0x4592A0 collects) stacks the boxes that pass their condition from the top: the first at
    -- y 133, 28 pixels more for each next one, no gap for a box that is left out; a box is 20 x 20. Conditions: Summary always;
    -- change controls `<misc> bound: 1` (not in a demo or a replay); hit counter `<combo> bound: 1`; radar `<radar> bound: 1` and
    -- `action: 1`; death counter `<bmp_begin> bound: 1` and the current mode listed by its `mode:` lines.
    local which = {"summary"}
    if pad_possible(view, current) then which[#which + 1] = "controls" end
    local combo = ui_modes.combo_settings(layout)
    if combo and combo.checkbox then which[#which + 1] = "combo" end
    local style = ui_hud.current(layout, options.wide_width(layout), options.current().hud_style)
    if style and style.radar and style.radar.action == 1 then which[#which + 1] = "radar" end
    local kill = ui_modes.kill_settings(layout)
    if kill and kill.checkbox and not (kill.modes and not kill.modes[current.mode]) then which[#which + 1] = "kill" end
    local rows, x = {}, constants.screen.width + wide_gap() - 27
    for index, name in ipairs(which) do rows[index] = {which = name, x = x, y = 133 + 28 * (index - 1), size = 20} end
    return rows
end
local function inside(held_x, held_y, x, y, w, h) return held_x >= x and held_x <= x + w and held_y >= y and held_y <= y + h end

-- `Change controls` (`<misc> bound: 1`): the control window, the picture `pic` of <misc> (MENU_CLIP2b, 704 x 353) with the four player
-- columns drawn on its dark boxes: the name, the device picture, seven key rows; ok and cancel are part of the picture. The same
-- editing as the launch screen's Control Settings page: a click on the picture cycles the device, on a name types it, on a key row
-- waits for the key (or controller button), OK saves into config.json and applies at once, Cancel or Escape drops the changes.
-- The match stays frozen while it is open. [BELUM PASTI] its place (centered, y 108) and the exact boxes, measured on the picture.
local virtual_keys = constants.virtual_keys
-- Column x, relative to the picture: the launch screen's Control Settings page puts them at 0xc2 + 0x8b per column with its picture at 0x2e.
local control_columns = {148, 287, 426, 565}
local control_devices = {[constants.input_devices.keyboard] = "pe/cs6",
    [constants.input_devices.controller_one] = "pe/cs2", [constants.input_devices.controller_two] = "pe/cs3",
    [constants.input_devices.controller_three] = "pe/cs4", [constants.input_devices.controller_four] = "pe/cs5"}
local control_picture_cache = {}
local function control_picture(layout)
    local key = tostring(layout)
    if control_picture_cache[key] ~= nil then return control_picture_cache[key] or nil end
    local found = false
    local pic = ui_modes.misc_picture(layout)
    if pic and type(engine) == "table" and type(engine.read_resource) == "function" then
        local plain = (pic:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\\", "/"))
        for _, candidate in ipairs({plain, plain:lower(), "sprite/" .. plain, ("sprite/" .. plain):lower()}) do
            if pcall(engine.read_resource, candidate) then found = candidate break end
        end
    end
    control_picture_cache[key] = found
    return found or nil
end
local function window_origin() return math.floor((constants.screen.width + wide_gap() - 704) / 2), 108 end
local function open_control_window(state)
    state.control_window = {editing = controls.copy(controls.current()), capture = nil, name_player = 0, previous_keys = {}, keyboard = false, nav = navigation.create()}
end
local function typed_character(input, code)
    if code >= virtual_keys.left and code <= virtual_keys.down then return nil end
    return controls.key_character(code, input.keys[virtual_keys.shift] == true)
end
local function type_name(win, input)
    local name = win.editing.names[win.name_player]
    for code = 0, 255 do
        if input.keys[code] and not win.previous_keys[code] then
            local character = typed_character(input, code)
            if character and code ~= virtual_keys.backspace then
                if #name < constants.text_limits.player_name_bytes and code ~= virtual_keys.enter then name = name .. character end
            elseif code == virtual_keys.backspace and #name > 0 then
                name = name:sub(1, -2)
            end
        end
    end
    win.editing.names[win.name_player] = (name .. (input.text or "")):sub(1, constants.text_limits.player_name_bytes)
end
function control_window_update(state, input, context)
    local win = state.control_window
    -- The match's input has no `nav` (fresh ok / cancel presses): the launch screens get it from the navigation module, as here.
    input = navigation.apply(win.nav, input, {page = "match_controls", targets = {}, locked = win.capture ~= nil or win.name_player > 0})
    local editing = win.editing
    local wx, wy = window_origin()
    local used_cancel = false
    if win.capture then
        local set = editing.sets[win.capture.player]
        if set.device == constants.input_devices.keyboard then
            if input.nav.cancel then
                win.capture, used_cancel = nil, true
            else
                for code = 0, 249 do
                    if input.keys[code] then
                        set.keys[win.capture.row] = code
                        win.capture = nil
                        break
                    end
                end
            end
        elseif input.keys[virtual_keys.escape] and not win.previous_keys[virtual_keys.escape] then
            win.capture, used_cancel = nil, true
        else
            local pad, lowest = input.pads[set.device], nil
            for button = 0, 31 do
                if pad and pad.buttons[button] then lowest = button break end
            end
            if not lowest then win.capture.armed = true
            elseif win.capture.armed then
                set.buttons[win.capture.row - 4] = lowest
                win.capture = nil
            end
        end
    end
    if win.name_player > 0 then
        if input.nav.cancel or input.nav.ok or (input.keys[virtual_keys.tab] and not win.previous_keys[virtual_keys.tab]) then
            win.name_player, used_cancel = 0, true
        else
            type_name(win, input)
        end
    end
    local px, py, finished = input.pointer_x, input.pointer_y, nil
    if type(px) == "number" and type(py) == "number" then state.hover_x, state.hover_y = px, py end
    -- The same boxes and rules as the launch screen's Control Settings page (the original mechanism); only the picture comes from <misc>.
    if input.click and type(px) == "number" and type(py) == "number" then
        for player = 1, 4 do
            local x = wx + control_columns[player]
            local set = editing.sets[player]
            if inside(px, py, x, wy + 0x3d, 0x69, 0x5a) then
                win.capture = nil
                set.device = (set.device + 1) % (constants.input_devices.controller_four + 1)
            end
            if inside(px, py, x, wy + 0x23, 0x69, 0x11) then
                win.capture, win.name_player = nil, player
            end
            for row = 1, 7 do
                local y = wy + 0xa2 + (row - 1) * 0x16
                if inside(px, py, x, y - 3, 0x69, 0x12) then
                    if set.device == constants.input_devices.keyboard or row > 4 then win.capture = {player = player, row = row} end
                    win.name_player = 0
                end
            end
        end
        if inside(px, py, wx + 0x167, wy + 0x140, 0x9b, 0x18) then finished = "ok" end
        if inside(px, py, wx + 0x218, wy + 0x140, 0x9b, 0x18) then finished = "cancel" end
        -- The `Change controls` check box closes the window as well (like Cancel: nothing is saved).
        for _, row in ipairs(state.view and pause_layout(state.view, state.match) or {}) do
            if row.which == "controls" and inside(px, py, row.x, row.y, row.size, row.size) then finished = "cancel" end
        end
    end
    if not finished and input.nav.cancel and not used_cancel and not win.capture and win.name_player == 0 then finished = "cancel" end
    local typing = win.name_player > 0
    if finished then
        if win.keyboard and context.text_input then context.text_input(false) end
        -- As on the launch page: OK saves into config.json, Cancel reloads the stored settings; both play their menu sound.
        if finished == "ok" then controls.save(editing) else controls.load() end
        state.control_window = nil
        sounds.direct(state.match, finished)
        for _, sound in ipairs(sounds.flush(state.match)) do context.sound(sound.resource, sound.volume, sound.pan) end
        return
    end
    if typing ~= win.keyboard then
        win.keyboard = typing
        if context.text_input then context.text_input(typing) end
    end
    win.previous_keys = input.keys
end
local function draw_control_window(context, state)
    local win = state.control_window
    if not win then return end
    local wx, wy = window_origin()
    local picture = control_picture(options.current().battlefield_layout)
    if picture then context.image(picture, wx, wy, false) else context.fill(wx, wy, 704, 353, 110, 24, 161) end
    -- Drawn like the launch screen's Control Settings page: every name and key on a dark box as wide as its text, white, and blue
    -- (0x1946ff) while it is edited; a translated language centres the text in the column instead.
    local box, edited = 0x00092c, 0x1946ff
    local function field(value, x, left, y, color)
        if not i18n.active() then font.gdi(context, value, left, y, color, box)
        else font.gdi(context, value, x + 0x35, y, color, nil, "center") end
    end
    for player = 1, 4 do
        local x = wx + control_columns[player]
        local set, name = win.editing.sets[player], win.editing.names[player]
        if win.name_player == player then
            field(#name < constants.text_limits.player_name_bytes and name .. "_" or name, x, x + 0x15, wy + 0x26, edited)
        else
            field(name, x, x + 0x15, wy + 0x26, 0xffffff)
        end
        for row = 1, 7 do
            local capturing = win.capture and win.capture.player == player and win.capture.row == row
            local y = wy + 0xa2 + (row - 1) * 0x16
            local color = capturing and edited or 0xffffff
            if set.device == constants.input_devices.keyboard then
                local label, kind = controls.key_label(set.keys[row])
                field(label, x, x + 0x29 - kind, y, color)
            elseif row <= 4 then
                field("-", x, x + 0x30, y, 0xffffff)
            else
                field(i18n.tr("Button: %d", set.buttons[row - 4] + 1), x, x + 0x22, y, color)
            end
        end
        if control_devices[set.device] then context.image(control_devices[set.device], x, wy + 0x3d, false) end
    end
    -- The pictures that light up OK and Cancel while the pointer is on them (the launch page's menu_clip 13 and 12).
    local hx, hy = state.hover_x, state.hover_y
    if type(hx) == "number" and type(hy) == "number" then
        if inside(hx, hy, wx + 0x167, wy + 0x140, 0x9b, 0x18) then context.sprite("pe/menu_clip", {489, 426, 151, 26}, wx + 0x16a, wy + 0x140, true) end
        if inside(hx, hy, wx + 0x218, wy + 0x140, 0x9b, 0x18) then context.sprite("pe/menu_clip", {643, 426, 151, 26}, wx + 0x216, wy + 0x140, true) end
    end
end
function screen.pause_toggle(state, held)
    local view = state.view
    if type(held) == "table" and type(held.pointer_x) == "number" and type(held.pointer_y) == "number" then state.hover_x, state.hover_y = held.pointer_x, held.pointer_y end
    if not (view and view.paused and type(held) == "table" and held.click and type(held.pointer_x) == "number" and type(held.pointer_y) == "number") then return false end
    local rows = pause_layout(view, state.match)
    for _, row in ipairs(rows) do
        if inside(held.pointer_x, held.pointer_y, row.x, row.y, row.size, row.size) then
            if row.which == "summary" then state.summary_hidden = not state.summary_hidden
            elseif row.which == "kill" then state.kill_hidden = not state.kill_hidden
            elseif row.which == "combo" then state.combo_hidden = not state.combo_hidden
            elseif row.which == "radar" then state.radar_hidden = not state.radar_hidden
            else open_control_window(state) end
            return row.which
        end
    end
    return false
end
-- The box is a sprite of MENU_CLIP6 (the 7th picture of resource.dat's <bmp_begin>), 20 x 20, so it takes the mod's own colours: frame 4
-- (empty box, in the recording window of that sheet) always, frame 2 (the box with the tick) over it when on, and frame 1 (a white
-- outline on black, black being clear) while the pointer is on it. Cells found by measuring the sheet (exe routine 0x459370).
-- [BELUM PASTI] the label strips (a second sprite, one frame per box) are not identified, so the label is text.
local checkbox_sheet = "pe/menu_clip6"
local checkbox_base, checkbox_tick, checkbox_hover = {243, 166, 20, 20}, {24, 244, 20, 20}, {0, 244, 20, 20}
local function draw_checkbox(context, row, on, hovered)
    local x, y = row.x, row.y
    context.sprite(checkbox_sheet, checkbox_base, x, y, true)
    if on then context.sprite(checkbox_sheet, checkbox_tick, x, y, true) end
    if hovered then
        context.sprite(checkbox_sheet, checkbox_hover, x, y, true)
        font.gdi(context, i18n.tr(pause_labels[row.which]), x - 92, y + 3, colorref(0xffffff))
    end
end
local function draw_pause_checkboxes(context, state, view, current)
    if not view.paused then return end
    local rows = pause_layout(view, current)
    local hx, hy = state.hover_x, state.hover_y
    for _, row in ipairs(rows) do
        local on = true
        if row.which == "summary" then on = not state.summary_hidden
        elseif row.which == "kill" then on = not state.kill_hidden
        elseif row.which == "combo" then on = not state.combo_hidden
        elseif row.which == "radar" then on = not state.radar_hidden
        else on = state.control_window ~= nil end
        draw_checkbox(context, row, on, type(hx) == "number" and type(hy) == "number" and inside(hx, hy, row.x, row.y, row.size, row.size))
    end
    draw_control_window(context, state)
end

-- LF2 Darkfiren team HP bars: the `frame:` blocks of the background (bg.dat, kept by the mode's `wait:`; `current.stage.team_frames`).
-- A frame of type 0 is a picture, type 1 a bar for the team's hp and type 2 one for its dark hp (the red part that can still be
-- healed), cut from the picture at (dx, dy) and `w` wide when the team is whole (background.team_bar_rect). They sit on the screen at
-- x, y: x from the left edge of the classic 794 wide block, y from the top of the window. A team is shown while it has a fighter
-- (slots 0..19 of the HUD). [BELUM PASTI] how the readme adds a team up (here: hp over the fighters' maximum, dead ones as 0).
local function draw_team_bars(context, current, origin_x)
    local frames = current.stage and current.stage.team_frames
    if type(frames) ~= "table" or #frames == 0 then return end
    local totals = {}
    for slot = 0, 19 do
        local value = current.items[slot]
        if value and value.team and value.team >= 1 and value.team <= 4 and value.record
           and value.record.kind == constants.record_kinds.character then
            local total = totals[value.team] or {hp = 0, dark = 0, maximum = 0}
            local hp = math.max(0, value.hp or 0)
            total.hp = total.hp + hp
            total.dark = total.dark + math.max(hp, value.dark_hp or 0)
            total.maximum = total.maximum + (value.max_hp or constants.points.full)
            totals[value.team] = total
        end
    end
    for _, frame in ipairs(frames) do
        local total = totals[frame.team]
        if total and total.maximum > 0 and background.team_frame_visible(frame, current.elapsed) and type(frame.path) == "string" then
            local amount = frame.type == 2 and total.dark or total.hp
            local rect = background.team_bar_rect(frame, amount, total.maximum)
            if rect then
                context.sprite(frame.path:gsub("\\", "/"):lower(), {rect.sx, rect.sy, rect.sw, rect.sh}, rect.x + origin_x, rect.y, false)
            end
        end
    end
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
        wide = {left = window_bounds.left, right = window_bounds.right, camera = camera,
            top = window_bounds.top, bottom = window_bounds.bottom}
        -- World x is drawn at x - shift in viewport coordinates.
        local shift = camera - window_bounds.left
        local classic_right = view.camera + constants.screen.width - shift
        view = {camera = shift, items = view.items, paused = view.paused, shake = view.shake, stage = view.stage,
            time_left = view.time_left, time_row = view.time_row, cost_pool = view.cost_pool, kills = view.kills, kill_clock = view.kill_clock, etc_width = view.etc_width, names_kind = view.names_kind, boss_slot = view.boss_slot}
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
    background.paint(arena, current.stage, current.view, view.camera, bounds, wide)
    -- Objects are clipped to the stage's own width, except where the background paints across the whole window (HK Coliseum):
    -- there a fighter at the stage's edge would be cut off in front of a picture that goes on (Stage mode keeps its section limit).
    local object_bounds = passable_bounds
    if passable_bounds and wide and not (current.stage_bound and current.stage_bound > 0)
       and background.bleeds(current.stage, wide.right - wide.left) then
        object_bounds = {left = wide.left, right = wide.right}
    end
    context.clip(object_bounds and object_bounds.left or 0, 128,
        object_bounds and object_bounds.right - object_bounds.left or constants.screen.width, view_height - 128)
    local lighting = options.current()
    minibar_mode = current.random_game and constants.modes.demo or current.mode
    hitbox_settings = system_data.hitboxes()
    combo_settings = not state.combo_hidden and ui_modes.combo_settings(options.current().battlefield_layout) or nil
    for _, entry in ipairs(view.items) do
        draw_item(arena, current.stage, view, entry, object_bounds, lighting)
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
    draw_team_bars(context, current, wide and wide.left + math.floor((wide.right - wide.left - constants.screen.width) / 2) or 0)
    do
        local layout = options.current().battlefield_layout
        local style = ui_hud.current(layout, options.wide_width(layout), options.current().hud_style)
        draw_status(context, current, style)
        if style and style.radar and not state.radar_hidden then
            local _, radar_shift = hud_shifts(style)
            draw_radar(context, view, current, style.radar, radar_shift, options.wide_width(layout) or constants.screen.width)
        end
    end
    if not state.kill_hidden then draw_kill_board(context, view, current) end
    draw_pause_checkboxes(context, state, view, current)
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
        -- While the control window (`Change controls`) is open the summary box is hidden (its check box keeps its state, so the box
        -- comes back when the window is closed).
        local control_open = state.control_window ~= nil
        local summary = summary_possible(view, current) and not state.summary_hidden and not control_open
        if summary then draw_scoreboard(wide_center() ~= 0 and shifted(context, wide_center(), 0) or context, current, true) end
        -- With the summary box or the control window up the pause picture goes to the top (above them) so that it does not cover them.
        context.image("pe/pause", centered_x(), (summary or control_open) and 6 or 288, true)
        return
    end
    -- After the end loop: the demo's exit hint and DEMO picture, or the function-key line (GDI
    -- text; font.gdi stands in).
    if current.random_game then
        font.gdi(context, i18n.tr("Press F4 or 'Attack' to exit"), 0x262 + wide_gap(), 0x6e, 0x7d7d7d)
        font.gdi(context, "http://www.LittleFighter.com", 5, 0x6e, 0xc8c8c8)
        context.image("pe/demo", centered_x(), 0x120, true)
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
