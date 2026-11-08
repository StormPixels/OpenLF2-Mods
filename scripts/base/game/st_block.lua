-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren absolute block (itr kind X1, docs/txt/readme/platform.txt; real use: floor.dat frame 350, kinds 31 and 61).
-- Called at the end of physics.step (AI 2). Rules from a reading of the PDK.exe platform routine (0x417ab0, Neora, passed on
-- by the user's acquaintance; read from the code, not run):
-- * Hit when top < y < bottom (top = object y_int + itr.y - frame centery, bottom = top + itr.h; the integer y of the item,
--   now), x_int in (x, x + width) and |object z + itr.z - item z| < zwidth (0 = 15): every edge EXCLUSIVE. The itr's own x
--   comes from the frame's centerx (mirrored when the object faces left). Who: 31 all, 41/71 same team as the object, 51/81
--   other team; 31-51 characters only, 61-81 types 1, 2, 4 and 6 (not 5, not balls). Kind 30 does not use the y range.
-- * The routine compares this tick's position with last tick's, per axis. An axis that was outside the box last tick and is
--   inside now is put back on the edge the item came from; a corner entry corrects two axes. An item that is already inside
--   (inside on every axis last tick too) is left alone.
-- * From below the item is stopped at the box's bottom edge (y); from above nothing is done (standing on top is the plane,
--   kind X0). Velocity is never changed, there is no bounce; fall / vrest are not read.
-- [BELUM PASTI] what runs before or after the routine in the original tick, and the x range's exact edges beyond "exclusive".
local constants = require("base/game/constants")
local st_block = {}

local K = constants.record_kinds
local facing_left = constants.facings.left
local default_zwidth = constants.combat.default_zwidth
local item_slots = constants.item_slots
local object_types = {[K.light_item] = true, [K.heavy_item] = true, [K.baseball] = true, [K.drink] = true}

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
                        centre = centre, window = window, top = top, bottom = top + itr.height}
                end
            end
        end
    end
    match.st_block_list, match.st_block_stamp = list, stamp
    return list
end

-- Put `value` back outside every block it entered this tick. `prev_x`, `prev_z`, `prev_y`: where it was last tick.
function st_block.resolve(match, value, prev_x, prev_z, prev_y)
    if not match.items then return end
    local list = boxes(match)
    for i = 1, #list do
        local box = list[i]
        if box.object ~= value and affects(box.kind, box.object, value) then
            local x, z, y = value.x, value.z, value.y
            local xi = x >= 0 and math.floor(x) or math.ceil(x)
            local zi = z >= 0 and math.floor(z) or math.ceil(z)
            local yi = y >= 0 and math.floor(y) or math.ceil(y)
            local depth = zi - box.centre
            if xi > box.x0 and xi < box.x1 and depth > -box.window and depth < box.window and yi > box.top and yi < box.bottom then
                local out_x = prev_x <= box.x0 or prev_x >= box.x1
                local prev_depth = prev_z - box.centre
                local out_z = prev_depth <= -box.window or prev_depth >= box.window
                if out_x then value.x = prev_x <= box.x0 and box.x0 + 0.0 or box.x1 + 0.0 end
                if out_z then value.z = prev_depth <= -box.window and box.centre - box.window + 0.0 or box.centre + box.window + 0.0 end
                if prev_y ~= nil and prev_y >= box.bottom then value.y = box.bottom + 0.0 end
            end
        end
    end
end

return st_block
