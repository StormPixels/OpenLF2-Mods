-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- Per-object statistics for the result screen (interface I6, read by AI 4), all kept in value.fx:
--   fx.killed_by    = {[killer slot] = how many times this object was killed by that slot}
--   fx.last_killer  = slot that dealt the killing blow (nil when none)
--   fx.combo        = running number of hits this object (as an attacker) landed in a row, 0 when none
--   fx.combo_age    = ticks since the last of those hits (0 on the tick of the hit)
-- Existing item fields (kills, damage_dealt, hp_spent) are untouched.
local constants = require("base/game/constants")
local fx_constants = require("base/game/fx_constants")
local fx = {}

local function extra_of(value)
    local extra = value.fx
    if not extra then extra = {} value.fx = extra end
    return extra
end

-- The killing blow. `killer` is the slot of the attacker's owner (a ball or weapon counts for its owner).
function fx.record_kill(victim, killer)
    local extra = extra_of(victim)
    local by = extra.killed_by
    if not by then by = {} extra.killed_by = by end
    if killer ~= nil and killer >= 0 then
        by[killer] = (by[killer] or 0) + 1
        extra.last_killer = killer
    end
end

-- A hit that landed (not defended) on an enemy character counts toward its owner's combo.
-- UNCERTAIN: the Darkfiren <combo> rules (times / respond) are not read here; see fx_constants.combo_reset_ticks.
function fx.hit(state, attacker, victim)
    local owner = state.items[attacker.owner]
    if not owner or owner.record.kind ~= constants.record_kinds.character then return end
    if victim.record.kind ~= constants.record_kinds.character or victim == owner then return end
    if victim.team == owner.team and owner.team ~= constants.teams.independent then return end
    local extra = extra_of(owner)
    extra.combo = (extra.combo or 0) + 1
    extra.combo_age = 0
end

-- Once per tick for each object: ages the combo and drops it after combo_reset_ticks without a new hit.
function fx.tick(value)
    local extra = value.fx
    local combo = extra and extra.combo
    if combo and combo > 0 then
        local age = (extra.combo_age or 0) + 1
        if age > fx_constants.combo_reset_ticks then
            extra.combo, extra.combo_age = 0, 0
        else
            extra.combo_age = age
        end
    end
end

-- For whoever starts a new round / match with the same objects.
function fx.reset(value)
    local extra = value.fx
    if extra then extra.killed_by, extra.last_killer, extra.combo, extra.combo_age = {}, nil, 0, 0 end
end
return fx
