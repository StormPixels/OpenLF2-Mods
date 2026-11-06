-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- Parsed data of LF2 Darkfiren's kind.dat (ball transformation), fusion.dat (type 0 fusion) and the stage damage
-- modifier file (`<stage_dmg_dec>` blocks, data\stage\dmg.dat). Only the data is provided here; applying it in
-- a fight belongs to the combat and state modules. Kept compatible with Lua 5.1/LuaJIT.
local sd_text = require("base/game/sd_text")
local sd_global = {}

local max_kinds, max_fusions, max_damage, max_ids = 100, 50, 50, 100
local cache = {}

-- kind.dat: up to 100 `<kind>` blocks, each `effect: <t3 id>`, `frame: <frame>` and the id lists `bound:` ...
-- `bound_end:` and `respond:` ... `respond_end:`. The readme says the feature mimics normal balls turning into ice
-- balls through ids 8, 209 and 213; which list means "trigger" and which "affected" is [UNCERTAIN], so both lists
-- are returned under their own tag names. Result: {{effect = 209, frame = 40, bound = {[8] = true, ...},
-- respond = {[200] = true, ...}}, ...}.
function sd_global.parse_kinds(text)
    local kinds = {}
    for _, block in ipairs(sd_text.scan(text).blocks) do
        if block.name == "kind" and #kinds < max_kinds then
            local kind, list = {}, nil
            for _, line in ipairs(block.lines) do
                if line:match("^[%a_][%w_]*_end%s*:") then list = nil
                else
                    local opener = line:match("^([%a_][%w_]*)%s*:%s*$")
                    if opener then
                        list = {}
                        kind[opener] = list
                    else
                        for _, pair in ipairs(sd_text.pairs_of_line(line)) do
                            local number = sd_text.int(pair[2])
                            if number then
                                if list and pair[1] == "id" then
                                    local count = 0
                                    for _ in pairs(list) do count = count + 1 end
                                    if count < max_ids then list[number] = true end
                                elseif not list then kind[pair[1]] = number end
                            end
                        end
                    end
                end
            end
            kinds[#kinds + 1] = kind
        end
    end
    return kinds
end

-- fusion.dat: up to 50 entries between `fusion: <n>` and `fusion_end:` inside the `<fusion_begin>` block. Every
-- `key: number` is kept under its tag name (id1, id2, id3, hp, mp, respond, decrease, wait, state, action, frame,
-- chp, hit_ja, cover, fronthurtact, backhurtact); a tag the entry leaves out is nil. `number` is the reference
-- number of the entry. Result: {{number = 1, id1 = 7, id2 = 8, id3 = 51, hp = 177, ...}, ...}.
function sd_global.parse_fusions(text)
    local fusions, entry = {}, nil
    for _, block in ipairs(sd_text.scan(text).blocks) do
        if block.name == "fusion_begin" then
            for _, line in ipairs(block.lines) do
                if line:match("^fusion_end%s*:") then entry = nil
                else
                    for _, pair in ipairs(sd_text.pairs_of_line(line)) do
                        local number = sd_text.int(pair[2])
                        if pair[1] == "fusion" and number then
                            if #fusions < max_fusions then
                                entry = {number = number}
                                fusions[#fusions + 1] = entry
                            else entry = nil end
                        elseif entry and number then entry[pair[1]] = number end
                    end
                end
            end
        end
    end
    return fusions
end

-- `<stage_dmg_dec>` blocks (up to 50): `decrease:` the damage percentage (negative is not allowed, so it is
-- clamped to 0), `team:` (1..5 in the readme; the shipped file uses 6), `bound:` 0/1 (1: friendly fire follows the
-- decrease), and `type:` / `id:` lists (up to 100 each). Result: {{decrease = 50, team = 1, bound = 1,
-- types = {[0] = true, [3] = true}, ids = {}}, ...}.
function sd_global.parse_damage_rules(text)
    local rules = {}
    for _, block in ipairs(sd_text.scan(text).blocks) do
        if block.name == "stage_dmg_dec" and #rules < max_damage then
            local rule = {types = {}, ids = {}, type_count = 0, id_count = 0}
            for _, line in ipairs(block.lines) do
                for _, pair in ipairs(sd_text.pairs_of_line(line)) do
                    local number = sd_text.int(pair[2])
                    if number then
                        if pair[1] == "type" and rule.type_count < max_ids then rule.types[number] = true; rule.type_count = rule.type_count + 1
                        elseif pair[1] == "id" and rule.id_count < max_ids then rule.ids[number] = true; rule.id_count = rule.id_count + 1
                        elseif pair[1] == "decrease" then rule.decrease = math.max(0, number)
                        elseif pair[1] == "team" or pair[1] == "bound" then rule[pair[1]] = number end
                    end
                end
            end
            rules[#rules + 1] = rule
        end
    end
    return rules
end

-- Reads and parses a data file once: sd_global.kinds(), sd_global.fusions() and sd_global.damage_rules(path)
-- (the path is the stage's `file:` tag such as "data\\stage\\dmg.dat"). A missing file gives an empty list; data
-- that is not attached yet is retried on the next call.
local function read_cached(path, parse)
    local key = path:lower():gsub("\\", "/")
    if cache[key] then return cache[key] end
    local text, message = sd_text.read(key)
    if text then
        cache[key] = parse(text)
        return cache[key]
    end
    if sd_text.not_ready(message) then return {} end
    cache[key] = {}
    return cache[key]
end
function sd_global.kinds() return read_cached("data/kind.dat", sd_global.parse_kinds) end
function sd_global.fusions() return read_cached("data/fusion.dat", sd_global.parse_fusions) end
function sd_global.damage_rules(path) return read_cached(path, sd_global.parse_damage_rules) end

-- The `<combo>` block of the mode file data\mode\mode1.dat (the three mode files carry the same one):
-- {times = display ticks, respond = ticks without a hit before the count returns to 0, facing = 1 (above the
-- attacker) / 0 (above the victim), caughtact = 1 (hits while catching count), effect = who sees it: 8 humans,
-- 20 humans and menu-chosen computers, 1000 everyone}. nil when the game has no such block.
function sd_global.parse_combo(text)
    for _, block in ipairs(sd_text.scan(text).blocks) do
        if block.name == "combo" then
            local combo = {}
            for _, line in ipairs(block.lines) do
                for _, pair in ipairs(sd_text.pairs_of_line(line)) do
                    local number = sd_text.int(pair[2])
                    if number then combo[pair[1]] = number end
                end
            end
            return combo
        end
    end
    return nil
end

function sd_global.combo()
    if cache.combo ~= nil then return cache.combo or nil end
    local text, message = sd_text.read("data/mode/mode1.dat")
    if text then
        cache.combo = sd_global.parse_combo(text) or false
    elseif not sd_text.not_ready(message) then
        cache.combo = false
    else
        return nil
    end
    return cache.combo or nil
end

-- Forgets the loaded files (tests, a changed game folder).
function sd_global.reset() cache = {} end
return sd_global
