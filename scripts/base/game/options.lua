-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- OpenLF2's own settings, which the original game does not have. They
-- live in config.json's "options" member, next to the original's controls and recording values.
local unlock = require("base/game/unlock")
local onscreen = require("base/game/onscreen")
local i18n = require("base/i18n/i18n")
local ui_modes = require("base/game/ui_modes")
local ui_hud = require("base/game/ui_hud")
local constants = require("base/game/constants")
local options = {}

-- The battlefield layouts: "classic" and "expand" are built into the code (so the game runs without a data/mode.dat);
-- every other one is a mode of the game's data/mode.dat (see game/ui_modes), stored as "mode:<file>". The widths and
-- player slots of those come from the mode.dat entry (`respond`; mode3.dat has ten player slots).
-- What the "Battlefield layout" row offers, in the dropdown's order.
function options.battlefield_layouts() return ui_modes.layout_choices() end
-- The text the dropdown shows for a layout.
function options.layout_label(layout)
    return ui_modes.layout_label(layout) or i18n.tr(layout)
end
-- The width of the fixed picture a mode.dat layout draws on; nil for classic, expand and the 794 wide modes.
function options.wide_width(layout)
    local width = ui_modes.layout_width(layout)
    if width and width ~= constants.screen.width then return width end
    return nil
end
-- How many player slots a layout has: 10 in the 10 player layout, 8 otherwise.
function options.slot_count(layout)
    return ui_modes.slot_count(layout)
end
local function valid_layout(value)
    return ui_modes.resolve(value) ~= nil
end
-- The layout of a game nobody has played yet: the first mode of mode.dat, classic when the game has none.
local function default_layout()
    return ui_modes.default_layout()
end

-- Every valid value, in the dropdown's order. "xbrz" is a shader: the host offers it only on
-- renderers that can run it (see options.available_filters), but a saved choice stays valid.
options.upscaling_filters = {"nearest", "linear", "xbrz"}
-- The values to offer: `features` is what the host reported ({xbrz = true} when it can run the shader).
function options.available_filters(features)
    local list = {}
    for _, filter in ipairs(options.upscaling_filters) do
        if filter ~= "xbrz" or (features and features.xbrz) then list[#list + 1] = filter end
    end
    return list
end
-- The values to offer: the default language always, the others when the host can draw TrueType text
-- (`features.text`, see i18n.host).
function options.available_languages(features)
    local list = {"default"}
    if features and features.text then
        for _, language in ipairs(i18n.languages) do list[#list + 1] = language end
    end
    return list
end
-- On-screen gamepad layout, in pixels of the 794x550 viewport measured from the window's edges
-- (so it can sit in the letterbox bars): the stick's `left` counts from the left edge, each
-- button's `right` from the right edge, and `bottom` from the bottom edge. Sizes are radii.
-- `touch.tolerance` is the press tolerance.
local gamepad_defaults = {
    stick = {left = 125, bottom = 110, radius = 56},
    -- The digipad (a fixed cross) used instead of the stick when `digipad` is on; `radius` is the
    -- length of its arms (the cross is twice that wide); `left` and `bottom` keep it clear of the edges.
    dpad = {left = 160, bottom = 160, radius = 110},
    c = {right = 188, bottom = 92, radius = 44},
    b = {right = 180, bottom = 186, radius = 32},
    f = {right = 282, bottom = 150, radius = 32},
    -- How far (pixels) outside a button's edge a finger still presses it; it presses the button
    -- whose edge is nearest.
    touch = {tolerance = 40},
    -- Small pause button in the top right corner: `right` and `top` count from those edges.
    pause = {right = 30, top = 30, radius = 16},
    -- Small fast-forward button in the top left corner: `left` and `top` count from those edges.
    fast = {left = 30, top = 30, radius = 16},
    -- Chords of defend (D), jump (J) and attack (A), a column on the right edge; disabled unless
    -- the character has the move.
    da = {right = 72, bottom = 250, radius = 26},
    dj = {right = 72, bottom = 165, radius = 26},
    daj = {right = 72, bottom = 80, radius = 26},
}
-- The game folders of LF2_ENGINE (Android; the host lists them in "game/game_list": the opened game's name
-- first, then every selectable name, a line each). Elsewhere the list is empty and the option is hidden.
local game_list
local function read_games()
    if game_list then return game_list end
    game_list = {current = "", names = {}}
    local ok, text = pcall(engine.read_resource, "game/game_list")
    if ok and type(text) == "string" then
        local first = true
        for line in text:gmatch("[^\n]+") do
            if first then
                game_list.current, first = line, false
            else
                game_list.names[#game_list.names + 1] = line
            end
        end
    end
    return game_list
end
function options.game_names() return read_games().names end
-- The text of a game's dropdown value: the name, or the opened game's name for none (or a folder that is gone).
function options.game_label(value)
    local list = read_games()
    for _, name in ipairs(list.names) do
        if name == value then return value end
    end
    return list.current
end
-- Whether `value` names another game than the one running; false where the host lists no games.
function options.game_differs(value)
    local list = read_games()
    return #list.names > 0 and options.game_label(value) ~= list.current
end
-- A game folder name as saved: at most 64 characters, no control characters; "" picks the default game.
local function valid_game(value)
    return type(value) == "string" and #value <= 64 and not value:find("%c")
end
local defaults = {game = "", gamepad = gamepad_defaults, onscreen = onscreen.defaults(), unlock_characters = false, upscaling_filter = "linear", fullscreen = false, digipad = true, show_fps = false,
    rumble = false, show_gamepad = false, language = "default", font_antialiasing = true,
    character_shading = false, projected_shadows = false,
    light_azimuth = -50, light_elevation = 70, shadow_blur = 2, shadow_opacity = 0.275}
local current

local function valid_filter(value)
    for _, filter in ipairs(options.upscaling_filters) do
        if value == filter then return true end
    end
    return false
end
local function copy_gamepad(layout)
    local result = {}
    for name, entry in pairs(gamepad_defaults) do
        result[name] = {}
        for key, default in pairs(entry) do
            local value = type(layout) == "table" and type(layout[name]) == "table" and layout[name][key]
            if type(value) ~= "number" or value ~= value or value < 0 or value > 2000 or (key == "radius" and value < 8) then
                value = default
            end
            result[name][key] = value
        end
    end
    return result
end
local function angle(value, default, low, high)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return default end
    return math.max(low, math.min(high, value))
end
-- The name of a HUD style of data/frame.dat ("Default" is the built-in HUD, only for a game without a frame.dat).
local function valid_hud_style(value)
    return type(value) == "string" and #value >= 1 and #value <= 40 and value:find("^[%w_%-]+$") ~= nil and ui_hud.known(value)
end
local function copy(values)
    return {game = valid_game(values.game) and values.game or defaults.game,
        battlefield_layout = ui_modes.resolve(values.battlefield_layout) or default_layout(),
        gamepad = copy_gamepad(values.gamepad), onscreen = onscreen.normalize(values.onscreen), unlock_characters = values.unlock_characters,
        upscaling_filter = valid_filter(values.upscaling_filter) and values.upscaling_filter or defaults.upscaling_filter,
        fullscreen = values.fullscreen, digipad = values.digipad, show_fps = values.show_fps, rumble = values.rumble,
        show_gamepad = values.show_gamepad, font_antialiasing = values.font_antialiasing,
        character_shading = values.character_shading == true,
        projected_shadows = values.projected_shadows == true,
        light_azimuth = angle(values.light_azimuth, defaults.light_azimuth, -180, 180),
        light_elevation = angle(values.light_elevation, defaults.light_elevation, 12, 89),
        shadow_blur = math.floor(angle(values.shadow_blur, defaults.shadow_blur, 0, 8)),
        shadow_opacity = angle(values.shadow_opacity, defaults.shadow_opacity, 0, 1),
        language = i18n.is_language(values.language) and values.language or defaults.language,
        hud_style = valid_hud_style(values.hud_style) and values.hud_style or ui_hud.default_name()}
end

-- The saved options, or the defaults for anything missing or invalid.
function options.load()
    local document = engine.read_settings()
    local saved = type(document) == "table" and document.options
    local values = copy(defaults)
    if type(saved) == "table" then
        if type(saved.character_shading) == "boolean" then values.character_shading = saved.character_shading end
        if type(saved.projected_shadows) == "boolean" then values.projected_shadows = saved.projected_shadows end
        values.light_azimuth = angle(saved.light_azimuth, defaults.light_azimuth, -180, 180)
        values.light_elevation = angle(saved.light_elevation, defaults.light_elevation, 12, 89)
        values.shadow_blur = math.floor(angle(saved.shadow_blur, defaults.shadow_blur, 0, 8))
        values.shadow_opacity = angle(saved.shadow_opacity, defaults.shadow_opacity, 0, 1)
    end
    if type(saved) == "table" and type(saved.unlock_characters) == "boolean" then
        values.unlock_characters = saved.unlock_characters
    end
    if type(saved) == "table" and valid_filter(saved.upscaling_filter) then
        values.upscaling_filter = saved.upscaling_filter
    end
    if type(saved) == "table" and type(saved.fullscreen) == "boolean" then
        values.fullscreen = saved.fullscreen
    end
    if type(saved) == "table" and type(saved.digipad) == "boolean" then
        values.digipad = saved.digipad
    end
    if type(saved) == "table" and type(saved.show_fps) == "boolean" then
        values.show_fps = saved.show_fps
    end
    if type(saved) == "table" and type(saved.rumble) == "boolean" then
        values.rumble = saved.rumble
    end
    if type(saved) == "table" and type(saved.show_gamepad) == "boolean" then
        values.show_gamepad = saved.show_gamepad
    end
    if type(saved) == "table" and type(saved.font_antialiasing) == "boolean" then
        values.font_antialiasing = saved.font_antialiasing
    end
    if type(saved) == "table" and i18n.is_language(saved.language) then
        values.language = saved.language
    end
    if type(saved) == "table" then values.gamepad = copy_gamepad(saved.gamepad) end
    if type(saved) == "table" then values.onscreen = onscreen.normalize(saved.onscreen) end
    if type(saved) == "table" and valid_layout(saved.battlefield_layout) then
        values.battlefield_layout = ui_modes.resolve(saved.battlefield_layout)
    end
    if type(saved) == "table" and valid_hud_style(saved.hud_style) then values.hud_style = saved.hud_style end
    if type(saved) == "table" and valid_game(saved.game) then values.game = saved.game end
    current = values
    return copy(values)
end
function options.current()
    if not current then options.load() end
    return copy(current)
end

local function apply(before, after)
    i18n.use(after.language, after.font_antialiasing)
    if after.unlock_characters and not (before and before.unlock_characters) then
        unlock.flags.characters = 1
    elseif before and before.unlock_characters and not after.unlock_characters then
        unlock.flags.characters = 0
    end
end

local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for key, value in pairs(a) do
        if not same(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

-- At startup: load and apply the saved options, then rewrite config.json's "options" so it
-- lists every option: missing ones filled with defaults, invalid or unknown ones dropped.
function options.start()
    local loaded = options.load()
    apply(nil, loaded)
    local document, problem = engine.read_settings()
    if problem then return end
    if type(document) == "table" and same(document.options, loaded) then return end
    options.save(loaded)
end

-- Saves `values` into config.json (other members are kept) and applies what changed. Returns
-- true, or nil and a message; the options apply even when saving fails.
function options.save(values)
    local before = options.current()
    current = copy(values)
    apply(before, current)
    local document = engine.read_settings()
    if type(document) ~= "table" then document = {} end
    document.version = 1
    document.options = copy(current)
    return engine.write_settings(document)
end
return options
