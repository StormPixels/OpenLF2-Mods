-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local title = {}
local constants = require("base/game/constants")
local navigation = require("base/ui/input")
local sounds = require("base/game/sounds")
local controls = require("base/ui/controls")
local font = require("base/ui/font")
local menu_sheet = "pe/menu_clip3"
local highlighted = {
    {32, 331, 210, 22, 289, 204},
    {18, 358, 238, 24, 275, 231},
    {0, 385, 275, 23, 257, 258},
    {0, 412, 275, 24, 257, 285},
    {33, 438, 206, 24, 290, 311},
    {42, 466, 188, 23, 299, 339},
    {0, 493, 277, 25, 257, 366},
    {55, 521, 165, 23, 312, 394},
}
local destinations = {"versus", "stage", "championship", "team_championship", "battle", "demo", "replay", "quit"}

function title.create(options)
    options = options or {}
    return {selection = 0, replay_disabled = false, vertical_offset = 0,
        background = (options.menu_seed or 0) % 13 + 1, input = navigation.create(),
        key_list = 0, pointer_x = 0, pointer_y = 0}
end

function title.set_replay_disabled(state, disabled)
    state.replay_disabled = disabled
end

function title.latch_input(state, held)
    for slot = 0, 7 do
        if held[slot] ~= "" then state.input.latched[slot] = true end
    end
end

function title.update(state, held, context)
    state.pointer_x, state.pointer_y = held.pointer_x, held.pointer_y
    local input = navigation.sample(state.input, held)
    if input == "u" or input == "d" or input == "c" then state.key_list = 0 end
    -- Original code processes up before down, then confirm in each input snapshot.
    if input:find("u", 1, true) then
        state.selection = (state.selection + 7) % 8
        if state.replay_disabled and state.selection == constants.title_entries.replay then state.selection = constants.title_entries.replay - 1 end
    end
    if input:find("d", 1, true) then
        state.selection = (state.selection + 1) % 8
        if state.replay_disabled and state.selection == constants.title_entries.replay then state.selection = constants.title_entries.quit end
    end
    if input:find("c", 1, true) then
        if state.selection < constants.title_entries.quit then sounds.direct(state, "ok") end
        context.action(destinations[state.selection + 1])
    end
    for _, sound in ipairs(sounds.flush(state)) do context.sound(sound.resource, sound.volume, sound.pan) end
    -- The key list counts down while shown; a click on the menu area shows it for 450 frames.
    state.showing_keys = state.key_list > 0
    if state.key_list > 0 then state.key_list = state.key_list - 1 end
    local x, y = held.pointer_x, held.pointer_y - state.vertical_offset
    if held.click and x >= 0xdf and x < 0x23e and y > 0xc2 and y < 0x1b0 and x ~= 0 then state.key_list = 450 end
end

-- The background picture is the classic 794 x 550 or any other width (a wider one such as LF2 Darkfiren's 1018 x 550). It
-- stands in the middle of the viewport, which is where the menu and the logo are, and a window of another shape shows
-- more or less of it: what the window has beyond the picture is painted with the picture's own outermost column,
-- stretched, and a picture wider than the window is cropped equally on both sides. The viewport stays 794 x 550, so
-- the menu, the pointer's coordinates and every other screen are untouched.
local picture_sizes = {}
-- Width and height of an original picture, read from its header (BMP or PNG); the classic size when it cannot be read.
local function picture_size(resource)
    local size = picture_sizes[resource]
    if size then return size[1], size[2] end
    size = {constants.screen.width, constants.screen.height}
    local ok, bytes = pcall(engine.read_resource, resource)
    if ok and type(bytes) == "string" then
        local width, height
        if #bytes >= 26 and bytes:sub(1, 2) == "BM" then
            local a, b, c, d, e, f, g, h = bytes:byte(19, 26)
            width = a + b * 256 + c * 65536 + d * 16777216
            height = e + f * 256 + g * 65536 + h * 16777216
            if height >= 2147483648 then height = 4294967296 - height end   -- a top-down bitmap stores it negative
        elseif #bytes >= 24 and bytes:sub(2, 4) == "PNG" then
            local a, b, c, d, e, f, g, h = bytes:byte(17, 24)
            width = a * 16777216 + b * 65536 + c * 256 + d
            height = e * 16777216 + f * 65536 + g * 256 + h
        end
        if width and height and width >= 1 and width <= 4096 and height >= 1 and height <= 4096 then size = {width, height} end
    end
    picture_sizes[resource] = size
    return size[1], size[2]
end

-- Paints [from, to) with one column of the picture stretched across it.
local function paint_side(context, picture, column, rows, from, to, offset)
    local x = from
    while x < to do
        local width = math.min(32, to - x)   -- the renderer scales a sprite 32 times at most
        local at = x
        if width < 2 then width, at = 2, to - 2 end   -- a scale of exactly 1 would be a plain sprite
        context.sprite(picture, {column, 0, 1, rows}, 0, offset, true, false, false, 0xffffff, width, at)
        x = x + width
    end
end

-- window_bounds: the window's edges in viewport coordinates (left, top, right, bottom), as flow.lua gets them from the host.
function title.draw(state, context, window_bounds)
    context.viewport(constants.screen.width, constants.screen.height, 18, 37, 101)
    local offset = state.vertical_offset
    local picture = "pe/menu_back" .. state.background
    local bounds
    if window_bounds then
        bounds = {left = math.floor(math.min(window_bounds.left or 0, 0)), top = math.floor(math.min(window_bounds.top or 0, 0)),
            right = math.ceil(math.max(window_bounds.right or 0, constants.screen.width)),
            bottom = math.ceil(math.max(window_bounds.bottom or 0, constants.screen.height))}
        -- Nothing to extend, or a size the renderer would refuse (a stale value from another screen's viewport).
        if (bounds.left == 0 and bounds.top == 0 and bounds.right == constants.screen.width and bounds.bottom == constants.screen.height)
                or bounds.right - bounds.left > 4096 or bounds.bottom - bounds.top > 4096 then
            bounds = nil
        end
    end
    local width, height = picture_size(picture)
    local x = math.floor((constants.screen.width - width) / 2)
    local left, right = bounds and bounds.left or 0, bounds and bounds.right or constants.screen.width
    if bounds then
        context.render_area(bounds.left, bounds.top, bounds.right - bounds.left, bounds.bottom - bounds.top)
    end
    if left < x then paint_side(context, picture, 0, height, left, x, offset) end
    if right > x + width then paint_side(context, picture, width - 1, height, x + width, right, offset) end
    context.image(picture, x, offset, true)
    -- The whole logo, with the "ver 2.0a" in its bottom-right corner (it was drawn in two pieces to leave it out).
    context.sprite("pe/menu_clip", {0, 41, 496, 80}, 153, 96 + offset, true)
    context.sprite(menu_sheet, {0, 116, 305, 213}, 244, 206 + offset, true)
    local replay = state.replay_disabled and {293, 504, 277, 25} or {405, 532, 277, 25}
    context.sprite(menu_sheet, replay, 257, 366 + offset, true)
    local frame = highlighted[state.selection + 1]
    context.sprite(menu_sheet, frame, frame[5], frame[6] + offset, false)
    if state.showing_keys then
        context.sprite("pe/menu_clip5", {0, 389, 530, 200}, 5, 0x27, true)
        local settings = controls.current()
        for set = 1, 4 do
            for row = 1, 7 do
                local label, kind = controls.key_label(settings.sets[set].keys[row])
                font.gdi(context, label, (set - 1) * 0x6c - kind + 0x82, 0x5d + (row - 1) * 0x14, 0xffffff, 0x122565)
            end
        end
    end
    context.image("pe/lf2_cursor", math.min(state.pointer_x, 0x307), math.min(state.pointer_y + 2, 0x217), true)
end
function title.describe(state)
    return string.format("selection=%d key_list=%d", state.selection, state.key_list)
end
return title
