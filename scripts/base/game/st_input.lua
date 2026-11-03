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

local function key_down(value, name)
    local keys = value.keys
    if name == "a" then return keys.attack end
    if name == "d" then return keys.defend end
    if name == "j" then return keys.jump end
    if name == "uz" then return keys.up and not keys.down end
    if name == "dz" then return keys.down and not keys.up end
    local right = value.facing == facing_right
    if name == "f" then
        if right then return keys.right and not keys.left end
        return keys.left and not keys.right
    end
    if name == "b" then
        if right then return keys.left and not keys.right end
        return keys.right and not keys.left
    end
    return false
end

local press_of = {uz = "up_press", dz = "down_press"}

-- hit_Faj/Uaj/Daj read as the J-key sequences' fallback (see st_constants.alias_aj).
local alias_field = {Fj = "Faj", Uj = "Uaj", Dj = "Daj"}
function st_input.alias_target(frame, field)
    if not st_constants.alias_aj then return 0 end
    local ext = frame.hit_ext
    local name = alias_field[field]
    if not ext or not name then return 0 end
    return ext[name] or 0
end

-- Called once per tick after the hit_a/d/j check. `enter` is control.enter_frame; `moved` tells that the fighter already
-- left its frame this tick (then nothing else is read).
function st_input.step(match, value, enter, moved)
    local frame = value.record.frame(value.frame)
    local ext, hold = frame.hit_ext, frame.hold
    if not ext and not hold then
        if value.st and value.st.hold_n then value.st.hold_n = nil end
        return
    end
    local st = ensure(value)
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
    -- hold_*: the key must stay down for st_constants.hold_ticks ticks inside this very frame. Computer fighters never hold.
    if not hold or not value.human then
        st.hold_n, st.hold_frame = nil, nil
        return
    end
    if st.hold_frame ~= value.frame then st.hold_frame, st.hold_n = value.frame, {} end
    local counts = st.hold_n
    for _, name in ipairs({"a", "d", "j", "f", "b", "uz", "dz"}) do
        local target = hold[name]
        if target and target ~= 0 then
            if key_down(value, name) then counts[name] = (counts[name] or 0) + 1 else counts[name] = 0 end
            if not moved and counts[name] >= st_constants.hold_ticks then
                enter(match, value, target)
                st.hold_frame, st.hold_n = nil, nil
                moved = true
            end
        end
    end
end
return st_input
