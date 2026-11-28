-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- Tipe game 1: LF2 original (v2.0a as released). Only what differs from the shared settings of base/game/tipe_game.lua.
return {
    id = 1,
    kind = "original",  -- the name the host detects (resource "game/kind")
    name = "LF2 original",
    settings = {
        tall_view_height = 550,  -- every background keeps the classic 550 high picture
    },
}
