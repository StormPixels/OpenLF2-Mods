-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local catalog = {}
local cached
local cached_backgrounds
local cached_objects
local function canonical(path)
    path = path:gsub("\\", "/"):lower()
    assert(path:match("^[a-z0-9_./-]+$"), "unsupported original resource path")
    return path
end
local function decode(source)
    assert(#source >= 123, "truncated character data")
    local key = "SiuHungIsAGoodBearBecauseHeIsVeryGood"
    local result = {}
    for position = 124, #source do
        result[#result + 1] = string.char((source:byte(position) - key:byte((position - 1) % #key + 1)) % 256)
    end
    return table.concat(result)
end
function catalog.load()
    if cached then return cached end
    local source = engine.read_resource("data/data.txt")
    local section = assert(source:match("<object>(.-)<object_end>"), "missing object catalog")
    local fighters = {}
    local record = -1
    -- LF2 Darkfiren: `hidden:` and `kind:` written in <bmp_begin> decide; the id range only gives a default.
    local function header_number(header, key)
        for line in (header .. "\n"):gmatch("([^\r\n]*)[\r\n]") do
            local name, value = line:match("^%s*([%a_]+)%s*:%s*(%-?%d+)")
            if name == key then return tonumber(value) end
        end
        return nil
    end
    local function default_locked(id)
        local ok, system_data = pcall(require, "base/game/system_data")
        if ok and type(system_data) == "table" and system_data.ids then
            local listed = system_data.ids("id_locked")
            if type(listed) == "table" and next(listed) ~= nil then return listed[id] == true end
        end
        local group = math.floor(id / 10)
        return group == 3 or group == 5
    end
    for line in (section .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("#.*$", "")
        local id, kind, path = line:match("id:%s*(%d+)%s+type:%s*(%d+)%s+file:%s*(%S+)")
        -- Object records are numbered in file order across all types.
        if id then record = record + 1 end
        if id and tonumber(kind) == 0 then
            id = tonumber(id)
            do
                path = canonical(path)
                local data = engine.read_resource(path)
                if path:sub(-4) == ".dat" then data = decode(data) end
                local header = assert(data:match("<bmp_begin>(.-)<bmp_end>"), "missing character header: " .. path)
                local name = assert(header:match("name:%s*(%S+)"), "missing character name: " .. path)
                local portrait = assert(header:match("head:%s*(%S+)"), "missing portrait: " .. path)
                -- The small picture of the HP frame, also the face on the wide layout's roster (optional).
                local small = header:match("small:%s*(%S+)")
                local lock = header_number(header, "hidden")
                local menu_kind = header_number(header, "kind")
                fighters[#fighters + 1] = {id = id, record = record, name = name,
                    portrait = canonical(portrait), small = small and canonical(small) or nil, path = path,
                    hidden = default_locked(id), lock = lock, menu_hidden = menu_kind == -1}
                assert(#fighters <= 1000, "too many character records")
            end
        elseif line:find("%S") and not id then error("invalid object catalog line") end
    end
    assert(#fighters > 0, "empty fighter catalog")
    cached = fighters
    return cached
end
function catalog.words_checksum()
    local source = engine.read_resource("data/data.txt")
    local words = {}
    for word in source:gmatch("%S+") do words[#words + 1] = word end
    local sum, position, last = 0, 1, nil
    local function next_word()
        local word = words[position]
        position = position + 1
        return word
    end
    local function add(word)
        for index = 1, #word do
            local byte = word:byte(index)
            if byte > 127 then byte = byte - 256 end
            sum = sum + byte * (index - 1)
        end
    end
    local function skip_list(closing, extra)
        local word = next_word()
        while word ~= closing and word ~= nil do
            if word == "id:" then for _ = 1, extra do next_word() end end
            word = next_word()
        end
        return word
    end
    local repeated = false
    while true do
        local word = next_word()
        if word then last = word else word = last end
        if word then add(word) end
        if word == "<object>" then word = skip_list("<object_end>", 5) end
        if word == "<background>" then skip_list("<background_end>", 3) end
        if position > #words then
            if source:find("%s$") and not repeated then repeated = true else break end
        end
    end
    return sum
end

function catalog.selectable(fighter)
    local unlock = require("base/game/unlock")
    local lock = fighter.lock
    if lock ~= nil then   -- `hidden:` written in the file overrides the id default
        if lock == 4 then return false end   -- never selectable
        if lock >= 1 and lock <= 3 then
            if unlock.allows then return unlock.allows(lock) == true end
            return unlock.flags.characters == 1
        end
        return true   -- 0, or 10~1000: the phase grid checks those keys with unlock.allows
    end
    return not fighter.hidden or unlock.flags.characters == 1
end
-- The next (step 1) or previous (step -1) selectable fighter after list position `position`
-- (0 is Random); running past either end gives Random, as the original's -1.
-- Shown in the character menu and roster: `kind: -1` ids stay out, but a <phase> list can still offer them.
function catalog.listed(fighter)
    return not fighter.menu_hidden and catalog.selectable(fighter)
end

function catalog.step(fighters, position, step)
    repeat
        position = (position + step) % (#fighters + 1)
    until position == 0 or catalog.listed(fighters[position])
    return position
end
-- Every <object> record in file order: {id, kind (type:), path}. FindRecordIndex in the original
-- takes the first record with a given id.
function catalog.objects()
    if cached_objects then return cached_objects end
    local source = engine.read_resource("data/data.txt")
    local section = assert(source:match("<object>(.-)<object_end>"), "missing object catalog")
    local objects, by_id = {}, {}
    for id, kind, path in section:gmatch("id:%s*(%d+)%s+type:%s*(%d+)%s+file:%s*(%S+)") do
        local entry = {id = tonumber(id), kind = tonumber(kind), path = canonical(path)}
        objects[#objects + 1] = entry
        if not by_id[entry.id] then by_id[entry.id] = entry end
        assert(#objects <= 1000, "too many object records")
    end
    cached_objects = {list = objects, by_id = by_id}
    return cached_objects
end

function catalog.backgrounds()
    if cached_backgrounds then return cached_backgrounds end
    local source = engine.read_resource("data/data.txt")
    local section = assert(source:match("<background>(.-)<background_end>"), "missing background catalog")
    local backgrounds = {}
    for id, path in section:gmatch("id:%s*(%d+)%s+%S+%s+(%S+)") do
        backgrounds[#backgrounds + 1] = {id = tonumber(id), path = canonical(path)}
        assert(#backgrounds <= 100, "too many background records")
    end
    assert(#backgrounds > 0, "empty background catalog")
    cached_backgrounds = backgrounds
    return backgrounds
end
return catalog
