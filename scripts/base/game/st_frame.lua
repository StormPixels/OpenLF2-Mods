-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren per-frame movement and point effects: dx/dy/dz, hp/chp/cmp, caught, hit_g (frame.hit_ext.g).
-- Frames without these keys are untouched.
local st_constants = require("base/game/st_constants")
local constants = require("base/game/constants")
local facing_right = constants.facings.right
local points_full = constants.points.full
local st_frame = {}

local function cdiv(a, b)
    local q = a / b
    if q >= 0 then return math.floor(q) end
    return math.ceil(q)
end

-- Direct movement without inertia, once per physics step. dx follows the facing; dy < 0 is up, dz > 0 is down the screen.
function st_frame.direct_move(value)
    local frame = value.record.frame(value.frame)
    local dx, dy, dz = frame.dx, frame.dy, frame.dz
    if not dx and not dy and not dz then return end
    if dx and dx ~= 0 then value.x = value.x + (value.facing == facing_right and dx or -dx) end
    if dy and dy ~= 0 then
        value.y = value.y + dy
        if value.y > 0 then value.y = 0.0 end
    end
    if dz and dz ~= 0 then value.z = value.z + dz end
end

-- hp that a frame takes (hp), fills (chp) and mp it fills (cmp, negative takes). False when the fighter cannot pay.
function st_frame.affordable(value, frame)
    local hp, cmp = frame.hp, frame.cmp
    if hp and hp > 0 and value.hp <= hp then return false end
    if cmp and cmp < 0 and value.mp < -cmp then return false end
    return true
end

-- The frame the fighter goes to when it cannot pay for `frame` (frame.caught), or nil.
function st_frame.caught_target(frame)
    local target = frame.caught
    if target and target ~= 0 then return target end
    return nil
end

-- Called when a frame is entered. Takes or fills hp/mp; when the fighter cannot pay it goes to `caught` instead.
function st_frame.on_enter(match, value, frame)
    if not match.running then return end
    local hp, chp, cmp = frame.hp, frame.chp, frame.cmp
    if not hp and not chp and not cmp then return end
    if not st_frame.affordable(value, frame) then
        local target = st_frame.caught_target(frame)
        if target and value.record.frames[target] then
            value.frame = target
            value.wait_counter = 0
        end
        return
    end
    if hp and hp ~= 0 then
        value.hp = value.hp - hp
        if hp > 0 then value.hp_spent = value.hp_spent + hp end
        if value.hp > value.max_hp then value.hp = value.max_hp end
    end
    if chp and chp ~= 0 then
        value.hp = math.min(value.max_hp, value.hp + chp)
        value.dark_hp = math.min(value.max_hp, value.dark_hp + cdiv(chp, st_constants.chp_dark_divisor))
        if value.dark_hp < value.hp then value.dark_hp = value.hp end
    end
    if cmp and cmp ~= 0 then
        value.mp = value.mp + cmp
        if cmp < 0 then value.mp_spent = value.mp_spent - cmp end
        if value.mp > points_full then value.mp = points_full end
        if value.mp < 0 then value.mp = 0 end
    end
end

-- hit_g: the frame a fighter or object lands into, replacing the default landing frame. `air_frame` is the frame before
-- the physics step, `was_airborne` whether it was in the air then.
function st_frame.landing(value, air_frame, was_airborne)
    if not was_airborne or value.y_int ~= 0 then return end
    local ext = value.record.frame(air_frame).hit_ext
    local target = ext and ext.g
    if target and target ~= 0 and value.record.frames[target] then
        value.frame = target
        value.wait_counter = 0
    end
end
return st_frame
