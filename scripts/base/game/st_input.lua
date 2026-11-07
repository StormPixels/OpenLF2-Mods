-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren input tags of a frame: hold_a/d/j/f/b/uz/dz and hit_f/b/uz/dz (frame.hold, frame.hit_ext tables of
-- CONTRACT_DATA). A frame without these tables behaves exactly as before.
local st_constants = require("base/game/st_constants")
local constants = require("base/game/constants")
local facing_right = constants.facings.right
local st_input = {}

local function ensure(value)
    local st = value.st
    if not st then
        st = {}
        value.st = st
    end
    return st
end

-- Press counters of the forward/backward direction for the fighter's facing.
local function directional_press(value, forward)
    local right = value.facing == facing_right
    if forward == right then return "right_press" end
    return "left_press"
end

local physical_keys = {"up", "down", "left", "right", "attack", "jump", "defend"}

-- Ticks each physical key has been held down without a break (human fighters only). The readme counts the hold from
-- the key, not from the frame ("it ignores the holding time" when used in the first frame), so it survives frame changes.
local function track_keys(value)
    local st = ensure(value)
    local counts = st.key_n
    if not counts then
        counts = {}
        st.key_n = counts
    end
    for _, key in ipairs(physical_keys) do
        counts[key] = value.keys[key] and ((counts[key] or 0) + 1) or 0
    end
    return counts
end

-- Which physical key a hold tag watches (forward/backward depend on the facing), or nil.
local function hold_key(value, name)
    if name == "a" then return "attack" end
    if name == "d" then return "defend" end
    if name == "j" then return "jump" end
    if name == "uz" then return "up" end
    if name == "dz" then return "down" end
    local right = value.facing == facing_right
    if name == "f" then return right and "right" or "left" end
    return right and "left" or "right"
end

local press_of = {uz = "up_press", dz = "down_press"}

-- hit_Faj/Uaj/Daj read as the J-key sequences' fallback (see st_constants.alias_aj).
local alias_field = {Fj = "Faj", Uj = "Uaj", Dj = "Daj"}
-- The pdk control (a background mode's dicontrol = 1) renames them hit_aj, hit_jj, hit_aa (feature list 16.3).
local pdk_field = {Fj = "aj", Uj = "jj", Dj = "aa"}
function st_input.alias_target(frame, field, match)
    if not st_constants.alias_aj then return 0 end
    local ext = frame.hit_ext
    local name = alias_field[field]
    if not ext or not name then return 0 end
    local area = match and match.bg_area
    if area and area.dicontrol == 1 then return ext[pdk_field[field]] or ext[name] or 0 end
    return ext[name] or 0
end

-- Called once per tick after the hit_a/d/j check. `enter` is control.enter_frame; `moved` tells that the fighter already
-- left its frame this tick (then nothing else is read).
function st_input.step(match, value, enter, moved)
    local counts = value.human and track_keys(value) or nil
    local frame = value.record.frame(value.frame)
    local ext, hold = frame.hit_ext, frame.hold
    if not ext and not hold then return end
    if not moved and ext then
        local order = {"f", "b", "uz", "dz"}
        for _, name in ipairs(order) do
            local target = ext[name]
            if target and target ~= 0 then
                local field = press_of[name]
                if not field then field = directional_press(value, name == "f") end
                if value[field] > 0 then
                    enter(match, value, target)
                    value[field] = 0
                    moved = true
                    break
                end
            end
        end
    end
    -- hold_*: the key must have been down for st_constants.hold_ticks ticks. Computer fighters never hold.
    if not hold or not counts or moved then return end
    for _, name in ipairs({"a", "d", "j", "f", "b", "uz", "dz"}) do
        local target = hold[name]
        if target and target ~= 0 then
            local key = hold_key(value, name)
            local opposite = (name == "uz" and "down") or (name == "dz" and "up") or nil
            if counts[key] >= st_constants.hold_ticks and not (opposite and counts[opposite] > 0) then
                counts[key] = 0
                enter(match, value, target)
                return
            end
        end
    end
end
return st_input
