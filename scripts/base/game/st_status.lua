-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren itr status effects as the control and mp code needs them. fx_status (AI 3) applies and ticks the effects
-- and `active(value, name)` tells whether one runs; this module only reads it and never writes value.fx.
--   manacle: no combination moves (the same as a background mode's bound 2)
--   bound:   the victim cannot press the jump key (DOCX; the same as a background mode's bound 1)
--   facing:  the mp a move costs is multiplied (st_constants.facing_mp_factor)
--   weak:    hp recovery stops, mp recovery slows (regenerate in match.lua)
--   confus:  the keys are permuted at random (PDK 0x430e9e; see remap_keys)
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

-- confus (PDK 0x430e9e-0x430eec, read from the code): when the effect lands the victim gets a RANDOM permutation of its seven keys (no key
-- twice); every key press is replaced by the key it maps to, for the whole effect. A new application gets a new permutation. Applied once
-- per control step, where the keys are written (match.read_input). The permutation lives in value.st.confus_perm.
local key_names = {"up", "down", "left", "right", "attack", "jump", "defend"}
local function new_permutation()
    local order = {1, 2, 3, 4, 5, 6, 7}
    for i = #order, 2, -1 do
        local j = engine.random(i) + 1
        order[i], order[j] = order[j], order[i]
    end
    return order
end
function st_status.remap_keys(value)
    if not (is_fighter(value) and active(value, "confus")) then
        if value.st and value.st.confus_perm then value.st.confus_perm = nil end
        return
    end
    value.st = value.st or {}
    local perm = value.st.confus_perm
    if not perm then perm = new_permutation() value.st.confus_perm = perm end
    local keys, swapped = value.keys, {}
    for i = 1, 7 do swapped[key_names[i]] = keys[key_names[perm[i]]] end
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
