-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren interaction constants (capacities from the feature list, section 1).
return {
    max_itr = 100,      -- itr per frame
    max_bdy = 100,      -- bdy per frame
    max_opoints = 20,   -- opoint per frame, all spawned
    max_sounds = 20,    -- sounds played at the same time (enforced by sounds.lua, owned by AI 5)
    frozen_can_be_hit = true,  -- time stop: a frozen object never attacks; true = the user of the time stop can still hit it
    platform = {               -- itr kind 30-89 (docs/txt/readme/platform.txt), see platform.lua
        supported_subtypes = {[0] = true}, -- stage 1: only kind X0 (landing plane); X1..X5 are ignored until specified
        land_tolerance = 0.0001,           -- feet may be this far below the plane and still land on it
    },
    ppoint_mirror_x = true,    -- [BELUM PASTI] ppoint x is mirrored when the owner faces left (docs show only a right-facing example)
    ppoint_copy_facing = true, -- [BELUM PASTI] a ppoint object takes the owner's facing every tick
    combo_reset_ticks = 50,    -- ticks without a new hit after which fx.combo drops to 0 (used when mode.dat has no <combo> respond)
}
