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
return fx
