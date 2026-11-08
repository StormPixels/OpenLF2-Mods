-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren absolute block (itr kind X1, docs/txt/readme/platform.txt; real use: floor.dat frame 350, kinds 31 and 61).
-- An item whose centre would be inside the block's box is pushed back out. Called at the end of physics.step (AI 2).
--
-- The box: x range and z window exactly as platform.lua reads them (x = itr.x - centerx from the object, mirrored when it
-- faces left; z = object z + itr.z +- zwidth, 0 = the default); the vertical range is the itr's y .. y + height, taken from
-- the frame's centery, i.e. y_top = object.y_int + itr.y - centery. With floor.dat that is the body under the platform
-- plane (plane + 2 .. plane + 46), so an item standing on top of the plane is outside it and one on the ground is not.
-- Who is blocked follows the kind: 31 all type 0, 41 allied, 51 enemy; 61 / 71 / 81 the same for types 1, 2, 4, 5, 6.
--
-- [BELUM PASTI] (readme gives no rules): which way the item is pushed (here: back to the side it came from, or the nearest
-- edge when it was already inside), that only the velocity component into the block is cancelled, and that the vertical
-- range is measured against the item's feet (value.y).
local constants = require("base/game/constants")
local st_block = {}

local K = constants.record_kinds
local facing_left = constants.facings.left
local default_zwidth = constants.combat.default_zwidth
local item_slots = constants.item_slots
local object_types = {[K.light_item] = true, [K.heavy_item] = true, [K.baseball] = true, [K.prisoner] = true, [K.drink] = true}

local function is_block_kind(kind) return kind >= 30 and kind <= 89 and kind % 10 == 1 end

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
                    list[#list + 1] = {object = object, kind = itr.kind, x0 = x, x1 = x + itr.width,
                        z0 = centre - window, z1 = centre + window, top = top, bottom = top + itr.height}
                end
            end
        end
    end
    match.st_block_list, match.st_block_stamp = list, stamp
    return list
end

-- Push `value` out of every block that holds its centre. `prev_x`, `prev_z`: where it was last tick.
function st_block.resolve(match, value, prev_x, prev_z)
    if not match.items then return end
    local list = boxes(match)
    for i = 1, #list do
        local box = list[i]
        if box.object ~= value and affects(box.kind, box.object, value) then
            local x, z, y = value.x, value.z, value.y
            local xi = x >= 0 and math.floor(x) or math.ceil(x)
            local zi = z >= 0 and math.floor(z) or math.ceil(z)
            if xi >= box.x0 and xi < box.x1 and zi >= box.z0 and zi <= box.z1 and y >= box.top and y <= box.bottom then
                local was_in_x = prev_x >= box.x0 and prev_x < box.x1
                local was_in_z = prev_z >= box.z0 and prev_z <= box.z1
                local axis, side
                if not was_in_x and was_in_z then
                    axis, side = "x", prev_x < box.x0 and -1 or 1
                elseif was_in_x and not was_in_z then
                    axis, side = "z", prev_z < box.z0 and -1 or 1
                else
                    -- came in at a corner, or was already inside: the nearest edge
                    local left, right, near, far = xi - box.x0 + 1, box.x1 - xi, zi - box.z0 + 1, box.z1 - zi + 1
                    local least = math.min(left, right, near, far)
                    if least == left then axis, side = "x", -1
                    elseif least == right then axis, side = "x", 1
                    elseif least == near then axis, side = "z", -1
                    else axis, side = "z", 1 end
                end
                if axis == "x" then
                    value.x = side < 0 and box.x0 - 1.0 or box.x1 + 0.0
                    if (side < 0 and value.vx > 0) or (side > 0 and value.vx < 0) then value.vx = 0.0 end
                else
                    value.z = side < 0 and box.z0 - 1.0 or box.z1 + 1.0
                    if (side < 0 and (value.vz or 0) > 0) or (side > 0 and (value.vz or 0) < 0) then value.vz = 0.0 end
                end
            end
        end
    end
end

return st_block
