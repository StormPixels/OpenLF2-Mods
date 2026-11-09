-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren opoint extras (feature list section 6, docs/txt/readme/frame/opoint.txt).
-- Everything is nil-safe: an opoint without the new tags spawns exactly as in original LF2.
local constants = require("base/game/constants")
local K = constants.record_kinds
local fx = {}

-- Holding kinds: 2 (original) = light weapon; 3 = like t2 (heavy), 5 = like t4, 6 = like t5, 7 = like t6.
local held = {[2] = K.light_item, [3] = K.heavy_item, [5] = K.baseball, [6] = K.prisoner, [7] = K.drink}
function fx.held_code(kind) return held[kind] end

local function offset(random, spread)
    if spread and spread > 0 then return random(spread * 2 + 1) - spread end
    return 0
end

-- Applied to a freshly spawned object before its integer position is derived.
-- UNCERTAIN choices (see docs/darkfiren/ai3_interactions.md): dvz is added to the key-based z speed,
-- centerx/y/z = +-N uniform, framea = action + 0..N, reserve / attacking / skin_owner are stored only.
function fx.extend(index, parent, value, record, point, random, state)
    local kind = point.kind
    if kind == 1 or kind == 2 then
        if point.hp and point.hp ~= 0 then
            value.hp, value.dark_hp = point.hp, point.hp
            if value.max_hp < point.hp then value.max_hp = point.hp end
        end
        if point.team ~= nil then value.team = point.team end
    end
    if kind == 1 then
        if point.z then value.z = value.z + point.z end -- negative = up the screen, positive = down
        if point.mp and point.mp ~= 0 then value.mp = point.mp end
        if point.dvz then value.vz = value.vz + point.dvz end
        if point.effect and point.effect ~= 0 then value.blink = point.effect end -- invincibility time
    end
    value.x = value.x + offset(random, point.centerx)
    value.y = value.y + offset(random, point.centery)
    value.z = value.z + offset(random, point.centerz)
    if point.framea and point.framea > 0 then value.frame = value.frame + random(point.framea + 1) end
    local extra = value.fx
    if not extra then extra = {} value.fx = extra end -- AI 3 runtime fields live only in value.fx
    if point.reserve ~= nil and (record.kind == K.character or record.kind == K.prisoner) then extra.reserve = point.reserve end
    if point.attacking and point.attacking ~= 0 then extra.attacking = point.attacking end
    if point.pic == 1 then extra.skin_owner = index end -- the drawing code follows the owner's skin offset
    -- Clone (user decision): a character made by an opoint whose record id is the creator's own (or the creator's
    -- owner's). Marked once, here, at creation: fx.clone = true and fx.clone_owner = the creator's slot.
    if record.kind == K.character then
        local owner = state and state.items[parent.owner]
        if record.id == parent.record.id or (owner and record.id == owner.record.id) then
            extra.clone, extra.clone_owner = true, index
        end
    end
end

-- ppoint (docs/txt/readme/frame/ppoint.txt): an object whose current frame has a ppoint stays at (x, y, z) relative to its
-- owner. Called once per tick after the owner has moved. Objects without ppoint, or without a live owner, are untouched.
local fx_constants = require("base/game/fx_constants")
local owner_none = 99 -- item.create default owner
function fx.follow(state, index, value)
    local point = value.record.frame(value.frame).ppoint
    if not point or point.kind ~= 1 then return end
    local owner = value.owner
    if owner == owner_none or owner == index then return end
    local parent = state.items[owner]
    if not parent then return end
    local dx = point.x or 0
    local left = parent.facing == constants.facings.left
    if left and fx_constants.ppoint_mirror_x then dx = -dx end
    value.x_int = parent.x_int + dx
    value.y_int = parent.y_int + (point.y or 0)
    value.z_int = parent.z_int + (point.z or 0)
    value.x, value.y, value.z = value.x_int, value.y_int, value.z_int
    if fx_constants.ppoint_copy_facing then value.facing = parent.facing end
end

function fx.follow_all(state)
    for index = 0, constants.item_slots - 1 do
        local value = state.items[index]
        if value and value.record.kind ~= K.character then fx.follow(state, index, value) end
    end
end

-- cpoint extras (docs/txt/readme/frame/cpoint.txt). All keys are nil unless the data wrote them, so original cpoints
-- behave exactly as before. A holder pressing a key during a hold jumps to the named frame (not based on mp).
-- UNCERTAIN: "forward"/"backward" are taken relative to the holder's facing; a key counts when its press counter is > 0
-- (same rule as aaction/jaction in grab.lua); order when several fire in one tick: d, forward, backward, up, down.
function fx.cpoint_action(holder, hit)
    local keys = holder.keys
    local right = holder.facing ~= constants.facings.left
    local forward, backward = right and "right" or "left", right and "left" or "right"
    local function pressed(key) return keys[key] and (holder[key .. "_press"] or 0) > 0 end
    local function pick(action, key)
        if action and action ~= 0 and pressed(key) then return action end
    end
    return pick(hit.daction, "defend") or pick(hit.faction, forward) or pick(hit.baction, backward)
        or pick(hit.uzaction, "up") or pick(hit.dzaction, "down")
end

-- cpoint z: the victim's depth is the holder's z plus z (negative = up the screen); the cover shift is then skipped.
function fx.cpoint_z(hit) return hit.z end

-- cpoint drain / gain / recover work like the itr keys; reuse the itr code (heal gain 17xxx included).
function fx.cpoint_hit(holder, target, hit)
    if (hit.drain and hit.drain ~= 0) or (hit.gain and hit.gain ~= 0) or (hit.recover and hit.recover ~= 0) then
        require("base/game/fx_itr").after_hit(holder, target, {drain = hit.drain, gain = hit.gain, recover = hit.recover, kind = 0}, false)
    end
end

-- itr bounce (docs/txt/readme/frame/itr.txt "bounce in itr"): an itr with dx / dy / dz (and pickingact / pickedact) makes a
-- character victim, when it hits the ground after the hit, gain x / y / z velocity (dx mirrored by the attacker's facing)
-- and be forced into a frame: pickingact when the attacker faced right, pickedact when it faced left (the same sides as a
-- catching itr). [BELUM PASTI]: which frame belongs to which side, the sign convention of dx and that the frame is
-- forced on the landing tick. State lives in value.fx.bounce (marked on the hit, consumed on the first landing).
function fx.bounce_mark(attacker, victim, itr, defended)
    if defended or victim.record.kind ~= K.character or not victim.fx then return end
    local dx, dy, dz = itr.dx or 0, itr.dy or 0, itr.dz or 0
    local right = attacker.facing ~= constants.facings.left
    local frame = right and itr.pickingact or itr.pickedact
    frame = frame and frame[1] or 0
    if dx == 0 and dy == 0 and dz == 0 and frame == 0 then return end
    victim.fx.bounce = {dx = dx, dy = dy, dz = dz, frame = frame, facing = attacker.facing, air = false, age = 0}
end

function fx.bounce_step(value)
    local mark = value.fx and value.fx.bounce
    if not mark then return end
    local floor = value.floor_y or 0
    mark.age = mark.age + 1
    if value.y_int < floor then
        mark.air = true
    elseif mark.air then -- landed after having been in the air
        local sign = mark.facing == constants.facings.left and -1 or 1
        value.vx, value.vy, value.vz = mark.dx * sign, mark.dy, mark.dz
        if mark.frame ~= 0 then value.frame = mark.frame end
        value.fx.bounce = nil
        return
    end
    if mark.age > fx_constants.bounce_ticks then value.fx.bounce = nil end
end

function fx.bounce_all(state)
    for index = 0, constants.item_slots - 1 do
        local value = state.items[index]
        if value then fx.bounce_step(value) end
    end
end
-- Leaf.F kind 8 caughtact: heals MP over time, like injury heals HP (+8 every 8 ticks); MP may exceed 500 up to heal_mp_limit.
function fx.heal_mp_step(value)
    local fx_state = value.fx
    local ticks = fx_state and fx_state.mp_regen
    if not ticks or ticks <= 0 then return end
    if value.hp <= 0 then fx_state.mp_regen = nil return end
    ticks = ticks - 1
    fx_state.mp_regen = ticks > 0 and ticks or nil
    if ticks % 8 == 0 then value.mp = math.min(value.mp + 8, fx_constants.heal_mp_limit) end
end

function fx.heal_mp_all(state)
    for index = 0, constants.item_slots - 1 do
        local value = state.items[index]
        if value then fx.heal_mp_step(value) end
    end
end

return fx
