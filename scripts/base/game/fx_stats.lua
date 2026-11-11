-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- Per-object statistics for the result screen (interface I6, read by AI 4), all kept in value.fx:
--   fx.killed_by    = {[killer slot] = how many times this object was killed by that slot}
--   fx.last_killer  = slot that dealt the killing blow (nil when none)
--   fx.last_killer_type = record kind (0..6) of the object that actually dealt it: 0 character, 1 light weapon, 3 ball, ... (nil when unknown)
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
    if extra then extra.killed_by, extra.last_killer, extra.last_killer_type, extra.combo, extra.combo_age = {}, nil, nil, 0, 0 end
end
return fx
