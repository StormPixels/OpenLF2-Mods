-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren interaction constants (capacities from the feature list, section 1).
return {
    max_itr = 100,      -- itr per frame
    max_bdy = 100,      -- bdy per frame
    max_opoints = 20,   -- opoint per frame, all spawned
    max_sounds = 20,    -- sounds played at the same time (enforced by sounds.lua, owned by AI 5)
}
