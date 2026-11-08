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

-- kind 30-39 / 40-49 / 50-59 act on type 0 (characters); 60-69 / 70-79 / 80-89 on types 1, 2, 4, 5, 6.
-- Within a decade: 0-9 = all teams, 4x/7x = allied to the platform's team, 5x/8x = enemy of it.
local object_types = {[K.light_item] = true, [K.heavy_item] = true, [K.baseball] = true, [K.prisoner] = true, [K.drink] = true}

function platform.is_platform_kind(kind) return kind >= 30 and kind <= 89 end

local function affects(itr_kind, platform_item, item)
    local tens = (itr_kind - itr_kind % 10) / 10
    local character = item.record.kind == K.character
    if tens <= 5 then
        if not character then return false end
    elseif not object_types[item.record.kind] then
        return false
    end
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

-- Is the item's centre inside the platform itr (x range and z window)?
local function inside(platform_item, frame, itr, item)
    local x
    if platform_item.facing == facing_left then x = frame.center_x + platform_item.x_int - itr.width - itr.x
    else x = itr.x + platform_item.x_int - frame.center_x end
    if item.x_int < x or item.x_int >= x + itr.width then return false end
    local window = itr.zwidth ~= 0 and itr.zwidth or default_zwidth
    local centre = platform_item.z_int + (itr.z or 0) -- [BELUM PASTI] itr z shifts the window, zwidth is its half width
    local depth = item.z_int - centre
    return depth >= -window and depth <= window
end

-- Height (<= 0, negative = up) of the highest platform plane at or below the item's feet that affects it, or nil.
-- plane = the platform object's y plus the itr's dvy (readme). An item whose feet were already below the plane on
-- the previous tick passes through it (walking under, jumping up through it).
function platform.plane_at(match, value)
    local best
    local previous_feet = value.y - (value.vy or 0)
    for index = 0, item_slots - 1 do
        local object = match.items[index]
        if object and object ~= value and record_has_platform(object.record) then
            local frame = object.record.frame(object.frame)
            for _, itr in ipairs(frame.interactions or {}) do
                local kind = itr.kind
                if platform.is_platform_kind(kind) and config.supported_subtypes[kind % 10]
                   and affects(kind, object, value) and inside(object, frame, itr, value) then
                    local plane = object.y_int + (itr.dvy or 0)
                    if plane <= 0 and previous_feet <= plane + config.land_tolerance and (best == nil or plane < best) then
                        best = plane
                    end
                end
            end
        end
    end
    return best
end
return platform
