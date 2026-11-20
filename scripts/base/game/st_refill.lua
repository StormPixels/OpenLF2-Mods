-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- Which objects refill hp or mp when drunk. LF2 Darkfiren's system.dat names them (`<hp_refill>` / `<mp_refill>` blocks of `id:` lines, up to
-- 100 each; the stock file lists 122 and 123); the code used to compare against the milk (122) and beer (123) ids directly. With the block in
-- system.dat the list decides; without it the old ids stay (milk refills hp, beer refills mp).
local constants = require("base/game/constants")
local system_data = require("base/game/system_data")

local st_refill = {}

function st_refill.hp(id)
    if system_data.has("hp_refill") then return system_data.ids("hp_refill")[id] == true end
    return id == constants.item_ids.milk
end

function st_refill.mp(id)
    if system_data.has("mp_refill") then return system_data.ids("mp_refill")[id] == true end
    return id == constants.item_ids.beer
end

-- Either kind (the old `id == milk or id == beer`).
function st_refill.any(id) return st_refill.hp(id) or st_refill.mp(id) end

return st_refill
