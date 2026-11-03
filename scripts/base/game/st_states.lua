-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren frame states that change the flow of an object (not the outcome of a hit): conditional/random `next`,
-- set hp/mp, facing, invisibility, reserve lives, team, healing and holding a frame. Runtime fields live in value.st.
local st_constants = require("base/game/st_constants")
local constants = require("base/game/constants")
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

local function kind_of(s)
    if s == S.invisible or s == S.invisible_not_clone or s == S.turn or s == S.turn_and_step
       or s == S.hold_round or s == S.move_to_center then return "exact" end
    if s >= S.set_hp_one and s <= S.set_mp_full then return "set" end
    if s >= S.mp_regen_first and s <= S.mp_regen_last then return "mp_regen" end
    if s >= S.team_first and s <= S.team_last then return "team" end
    if s >= S.reserve_first and s <= S.reserve_last then return "reserve" end
    if s >= S.heal_first and s <= S.heal_last then return "heal" end
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
    elseif not entered then
        return
    elseif kind == "team" then value.team = s - S.team_first
    elseif kind == "reserve" then
        if value.record.kind == constants.record_kinds.character then value.lives = s - S.reserve_first end
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
    if value.record.frame(value.frame).state == S.hold_round then st.hold_frame = value.frame
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
return st_states
