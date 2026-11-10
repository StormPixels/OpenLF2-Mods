-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren platforms (docs/txt/readme/platform.txt): itr kind 30-89 on an object (e.g. floor.dat, id 333) make a
-- landing plane for characters and other objects. physics.lua (AI 2) asks `platform.plane_at` for the plane under an
-- item and uses it instead of the ground (y = 0). Stage 1 supports only kind X0 (the landing plane); X1 absolute block,
-- X2/X3 moving platforms, X4 resistance and X5 bounce are ignored until they are specified.
local constants = require("base/game/constants")
local fx_constants = require("base/game/fx_constants")
local platform = {}

local K = constants.record_kinds
local facing_left = constants.facings.left
local default_zwidth = constants.combat.default_zwidth
local item_slots = constants.item_slots
local config = fx_constants.platform

-- Who is affected: kind 30-59 act on types 0 and 3 (characters and energy balls), kind 60-89 on types 1, 2, 4, 5 and 6 (PDK.exe
-- has no type 5 there; the Darkfiren developer added it on purpose, and the readme lists it, so the readme wins). Within a
-- decade: 3x / 6x = all teams, 4x / 7x = the platform's team, 5x / 8x = any other team.
local lower_types = {[K.character] = true, [K.ball] = true}
local upper_types = {[K.light_item] = true, [K.heavy_item] = true, [K.baseball] = true, [K.prisoner] = true, [K.drink] = true}

function platform.is_platform_kind(kind) return kind >= 30 and kind <= 89 end

local function affects(itr_kind, platform_item, item)
    local tens = (itr_kind - itr_kind % 10) / 10
    if not (tens <= 5 and lower_types or upper_types)[item.record.kind] then return false end
    local group = tens <= 5 and tens or tens - 3 -- 3 all, 4 allied, 5 enemy
    if group == 3 then return true end
    local same = item.team == platform_item.team
    if group == 4 then return same end
    return not same
end

-- Records with no platform itr in any frame are skipped quickly: the answer is cached per parsed data table.
local has_platform = {} -- no weak table: setmetatable is not available in the game's Lua
local function record_has_platform(record)
    local data = record.data
    if not data then return false end
    local cached = has_platform[data]
    if cached ~= nil then return cached end
    local found = false
    local frames = data and data.frames
    if frames then
        for _, frame in pairs(frames) do
            for _, itr in ipairs(frame.interactions or {}) do
                if platform.is_platform_kind(itr.kind) then found = true break end
            end
            if found then break end
        end
    end
    has_platform[data] = found
    return found
end

-- The itr's x range and z window in world coordinates: x_int in (left, right) and |z_int - z_centre| < z_window, all bounds
-- exclusive (PDK, [KODE]). [BELUM PASTI] the x range is mirrored when the platform faces left (the PDK notes do not say).
function platform.itr_box(platform_item, frame, itr)
    local left
    if platform_item.facing == facing_left then left = frame.center_x + platform_item.x_int - itr.width - itr.x
    else left = itr.x + platform_item.x_int - frame.center_x end
    local window = itr.zwidth ~= 0 and itr.zwidth or default_zwidth
    return left, left + itr.width, platform_item.z_int + (itr.z or 0), window
end

-- Is the item's centre inside the platform itr (x range and z window)?
function platform.inside(platform_item, frame, itr, item)
    local left, right, centre, window = platform.itr_box(platform_item, frame, itr)
    if item.x_int <= left or item.x_int >= right then return false end
    local depth = item.z_int - centre
    return depth > -window and depth < window
end
platform.affects = affects

-- Height (<= 0, negative = up) of the highest platform plane at or below the item's feet that affects it, or nil.
-- plane = the platform object's y plus the itr's dvy, rounded (readme / PDK). An item whose feet are below the plane both
-- now and a tick ago passes through it (walking under, jumping up); once its feet are above the plane it is held by it. `current` (optional) is the plane the item
-- stood on last tick (value.floor_y): a plane that is at most `rise_limit` above it still holds the item (a safety net for a
-- platform that rises without a frame dvy; AI2's st_block.carry normally moves such items).
function platform.plane_at(match, value, current)
    if not match or not match.items then return nil end
    local best
    local previous_feet = value.y - (value.vy or 0)
    for index = 0, item_slots - 1 do
        local object = match.items[index]
        if object and object ~= value and record_has_platform(object.record) then
            local frame = object.record.frame(object.frame)
            for _, itr in ipairs(frame.interactions or {}) do
                local kind = itr.kind
                if platform.is_platform_kind(kind) and config.supported_subtypes[kind % 10]
                   and affects(kind, object, value) and platform.inside(object, frame, itr, value) then
                    local plane = math.floor(object.y_int + (itr.dvy or 0) + 0.5) -- rounded to the nearest (PDK)
                    local slack = config.land_tolerance
                    if current and plane <= current and current - plane <= config.rise_limit then slack = config.rise_limit end
                    -- recorded when the feet were above the plane a tick ago or are above it now (PDK: plane >= y)
                    local above = value.y <= plane + slack or previous_feet <= plane + slack
                    if plane <= 0 and above and (best == nil or plane < best) then
                        best = plane
                    end
                end
            end
        end
    end
    return best
end
-- State 3007 (a ball that interacts with platforms, PDK rule relayed by AI2): when the feet of an energy ball in a 3007 frame
-- reach the plane stored in value.floor_y by physics.lua, the ball is put on the plane (y := plane), stopped (velocity 0) and
-- sent to its hit_g frame. It must run AFTER physics.step of the same item in the same tick (floor_y only exists on the tick
-- the ball crosses the plane); AI2 calls it from match.lua. Safe for any item: other kinds / states / no floor_y return false.
-- [BELUM PASTI]: without a hit_g frame the ball is still stopped on the plane; it is not moved again while it already is in
-- its hit_g frame. Returns true when the ball was put on a plane.
function platform.land_ball(value)
    local plane = value.floor_y
    if plane == nil or value.record.kind ~= K.ball or value.y < plane then return false end
    local frame = value.record.frame(value.frame)
    if frame.state ~= config.ball_state then return false end
    value.y, value.y_int = plane + 0.0, plane
    value.vx, value.vy, value.vz = 0.0, 0.0, 0.0
    local ext = frame.hit_ext
    local target = ext and ext.g
    if target and target ~= 0 and target ~= value.frame and value.record.frames[target] then
        value.frame, value.wait_counter = target, 0
    end
    return true
end
return platform
