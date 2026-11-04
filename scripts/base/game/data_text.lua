-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- The text of a game data file (data/mode/mode2.dat, data/frame.dat ...) for the scripts. The host's game/dat_text/<path>
-- resource is tried first; when the host does not have it, the file is read as it is in the game folder and a .dat is
-- decoded here the way the host decodes it (src/resources/data_file.cpp: the first 123 bytes are skipped and the key
-- "SiuHungIsAGoodBearBecauseHeIsVeryGood" is subtracted from the rest, byte by byte, from the start of the file).
-- Compatible with Lua 5.1/LuaJIT (no bit operators).
local data_text = {}

local key = "SiuHungIsAGoodBearBecauseHeIsVeryGood"
local prefix = 123

-- The decoded text of the bytes of a .dat file, or nil when they are too short or the result is not text.
function data_text.decode(bytes)
    if type(bytes) ~= "string" or #bytes <= prefix then return nil end
    local out, key_length = {}, #key
    for position = prefix + 1, #bytes do
        local mask = key:byte((position - 1) % key_length + 1)
        out[#out + 1] = string.char((bytes:byte(position) + 256 - mask) % 256)
    end
    local text = table.concat(out)
    -- A wrong file decodes to noise: the first characters of real data text are printable ASCII or white space.
    for index = 1, math.min(#text, 64) do
        local byte = text:byte(index)
        if byte > 126 or (byte < 32 and byte ~= 9 and byte ~= 10 and byte ~= 13) then return nil end
    end
    return text
end

local decoded = {}
-- Reads `path` ("data/mode/mode2.dat") from the host. Returns the text and where it came from ("host" for
-- game/dat_text/<path>, "file" for the game folder's own file), or nil.
function data_text.read(path)
    local ok, text = pcall(engine.read_resource, "game/dat_text/" .. path)
    if ok and type(text) == "string" and text ~= "" then return text, "host" end
    local raw
    ok, raw = pcall(engine.read_resource, path)
    if not ok or type(raw) ~= "string" or raw == "" then return nil end
    if path:sub(-4):lower() ~= ".dat" then return raw, "file" end
    local text_of = decoded[raw]
    if text_of == nil then
        text_of = data_text.decode(raw) or false
        decoded[raw] = text_of
    end
    if text_of then return text_of, "file" end
    return nil
end

-- Forgets the files decoded so far (tests).
function data_text.reset() decoded = {} end

return data_text
