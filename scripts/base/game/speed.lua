-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local system_data = require("base/game/system_data")
local speed = {fast = false, slow = 0}

local round_end_jingle = 80  -- match.lua: at this round_counter the end jingle plays and normal speed returns
local slow_power_limit = 200

-- LF2 Darkfiren: the milliseconds added to each frame while a round ends (system.dat `slow_motion:` 0/1 and
-- `slow_power:` "add 65 to default fps value"); 0 when slow motion is off. Without a system.dat tag slow motion
-- stays off, as it was before. The result is clamped to 0..200.
function speed.slow_extra()
    if system_data.number("slow_motion", 0) ~= 1 then return 0 end
    local power = system_data.number("slow_power", 65)
    if power < 0 then return 0 end
    return math.min(power, slow_power_limit)
end

-- The extra frame time of a round that has been ending for `counter` ticks (1 = the tick the last team stood alone):
-- slow motion lasts until the end jingle at counter 80.
function speed.round_end_slow(counter)
    if counter >= 1 and counter < round_end_jingle then return speed.slow_extra() end
    return 0
end
return speed
