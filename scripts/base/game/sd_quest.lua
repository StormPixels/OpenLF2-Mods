-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren background quests (bg.dat `quest:` blocks, data.quests; readme background.txt, "NEW QUEST MODE").
-- Pure bookkeeping: a tracker says when a quest's goal has been reached; the round gives the reward. Kept compatible
-- with Lua 5.1/LuaJIT.
--   type: 1 kill, 2 total attack, 3 mp usage, 4 hp lost (the player's totals since the round started)
--   respond (the reward): 1 hp, 2 heal, 3 mp, 4 total hp, 5 dark hp, 6 reserve, 7 double damage, 8 double mp regen,
--     9 double dhp regen, 10 double hp regen, 11 unlimited hp, 12 unlimited mp (7-12 last `amount` units)
--   start, recover: units of 1/30 s; times: how many checks; bound: game mode (0 vs, 1 stage, 4 battle)
--   fall: the quest runs only in a background mode whose `fall:` lists it (background.filtered keeps data.quests
--     of the round's background to those; the event's `fall` repeats the value)
-- [UNCERTAIN] the readme's example says only: the first check is at `start`, a goal of `next` earns the reward, the
-- goal then grows by `next`, and checks repeat every `recover` units, `times` times. Here a goal that is missed is
-- checked again with the same goal at the next loop; a quest without `next` is rewarded at every check.
local sd_quest = {}

local metrics = {"kill", "attack", "mp", "hp_lost"}  -- stats field of quest type 1..4

-- A tracker for one player in game mode `mode`; only the quests whose `bound` equals the mode count.
function sd_quest.create(quests, mode)
    local tracker = {entries = {}}
    for index, quest in ipairs(quests or {}) do
        if (quest.bound or 0) == (mode or 0) and metrics[quest.type or 0] then
            tracker.entries[#tracker.entries + 1] = {index = index, quest = quest, checked = 0,
                due = quest.start or 0, goal = quest.next or 0}
        end
    end
    return tracker
end

-- Runs every check that is due at `tick` (units since the round started) and returns the rewards earned, in
-- order: {{index, respond, amount, sound, fall, check}}. `stats` = {kill, attack, mp, hp_lost} totals of the player.
function sd_quest.step(tracker, tick, stats)
    local events = {}
    if type(tracker) ~= "table" or type(stats) ~= "table" then return events end
    for _, entry in ipairs(tracker.entries) do
        local quest = entry.quest
        while entry.checked < (quest.times or 0) and tick >= entry.due do
            entry.checked = entry.checked + 1
            entry.due = entry.due + math.max(quest.recover or 0, 1)
            if (tonumber(stats[metrics[quest.type]]) or 0) >= entry.goal then
                events[#events + 1] = {index = entry.index, respond = quest.respond, amount = quest.amount,
                    sound = quest.sound, fall = quest.fall, check = entry.checked}
                entry.goal = entry.goal + (quest.next or 0)
            end
        end
    end
    return events
end
return sd_quest
