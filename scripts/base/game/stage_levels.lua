-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren's stage list (data/stage.dat): a list of levels, each with a file of stages. Stage number =
-- level id * 10 + the id inside the level's file. `data` is what engine.read_stage_data returns:
-- {stages = {[number] = stage}, levels = {{id, name, small, hidden, boss, ...}}}. The original's stage.dat has no
-- levels, and none of this applies to it. Compatible with Lua 5.1/LuaJIT.
local stage_levels = {}

function stage_levels.active(data)
    return data ~= nil and data.levels ~= nil and #data.levels > 0
end

-- Row of the background list a stage plays on: its `bg:` (the first when absent), or the original's rule
-- (`legacy_row`, group + 1) without levels.
function stage_levels.background_row(data, id, legacy_row)
    if not stage_levels.active(data) then return legacy_row end
    local stage = data.stages[id]
    local bg = stage and stage.bg or -1
    return bg >= 0 and bg or 0
end

local function background_of(data, id)
    return stage_levels.background_row(data, id, 0)
end

-- What follows a cleared stage: {action = "stage", id}   the next stage on the same background (id + 1, or the
--                                                         target of the phase's when_clear_goto_stage),
--                               {action = "group", id}   a stage that needs a new match (other background, or the
--                                                         first stage of the next level),
--                               {action = "ending"}      the credits (the stage's `end: 1`),
--                               {action = "menu"}        back to the character menu (`end: 2`, or nothing left).
-- After a level's last stage without `end:` comes the next level that is not hidden.
function stage_levels.plan(data, id, goto_stage)
    local stages = data.stages
    local target
    if goto_stage and goto_stage >= 0 and stages[goto_stage] then target = goto_stage
    elseif id % 10 ~= 9 and stages[id + 1] then target = id + 1 end
    if target then
        if background_of(data, target) == background_of(data, id) then return {action = "stage", id = target} end
        return {action = "group", id = target}
    end
    local stage = stages[id]
    local kind = stage and stage["end"] or 0
    if kind == 1 then return {action = "ending"} end
    if kind == 2 then return {action = "menu"} end
    local level = math.floor(id / 10)
    for _, info in ipairs(data.levels) do
        if info.id > level and info.hidden == 0 and stages[info.id * 10] then return {action = "group", id = info.id * 10} end
    end
    return {action = "menu"}
end

-- The name a stage shows: `Survival Stage: %d` takes the stage's number inside its level.
function stage_levels.title(stage, id)
    local name = stage and stage.name or ""
    return (name:gsub("%%d", tostring(id % 10 + 1)))
end

-- The levels a player may choose: hidden 0, or 1 to 3 once the cheat code is in; 4 and the lock values (10 and
-- up, kept in saves.txt, not done) stay hidden. Level numbers with no stage in the data are left out.
function stage_levels.visible(data, cheat)
    local list = {}
    if not stage_levels.active(data) then return list end
    for _, info in ipairs(data.levels) do
        local hidden = info.hidden or 0
        if (hidden == 0 or (hidden <= 3 and cheat)) and data.stages[info.id * 10] then list[#list + 1] = info end
    end
    return list
end

function stage_levels.level(data, id)
    for _, info in ipairs(data.levels or {}) do
        if info.id == id then return info end
    end
end

return stage_levels
