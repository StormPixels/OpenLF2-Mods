-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren itr status effects as the control and mp code needs them. fx_status (AI 3) applies and ticks the effects
-- and `active(value, name)` tells whether one runs; this module only reads it and never writes value.fx.
--   manacle: no combination moves (the same as a background mode's bound 2)
--   bound:   the victim cannot press the jump key (DOCX; the same as a background mode's bound 1)
--   facing:  the mp a move costs is multiplied (st_constants.facing_mp_factor)
--   weak:    hp recovery stops, mp recovery slows (regenerate in match.lua)
--   confus:  the keys are swapped (st_constants.confus_map)
--   mimic:   the victim copies the keys of the fighter that applied it (value.fx.status.mimic_by = that slot)
-- delay ("cannot move fast") is not applied yet: its exact effect is not settled. [UNCERTAIN]
local st_constants = require("base/game/st_constants")
local constants = require("base/game/constants")
local st_status = {}

local fx_status
local function active(value, name)
    if fx_status == nil then
        local ok, module = pcall(require, "base/game/fx_status")
        fx_status = ok and module or false
    end
    if not fx_status then return false end
    return fx_status.active(value, name)
end
st_status.active = active

local function is_fighter(value) return value.record.kind == constants.record_kinds.character end

function st_status.no_jump(value) return is_fighter(value) and active(value, "bound") end
function st_status.no_combos(value) return is_fighter(value) and active(value, "manacle") end
function st_status.weak(value) return is_fighter(value) and active(value, "weak") end

-- Multiplier of the mp a move costs.
function st_status.mp_factor(value)
    if is_fighter(value) and active(value, "facing") then return st_constants.facing_mp_factor end
    return 1
end

-- Swap the keys of a confused fighter once, where the keys are written (match.read_input).
function st_status.remap_keys(value)
    if not (is_fighter(value) and active(value, "confus")) then return end
    local keys, map = value.keys, st_constants.confus_map
    local swapped = {}
    for key, other in pairs(map) do swapped[key] = keys[other] end
    for key, down in pairs(swapped) do keys[key] = down end
end

-- Once per control step: a mimicking fighter takes the keys of whoever applied the effect.
function st_status.mimic(match, value)
    if not (is_fighter(value) and active(value, "mimic")) then return end
    local slot = value.fx.status.mimic_by
    local source = slot and match.items and match.items[slot]
    if not source or source == value then return end
    for key in pairs(value.keys) do
        value.previous_keys[key] = value.keys[key]
        value.keys[key] = source.keys[key] or false
    end
end
return st_status
