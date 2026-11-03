-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren bdy semantics (feature list section 5, docs/txt/readme/frame/bdy.txt).
-- Every function is nil-safe: a bdy without the new tags behaves like an original LF2 bdy.
local constants = require("base/game/constants")
local fx = {}

fx.complex_base = 1000000000 -- bdy kind 1xxyyyzzzw (10 digits) starts here
fx.frame_base = constants.body_kinds.frame_base

-- UNCERTAIN: the notes list "kind 53" twice (the second one, "same team and enemy", is most likely
-- 55); 55 is treated as "no restriction" here.
fx.kind_same_team, fx.kind_same_owner, fx.kind_any_team = 53, 54, 55

local team_flags = setmetatable({}, {__mode = "k"})

-- Bodies of kind 53/54/55 can be touched by their own team (the original team immunity is lifted for them).
local function is_team_body(body)
    local kind = body.kind
    return kind == 53 or kind == 54 or kind == 55
end
fx.team_body = is_team_body

function fx.has_team_body(bodies)
    local cached = team_flags[bodies]
    if cached == nil then
        cached = false
        for _, body in ipairs(bodies) do
            if is_team_body(body) then cached = true break end
        end
        team_flags[bodies] = cached
    end
    return cached
end

function fx.allows(attacker, defender, body)
    local kind = body.kind
    if kind == 53 then return attacker.team == defender.team end
    if kind == 54 then return attacker.owner == defender.owner end
    return true
end

-- bdy zwidth widens the depth window of the hit (UNCERTAIN: the larger of itr and bdy zwidth wins).
function fx.depth_ok(depth, window, body)
    local own = body.zwidth
    if own and own > window then window = own end
    return depth < window and depth > -window
end

-- bdy kind 1xxx (with shaking) / 2xxx (without): the owner goes to frame xxx when hit.
-- Returns {frame =, shake =} for them, nil otherwise (kind 1000 itself and 1xxyyyzzzw are not this).
function fx.frame_hit(body)
    if not body then return nil end
    local kind = body.kind
    if kind > fx.frame_base and kind < 3000 then
        return {frame = kind % 1000, shake = kind < 2000}
    end
    return nil
end

-- Team a bdy respond names for a victim that was hit through a 1xxx/2xxx body: 0 / nil = team 1
-- (default), -1 = the attacker's team, anything else = that team.
function fx.team_of(respond, attacker)
    if respond == nil or respond == 0 then return constants.teams.player_one end
    if respond == -1 then return attacker.team end
    return respond
end

-- bdy 1xxyyyzzzw: chance % (0 = always), target frame, attacker frame, effect digit.
function fx.complex(body)
    if not body or body.kind < fx.complex_base then return nil end
    local kind = body.kind
    local effect = kind % 10
    return {
        chance = math.floor(kind / 10000000) % 100,
        target_frame = math.floor(kind / 10000) % 1000,
        attacker_frame = math.floor(kind / 10) % 1000,
        take_team = effect % 2 == 1,
        damage = (effect % 4) >= 2,
        shake = effect >= 4,
    }
end

-- bdy 50 (no injured + no fall), 51 (no injured), 52 (no fall).
local frames = constants.character_frames
local function in_range(frame, first, count) return frame >= first and frame <= first + count end
function fx.keep_pose(body, victim, before_frame, before_b0, before_impulse_y)
    local kind = body and body.kind
    if kind ~= 50 and kind ~= 51 and kind ~= 52 then return end
    local frame = victim.frame
    if frame == before_frame then return end
    local injured = in_range(frame, frames.injured, 8)
    local falling = in_range(frame, frames.falling, 6)
    if (kind == 50 and (injured or falling)) or (kind == 51 and injured) or (kind == 52 and falling) then
        victim.frame, victim.timer_b0, victim.impulse_y = before_frame, before_b0, before_impulse_y
    end
end
return fx
