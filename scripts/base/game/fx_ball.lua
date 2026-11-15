-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren state 3007 (readme frame/new states.txt, "NEW state 3007"): an energy ball (record kind 3) with its own HP.
-- Works only with kind 3. The HP comes from the opoint `hp:` tag (fx_point.lua; 500 when absent) and the ball takes damage from
-- itr hits; at zero or below it goes to the frame named by hit_d. Two frame tags work with this state:
--   attacking: 1 = destroyed directly on hitting kind 0 and kind 2, 2 = only kind 0, 3 = only kind 2
--   cover:     1 = a defending kind 0 forces the ball to its destroyed frame, 2 = a defending kind 0 rebounds it like state 3000
-- Everything is nil-safe: a ball without state 3007 is never touched. Guesses are named in fx_constants.hp_ball [BELUM PASTI].
local constants = require("base/game/constants")
local fx_constants = require("base/game/fx_constants")
local fx_ball = {}

local record_kinds = constants.record_kinds

local function in_state(ball)
    return ball.record.kind == record_kinds.ball and ball.record.frame(ball.frame).state == fx_constants.platform.ball_state
end

-- Sends the ball to the frame named by hit_d of its current frame (the destroyed frame).
local function destroy(ball)
    local config = fx_constants.hp_ball
    local target = ball.record.frame(ball.frame).hits.d
    if not target or target == 0 or not ball.record.frames[target] then target = config.fallback_frame end
    ball.frame = target
    ball.wait_counter = 0
    ball.vx = 0.0
end

fx_ball.in_state = in_state

-- After an itr hit took its damage: the ball is destroyed when its HP fell below the limit.
function fx_ball.struck(ball)
    if not in_state(ball) then return false end
    if ball.hp <= fx_constants.hp_ball.destroy_at_or_below then destroy(ball) return true end
    return false
end

-- The ball (attacker) hit something: attacking 1 destroys it on kinds 0 and 2, 2 on kind 0, 3 on kind 2.
function fx_ball.attacker_hit(ball, victim_kind)
    if not in_state(ball) then return false end
    local mode = ball.record.frame(ball.frame).attacking or 0
    local on_character, on_heavy = victim_kind == record_kinds.character, victim_kind == record_kinds.heavy_item
    if (mode == 1 and (on_character or on_heavy)) or (mode == 2 and on_character) or (mode == 3 and on_heavy) then
        destroy(ball)
        return true
    end
    return false
end

-- The ball hit a defending fighter: cover 1 = destroyed frame, cover 2 = it rebounds like state 3000 (frame "hitting", stopped).
function fx_ball.defended(ball)
    if not in_state(ball) then return false end
    local mode = ball.record.frame(ball.frame).cover or 0
    if mode == 1 then destroy(ball) return true end
    if mode == 2 then
        ball.frame = constants.ball_frames.hitting
        ball.wait_counter = 0
        ball.vx = 0.0
        return true
    end
    return false
end

return fx_ball
