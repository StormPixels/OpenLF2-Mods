-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- Tipe game 4: LF2 Neora (an engine modification: neora.dll next to its own executable PDK.exe; detected by neora.dll).
-- Only what differs from the shared settings of base/game/tipe_game.lua.
return {
    id = 4,
    kind = "neora",
    name = "LF2 Neora",
    settings = {
        compact_sheet = true,  -- PDK.exe's MENU_CLIP6 is the compact 794 x 264 sheet
        -- The Configuration Block of neora.dll (DLL/Main.asm); only what OpenLF2 has a counterpart for.
        slow_motion = 1,           -- slow_motion: 1, at the end of a round
        slow_power = 65,           -- slow_power: 65
        battle_defense_max = 1000, -- battle_limit: 1000 (10.0), the original stops at 300
        battle_defense_step = 100, -- battle_step: 100 (1.0), the original steps 50
        f7_after_round = true,     -- F7_for_dead: 1, F7 after the round ends as in LF2 1.9
    },
}
