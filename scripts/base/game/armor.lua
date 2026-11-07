-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren <armor> (feature list section 8, docs/txt/readme/dat file/armor.txt).
-- `record.data.armor` is optional: a victim without it keeps the original hard-coded Knight / Louis / Julian
-- armor in combat.lua. Shape from the C++ parser: numbers type ratio decrease mp fall bdefend injury spark delay
-- hp recover facing action; text sound1 sound2; arrays `ids`, `states`, `effects`; `frames` = list of {first, last}.
-- Runtime state lives only in `value.fx.armor` (the scalar `value.armor` is the old armor multiplier).
local system_data = require("base/game/system_data")
local armor = {}

-- system.dat <armor_s> (states where armor never works); the original LF2 list when the block is absent.
armor.default_invalid_states = {[8] = true, [11] = true, [12] = true, [13] = true, [14] = true, [16] = true, [18] = true}

function armor.invalid_states()
    local set = system_data.states("armor_s")
    if set and next(set) ~= nil then return set end
    return armor.default_invalid_states
end

-- system.dat <defend>: attacker ids whose hits can be blocked from both sides (empty = only the original rule).
function armor.two_way(id)
    local set = system_data.ids("defend")
    return set ~= nil and set[id] == true
end

local function has(list, value)
    if not list then return false end
    for _, item in ipairs(list) do if item == value then return true end end
    return false
end

-- `frame: a b` = the armor is valid from frame a to frame b; several groups = any of them; `{a}` = frame a only.
local function in_frames(frames, frame)
    for _, group in ipairs(frames) do
        local first, last = group[1], group[2] or group[1]
        if first ~= nil and frame >= first and frame <= last then return true end
    end
    return false
end

local function runtime(victim, def)
    local extra = victim.fx
    if not extra then extra = {} victim.fx = extra end
    local rt = extra.armor
    if not rt then rt = {hp = def.hp, timer = 0, broken = false} extra.armor = rt end
    return rt
end

-- Decides what the victim's <armor> does with this hit. Returns nil without <armor>, else
-- {def =, absorb =}: absorb = the armor takes the hit (no stagger).
function armor.evaluate(attacker, victim, itr)
    local def = victim.record.data and victim.record.data.armor
    if not def then return nil end
    local rule = {def = def, absorb = false}
    local kind = def.type or 1
    if kind == 0 or kind == 4 then return rule end -- 0: block sound only, 4: damage scaling only
    local rt = runtime(victim, def)
    if rt.broken then return rule end
    if has(def.ids, attacker.record.id) or has(def.effects, itr.effect) then return rule end
    if kind ~= 2 then -- type 2 only looks at ids and effects
        local state = victim.record.frame(victim.frame).state
        if armor.invalid_states()[state] then return rule end
        -- `frame` and `state` each name where the armor is active; with both given it is active in either (the original
        -- Louis armor: frames below 20 OR dashing / jumping / defending); with one it is that one; with none, everywhere.
        local frames_given = def.frames and #def.frames > 0
        local states_given = def.states and #def.states > 0
        if frames_given or states_given then
            if not ((frames_given and in_frames(def.frames, victim.frame)) or (states_given and has(def.states, state))) then
                return rule
            end
        end
        if kind ~= 3 and def.fall and def.fall >= 0 and itr.fall >= def.fall then return rule end
        if def.bdefend and def.bdefend >= 0 and itr.bdefend >= def.bdefend then return rule end
        if def.injury and def.injury >= 0 and itr.injury >= def.injury then return rule end
        if def.ratio and victim.timer_b8 > def.ratio then return rule end
        if kind == 1 and def.facing and def.facing ~= 0 then
            local from_front = attacker.facing ~= victim.facing
            if (def.facing == -1 and not from_front) or (def.facing == -2 and from_front) then return rule end
        end
        if def.mp and def.mp > 0 and victim.mp < def.mp then return rule end
    end
    rule.absorb = true
    return rule
end

-- Damage while the armor absorbs: `decrease` percent of the hit (0 = none, 100 = all); -1 / nil = the original
-- LF2 tenth (returns nil so the caller keeps its own rule).
function armor.absorbed_damage(rule, base)
    local decrease = rule and rule.absorb and rule.def.decrease
    if decrease and decrease >= 0 then return math.floor(base * decrease / 100) end
    return nil
end
-- Type 4 armor scales every damaging hit by `decrease` percent (500 = five times).
function armor.scaled_damage(rule, damage)
    if rule and (rule.def.type or 1) == 4 and rule.def.decrease and rule.def.decrease >= 0 then
        return math.floor(damage * rule.def.decrease / 100)
    end
    return damage
end

-- delay >= 0 replaces the hit lag (short shaking); -1 / nil keeps the original.
function armor.delay(rule, attacker, victim)
    local delay = rule and rule.def.delay
    if delay and delay >= 0 and ((rule.def.type or 1) == 4 or rule.absorb) then
        attacker.hit_lag, victim.hit_lag = delay, -delay
    end
end

-- Sound: sound1 when the armor takes the hit, sound2 when the hit was blocked (types 0 and 4 only have sound2).
function armor.sound(rule)
    if not rule then return nil end
    if rule.absorb then return rule.def.sound1 end
    return rule.def.sound2
end

-- The armor took a hit: MP cost, armor HP, break, action frame, recovery timer.
function armor.commit(rule, itr, victim)
    local def = rule.def
    if def.mp and def.mp > 0 then victim.mp = victim.mp - def.mp end
    if def.hp then
        local rt = runtime(victim, def)
        rt.hp = rt.hp - itr.injury
        if rt.hp <= 0 then
            rt.broken = true
            rt.timer = def.recover or -1
            if def.action and itr.fall < 80 then victim.frame = def.action end
        end
    end
end

-- Once per frame: broken armors come back after `recover` frames (-1 = never).
function armor.update(state, slots)
    for index = 0, slots - 1 do
        local value = state.items[index]
        local rt = value and value.fx and value.fx.armor
        if rt and rt.broken and rt.timer > 0 then
            rt.timer = rt.timer - 1
            if rt.timer == 0 then
                rt.broken = false
                local def = value.record.data and value.record.data.armor
                rt.hp = def and def.hp or rt.hp
            end
        end
    end
end
return armor
