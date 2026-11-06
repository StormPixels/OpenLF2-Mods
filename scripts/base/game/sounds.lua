-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local constants = require("base/game/constants")
local sd_text = require("base/game/sd_text")
local system_data = require("base/game/system_data")
local spatialization = constants.sound_spatialization
local sounds = {}

local function cdiv(a, b)
    local q = a / b
    if q >= 0 then return math.floor(q) end
    return math.ceil(q)
end

local fixed = {[0] = "data/001.wav", "data/002.wav", "data/006.wav", "data/010.wav",
    "data/011.wav", "data/004.wav", "data/016.wav", "data/017.wav", "data/020.wav",
    "data/021.wav", "data/025.wav", "data/032.wav", "data/033.wav", "data/039.wav",
    "data/065.wav", "data/066.wav", "data/068.wav", "data/085.wav"}
sounds.fixed_files = fixed
-- Pan and volume each sound buffer last accepted; buffers persist for the whole session.
local last_pan = {}
local last_volume = {}

sounds.menu = {join = "data/m_join.wav", ok = "data/m_ok.wav", cancel = "data/m_cancel.wav",
    pass = "data/m_pass.wav", finish = "data/m_end.wav"}

-- Data files write Windows paths; resources use lowercase forward slashes.
function sounds.canonical(path)
    return (path:lower():gsub("\\", "/"))
end

-- LF2 Darkfiren's data\sound.dat: the `file:` lines of its <sound> block replace the built-in list of the eighteen
-- fixed sound buffers (index 0 first). Loaded on first use; without the file the built-in list stays.
local max_fixed = 1000
local settled = false

function sounds.parse_list(text)
    local list = {}
    for _, block in ipairs(sd_text.scan(text).blocks) do
        if block.name == "sound" then
            for _, line in ipairs(block.lines) do
                for _, pair in ipairs(sd_text.pairs_of_line(line)) do
                    if pair[1] == "file" and pair[2] ~= "" and #list < max_fixed then list[#list + 1] = sounds.canonical(pair[2]) end
                end
            end
        end
    end
    return list
end

-- Loads sound.dat now (from `text` when given, else through the engine). The shared table sounds.fixed_files is
-- refilled in place. Returns true when the file's list is in use.
function sounds.load(text)
    local message
    if text == nil then text, message = sd_text.read("data/sound.dat") end
    if text == nil then
        if not sd_text.not_ready(message) then settled = true end
        return false
    end
    settled = true
    local list = sounds.parse_list(text)
    if #list == 0 then return false end
    for key in pairs(fixed) do fixed[key] = nil end
    for index, path in ipairs(list) do fixed[index - 1] = path end
    return true
end

-- The simultaneous sound limit; fx_constants.max_sounds (AI 3) when that module exists, else 20.
local function max_sounds()
    local ok, constants_fx = pcall(require, "base/game/fx_constants")
    local value = ok and type(constants_fx) == "table" and constants_fx.max_sounds or nil
    return type(value) == "number" and value > 0 and value or 20
end

local function ensure()
    if not settled then sounds.load() end
end

-- system.dat <sound>: ids whose sounds play at the centre of the screen and ignore the boundaries (id 998, etc).
function sounds.ignores_bounds(id)
    return system_data.ids("sound")[id] == true
end

local function hear(distance)
    distance = math.abs(distance)
    if distance < spatialization.full_volume_radius then return 100 end
    if distance < spatialization.audible_radius then return cdiv((spatialization.audible_radius - distance) * 100, spatialization.audible_radius - spatialization.full_volume_radius) end
    return 0
end

-- Two "ears" 200 and 600 px right of the camera hear a sound fully within 200 px, fading to
-- nothing at 400 px.
local function ears(camera, x)
    local offset = x - camera
    return hear(offset - spatialization.left_ear_offset), hear(offset - spatialization.right_ear_offset)
end

-- system.dat <sound>: a sound of such an id is not limited by the screen: off-screen it still plays as if it
-- happened at the nearest edge of the hearing area. [UNCERTAIN] the exact pan and volume.
local function unbounded(camera, x, id)
    if id ~= nil and system_data.ids("sound")[id] then
        return math.max(camera + spatialization.left_ear_offset, math.min(camera + spatialization.right_ear_offset, x))
    end
    return x
end

local function queue(state, bank, key, x, id)
    state.sound_queue = state.sound_queue or {}
    local channel = state.sound_queue[bank .. key]
    if not channel then
        channel = {bank = bank, resource = bank == "fixed" and fixed[key] or key, left = 0, right = 0}
        state.sound_queue[bank .. key] = channel
        state.sound_order = state.sound_order or {}
        state.sound_order[#state.sound_order + 1] = channel
    end
    local left, right = ears(state.camera or 0, unbounded(state.camera or 0, x, id))
    channel.left = channel.left + left
    channel.right = channel.right + right
end

function sounds.item(state, x, path, id)
    if path then queue(state, "item", sounds.canonical(path), x, id) end
end

function sounds.effect(state, x, channel, id)
    ensure()
    if fixed[channel] then queue(state, "fixed", channel, x, id) end
end

function sounds.buffer_play(channel)
    ensure()
    local resource = fixed[channel]
    return {resource = resource, volume = last_volume[resource] or 0, pan = last_pan[resource] or 0}
end

-- Menu and jingle sounds play at once without panning, at the master volume.
function sounds.direct(state, name)
    state.direct_sounds = state.direct_sounds or {}
    state.direct_sounds[#state.direct_sounds + 1] = sounds.menu[name]
end

function sounds.flush(state, master)
    ensure()
    master = master or require("base/game/music").master
    local output = {}
    for _, resource in ipairs(state.direct_sounds or {}) do
        -- A ready command (sounds.buffer_play) keeps its own volume and pan.
        if type(resource) == "table" then output[#output + 1] = resource
        elseif master > 0 then output[#output + 1] = {resource = resource, pan = 0, volume = cdiv((master - 100) * 3800, 100)} end
    end
    state.direct_sounds = nil
    local order = state.sound_order or {}
    -- At most max_sounds (20, fx_constants) different sounds play at once: when more are audible, the loudest
    -- (nearest) ones are kept, the earlier queued winning ties; the rest are dropped. Menu sounds do not count.
    local limit = max_sounds()
    local heard = {}
    for _, channel in ipairs(order) do
        channel.strength = math.min(channel.left + channel.right, 100)
        if channel.strength > 0 and master > 0 then heard[#heard + 1] = channel end
    end
    local dropped = {}
    if #heard > limit then
        local ranked = {}
        for position, channel in ipairs(heard) do ranked[position] = {channel = channel, position = position} end
        table.sort(ranked, function(a, b)
            if a.channel.strength ~= b.channel.strength then return a.channel.strength > b.channel.strength end
            return a.position < b.position
        end)
        for rank = limit + 1, #ranked do dropped[ranked[rank].channel] = true end
    end
    for _, bank in ipairs({"item", "fixed"}) do
        for _, channel in ipairs(order) do
            if channel.bank == bank then
                local strength = channel.strength
                if strength > 0 and master > 0 and not dropped[channel] then
                    -- Ear totals can exceed 100 each; DirectSound rejects a pan outside +/-10000
                    -- and the buffer keeps the pan it had (assumed from the API contract).
                    local pan = cdiv((channel.right - channel.left) * 1500, 100)
                    if pan < -10000 or pan > 10000 then pan = last_pan[channel.resource] or 0 end
                    last_pan[channel.resource] = pan
                    local volume = cdiv((master - 100) * 3800, 100) + cdiv((strength - 100) * 2000, 100)
                    last_volume[channel.resource] = volume
                    output[#output + 1] = {resource = channel.resource, pan = pan, volume = volume}
                end
            end
        end
    end
    state.sound_queue, state.sound_order = nil, nil
    return output
end
return sounds
