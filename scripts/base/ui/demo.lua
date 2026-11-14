-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local constants = require("base/game/constants")
local catalog = require("base/game/catalog")
local demo = {}

local picks = {[0] = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
function demo.reset() picks = {[0] = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0} end
-- Eight demo fighters, ten in the 10 player layout (the match, game/match.lua create_demo, takes as many as it is given).
local function fighter_count()
    local options = require("base/game/options")
    return options.slot_count and options.slot_count(options.current().battlefield_layout) or 8
end

local function pick_all(fighters)
    local count = fighter_count()
    for slot = 0, count - 1 do
        local candidates = {}
        for index, fighter in ipairs(fighters) do
            if fighter.record >= 1 and fighter.id < constants.record_id_ranges.random_fighter_end_exclusive then
                local taken = false
                for other = 0, count - 1 do
                    if picks[other] == index then taken = true end
                end
                if not taken then candidates[#candidates + 1] = index end
            end
        end
        assert(#candidates > 0, "no fighter left for the demo")
        picks[slot] = candidates[engine.random(#candidates) + 1]
    end
    return picks
end

-- Match options for one demo round. `characters` is the last character-menu state, if any.
function demo.match_options(characters)
    if characters and characters.slots then
        for slot = 0, fighter_count() - 1 do
            if characters.slots[slot] and characters.slots[slot].fighter > 0 then picks[slot] = characters.slots[slot].fighter end
        end
    end
    local fighters = catalog.load()
    local options = characters and characters.options
    return {mode = constants.modes.demo,
        difficulty = options and options.difficulty or 0, background = constants.background_rows.random,
        fighters = fighters, backgrounds = catalog.backgrounds(), slots = {},
        demo = {pick = function() return pick_all(fighters) end}}
end
return demo
