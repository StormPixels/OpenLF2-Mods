-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- Per-object statistics for the result screen (interface I6, read by AI 4), all kept in value.fx:
--   fx.killed_by    = {[killer slot] = how many times this object was killed by that slot}
--   fx.last_killer  = slot that dealt the killing blow (nil when none)
--   fx.last_killer_type = record kind (0..6) of the object that actually dealt it: 0 character, 1 light weapon, 3 ball, ... (nil when unknown)
--   fx.deaths       = deaths recorded through record_kill (counted hits, poison, grabs), also when the killer is unknown; deaths that do not
--                     pass through record_kill (e.g. an uncounted hit) are not seen [BELUM PASTI]; nil until the first death
--   fx.combo        = running number of hits this object (as an attacker) landed in a row, 0 when none
--   fx.combo_age    = ticks since the last of those hits (0 on the tick of the hit)
-- Existing item fields (kills, damage_dealt, hp_spent) are untouched.
local constants = require("base/game/constants")
local fx_constants = require("base/game/fx_constants")
-- The <combo> block of mode.dat (AI 5): {times, respond, facing, caughtact, effect}; nil when the game has none.
local ok_sd, sd_global = pcall(require, "base/game/sd_global")
local fx = {}

local function combo_rules()
    if ok_sd and type(sd_global) == "table" and type(sd_global.combo) == "function" then
        local ok, rules = pcall(sd_global.combo)
        if ok and type(rules) == "table" then return rules end
    end
    return nil
end

-- Who is counted (and shown): effect 8 = human players, 20 = humans and computers chosen in the menu, anything
-- else (1000, or no <combo> block) = everyone.
local function counted(owner, rules)
    local effect = rules and rules.effect
    if effect == 8 then return owner.human == true end
    if effect == 20 then return owner.slot ~= nil end
    return true
end

local function extra_of(value)
    local extra = value.fx
    if not extra then extra = {} value.fx = extra end
    return extra
end

-- The killing blow. `killer` is the slot of the attacker's owner (a ball or weapon counts for its owner).
function fx.record_kill(victim, killer, killer_type)
    local extra = extra_of(victim)
    local by = extra.killed_by
    if not by then by = {} extra.killed_by = by end
    extra.deaths = (extra.deaths or 0) + 1
    if killer ~= nil and killer >= 0 then
        by[killer] = (by[killer] or 0) + 1
        extra.last_killer = killer
        extra.last_killer_type = killer_type -- nil when the caller does not know
    end
end

-- A hit that landed (not defended) on an enemy character counts toward its owner's combo.
-- Rules from <combo>: effect (who is counted), caughtact = 1 (hits dealt while catching count; `catching` is true
-- for those), respond (see tick). A hit by a clone counts for its creator because a clone's owner is the creator.
function fx.hit(state, attacker, victim, catching)
    local owner = state.items[attacker.owner]
    if not owner or owner.record.kind ~= constants.record_kinds.character then return end
    if victim.record.kind ~= constants.record_kinds.character or victim == owner then return end
    if victim.team == owner.team and owner.team ~= constants.teams.independent then return end
    local rules = combo_rules()
    if catching and not (rules and rules.caughtact == 1) then return end
    if not counted(owner, rules) then return end
    local extra = extra_of(owner)
    extra.combo = (extra.combo or 0) + 1
    extra.combo_age = 0
end

-- Once per tick for each object: ages the combo and drops it after `respond` ticks (mode.dat <combo>, else
-- fx_constants.combo_reset_ticks) without a new hit.
function fx.tick(value)
    local extra = value.fx
    local combo = extra and extra.combo
    if combo and combo > 0 then
        local age = (extra.combo_age or 0) + 1
        local rules = combo_rules()
        local limit = rules and rules.respond or fx_constants.combo_reset_ticks
        if age > limit then
            extra.combo, extra.combo_age = 0, 0
        else
            extra.combo_age = age
        end
    end
end

-- For whoever starts a new round / match with the same objects.
function fx.reset(value)
    local extra = value.fx
    if extra then
        extra.killed_by, extra.last_killer, extra.last_killer_type, extra.combo, extra.combo_age = {}, nil, nil, 0, 0
        extra.deaths = nil
    end
end
-- <stats> of an object's own data file (readme "dat file/stats.txt"), read from record.data.stats. The tags below belong to combat
-- and the opoint spawn; AI2's st_stats.lua reads regen_hp / regen_mp / recmp / caught / reserve. Every function is nil-safe:
-- without the tag (or with 0, 100 or a negative value, "if not specified the default is used") nothing changes.
local function stats_of(value)
    local data = value.record and value.record.data
    return data and data.stats
end
local function cdiv(a, b)
    local q = a / b
    return q >= 0 and math.floor(q) or math.ceil(q)
end
local function percent_of(stats, key)
    local percent = stats and stats[key]
    if percent and percent > 0 and percent ~= 100 then return percent end
    return nil
end
-- attacking: percent of the ATTACKING object's injury (any object type); defend: the victim's, only for t0 objects.
-- [BELUM PASTI]: applied to itr.injury only (not to the damage summary box, flute or breaking ice); a thrown body hits with the
-- <stats> of the thrown object, not of the thrower; defend 0 / 100 / negative = default; order attacking -> weak -> defend.
function fx.stat_damage(attacker, victim, damage)
    local percent = percent_of(stats_of(attacker), "attacking")
    if percent then damage = cdiv(damage * percent, 100) end
    if victim.record.kind == constants.record_kinds.character then
        local defend = percent_of(stats_of(victim), "defend")
        if defend then
            if fx_constants.defend_divides then damage = cdiv(damage * 100, defend) else damage = cdiv(damage * defend, 100) end
        end
    end
    return damage
end
-- ohp / ohp: overall percent multiplier of the hp: / mp: of every opoint of the SPAWNING object's data file (only when the opoint
-- writes hp: / mp:). [BELUM PASTI]: percent units like attacking.
function fx.scaled_opoint(parent, key, number)
    local percent = parent and percent_of(stats_of(parent), key)
    if percent then return cdiv(number * percent, 100) end
    return number
end

return fx
