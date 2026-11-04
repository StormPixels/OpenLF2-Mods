-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren frame states that change the flow of an object (not the outcome of a hit): conditional/random `next`,
-- set hp/mp, facing, invisibility, reserve lives, team, healing and holding a frame. Runtime fields live in value.st.
local st_constants = require("base/game/st_constants")
local constants = require("base/game/constants")
local st_frame = require("base/game/st_frame")
local st_camera = require("base/game/st_camera")
local timestop = require("base/game/timestop")
local S = st_constants.states
local st_states = {}

local function ensure(value)
    local st = value.st
    if not st then
        st = {}
        value.st = st
    end
    return st
end

local function between(s, range) return s >= range.first and s <= range.last end

local function kind_of(s)
    if s < 20 then return nil end
    if s == S.invisible or s == S.invisible_not_clone or s == S.turn or s == S.turn_and_step
       or s == S.hold_round or s == S.move_to_center then return "exact" end
    if s >= S.set_hp_one and s <= S.set_mp_full then return "set" end
    if s >= S.mp_regen_first and s <= S.mp_regen_last then return "mp_regen" end
    if s >= S.team_first and s <= S.team_last then return "team" end
    if s >= S.reserve_first and s <= S.reserve_last then return "reserve" end
    if s >= S.heal_first and s <= S.heal_last then return "heal" end
    local c = st_constants
    if between(s, c.charge) then return "charge" end
    if between(s, c.ai_takeover) then return "takeover" end
    if between(s, c.timestop) then return "timestop" end
    if between(s, c.transform) then return "transform" end
    if between(s, c.camera) then return "camera" end
    if between(s, c.quake) then return "quake" end
    local bg = c.background
    if between(s, bg.row) or between(s, bg.row_mode) or between(s, bg.mode) or between(s, bg.mode_row) then return "background" end
    return nil
end

local function stage_done(match)
    local run = match.stage_run
    return (match.round_counter or 0) >= constants.round_counters.finished or (run ~= nil and run.ending == true)
end

-- Offset a conditional state adds to `next` (states 80-82, 121-139), or nil for other states.
local function next_offset(match, value, s)
    if s == S.by_difficulty then
        local offset = (match.difficulty or constants.difficulties.normal) + 1
        if offset < 0 then offset = 0 elseif offset > 3 then offset = 3 end
        return offset
    end
    if s == S.by_mode then return (match.mode == constants.modes.stage and stage_done(match)) and 1 or 0 end
    if s == S.by_team then return value.team == constants.teams.enemies and 1 or 0 end
    if s >= S.random_first and s <= S.random_last then return engine.random(s - S.random_first + 2) end
    return nil
end

-- The frame an object goes to after its wait. 13XX jumps to a random frame in current+1..current+XX; the conditional
-- states add their offset to the magnitude of `next`. Anything else returns `next` untouched.
function st_states.resolve_next(match, value, frame)
    local nxt = frame.next
    local branch = st_constants.branch
    local s = frame.state
    if s >= branch.hp_first and s <= branch.mp_last and (s <= branch.hp_last or s >= branch.mp_first) then
        -- 1xxxyyy (hp) and 2xxxyyy (mp): xxx is the limit, yyy the other frame, next the frame for "not above".
        local is_hp = s <= branch.hp_last
        local rest = s - (is_hp and branch.hp_first or branch.mp_first)
        local limit, other = math.floor(rest / 1000), rest % 1000
        if is_hp then return value.hp > limit and other or nxt end
        if branch.mp_swapped then return value.mp > limit and nxt or other end
        return value.mp > limit and other or nxt
    end
    if nxt == 0 then return nxt end
    local sign, magnitude = 1, nxt
    if nxt < 0 then sign, magnitude = -1, -nxt end
    if magnitude > st_constants.next_random_base and magnitude < st_constants.next_random_limit then
        return value.frame + 1 + engine.random(magnitude - st_constants.next_random_base)
    end
    local offset = next_offset(match, value, frame.state)
    if offset then return sign * (magnitude + offset) end
    return nxt
end

local function center_of(match)
    local stage = match.stage or {}
    local x = (stage.width or constants.screen.width) / 2
    local zb = stage.zboundary
    local z = zb and zb[1] and zb[2] and (zb[1] + zb[2]) / 2 or nil
    return x, z
end

-- After each item's control step.
function st_states.after_control(match, index, value)
    local frame = value.record.frame(value.frame)
    local s = frame.state
    local kind = kind_of(s)
    local st = value.st
    if not kind and not st then return end
    st = st or ensure(value)
    local entered = st.seen_frame ~= value.frame
    st.seen_frame = value.frame
    if st.in_camera and kind ~= "camera" then
        st.in_camera = nil
        st_camera.release(match, index)
    end
    if not kind then
        if st.invisible then st.invisible = false end
        return
    end
    st.invisible = s == S.invisible or (s == S.invisible_not_clone and not st.clone)
    if kind == "set" then
        if s == S.set_hp_one then value.hp = 1
        elseif s == S.set_hp_zero then value.hp, value.dark_hp = 0, 0
        elseif s == S.set_mp_zero then value.mp = 0
        elseif s == S.set_hp_full then value.hp, value.dark_hp = constants.points.full, constants.points.full
        else value.mp = constants.points.full end
    elseif kind == "mp_regen" then
        st.mp_regen = s - S.mp_regen_first
    elseif kind == "quake" then
        st_camera.quake(match, s)
    elseif kind == "camera" then
        st.in_camera = true
        st_camera.follow(match, index, value, s)
    elseif kind == "charge" then
        st_states.charge(match, value, st, frame, entered)
    elseif not entered then
        return
    elseif kind == "timestop" then timestop.start(match, index, value, s)
    elseif kind == "takeover" then
        st.ai_timer = (s - st_constants.ai_takeover.first) * st_constants.ai_takeover.unit_ticks
    elseif kind == "transform" then st_states.transform(match, value, frame)
    elseif kind == "background" then st_states.switch_background(match, s)
    elseif kind == "team" then value.team = s - S.team_first
    elseif kind == "reserve" then
        if value.record.kind == constants.record_kinds.character then
            value.lives = s - S.reserve_first
            st.reserve = true
        end
    elseif kind == "heal" then
        local amount = s - S.heal_first
        if amount == 0 then amount = st_constants.heal_default end
        value.hp = math.min(value.max_hp, value.hp + amount)
        if value.dark_hp < value.hp then value.dark_hp = value.hp end
    elseif s == S.turn or s == S.turn_and_step then
        value.facing = 1 - value.facing
        if s == S.turn_and_step and st_constants.state86_takes_next then st.step_now = true end
    elseif s == S.move_to_center then
        local x, z = center_of(match)
        value.x = x
        value.x_int = math.floor(x)
        if z then value.z, value.z_int = z, math.floor(z) end
    end
end

-- Before an item's frame advance: state 86 takes its `next` at once, state 404 remembers the frame to keep.
function st_states.before_advance(match, index, value)
    local st = value.st
    if not st then return end
    if st.step_now then
        st.step_now = nil
        local frame = value.record.frame(value.frame)
        value.previous_frame = value.frame
        value.wait_counter = frame.wait
    end
    if value.record.frame(value.frame).state == S.hold_round or st.charge then st.hold_frame = value.frame
    else st.hold_frame = nil end
end

-- After an item's frame advance: state 404 puts the fighter back in its frame until the round is over.
function st_states.after_advance(match, index, value)
    local st = value.st
    if not st or not st.hold_frame then return end
    if (match.round_counter or 0) > 0 then
        st.hold_frame = nil
        return
    end
    value.frame, value.previous_frame, value.wait_counter = st.hold_frame, st.hold_frame, 0
end
-- 8XXXX: the item turns into record XXXX; it goes to the old frame's next (0 or 999: frame 0). The skin offset stays.
function st_states.transform(match, value, frame)
    local objects = require("base/game/objects")
    local record = objects.record(match, frame.state - st_constants.transform.first)
    if not record then return end
    local nxt = frame.next
    value.record = record
    value.frame = (nxt == 0 or nxt == 999) and 0 or math.abs(nxt)
    value.wait_counter = 0
end

-- 9XX, 9XXYY, 7XX, 7XXYY: background.switch(match, row, mode) when AI 5's function exists (see st_constants.background).
function st_states.switch_background(match, s)
    local ok, background = pcall(require, "base/game/background")
    if not ok or type(background) ~= "table" or not background.switch then return end
    local bg = st_constants.background
    local row, mode
    if between(s, bg.row) then row = s % 100
    elseif between(s, bg.row_mode) then row, mode = math.floor(s / 100) % 100, s % 100
    elseif between(s, bg.mode) then mode = s % 100
    else mode, row = math.floor(s / 100) % 100, s % 100 end
    pcall(background.switch, match, row, mode)
end

local function held_keys(value)
    local keys, right = value.keys, value.facing == constants.facings.right
    local held = {}
    if keys.attack then held.a = true end
    if keys.defend then held.d = true end
    if keys.jump then held.j = true end
    if (right and keys.right) or (not right and keys.left) then held.f = true end
    if (right and keys.left) or (not right and keys.right) then held.b = true end
    if next(held) then return held end
    return nil
end

local function key_still_down(value, name)
    local keys, right = value.keys, value.facing == constants.facings.right
    if name == "a" then return keys.attack end
    if name == "d" then return keys.defend end
    if name == "j" then return keys.jump end
    if name == "f" then return right and keys.right or (not right and keys.left) end
    return right and keys.left or (not right and keys.right)
end

-- 6XXX: a charge move. A, D, J, forward or backward held when the frame is entered keeps the fighter in the frame.
-- Held for `wait` ticks it goes to hit_a/d/j/f/b of the held key (mp of that frame needed); released earlier it goes to
-- `next`; every tick of holding costs the frame's mp. When a target cannot be paid for, or the mp runs out, the frame's
-- `caught` is used (or the target's own). [UNCERTAIN] The notes only call that frame "XXX".
function st_states.charge(match, value, st, frame, entered)
    local grace = st_constants.charge.grace_ticks
    if entered then
        -- held may be nil: the player may press the key a moment after the frame starts (see grace_ticks).
        st.charge = {held = held_keys(value), count = 0, age = 0}
        return
    end
    local charge = st.charge
    if not charge then return end
    charge.age = charge.age + 1
    if not charge.held then
        if charge.age > grace then st.charge = nil return end
        charge.held = held_keys(value)
        if not charge.held then return end
    end
    local control = require("base/game/control")
    local function go(target)
        st.charge = nil
        local before = value.frame
        control.enter_frame(match, value, target)
        if value.frame == before then
            local caught = st_frame.caught_target(frame)
            if caught and value.record.frames[caught] then value.frame = caught end
        end
    end
    for name in pairs(charge.held) do
        if not key_still_down(value, name) then
            if charge.age <= grace and charge.count == 0 then
                -- A tap right after entering: forget it and wait for the key to be pressed and held.
                charge.held = nil
                return
            end
            if frame.next ~= 0 then go(frame.next) else st.charge = nil end
            return
        end
    end
    local cost = frame.mp > 0 and frame.mp or 0
    if cost > 0 then
        if value.mp < cost then
            st.charge = nil
            local caught = st_frame.caught_target(frame)
            if caught and value.record.frames[caught] then value.frame = caught end
            return
        end
        value.mp = value.mp - cost
        value.mp_spent = value.mp_spent + cost
    end
    charge.count = charge.count + 1
    if charge.count < frame.wait then return end
    local ext = frame.hit_ext or {}
    local targets = {a = frame.hits.a, d = frame.hits.d, j = frame.hits.j, f = ext.f, b = ext.b}
    for _, name in ipairs({"a", "d", "j", "f", "b"}) do
        if charge.held[name] and targets[name] and targets[name] ~= 0 then return go(targets[name]) end
    end
    st.charge = nil
end

function st_states.takes_over(value)
    local st = value.st
    return st ~= nil and st.ai_timer ~= nil and st.ai_timer > 0
end

-- 7XXX: the computer plays a human fighter for XXX ticks.
function st_states.run_takeover(match, ai)
    local scan
    for index = 0, 7 do
        local value = match.items[index]
        if value and value.human and st_states.takes_over(value) then
            value.st.ai_timer = value.st.ai_timer - 1
            for key, down in pairs(value.keys) do value.previous_keys[key] = down end
            if not scan and ai.prepare then scan = ai.prepare(match) end
            ai.control(match, index, match.mode, scan)
        end
    end
end

-- Once per tick before the items run: time stop timer and the earthquake reset.
function st_states.begin_tick(match)
    timestop.tick(match)
    st_camera.begin_tick(match)
end
return st_states
