-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- Constants of the LF2 Darkfiren frame/input/state engine (AI 2 scope).
-- Everything marked [UNCERTAIN] is a decision the documentation does not settle; change it here only.
local st_constants = {
    -- hold_* tags: "about 2 seconds" at 30 ticks per second. [UNCERTAIN] exact length.
    hold_ticks = 60,
    -- hit_Faj / hit_Uaj / hit_Daj: documented as hit_Fa/Ua/Da with the J key. That key sequence is the one hit_Fj/Uj/Dj
    -- already use, so the new tags are read as a fallback of those (hit_Fj wins when both exist). [UNCERTAIN]
    -- The pdk renames (hit_aj, hit_jj, hit_aa) are not understood and are not read.
    alias_aj = true,
    -- chp: hp is filled by the value; this share divisor of it also raises the dark hp ("1/3 to dhp"). [UNCERTAIN]
    chp_dark_divisor = 3,
    -- next: 13XX jumps to a random frame from current+1 to current+XX.
    next_random_base = 1300,
    next_random_limit = 1400,
    -- State 86 turns around and "advances one frame": read as taking the frame's own `next` at once. [UNCERTAIN]
    state86_takes_next = true,
    states = {
        invisible = 20,            -- invisible during the frame's wait
        invisible_not_clone = 21,  -- same, but not for clones
        set_hp_one = 62,
        set_hp_zero = 63,
        set_mp_zero = 64,
        set_hp_full = 65,          -- hp and dark hp 500
        set_mp_full = 66,
        by_difficulty = 80,        -- next + (easy 3, normal 2, difficult 1, crazy 0)
        by_mode = 81,              -- next + 1 when the stage is finished [UNCERTAIN: "finished" test]
        by_team = 82,              -- next + 1 for team 5
        turn = 85,
        turn_and_step = 86,
        random_first = 121,        -- 121 adds 0..1, 122 adds 0..2, ... 139 adds 0..19
        random_last = 139,
        mp_regen_first = 150,      -- sets an extra mp recovery of 0..9 [UNCERTAIN: persists until changed]
        mp_regen_last = 159,
        team_first = 3640,         -- 364X sets the team to X (0-5)
        team_last = 3645,
        reserve_first = 4000,      -- 4xxx sets the reserve lives to xxx (characters only)
        reserve_last = 4999,
        heal_first = 17000,        -- 17xxx heals xxx hp (0 means 100) [UNCERTAIN: cap]
        heal_last = 17999,
        hold_round = 404,          -- stays in the frame until the round is over
        move_to_center = 405,      -- moves the object to the middle of the map [UNCERTAIN: x only or x and z]
    },
    heal_default = 100,
    -- Round 2 states (the number is the whole frame `state`).
    branch = {
        hp_first = 1000000, hp_last = 1999999,   -- 1xxxyyy: hp > xxx goes to yyy, else to next
        mp_first = 2000000, mp_last = 2999999,   -- 2xxxyyy: see mp_swapped
        -- [UNCERTAIN] The notes disagree on the mp branch. txt/readme swaps yyy and the frame's next compared with hp:
        -- mp > xxx goes to next, otherwise to yyy. Set false to use the same direction as hp.
        mp_swapped = true,
    },
    timestop = {
        first = 3000000, last = 3999999,         -- 3xxyzzz: xx chance (0 = 100%), y kind, zzz duration
        unit_ticks = 1,                          -- [UNCERTAIN] one duration unit is this many ticks
    },
    charge = {first = 6000, last = 6999,         -- 6XXX
        grace_ticks = 8},                        -- a key released this soon after entering (a tap) is forgotten; the next press starts the charge
    ai_takeover = {first = 7000, last = 7999, unit_ticks = 1},    -- 7XXX [UNCERTAIN: unit]
    transform = {first = 80000, last = 89999},   -- 8XXXX: record id = state - 80000
    landing = {first = 9000, last = 9399},       -- 9xxx: frame to go to when landing
    camera = {first = 99000, last = 99999},      -- 99XXX (XXX ticks, 0 = while in the frame)
    quake = {first = 50000, last = 59999, base = 50},  -- 5XXYY: x = XX-50, y = YY-50; an axis written 00 does not move (55200 = x +2 only)
    -- Background switch states 9XX, 9XXYY, 7XX, 7XXYY (readme "new states.txt"). Only the ranges live here (99XXX is the
    -- camera); AI 5's background.switch_state(match, state_number) knows what they mean and AI 2 hands the number over.
    background = {row = {first = 900, last = 999}, row_mode = {first = 90000, last = 98999},
        mode = {first = 700, last = 799}, mode_row = {first = 70000, last = 79999}},
    -- itr status effects (section 4) read by the control code. confus: the keys are swapped. [UNCERTAIN] The notes' eight
    -- "confuse key tables" are not in the documents (exe/pointer.txt lists only their addresses), so this map is AI 2's own.
    confus_map = {left = "right", right = "left", up = "down", down = "up"},
    weak_mp_divisor = 2,   -- weak: mp recovery slows to this fraction; hp recovery stops
    facing_mp_factor = 2,  -- facing: the mp a move costs is multiplied by this
    -- hit_Fa values on attack objects that are new in Darkfiren.
    fa = {fire_chase = 24, ice_chase = 25, firen_explosion = 26, angel_first = 5000, demon_first = 6000, bat_first = 8000,
        range = 1000, chase_min = 4, chase_max = 10, demon_max = 7},
}
return st_constants
