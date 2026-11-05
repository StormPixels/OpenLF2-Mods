-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren itr status effects (feature list section 4, DOCX 20.2; only itr kind 0 and 9):
-- poison (xyyyzzww), manacle, delay, confus, weak, join, mimic, bound (xxyyy) and facing (xxyyy, MP x2).
-- Runtime state lives only in `value.fx.status`. This module applies and ticks the effects and
-- performs the ones that belong to combat (poison damage, join team swap, weak damage); the others
-- (manacle, delay, confus, bound, mimic, facing) are read by the control / MP code through `active`.
local constants = require("base/game/constants")
local fx_stats = require("base/game/fx_stats")
local fx = {}

-- UNCERTAIN (docs/darkfiren/ai3_interactions.md): the notes' examples contradict their own
-- explanation (section 20.2). Decisions, all easy to change here:
fx.poison_interval = 60  -- frames between poison ticks ("50 HP per 2 seconds" at 30 frames a second)
fx.timed = {"manacle", "delay", "confus", "weak", "join", "mimic", "bound", "facing"}
local only_characters = {weak = true, join = true, mimic = true}

-- poison: X = type, YYY = duration (frames), ZZ = damage (HP or percent), WW = chance % (0 = always).
function fx.parse_poison(value)
    return {
        kind = math.floor(value / 10000000) % 10,
        duration = math.floor(value / 10000) % 1000,
        amount = math.floor(value / 100) % 100,
        chance = value % 100,
    }
end
-- the other effects: XX = chance % (0 = always), YYY = duration (frames; 300 = 10 seconds).
function fx.parse_timed(value)
    return {chance = math.floor(value / 1000) % 100, duration = value % 1000}
end

local function rolled(chance, random)
    return chance == 0 or random(100) < chance
end

local function bag(value)
    local extra = value.fx
    if not extra then extra = {} value.fx = extra end
    local status = extra.status
    if not status then status = {} extra.status = status end
    return status
end

function fx.active(value, name)
    local extra = value.fx
    local status = extra and extra.status
    local entry = status and status[name]
    if not entry then return false end
    if type(entry) == "table" then return entry.timer > 0 end
    return entry > 0
end

-- Called once for a landed (not defended) plain hit.
function fx.apply(attacker, victim, itr, defended, random)
    if defended or (itr.kind ~= 0 and itr.kind ~= 9) then return end
    local character = victim.record.kind == constants.record_kinds.character
    if itr.poison and itr.poison ~= 0 then
        local poison = fx.parse_poison(itr.poison)
        if poison.duration > 0 and rolled(poison.chance, random) then
            bag(victim).poison = {kind = poison.kind, timer = poison.duration, amount = poison.amount, next = fx.poison_interval,
                by = attacker.owner}
        end
    end
    for _, name in ipairs(fx.timed) do
        local raw = itr[name]
        if raw and raw ~= 0 and (character or not only_characters[name]) then
            local timed = fx.parse_timed(raw)
            if name == "mimic" and attacker.record.kind ~= constants.record_kinds.character then timed.duration = 0 end
            if timed.duration > 0 and rolled(timed.chance, random) then
                local status = bag(victim)
                if name == "join" then
                    local old = status.join
                    status.join = {timer = timed.duration, team = old and old.team or victim.team, keep = itr.effect == 364}
                    victim.team = attacker.team
                else
                    local current = status[name] or 0
                    if timed.duration > current then status[name] = timed.duration end
                end
            end
        end
    end
end

-- Weak attackers (t0 only) deal half damage with their own attacks; opoint objects are unaffected.
function fx.weak_damage(attacker, injury)
    if attacker.record.kind == constants.record_kinds.character and fx.active(attacker, "weak") then
        return math.floor(injury / 2)
    end
    return injury
end

local function poison_damage(victim, poison)
    local kind, amount = poison.kind, poison.amount
    local damage = amount
    if kind == 2 or kind == 3 then damage = math.floor(victim.hp * amount / 100)
    elseif kind == 4 or kind == 5 then damage = math.floor(victim.max_hp * amount / 100) end
    if kind % 2 == 1 then
        -- types 1, 3, 5 never take the HP below 1
        local room = victim.hp - 1
        if room < 0 then room = 0 end
        if damage > room then damage = room end
    end
    return damage
end

-- Once per frame, over every object that carries a status.
function fx.update(state, slots)
    for index = 0, slots - 1 do
        local value = state.items[index]
        local status = value and value.fx and value.fx.status
        if status then
            local poison = status.poison
            if poison then
                poison.timer = poison.timer - 1
                poison.next = poison.next - 1
                if poison.next <= 0 then
                    poison.next = fx.poison_interval
                    local damage = poison_damage(value, poison)
                    if damage > 0 then
                        local before = value.hp
                        value.hp = value.hp - damage
                        value.hp_spent = value.hp_spent + damage
                        if before > 0 and value.hp <= 0 then
                            -- A lethal poison tick counts as a kill for whoever poisoned (same as a killing blow).
                            fx_stats.record_kill(value, poison.by)
                            local owner = poison.by and state.items[poison.by]
                            if owner then owner.kills = owner.kills + 1 end
                        end
                    end
                end
                if poison.timer <= 0 then status.poison = nil end
            end
            local join = status.join
            if join then
                join.timer = join.timer - 1
                if join.timer <= 0 then
                    if not join.keep then value.team = join.team end
                    status.join = nil
                end
            end
            for _, name in ipairs(fx.timed) do
                local timer = status[name]
                if type(timer) == "number" then
                    timer = timer - 1
                    status[name] = timer > 0 and timer or nil
                end
            end
        end
    end
end
return fx
