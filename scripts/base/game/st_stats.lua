-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren <stats> tags of an object's own data file (readme "dat file/stats.txt"), read from record.data.stats:
-- caught, regen_hp, regen_dhp, regen_mp, recmp and reserve. (ohp/omp belong to the opoint spawn, attacking/defend to
-- combat, bleed_hp to a bleeding effect that the engine does not have, the weapon settings to weapons.lua.)
-- Every function is nil-safe: without the tag the old behaviour stands.
local constants = require("base/game/constants")
local points_full = constants.points.full
local st_stats = {}

function st_stats.of(value)
    local data = value.record and value.record.data
    return data and data.stats or nil
end

-- stats.caught: the frame a fighter is forced to when it cannot pay for a move (frame `caught` has priority, see
-- st_frame.caught_target). nil without the tag or when it is 0.
function st_stats.caught(value)
    local stats = st_stats.of(value)
    local frame = stats and (stats.caught ~= 0 and stats.caught or stats.caughtact)   -- the readme writes the tag `caught` in its text and `caughtact` in its examples
    if frame and frame ~= 0 then return frame end
    return nil
end

-- stats.recmp: percentage of the mp a move costs (applied to a cost greater than 0; 0, 100 and negative are ignored).
function st_stats.recmp(value, cost)
    local stats = st_stats.of(value)
    local percent = stats and stats.recmp
    if percent and percent > 0 and percent ~= 100 and cost > 0 then return math.floor(cost * percent / 100) end
    return cost
end

-- Hit points a regeneration step gives (0 = none): stats.regen_hp -1 none, X adds X to the default +1.
function st_stats.hp_step(value)
    local stats = st_stats.of(value)
    local x = stats and stats.regen_hp
    if x == nil then return 1 end
    if x < 0 then return 0 end
    return 1 + x
end

-- stats.regen_dhp 1..5: dark hit points gained per regeneration step (0 without the tag).
function st_stats.dark_step(value)
    local stats = st_stats.of(value)
    local x = stats and stats.regen_dhp
    if x and x >= 1 and x <= 5 then return x end
    return 0
end

-- Mana a regeneration step gives, given the default amount (hp dependent). Returns an integer: 0 none, negative drains.
-- stats.regen_mp: -1 none; -2..-6 drain 1..5 (independent of hp); 0..4 default +X; 10..14 a fixed 1+(X-10) independent of hp.
function st_stats.mp_step(value, default)
    local stats = st_stats.of(value)
    local x = stats and stats.regen_mp
    if x == nil then return default end
    if x == -1 then return 0 end
    if x <= -2 and x >= -6 then return -(-x - 1) end
    if x >= 0 and x <= 4 then return default + x end
    if x >= 10 and x <= 14 then return 1 + (x - 10) end
    return default
end

-- stats.reserve: reserves (lives) of a player picked at the menu; nil without the tag.
function st_stats.reserve(value)
    local stats = st_stats.of(value)
    local reserve = stats and stats.reserve
    if reserve and reserve >= 0 then return reserve end
    return nil
end
st_stats.points_full = points_full
-- <stats> weapon attack frames (readme dat file/stats.txt "weapon attack settings"): normal_attack1 / normal_attack2 (default 20 / 25, t1 and t4),
-- jump_attack (30), run_attack (35), dash_attack (40), light_throw (45), heavy_throw (50, t2), sky_light_throw (52), run_heavy_throw (50, t2),
-- weapon_drink (55, t6): the frame a holder goes to instead of the default. `oids` (a list; AI 1 exposes the repeated `oid:` tag as stats.oids) limits
-- the settings to those weapon ids (up to 50); without it they apply to every weapon. `match.items[value.held_item]` is the held weapon.
-- A frame that is not in the character's data is ignored (the default stays).
function st_stats.weapon_frame(match, value, name, default)
    local stats = st_stats.of(value)
    local frame = stats and stats[name]
    if type(frame) ~= "number" or frame <= 0 or not value.record.frames[frame] then return default end
    local oids = stats.oids
    if type(oids) == "table" and #oids > 0 then
        local weapon = value.held_item and value.held_item ~= 0 and match.items and match.items[value.held_item]
        local id = weapon and weapon.record and weapon.record.id
        local found = false
        for _, oid in ipairs(oids) do if oid == id then found = true break end end
        if not found then return default end
    end
    return frame
end

return st_stats
