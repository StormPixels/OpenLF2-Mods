-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren hit_Fa values on attack objects: 24/25 fire or ice chase balls only, 26 Firen's blast with ground fire,
-- 5xxx healing angels (object xxx), 6xxx flying demons (object xxx), 8xxx three bats (object xxx).
-- The older values (1-12) stay in objects.update. update() returns true when it handled the object.
-- Objects are made with objects.create (owner of objects.lua is not touched).
local st_constants = require("base/game/st_constants")
local constants = require("base/game/constants")
local objects = require("base/game/objects")
local FA = st_constants.fa
local ids = constants.object_ids
local st_fa = {}

local function cdiv(a, b)
    local q = a / b
    if q >= 0 then return math.floor(q) end
    return math.ceil(q)
end
local function random(range) return engine.random(range) end

local function make(state, me, id)
    local slot = objects.create(state, id, me.owner, 0, me.team, me.x_int, me.y_int, me.z_int, 0.0, 0.0, 0.0, me.facing)
    if slot == -1 then return nil end
    return state.items[slot], slot
end

local function living(state, me, want_enemy)
    local list = {}
    for index = 0, constants.item_slots - 1 do
        local value = state.items[index]
        if value and value.record.kind == constants.record_kinds.character and value.hp > 0
           and ((value.team ~= me.team) == want_enemy) then list[#list + 1] = index end
    end
    return list
end

local function chase_balls(state, me, id_for)
    local enemies = living(state, me, true)
    local spawned, minimum, maximum = 0, FA.chase_min, FA.chase_max
    local pass, full = 0, false
    repeat
        for _, other in ipairs(enemies) do
            if spawned < minimum or pass == 0 then
                local value = make(state, me, id_for())
                if not value then full = true break end
                spawned = spawned + 1
                value.vx = random(21) - 11
                value.vy = -2.0 - random(40) / 6.0
                value.vz, value.facing = 0.0, constants.facings.right
                value.chase_target = other
            end
            if spawned >= maximum then break end
        end
        pass = pass + 1
    until full or #enemies == 0 or spawned >= maximum or spawned >= minimum
end

-- 26: both the blast and the six ground fires are made on the ground, whatever the height of the object. Firen's own
-- explosion frame (289: centery 79, opoint y 81, oid 211, action 109) puts the blast 2 below its ground line, and the
-- older explosion mode puts the ground fires at y -1; neither takes the object's vertical speed.
local blast_y = 2
local function ground_fire(state, me)
    local fire = ids.firen_flame
    local c = objects.create
    c(state, fire, me.owner, 109, me.team, me.x_int, blast_y, me.z_int, me.vx, 0.0, me.vz, me.facing)
    local spots = {{-30, -5, 1}, {30, -5, 1}, {-30, 2, 0}, {30, 2, 0}, {0, -9, 1}, {0, 6, 0}}
    for _, s in ipairs(spots) do
        c(state, fire, me.owner, 50, me.team, me.x_int + s[1], -1, me.z_int + s[2], me.vx, 0.0, me.vz, s[3])
    end
end

function st_fa.update(state, index)
    local me = state.items[index]
    local mode = me.record.frame(me.frame).hits.Fa
    if mode == FA.fire_chase or mode == FA.ice_chase then
        chase_balls(state, me, function() return mode == FA.fire_chase and ids.firzen_chase_fire or ids.firzen_chase_ice end)
    elseif mode == FA.firen_explosion then
        ground_fire(state, me)
    elseif mode >= FA.angel_first and mode < FA.angel_first + FA.range then
        for _, other in ipairs(living(state, me, false)) do
            local value = make(state, me, mode - FA.angel_first)
            if value then
                value.vx = cdiv(state.items[other].x_int - value.x_int, 50)
                value.vy, value.vz, value.facing = 0.0, 0.0, constants.facings.right
                value.chase_target = other
            end
        end
    elseif mode >= FA.demon_first and mode < FA.demon_first + FA.range then
        local spawned = 0
        for _, other in ipairs(living(state, me, true)) do
            if spawned >= FA.demon_max then break end
            local value = make(state, me, mode - FA.demon_first)
            if not value then break end
            spawned = spawned + 1
            value.vx = cdiv(state.items[other].x_int - value.x_int, 50)
            value.vy = -4 - random(4)
            value.vz, value.facing = 0.0, constants.facings.right
            value.chase_target = other
        end
    elseif mode >= FA.bat_first and mode < FA.bat_first + FA.range then
        local list = living(state, me, true)
        local amount = 3
        if #list > 4 then amount = cdiv(#list - 3, 2) + 3 end
        for _ = 1, amount do
            local value = make(state, me, mode - FA.bat_first)
            if not value then break end
            value.vx = random(21) - 11
            value.vy = 3.0 - random(24) * 0.25
            value.vz = 3.0 - random(24) * 0.25
            value.facing = me.facing
            value.chase_target = #list == 0 and index or list[random(#list) + 1]
        end
    else
        return false
    end
    objects.remove(state, index)
    return true
end
return st_fa
