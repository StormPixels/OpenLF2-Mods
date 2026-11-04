-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- Small tolerant scanner for the text of LF2 Darkfiren's global data files (system.dat, bgm.dat, sound.dat,
-- kind.dat, fusion.dat, dmg.dat). It never raises on odd input: unknown lines are skipped.
-- Compatible with Lua 5.1/LuaJIT and Lua 5.3.
local sd_text = {}

-- Trims white space on both ends.
function sd_text.trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The leading integer of a value ("99 ;comment" -> 99, "-1" -> -1), or nil.
function sd_text.int(text)
    local digits = type(text) == "string" and text:match("^%s*(-?%d+)") or nil
    return digits and tonumber(digits) or nil
end

-- All integers of a value in order ("1 2,3" -> {1, 2, 3}).
function sd_text.ints(text)
    local out = {}
    for digits in (text or ""):gmatch("-?%d+") do out[#out + 1] = tonumber(digits) end
    return out
end

-- Drops a trailing ";comment" (the readme documents values that way) and trims.
function sd_text.value(text)
    return sd_text.trim((text:gsub(";.*$", "")))
end

-- The `key: value` pairs of one line, in order. A key starts at the line start or after white space and a value
-- runs to the next key, so `name: Boss <boss>\thidden: 2\tmode: 1   respond: 4` gives four pairs.
function sd_text.pairs_of_line(line)
    local found, position = {}, 1
    while true do
        local first, last, key = line:find("([%a_][%w_]*)%s*:", position)
        if not first then break end
        if first == 1 or line:sub(first - 1, first - 1):match("%s") then
            found[#found + 1] = {first = first, last = last, key = key}
        end
        position = last + 1
    end
    local out = {}
    for index, item in ipairs(found) do
        local stop = found[index + 1] and found[index + 1].first - 1 or #line
        out[#out + 1] = {item.key, sd_text.trim(line:sub(item.last + 1, stop))}
    end
    return out
end

-- Splits a text into top-level scalar lines and `<name>` ... `<..._end>` blocks.
-- Returns {scalars = {key = value string, first one wins}, blocks = {{name = "armor_s", lines = {...}}, ...}}.
-- A block also ends when another block starts, so a missing end tag does not swallow the rest of the file.
function sd_text.scan(text)
    local result = {scalars = {}, blocks = {}}
    local current
    for raw in ((text or "") .. "\n"):gmatch("([^\n]*)\n") do
        local line = sd_text.trim((raw:gsub("\r", "")))
        local tag = line:match("^<([%w_]+)>")
        if tag == "boss" then
            -- Not a block: the flag of a bgm track name (`<boss>`), kept as a line of the open block.
            if current then current.lines[#current.lines + 1] = line end
        elseif tag then
            if tag:find("_end$") then current = nil
            else
                current = {name = tag, lines = {}}
                result.blocks[#result.blocks + 1] = current
            end
        elseif line ~= "" then
            if current then current.lines[#current.lines + 1] = line
            else
                local key, value = line:match("^([%a_][%w_]*)%s*:%s*(.-)$")
                if key and result.scalars[key] == nil then result.scalars[key] = sd_text.value(value) end
            end
        end
    end
    return result
end

-- Reads "game/dat_text/<path>" (the decrypted text of a data file); returns the text, or nil and a message.
function sd_text.read(path)
    if type(engine) ~= "table" or type(engine.read_resource) ~= "function" then return nil, "no engine" end
    local ok, text = pcall(engine.read_resource, "game/dat_text/" .. path)
    if not ok then return nil, tostring(text) end
    return text
end

-- True for the one failure that can heal later: the game data is not attached yet (the window exists, the
-- installer has not finished). Every other failure (missing file, no engine) is final for that file.
function sd_text.not_ready(message)
    return type(message) == "string" and message:find("not loaded yet", 1, true) ~= nil
end
return sd_text
