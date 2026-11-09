-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren platform kinds X1-X5 (itr kind 31-35, 41-45, 51-55, 61-65, 71-75, 81-85; docs/txt/readme/platform.txt; real use:
-- floor.dat frame 350, kinds 31 and 61). Called at the end of physics.step (AI 2). The rules are read from the PDK.exe platform
-- routine (wrapper 0x417a30, routine 0x417ab0, branches per unit digit; Neora; passed on by the user's acquaintance, read from
-- the code, not run). Kind X0 (the plane) is platform.lua's; X6-X9 do nothing.
-- * Gate (every unit): item centre x_int in (x, x + width), |object z + itr.z - item z| < zwidth (0 = 15), and for X1-X5 also
--   top < y < bottom (top = object y_int + itr.y - frame centery, bottom = top + itr.h; the integer y of the item), every edge
--   EXCLUSIVE. The itr's x comes from the frame's centerx (mirrored when the object faces left). Who: 3x all, 4x same team as
--   the object, 5x other team (6x-8x as 3x-5x); 3x-5x characters only (balls ignore X1-X5), 6x-8x types 1, 2, 4, 5 and 6 (type 5: Darkfiren added it on purpose, the PDK.exe code has none).
-- * X1 absolute block: per axis, an axis that was outside the box last tick and is inside now is put back on the edge the item
--   came from (corner entry: two axes); an item already inside is left alone; from below y goes back to the bottom edge, from
--   above nothing. No velocity change, no bounce.
-- * X2 constant speed: every tick inside the box x += dvx, z += dvy (pixels per tick); the velocity is not touched.
-- * X3 acceleration: every tick inside vx += dvx, vz += dvy, and the position moves by the same (x += dvx, z += dvy).
-- * X4 resistance: every tick inside vx = vx * dvx / 1000, vz = vz * dvy / 1000, the position moves by the velocity change.
-- * X5 bounce: when inside and last tick's y was outside the vertical range (above the top or at/below the bottom): vx += dvx,
--   vy += dvy (negative = up); a held victim is let go (grab.release_victim). The platform's facing and the item's facing are not used.
-- The velocity fields (vx, vy, vz) are the engine's own; the routine's are read as +0x40/+0x48/+0x50 [DUGAAN, consistent with the
-- readme]. [BELUM PASTI] what runs before or after the routine in the original tick: it runs after all objects have moved
-- (pair phase 0x419380); here it runs at the end of each item's own physics.step.
local constants = require("base/game/constants")
local st_block = {}

local K = constants.record_kinds
local facing_left = constants.facings.left
local default_zwidth = constants.combat.default_zwidth
local item_slots = constants.item_slots
local object_types = {[K.light_item] = true, [K.heavy_item] = true, [K.baseball] = true, [K.prisoner] = true, [K.drink] = true}

local function is_block_kind(kind) local unit = kind % 10 return kind >= 30 and kind <= 89 and unit <= 5 end

local function affects(itr_kind, block_item, item)
    local tens = (itr_kind - itr_kind % 10) / 10
    local character = item.record.kind == K.character
    if tens <= 5 then
        if not character then return false end
    elseif not object_types[item.record.kind] then
        return false
    end
    local group = tens <= 5 and tens or tens - 3
    if group == 3 then return true end
    local same = item.team == block_item.team
    if group == 4 then return same end
    return not same
end

local has_block = {}
local function record_has_block(record)
    local data = record.data
    if not data then return false end
    local cached = has_block[data]
    if cached ~= nil then return cached end
    local found = false
    for _, frame in pairs(data.frames or {}) do
        for _, itr in ipairs(frame.interactions or {}) do
            if is_block_kind(itr.kind) then found = true break end
        end
        if found then break end
    end
    has_block[data] = found
    return found
end

-- The boxes of this tick, cached on the match by frame_number (rebuilt on every call when the match has none).
local function boxes(match)
    local stamp = match.frame_number
    if stamp ~= nil and match.st_block_stamp == stamp then return match.st_block_list end
    local list = {}
    for index = 0, item_slots - 1 do
        local object = match.items[index]
        if object and record_has_block(object.record) then
            local frame = object.record.frame(object.frame)
            for _, itr in ipairs(frame.interactions or {}) do
                if is_block_kind(itr.kind) then
                    local x
                    if object.facing == facing_left then x = frame.center_x + object.x_int - itr.width - itr.x
                    else x = itr.x + object.x_int - frame.center_x end
                    local window = itr.zwidth ~= 0 and itr.zwidth or default_zwidth
                    local centre = object.z_int + (itr.z or 0)
                    local top = object.y_int + itr.y - frame.center_y
                    list[#list + 1] = {object = object, index = index, kind = itr.kind, unit = itr.kind % 10, dvx = itr.dvx or 0, dvy = itr.dvy or 0, x0 = x, x1 = x + itr.width,
                        centre = centre, window = window, top = top, bottom = top + itr.height}
                end
            end
        end
    end
    match.st_block_list, match.st_block_stamp = list, stamp
    return list
end

-- X5 on a victim that is being held (a grab): the PDK routine clears the held state (field +0x98 == 2) and ends the hold. AI 3's
-- grab.release_victim(state, victim_index) does that (false when the item is not held, nothing changes); the slot is found by a
-- scan, which only runs when an X5 bounce happens. Without grab.lua or the function nothing is done.
local function release_hold(match, value)
    local ok, grab_module = pcall(require, "base/game/grab")
    if not ok or type(grab_module) ~= "table" or not grab_module.release_victim then return end
    for index = 0, item_slots - 1 do
        if match.items[index] == value then grab_module.release_victim(match, index) return end
    end
end

-- Apply every platform box to `value`. `prev_x`, `prev_z`, `prev_y`: where it was last tick (integers).
function st_block.resolve(match, value, prev_x, prev_z, prev_y)
    if not match.items then return end
    local list = boxes(match)
    for i = 1, #list do
        local box = list[i]
        if box.unit ~= 0 and box.object ~= value and affects(box.kind, box.object, value) then
            local x, z, y = value.x, value.z, value.y
            local xi = x >= 0 and math.floor(x) or math.ceil(x)
            local zi = z >= 0 and math.floor(z) or math.ceil(z)
            local yi = y >= 0 and math.floor(y) or math.ceil(y)
            local depth = zi - box.centre
            if xi > box.x0 and xi < box.x1 and depth > -box.window and depth < box.window and yi > box.top and yi < box.bottom then
                local unit = box.unit
                if unit == 1 then
                    local out_x = prev_x <= box.x0 or prev_x >= box.x1
                    local prev_depth = prev_z - box.centre
                    local out_z = prev_depth <= -box.window or prev_depth >= box.window
                    if out_x then value.x = prev_x <= box.x0 and box.x0 + 0.0 or box.x1 + 0.0 end
                    if out_z then value.z = prev_depth <= -box.window and box.centre - box.window + 0.0 or box.centre + box.window + 0.0 end
                    if prev_y ~= nil and prev_y >= box.bottom then value.y = box.bottom + 0.0 end
                elseif unit == 2 then
                    value.x = value.x + box.dvx
                    value.z = value.z + box.dvy
                elseif unit == 3 then
                    value.vx = (value.vx or 0.0) + box.dvx
                    value.vz = (value.vz or 0.0) + box.dvy
                    value.x = value.x + box.dvx
                    value.z = value.z + box.dvy
                elseif unit == 4 then
                    local old_x, old_z = value.vx or 0.0, value.vz or 0.0
                    value.vx = old_x * box.dvx / 1000.0
                    value.vz = old_z * box.dvy / 1000.0
                    value.x = value.x + value.vx - old_x
                    value.z = value.z + value.vz - old_z
                elseif unit == 5 then
                    if prev_y ~= nil and (prev_y < box.top or prev_y >= box.bottom) then
                        value.vx = (value.vx or 0.0) + box.dvx
                        value.vy = (value.vy or 0.0) + box.dvy
                        release_hold(match, value)
                    end
                end
            end
        end
    end
end

local function round(v) return v >= 0 and math.floor(v + 0.5) or -math.floor(-v + 0.5) end

-- The platform object whose plane (kind X0) `value` stands on: same x / z gate as platform.lua (left edge inclusive), the plane
-- being the object's y_int + the itr's dvy (rounded), read now. Returns the object and its slot, or nil.
function st_block.owner(match, value, plane)
    if not match.items then return nil end
    local list = boxes(match)
    local xi = value.x_int
    local zi = value.z_int
    for i = 1, #list do
        local box = list[i]
        if box.unit == 0 and box.object ~= value and box.object.y_int + round(box.dvy) == plane and affects(box.kind, box.object, value) then
            local depth = zi - box.centre
            if xi >= box.x0 and xi < box.x1 and depth >= -box.window and depth <= box.window then return box.object, box.index end
        end
    end
    return nil
end

-- An item standing on a platform plane is carried by the platform's FRAME dvx / dvy / dvz every tick (PDK 0x413daa-0x413e7e):
-- 0 = nothing; > 500 = value - 550; else the value (dvx negated when the platform faces left). x and z move by it; dvy moves y and
-- the plane the item stands on. Called at the start of physics.step with the plane found last tick (`value.floor_object`).
function st_block.carry(match, value)
    local object = value.floor_object
    if not object or value.floor_y == nil or value.y ~= value.floor_y + 0.0 or match.items[value.floor_index] ~= object then
        value.floor_object, value.floor_index = nil, nil
        return
    end
    local frame = object.record.frame(object.frame)
    local dvx, dvz, dvy = frame.dvx or 0, frame.dvz or 0, frame.dvy or 0
    if dvx ~= 0 then
        local dx = dvx > 500 and dvx - 550 or (object.facing == facing_left and -dvx or dvx)
        value.x = value.x + dx
    end
    if dvz ~= 0 then value.z = value.z + (dvz > 500 and dvz - 550 or dvz) end
    if dvy ~= 0 then
        local ny = round(value.y + (dvy > 500 and dvy - 550 or dvy))
        value.y, value.floor_y = ny + 0.0, ny
    end
end

return st_block
