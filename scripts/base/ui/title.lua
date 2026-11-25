-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local title = {}
local constants = require("base/game/constants")
local sd_menu_back = require("base/game/sd_menu_back")  -- HOOK(AI5): system.dat <menu_back_N>
local navigation = require("base/ui/input")
local sounds = require("base/game/sounds")
local controls = require("base/ui/controls")
local font = require("base/ui/font")
local menu_data = require("base/game/menu_data")  -- HOOK(AI5): data\\menu.dat
local ui_modes = require("base/game/ui_modes")
local user_options = require("base/game/options")
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

-- The chosen wide layout's mode file (mode4.dat, ...) has a <frame> picture and a <name> label that LF2 Darkfiren draws on this
-- menu (menu 2), at the top left of the window: {frame = {pic, x, y, keyed} or nil, name = {name, x, y, hexf, hexb} or nil},
-- or nil for the classic layouts and a mode file without them. Kept per layout; a layout whose file cannot be read yet is asked
-- again next frame.
local banners = {}
local function banner()
    local layout = user_options.current().battlefield_layout
    local key = tostring(layout)
    local cached = banners[key]
    if cached ~= nil then return cached or nil end
    local text = ui_modes.layout_text(layout)
    local value = false
    if text then
        local frame, name = ui_modes.frame(text), ui_modes.title(text)
        if frame or name then value = {frame = frame, name = name} end
    end
    local width = ui_modes.layout_width(layout)
    if text or not width or width == constants.screen.width then banners[key] = value end
    return value or nil
end

-- A Windows COLORREF (0xBBGGRR) as 0xRRGGBB; nil stays nil.
local function from_colorref(value)
    if not value then return nil end
    return (value % 256) * 65536 + (math.floor(value / 256) % 256) * 256 + math.floor(value / 65536) % 256
end

local function draw_banner(context)
    local mode = banner()
    if not mode then return end
    -- Anchored to the window's top-left corner, not to the 794 wide layout in the middle of it.
    local origin = context.origin
    local left, top = origin and origin.x or 0, origin and origin.y or 0
    if mode.frame then
        local resource = menu_data.picture(mode.frame.pic)
        if resource then context.image(resource, left + mode.frame.x, top + mode.frame.y, mode.frame.keyed) end
    end
    if mode.name then
        local label = (mode.name.name:gsub("_", " ")):sub(1, 100)
        font.gdi(context, label, left + mode.name.x, top + mode.name.y, from_colorref(mode.name.hexf) or 0xffffff,
            from_colorref(mode.name.hexb))
    end
end

function title.create(options)
    options = options or {}
    return {selection = 0, replay_disabled = false, vertical_offset = 0,
        background = (options.menu_seed or 0) % 13 + 1, menu_seed = options.menu_seed or 0, input = navigation.create(),
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
    state.menu_ticks = (state.menu_ticks or 0) + 1  -- HOOK(AI5)
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
    -- Jump ("b" in base/ui/controls) goes back from this menu (menu.dat's <menu2>) to the launch menu (<menu1>). A network
    -- game (replay_disabled) stays here: the launch menu would drop its connection.
    if input == "b" and not state.replay_disabled then context.action("launch") end
    for _, sound in ipairs(sounds.flush(state)) do context.sound(sound.resource, sound.volume, sound.pan) end
    -- The key list counts down while shown; a click on the menu area shows it for 450 frames.
    state.showing_keys = state.key_list > 0
    if state.key_list > 0 then state.key_list = state.key_list - 1 end
    local x, y = held.pointer_x, held.pointer_y - state.vertical_offset
    if held.click and x >= 0xdf and x < 0x23e and y > 0xc2 and y < 0x1b0 and x ~= 0 then state.key_list = 450 end
    -- menu.dat's <menu2_name>: a link under the pointer opens its address on a click.
    local names = menu_data.names(2)
    if names and held.click then
        for _, item in ipairs(menu_data.texts(names, x, y, font.gdi_width)) do
            if item.hover and item.url then
                sounds.direct(state, "ok")
                context.open_url(item.url)
                break
            end
        end
    end
end

-- One picture of menu.dat's <menu2>: its place (the built-in one when unset) and whether black is clear; `custom` is the
-- resource to draw instead of the built-in sprite of `sheet` (nil: the sprite).
local function draw_picture(context, data, custom, sheet, rectangle, x, y, keyed, offset)
    x, y = data and data.x or x, data and data.y or y
    if data and data.keyed ~= nil then keyed = data.keyed end
    if custom then context.image(custom, x, y + offset, keyed)
    else context.sprite(sheet, rectangle, x, y + offset, keyed) end
end

function title.draw(state, context)
    local back = sd_menu_back.view(2, state.menu_seed)  -- HOOK(AI5): block <menu_back_2> of system.dat (nil without one)
    local color = back and back.color or {18, 37, 101}
    context.viewport(constants.screen.width, constants.screen.height, color[1], color[2], color[3])
    local offset = state.vertical_offset
    if back then sd_menu_back.paint(context, back, state.menu_ticks, offset)
    else context.image("pe/menu_back" .. state.background, 0, offset, true) end
    -- The pictures: menu.dat's <menu2> moves them, and swaps in its own pictures when the game has them (`pic2:` of the base
    -- while a network game runs, which is when the recording entry is off).
    local layers = menu_data.pictures(2) or {}
    -- The whole logo, with the "ver 2.0a" in its bottom-right corner (it was drawn in two pieces to leave it out).
    local logo = layers[1]
    draw_picture(context, logo, logo and menu_data.picture(logo.pic), "pe/menu_clip", {0, 41, 496, 80}, 153, 96, true, offset)
    local base = layers[2]
    local base_picture = base and (state.replay_disabled and menu_data.picture(base.pic2) or menu_data.picture(base.pic))
    draw_picture(context, base, base_picture, menu_sheet, {0, 116, 305, 213}, 244, 206, true, offset)
    if not base_picture then
        -- The recording entry is drawn again, dimmed or lit; it moves with the base picture.
        local replay = state.replay_disabled and {293, 504, 277, 25} or {405, 532, 277, 25}
        context.sprite(menu_sheet, replay, 257 + (base and base.x or 244) - 244, 366 + offset + (base and base.y or 206) - 206, true)
    end
    local frame = highlighted[state.selection + 1]
    local lit = layers[state.selection + 3]
    draw_picture(context, lit, lit and menu_data.picture(lit.pic), menu_sheet, frame, frame[5], frame[6], false, offset)
    local names = menu_data.names(2)
    if names then
        for _, item in ipairs(menu_data.texts(names, state.pointer_x, state.pointer_y - offset, font.gdi_width)) do
            font.gdi(context, item.value, item.x, item.y + offset, item.color)
        end
    end
    draw_banner(context)
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
