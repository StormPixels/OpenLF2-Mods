-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren time stop, state 3xxyzzz: xx chance in percent (0 = always), y kind, zzz duration.
-- Kind 0 freezes everything except the user, 1 everything except the user's team, 2 every object except characters
-- (and the user). Only one time stop runs at a time; a second one is ignored until the first has ended. [UNCERTAIN]
local st_constants = require("base/game/st_constants")
local constants = require("base/game/constants")
local timestop = {}

local function st_of(match)
    local st = match.st
    if not st then
        st = {}
        match.st = st
    end
    return st
end

-- Called when an item enters a time stop frame; `s` is the frame's state.
function timestop.start(match, index, value, s)
    local cfg = st_constants.timestop
    local rest = s - cfg.first
    local chance = math.floor(rest / 10000)
    local kind = math.floor(rest / 1000) % 10
    local duration = (rest % 1000) * cfg.unit_ticks
    if duration <= 0 or kind > 2 then return end
    local st = st_of(match)
    if st.timestop then return end
    if chance ~= 0 and engine.random(100) >= chance then return end
    st.timestop = {kind = kind, owner = index, team = value.team, timer = duration}
end

-- Once per tick, before the items are stepped.
function timestop.tick(match)
    local st = match.st
    local stop = st and st.timestop
    if not stop then return end
    stop.timer = stop.timer - 1
    if stop.timer <= 0 then st.timestop = nil end
end

-- True when `value` is frozen by a running time stop.
function timestop.frozen(match, index, value)
    local st = match.st
    local stop = st and st.timestop
    if not stop or index == stop.owner then return false end
    if stop.kind == 0 then return true end
    if stop.kind == 1 then return value.team ~= stop.team end
    return value.record.kind ~= constants.record_kinds.character
end
return timestop
