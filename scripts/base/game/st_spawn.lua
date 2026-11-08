-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren: what a player fighter (a human or a computer picked at the menu) takes from its own data and from the
-- background mode when it is put into the round. Called by match.create. Every part is nil-safe: with no tag the fighter
-- is exactly the one the old code made.
--   skin:        options.slots[slot].skin (1..10) -> record.data.skins[skin].offset as value.pic_offset; a random one when
--                skins.random == 1 and no skin was chosen
--   start_frame: <header> start_frame of the character first, then the mode's start_frame
--   reserve:     <stats> reserve of the character first, then the mode's reserve -> value.lives (a fighter with lives
--                of 2 or more gets up again, see animation.lua / frame_rules.lua)
--   dx, dvx, dz, dvz: the mode's start position: dvx/dvz make it random within 0..dvx (or dvz), dx/dz add an offset
--                (dvx and dx are not used in battle mode, where the side fixes x). [UNCERTAIN] battle mode and dx.
local st_stats = require("base/game/st_stats")
local st_spawn = {}

local function whole(n) return n ~= nil and n == math.floor(n) end

function st_spawn.skin(value, record, chosen)
    local skins = record.data and record.data.skins
    if not skins then return end
    local index = chosen
    if not index and skins.random == 1 then
        local count = 0
        for i = 1, 10 do if skins[i] then count = i end end
        if count > 0 then index = engine.random(count) + 1 end
    end
    local skin = index and skins[index]
    if skin and whole(skin.offset) then value.pic_offset = skin.offset end
end

function st_spawn.start_frame(value, record, area)
    local header = record.data and record.data.header
    local frame = (header and header.start_frame) or (area and area.start_frame)
    if frame and record.frames[frame] then
        value.frame, value.previous_frame = frame, frame
        -- A new item starts with vy 0.1; on the ground physics counts that as a landing and replaces the frame with the
        -- landing frame (219) on the first tick, so the start frame would never be seen.
        if value.y_int >= 0 then value.vy = 0.0 end
    end
end

function st_spawn.reserve(value, area)
    local reserve = st_stats.reserve(value) or (area and area.reserve)
    if reserve and reserve >= 0 then
        value.lives = reserve
        value.st = value.st or {}
        value.st.reserve = true
    end
end

-- width: the background's width, near/far: its z limits, battle: true in battle mode.
function st_spawn.position(value, area, width, near, far, battle)
    if not area then return end
    if not battle then
        if area.dvx and area.dvx > 0 and area.dvx <= width then
            value.x_int = engine.random(area.dvx) + (area.dx or 0)
        elseif area.dx then
            value.x_int = value.x_int + area.dx
        end
    end
    if area.dvz and area.dvz > 0 and area.dvz <= far - near then
        value.z_int = engine.random(area.dvz) + near + (area.dz or 0)
    elseif area.dz then
        value.z_int = value.z_int + area.dz
    end
    value.x, value.z = value.x_int + 0.0, value.z_int + 0.0
end

-- The whole step, after the fighter's team, position and mp are set.
function st_spawn.player(value, record, entry, area, width, near, far, battle)
    st_spawn.skin(value, record, entry.skin)
    st_spawn.position(value, area, width, near, far, battle)
    st_spawn.start_frame(value, record, area)
    st_spawn.reserve(value, area)
end
return st_spawn
