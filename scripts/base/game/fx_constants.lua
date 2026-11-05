-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren interaction constants (capacities from the feature list, section 1).
return {
    max_itr = 100,      -- itr per frame
    max_bdy = 100,      -- bdy per frame
    max_opoints = 20,   -- opoint per frame, all spawned
    max_sounds = 20,    -- sounds played at the same time (enforced by sounds.lua, owned by AI 5)
    frozen_can_be_hit = false, -- time stop: false = a frozen object neither attacks nor is attacked; true = it can still be hit
    combo_reset_ticks = 60,    -- UNCERTAIN: ticks without a new hit after which fx.combo drops to 0
}
