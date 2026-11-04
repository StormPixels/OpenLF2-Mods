-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- Music controls and host requests follow the original game's music routines.
local constants = require("base/game/constants")
local sd_text = require("base/game/sd_text")
local music_volume = constants.music_volume
local music = {enabled = true, selected = nil, master = music_volume.maximum, queue = {}, sent_volume = nil}

-- The original game's eight tracks, used whenever the game has no bgm.dat (LF2 Darkfiren keeps its list there).
local default_tracks = {"bgm/main.wma", "bgm/stage1.wma", "bgm/stage2.wma", "bgm/stage3.wma", "bgm/stage4.wma",
    "bgm/stage5.wma", "bgm/boss1.wma", "bgm/boss2.wma"}
local default_names = {"Main Theme", "Stage 1", "Stage 2", "Stage 3", "Stage 4", "Stage 5", "Boss", "Final Boss"}

local function canonical(path) return (path:gsub("\\", "/"):lower()) end

-- LF2 Darkfiren's data\\bgm.dat. music.tracks (paths), music.names (display names) and music.info (one record per
-- track: name, file, boss, hex, hidden, modes, responds) follow it; without the file they are the original eight
-- tracks. They are plain fields (the game's Lua environment has no metatables): the built-in list is in place from
-- the start and music.load() replaces it once bgm.dat is read. music.flush() (once per frame), music.selectable and
-- music.menu_track retry the load until the game data is attached, so nothing else has to call music.load().
local max_tracks, max_filter = 200, 50
local settled = false

local function set_of(text, limit)
    local set, count = {}, 0
    for _, number in ipairs(sd_text.ints(text)) do
        if count < limit then set[number] = true; count = count + 1 end
    end
    return count > 0 and set or nil
end

-- Parses the text of bgm.dat: {tracks = {...}, menu1 = "bgm\\main.wma", menu2 = ..., volume = 100}.
-- `hex:` is kept as text and as a number when it is plain hexadecimal. [UNCERTAIN] how a track's `mode:` and
-- `respond:` numbers map to the game modes is not documented; they are kept as opaque number sets.
function music.parse_bgm(text)
    local scan = sd_text.scan(text)
    local result = {tracks = {}, menu1 = scan.scalars.menu_bgm1, menu2 = scan.scalars.menu_bgm2,
        volume = sd_text.int(scan.scalars.st_vol)}
    for _, block in ipairs(scan.blocks) do
        if block.name == "bgm_begin" and #result.tracks < max_tracks then
            local track = {}
            for _, line in ipairs(block.lines) do
                if line:find("<boss>", 1, true) then
                    track.boss = true
                    line = (line:gsub("<boss>", " "))
                end
                for _, pair in ipairs(sd_text.pairs_of_line(line)) do
                    local key, value = pair[1], pair[2]
                    if key == "name" then track.name = value
                    elseif key == "file" then track.file = value
                    elseif key == "hidden" then track.hidden = sd_text.int(value)
                    elseif key == "hex" then
                        track.hex_text = value
                        track.hex = tonumber((value:gsub("^#", ""):gsub("^0[xX]", "")), 16)
                    elseif key == "mode" then
                        track.modes = track.modes or {}
                        for number in pairs(set_of(value, max_filter) or {}) do track.modes[number] = true end
                    elseif key == "respond" then
                        track.responds = track.responds or {}
                        for number in pairs(set_of(value, max_filter) or {}) do track.responds[number] = true end
                    end
                end
            end
            if track.file and track.file ~= "" then result.tracks[#result.tracks + 1] = track end
        end
    end
    return result
end

local function install(parsed)
    local tracks, names, info = {}, {}, {}
    for index, track in ipairs(parsed.tracks) do
        tracks[index] = canonical(track.file)
        names[index] = ((track.name or ""):gsub("_", " "))
        info[index] = track
    end
    if #tracks == 0 then return false end
    music.tracks = tracks
    music.names = names
    music.info = info
    music.menu = {parsed.menu1, parsed.menu2}
    return true
end

-- Loads bgm.dat now: from `text` when given, else through the engine. Returns true when the file's list is in use.
function music.load(text)
    local message
    if text == nil then text, message = sd_text.read("data/bgm.dat") end
    if text == nil then
        if sd_text.not_ready(message) then return false end
        settled = true
        return false
    end
    settled = true
    return install(music.parse_bgm(text))
end

do
    local names, info = {}, {}
    for index, path in ipairs(default_tracks) do
        names[index] = default_names[index]
        info[index] = {name = default_names[index]:gsub(" ", "_"), file = path:gsub("/", "\\")}
    end
    music.tracks, music.names, music.info = default_tracks, names, info
end

-- Reads bgm.dat once the game data is attached (a no-op afterwards).
local function sync()
    if not settled then music.load() end
end

-- The path of the menu music (which = 1 first menu, 2 second menu; system.dat's menu_bgm1/menu_bgm2, stored in
-- bgm.dat too), or nil when the data says `[MU]` (muted). Defaults to bgm/main.wma.
function music.menu_track(which)
    sync()
    local system_data = require("base/game/system_data")
    local tag = system_data.string(which == 2 and "menu_bgm2" or "menu_bgm1", nil)
    local entry = music.menu and music.menu[which == 2 and 2 or 1] or nil
    local value = entry and entry ~= "" and entry or tag
    if value == nil then return "bgm/main.wma" end
    if value:find("[MU]", 1, true) then return nil end
    return canonical(value)
end

-- Track numbers (1-based) a menu may offer or Random may pick: `hidden:` must be allowed by unlock.allows, and a
-- track that lists `mode:` / `respond:` numbers needs the caller's `mode` / `respond` among them. A nil argument
-- means "no filter on that key".
function music.selectable(mode, respond)
    sync()
    local unlock = require("base/game/unlock")
    local list = {}
    for index, track in ipairs(music.info) do
        local ok = track.hidden == nil or unlock.allows(track.hidden)
        if ok and mode ~= nil and track.modes and not track.modes[mode] then ok = false end
        if ok and respond ~= nil and track.responds and not track.responds[respond] then ok = false end
        if ok then list[#list + 1] = index end
    end
    return list
end

-- A random selectable track number (engine.random only, so recordings stay deterministic); nil when none.
function music.random_index(mode, respond)
    local list = music.selectable(mode, respond)
    if #list == 0 then return nil end
    return list[engine.random(#list) + 1]
end

function music.play(path)
    if not music.enabled then return end
    music.queue[#music.queue + 1] = {"play", canonical(path)}
    music.stopped = false
end
function music.play_selected()
    if music.selected then music.play(music.selected) end
end
function music.stop()
    if music.stopped then return end
    music.queue[#music.queue + 1] = {"stop"}
    music.stopped = true
end
function music.resume()
    music.queue[#music.queue + 1] = {"resume"}
    music.stopped = false
end

function music.change_volume(step)
    music.master = math.max(0, math.min(music_volume.maximum, music.master + step))
end

function music.flush(context)
    sync()
    local volume = music.master == 0 and music_volume.muted or music.master * music_volume.gain - music_volume.offset
    if volume ~= music.sent_volume then
        context.music("volume", volume)
        music.sent_volume = volume
    end
    for _, request in ipairs(music.queue) do context.music(request[1], request[2]) end
    music.queue = {}
end
return music
