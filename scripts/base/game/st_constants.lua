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
}
return st_constants
