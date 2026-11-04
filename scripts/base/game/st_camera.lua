-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren camera follow (state 99XXX) and earthquake (state 5XXYY). Runtime data is in match.st:
-- camera_follow = {index =, timer =}, camera_z (z of the followed object, for a vertical camera), quake_x, quake_y.
-- The earthquake offsets are only published (match.st.quake_x/quake_y, zero when no frame asks for one); the drawing
-- code applies them to the map.
local st_constants = require("base/game/st_constants")
local st_camera = {}

local function st_of(match)
    local st = match.st
    if not st then
        st = {}
        match.st = st
    end
    return st
end

-- Zero the earthquake before the items run (frames in an earthquake state set it again).
function st_camera.begin_tick(match)
    local st = match.st
    if st and (st.quake_x or st.quake_y) then st.quake_x, st.quake_y = 0, 0 end
end

function st_camera.quake(match, s)
    local cfg = st_constants.quake
    local rest = s - cfg.first
    local st = st_of(match)
    -- Base 50 per axis; 00 means "no movement on that axis" (so the notes' example 55200 shakes only along x).
    local x, y = math.floor(rest / 100), rest % 100
    st.quake_x = x == 0 and 0 or x - cfg.base
    st.quake_y = y == 0 and 0 or y - cfg.base
end

-- An item is in a 99XXX frame: the camera follows it for XXX ticks (0: for as long as it stays in the frame).
function st_camera.follow(match, index, value, s)
    local st = st_of(match)
    local follow = st.camera_follow
    local ticks = s - st_constants.camera.first
    if not follow or follow.index ~= index then
        follow = {index = index, timer = ticks > 0 and ticks or -1}
        st.camera_follow = follow
    end
    follow.in_frame = true
    st.camera_z = value.z_int
end

-- The item left its camera frame.
function st_camera.release(match, index)
    local follow = match.st and match.st.camera_follow
    if follow and follow.index == index and follow.timer == -1 then match.st.camera_follow = nil end
end

-- x the camera should look at instead of the fighters, or nil.
function st_camera.focus(match)
    local st = match.st
    local follow = st and st.camera_follow
    if not follow then return nil end
    local value = match.items[follow.index]
    if not value or (follow.timer == 0) then
        st.camera_follow = nil
        return nil
    end
    if follow.timer > 0 then follow.timer = follow.timer - 1 end
    st.camera_z = value.z_int
    return value.x_int
end
return st_camera
