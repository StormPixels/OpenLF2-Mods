-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren itr extras (feature list section 4): dvz, drain, gain, recover, dbdefend, spark.
-- Every function is nil-safe: an itr without these tags behaves exactly like an original LF2 itr.
local constants = require("base/game/constants")
local fx_status = require("base/game/fx_status")
local fx_point = require("base/game/fx_point")
local fx = {}

-- UNCERTAIN (documented in docs/darkfiren/ai3_interactions.md): the exact number formats are not
-- described by the Darkfiren notes, so every guess is a named value here and easy to change.
fx.heal_base = 17000        -- gain 17xxx heals xxx HP to the attacker
fx.heal_default = 100       -- gain 17000 (xxx = 0) heals this much ("default 100")
fx.mp_limit = constants.points.full

-- dbdefend 2/3/4 change who can be hit; 1 only changes defending (see combat.apply).
function fx.friendly(itr)
    local mode = itr.dbdefend
    return mode == 2 or mode == 3 or mode == 4
end

-- true when the itr may touch `defender` under its dbdefend mode (nil/0/1 = no restriction).
function fx.dbdefend_allows(attacker, defender, mode)
    if mode == 2 then return attacker.team == defender.team end
    if mode == 3 then return attacker.owner == defender.owner end
    return true
end

-- itr kind 17 = whirlwind (10) for t0 (characters) only; 18 = whirlwind for t1, t2, t4 and t6 only.
function fx.base_kind(kind)
    if kind == 17 or kind == 18 then return 10 end
    return kind
end
function fx.whirl_matches(kind, defender_kind)
    if kind == 17 then return defender_kind == 0 end
    if kind == 18 then return defender_kind == 1 or defender_kind == 2 or defender_kind == 4 or defender_kind == 6 end
    return true
end
-- itr kind 14 with respond 1-7 blocks only objects of type respond-1 (t0..t6).
function fx.obstacle_matches(respond, defender_kind)
    if respond and respond >= 1 and respond <= 7 then return defender_kind == respond - 1 end
    return true
end

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

-- Applied once per landed plain hit, after damage and hit lag were set.
function fx.after_hit(attacker, victim, itr, defended)
    local drain = itr.drain
    if drain and drain ~= 0 then victim.mp = clamp(victim.mp - drain, 0, fx.mp_limit) end
    local gain = itr.gain
    if gain and gain ~= 0 then
        if gain >= fx.heal_base and gain < fx.heal_base + 1000 then
            local amount = gain - fx.heal_base
            if amount == 0 then amount = fx.heal_default end
            attacker.hp = clamp(attacker.hp + amount, attacker.hp, attacker.max_hp or attacker.hp)
        else
            attacker.mp = clamp(attacker.mp + gain, 0, fx.mp_limit)
        end
    end
    local recover = itr.recover
    if recover == 1 or recover == 3 then attacker.hit_lag = 0 end
    if recover == 2 or recover == 3 then victim.hit_lag = 0 end
    if itr.dvz and itr.dvz ~= 0 and not defended then victim.impulse_z = victim.impulse_z + itr.dvz end
    fx_status.apply(attacker, victim, itr, defended, engine.random)
    fx_point.bounce_mark(attacker, victim, itr, defended)
end
-- Catching itr (kind 1) frames per side (docs/txt/readme/frame/cpoint.txt, ai1_data_fields.md "itr: catchingact ..."):
-- the LEFT side (attacker facing left) uses catchingact / caughtact, the RIGHT side pickingact / pickedact, each falling
-- back to the left pair; only the first number is used. A negative frame turns that character around (the caller does it).
-- Data with none of the new keys, or incomplete pairs, keeps the old catching_actions[1] / caught_actions[1].
function fx.catch_frames(itr, facing)
    local catching, caught
    if facing == constants.facings.left then
        catching = itr.catchingact and itr.catchingact[1]
        caught = itr.caughtact and itr.caughtact[1]
    else
        catching = (itr.pickingact or itr.catchingact or {})[1]
        caught = (itr.pickedact or itr.caughtact or {})[1]
    end
    if not catching or not caught or catching == 0 or caught == 0 then
        return itr.catching_actions[1], itr.caught_actions[1]
    end
    return catching, caught
end

-- Leaf.F effects 8-16 (docs/txt/readme/addons by Leaf.F.txt, "New effects working"). Types are record_kinds values.
-- 8-12: the extras (respond state, catchingact, caughtact) work only on the listed victim types; other types get a normal
-- hit. 13-16: the itr hits only the listed types. respond (non-zero) = only victims whose current frame state equals it
-- ([BELUM PASTI]: for 8-12 a state mismatch only drops the extras; for 13-16 it drops the whole hit).
local leaf_types = {
    [8] = {[0] = true}, [9] = {[3] = true}, [10] = {[0] = true, [3] = true}, [11] = {[1] = true, [2] = true, [4] = true, [6] = true},
    [13] = {[0] = true}, [14] = {[3] = true}, [15] = {[0] = true, [3] = true}, [16] = {[1] = true, [2] = true, [4] = true, [6] = true},
}
local function leaf_fits(itr, victim_kind, victim_state)
    local effect = itr.effect
    if effect == 12 then return true end
    local types = leaf_types[effect]
    if not types or not types[victim_kind] then return false end
    return (itr.respond or 0) == 0 or victim_state == itr.respond
end
-- true when the hit must not happen at all (effects 13-16 on a victim that does not fit)
function fx.leaf_blocks(itr, victim_kind, victim_state)
    local effect = itr.effect
    if not effect or effect < 13 or effect > 16 then return false end
    return not leaf_fits(itr, victim_kind, victim_state)
end
-- The extras of a hit by effect 8-16 that fits the victim, or nil.
function fx.leaf_extras(itr, victim_kind, victim_state)
    local effect = itr.effect
    if not effect or effect < 8 or effect > 16 then return nil end
    if effect == 12 then
        if (itr.respond or 0) ~= 0 and victim_state ~= itr.respond then return nil end
    elseif not leaf_fits(itr, victim_kind, victim_state) then
        return nil
    end
    local attacker_frame = itr.catchingact and itr.catchingact[1] or 0
    local victim_frame = itr.caughtact and itr.caughtact[1] or 0
    return {
        attacker_frame = attacker_frame > 0 and attacker_frame or 0,
        victim_frame = victim_frame > 0 and victim_frame or 0,
        no_injured = victim_frame == -1 or victim_frame == -3,
        no_fall = victim_frame == -2 or victim_frame == -3,
    }
end

return fx
