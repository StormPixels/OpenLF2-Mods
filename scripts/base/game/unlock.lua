-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local sounds = require("base/game/sounds")
local sd_text = require("base/game/sd_text")
local system_data = require("base/game/system_data")
local unlock = {}

unlock.flags = {characters = 0, function_keys = 0}

-- Virtual-key codes of each word (0xbe is the period key) with its record bit, flag and buffer.
local words = {
    {keys = {0x4c, 0x46, 0x32, 0xbe, 0x4e, 0x45, 0x54}, bit = 1, flag = "characters", buffer = 3},
    {keys = {0x48, 0x45, 0x52, 0x4f, 0x46, 0x49, 0x47, 0x48, 0x54, 0x45, 0x52, 0xbe, 0x43, 0x4f, 0x4d},
        bit = 2, flag = "function_keys", buffer = 4},
}
local progress = {0, 0}
-- Marks waiting for the next frame that takes them (the key table's 'd' at 0xf9 / 0xf8).
local marked = {}
-- Held keys of the previous trace frame, to turn traces' held "#n" keys into key-downs.
local previous_keys = {}

-- One key-down: the next letter advances; repeating the previous letter keeps place; anything
-- else restarts. The last letter marks the word and keeps place, so repeating it marks again.
local function key_down(code)
    for index, word in ipairs(words) do
        local place = progress[index]
        if code == word.keys[place + 1] then
            if place + 1 == #word.keys then marked[word.bit] = true
            else progress[index] = place + 1 end
        elseif place == 0 or code ~= word.keys[place] then
            progress[index] = 0
        end
    end
end

-- Flips a flag and returns the sound command of its buffer.
local function toggle(word)
    unlock.flags[word.flag] = 1 - unlock.flags[word.flag]
    return sounds.buffer_play(word.buffer)
end

-- Feeds one frame's input (base/ui/controls): live key-downs in order, or for traces the keys
-- newly held since the previous frame in code order.
function unlock.observe(input)
    local presses = input.presses
    if not presses then
        presses = {}
        for code = 0, 255 do
            if input.keys[code] and not previous_keys[code] then presses[#presses + 1] = code end
        end
        previous_keys = {}
        for code in pairs(input.keys) do previous_keys[code] = true end
    end
    for _, code in ipairs(presses) do key_down(code) end
end

function unlock.take_pending()
    local bits = 0
    for _, word in ipairs(words) do
        if marked[word.bit] then marked[word.bit] = nil; bits = bits + word.bit end
    end
    return bits
end
function unlock.take_marks()
    local bits = unlock.take_pending()
    return bits, unlock.apply_recorded(bits)
end

-- A new network session starts with equal flags and empty word recognizers on both peers.
function unlock.reset_session()
    unlock.end_replay()
    unlock.flags.characters, unlock.flags.function_keys = 0, 0
    progress, marked, previous_keys = {0, 0}, {}, {}
end

-- A replay frame's recorded bits (byte 9 of the record) toggle the flags instead.
function unlock.apply_recorded(bits)
    local played = {}
    for _, word in ipairs(words) do
        if math.floor(bits / word.bit) % 2 == 1 then played[#played + 1] = toggle(word) end
    end
    return played
end

local saved
function unlock.begin_replay(characters, function_keys)
    saved = {characters = unlock.flags.characters, function_keys = unlock.flags.function_keys}
    unlock.flags.characters, unlock.flags.function_keys = characters, function_keys
end
function unlock.end_replay()
    if saved then unlock.flags.characters, unlock.flags.function_keys = saved.characters, saved.function_keys end
    saved = nil
end

-- For headless descriptions: "characters:function_keys" when either is set.
function unlock.describe()
    if unlock.flags.characters == 0 and unlock.flags.function_keys == 0 then return nil end
    return unlock.flags.characters .. ":" .. unlock.flags.function_keys
end

-- LF2 Darkfiren locks (interface I5). A `hidden:` value of a character, stage, mode or track says what opens it:
-- 0 always, 1 the LF2.NET cheat, 2 the HEROFIGHTER.COM cheat, 3 both cheats, 4 never, 10..1000 a key kept in
-- the saves file (system.dat `file:`, data\saves.txt) or every key when system.dat says `join: -1`.
-- [UNCERTAIN] The readme does not describe the layout of saves.txt (the shipped file is empty). Keys are read as
-- every integer 10..1000 found in the file, one per unlock; replace unlock.parse_saves if the real layout differs.
unlock.keys = {}
unlock.on_change = nil  -- optional function(text): called with unlock.serialize() after a new key was granted
local saves_settled = false

function unlock.parse_saves(text)
    local keys = {}
    for digits in (text or ""):gmatch("-?%d+") do
        local number = tonumber(digits)
        if number >= 10 and number <= 1000 then keys[number] = true end
    end
    return keys
end

function unlock.load_saves(text)
    unlock.keys, saves_settled = unlock.parse_saves(text), true
end

-- Forgets the keys so the next lookup reads the file again (tests, a changed game folder).
function unlock.reset_saves()
    unlock.keys, saves_settled = {}, false
end

local function ensure_saves()
    if saves_settled then return end
    local path = system_data.string("file", "data\\saves.txt")
    local text, message = sd_text.read((path:lower():gsub("\\", "/")))
    if text then unlock.keys, saves_settled = unlock.parse_saves(text), true
    elseif not sd_text.not_ready(message) then saves_settled = true end
end

-- The text to store in the saves file: one key per line, ascending.
function unlock.serialize()
    local list = {}
    for key in pairs(unlock.keys) do list[#list + 1] = key end
    table.sort(list)
    for index, key in ipairs(list) do list[index] = tostring(key) end
    return #list > 0 and table.concat(list, "\n") .. "\n" or ""
end

-- Marks a key (10..1000) as unlocked for this session. Returns true when it was new. The game has no script
-- function that writes a file yet: whoever has one sets unlock.on_change to save the text.
function unlock.grant(key)
    key = tonumber(key)
    if not key or key < 10 or key > 1000 or key ~= math.floor(key) then return false end
    ensure_saves()
    if unlock.keys[key] then return false end
    unlock.keys[key] = true
    if type(unlock.on_change) == "function" then pcall(unlock.on_change, unlock.serialize()) end
    return true
end

-- Does a `hidden:` value allow the item to be used? nil, 0 and negative values always allow (nothing locks).
-- [UNCERTAIN] 5..9 and values above 1000 are not described anywhere; they stay locked.
function unlock.allows(hidden)
    hidden = tonumber(hidden)
    if hidden == nil or hidden <= 0 then return true end
    hidden = math.floor(hidden)
    if hidden == 1 then return unlock.flags.characters == 1 end
    if hidden == 2 then return unlock.flags.function_keys == 1 end
    if hidden == 3 then return unlock.flags.characters == 1 and unlock.flags.function_keys == 1 end
    if hidden >= 10 and hidden <= 1000 then
        if system_data.number("join", 0) == -1 then return true end
        ensure_saves()
        return unlock.keys[hidden] == true
    end
    return false
end
return unlock
