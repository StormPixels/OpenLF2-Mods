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
local default_keys = {words[1].keys, words[2].keys}
local word_limits = {7, 15}
local words_settled = false

-- The key codes of a cheat word of system.dat (`cheat1:` up to 7 characters, `cheat2:` up to 15): capital letters,
-- digits and the period. nil when the text is missing, too long or holds anything else.
-- [UNCERTAIN] the readme says "letter limit is 7 / 15, only capital letters" and "if removed the default is used";
-- a word that breaks the rules also falls back to the default here (the original's reaction is not documented).
function unlock.word_keys(text, limit)
    if type(text) ~= "string" or text == "" or #text > limit then return nil end
    local keys = {}
    for index = 1, #text do
        local char = text:sub(index, index)
        if char:match("[A-Z0-9]") then keys[index] = char:byte()
        elseif char == "." then keys[index] = 0xbe
        else return nil end
    end
    return keys
end

local function same_keys(a, b)
    if #a ~= #b then return false end
    for index = 1, #a do if a[index] ~= b[index] then return false end end
    return true
end

-- Takes the two cheat words from system.dat (`cheat1:`, `cheat2:`), the defaults LF2.NET and HEROFIGHTER.COM where
-- they are missing or invalid. Runs by itself on the first key input after system.dat is readable; returns false
-- while the game data is not attached yet.
function unlock.configure_words()
    local names = {"cheat1", "cheat2"}
    system_data.string("cheat1", nil)  -- reads system.dat
    if not system_data.loaded() then return false end
    for index, word in ipairs(words) do
        local keys = unlock.word_keys(system_data.string(names[index], nil), word_limits[index]) or default_keys[index]
        if not same_keys(word.keys, keys) then
            word.keys = keys
            progress[index] = 0
        end
    end
    words_settled = true
    return true
end

-- Back to the default words and to configuring again at the next key input (tests, a changed game folder).
function unlock.reset_words()
    for index, word in ipairs(words) do word.keys = default_keys[index] end
    progress[1], progress[2] = 0, 0
    words_settled = false
end
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
    if not words_settled then unlock.configure_words() end
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

-- The game file that keeps the keys: system.dat `file:` (data\\saves.txt by default), as a resource path.
local function saves_path()
    return (system_data.string("file", "data\\saves.txt"):lower():gsub("\\", "/"))
end

-- The keys config.json keeps when the saves file could not be written (a read-only installer, a failed write).
local function stored_keys()
    local keys = {}
    if type(engine) ~= "table" or type(engine.read_settings) ~= "function" then return keys end
    local ok, document = pcall(engine.read_settings)
    local list = ok and type(document) == "table" and type(document.unlock) == "table" and document.unlock.keys or nil
    if type(list) == "table" then
        for _, key in ipairs(list) do
            if type(key) == "number" and key >= 10 and key <= 1000 and key == math.floor(key) then keys[key] = true end
        end
    end
    return keys
end

local function ensure_saves()
    if saves_settled then return end
    local text, message = sd_text.read(saves_path())
    if text then unlock.keys, saves_settled = unlock.parse_saves(text), true
    elseif not sd_text.not_ready(message) then saves_settled = true end
    if saves_settled then
        for key in pairs(stored_keys()) do unlock.keys[key] = true end  -- keys saved to config.json earlier
    end
end

-- Stores the keys: in the game's saves file (a folder game; engine.write_game_file) like the original, otherwise,
-- when the data cannot be written, in config.json under `unlock.keys`. Never raises.
local function persist()
    local text = unlock.serialize()
    if type(unlock.on_change) == "function" then pcall(unlock.on_change, text) end
    if type(engine) ~= "table" then return false end
    if type(engine.write_game_file) == "function" then
        local ran, written = pcall(engine.write_game_file, saves_path(), text)
        if ran and written == true then return true end
    end
    if type(engine.read_settings) ~= "function" or type(engine.write_settings) ~= "function" then return false end
    local ran, document = pcall(engine.read_settings)
    if not ran or type(document) ~= "table" then document = {} end
    local list = {}
    for key in pairs(unlock.keys) do list[#list + 1] = key end
    table.sort(list)
    document.version = document.version or 1
    document.unlock = {keys = list}
    local saved, stored = pcall(engine.write_settings, document)
    return saved and stored == true
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
    persist()
    return true
end

-- LF2 Darkfiren difficulty locks (system.dat `bound:`, "difficulty lock for crazy and dummy only"): 0 none, 1 Crazy is
-- locked until the LF2.NET cheat, 2 Dummy until the HEROFIGHTER.COM cheat, 3 both. Without the tag (or with a value
-- outside 0..3) Crazy is locked by LF2.NET, the way the game has always had it.
function unlock.difficulty_lock()
    local value = system_data.number("bound", 1)
    if type(value) ~= "number" or value < 0 or value > 3 then return 1 end
    return math.floor(value)
end

function unlock.crazy_allowed()
    return unlock.difficulty_lock() % 2 == 0 or unlock.flags.characters == 1
end

function unlock.dummy_allowed()
    return math.floor(unlock.difficulty_lock() / 2) % 2 == 0 or unlock.flags.function_keys == 1
end

-- May this difficulty be chosen? Crazy (constants.difficulties.crazy) and, when the game defines it, Dummy
-- (constants.difficulties.dummy) follow the locks above; every other level is always open. [UNCERTAIN] the number
-- of Dummy: OpenLF2 has no such level yet, so without constants.difficulties.dummy only Crazy is locked.
function unlock.difficulty_allowed(level)
    local difficulties = require("base/game/constants").difficulties
    if level == difficulties.crazy then return unlock.crazy_allowed() end
    if difficulties.dummy ~= nil and level == difficulties.dummy then return unlock.dummy_allowed() end
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
