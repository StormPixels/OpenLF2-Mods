-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- Which rule set the opened game folder needs. The host detects it ("game/kind", see DirectoryArchive::detect_profile)
-- and answers "original" (LF2 v2.0a as released), "modded" (the original engine layout with other data or another
-- lf2.exe, e.g. NTSD) or "darkfiren" (LF2 Darkfiren: system.dat and resource.dat) or "neora" (LF2 Neora: neora.dll). A file game_kind.txt in the
-- game folder forces the answer. Kept compatible with Lua 5.1/LuaJIT.
local game_kind = {}

local cached
local function read_kind()
    if cached then return cached end
    cached = "original"
    local ok, text = pcall(engine.read_resource, "game/kind")
    if ok and type(text) == "string" then
        local word = text:match("%a+")
        if word == "darkfiren" or word == "neora" or word == "modded" or word == "original" then cached = word end
    end
    return cached
end

-- "original", "modded" or "darkfiren".
function game_kind.name() return read_kind() end
function game_kind.is_darkfiren() return read_kind() == "darkfiren" end
function game_kind.is_neora() return read_kind() == "neora" end
-- True for the original and for its mods: the engine's built-in rules apply, no Darkfiren data files steer them.
function game_kind.is_original_engine() return read_kind() ~= "darkfiren" and read_kind() ~= "neora" end
function game_kind.is_modded() return read_kind() == "modded" end

return game_kind
