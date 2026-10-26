-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- OpenLF2 extension: the settings of the on-screen controls (base/ui/touch_gamepad): where the seven round
-- buttons are, how big, which key each presses, and how opaque each group is. They live in config.json's
-- "options" member as `onscreen`; this module holds the defaults and checks whatever was saved.
local constants = require("base/game/constants")
local virtual_keys = constants.virtual_keys
local onscreen = {}

-- The pad and the action buttons, in the order the settings list them.
onscreen.controls = {"up", "down", "left", "right", "attack", "jump", "defend"}
-- The opacity groups: the pad, the action buttons, the F button and its grid, and the menu buttons.
onscreen.groups = {"pad", "action", "functions", "menu"}
-- The letters player 1's actions are held with; a button on "auto" holds its own letter, any other key
-- is pressed as a keyboard key, so the key set of the controls settings decides what it does.
onscreen.letters = {up = "u", down = "d", left = "l", right = "r", attack = "c", jump = "b", defend = "f"}

-- The keys a button can be set to, in the order of the key grid: "auto" first (the default), then A-Z,
-- 1-0, the arrows, space, enter, escape and tab. `code` is the virtual key.
onscreen.keys = {{name = "auto", label = "DEF"}}
for index = 0, 25 do
    onscreen.keys[#onscreen.keys + 1] = {name = string.char(97 + index), label = string.char(65 + index), code = 0x41 + index}
end
for index = 1, 10 do
    local digit = index % 10
    onscreen.keys[#onscreen.keys + 1] = {name = tostring(digit), label = tostring(digit), code = 0x30 + digit}
end
for _, entry in ipairs({{"up", "^", virtual_keys.up}, {"down", "v", virtual_keys.down}, {"left", "<", virtual_keys.left},
    {"right", ">", virtual_keys.right}, {"space", "SPC", virtual_keys.space}, {"enter", "ENT", virtual_keys.enter},
    {"escape", "ESC", virtual_keys.escape}, {"tab", "TAB", virtual_keys.tab}}) do
    onscreen.keys[#onscreen.keys + 1] = {name = entry[1], label = entry[2], code = entry[3]}
end
local key_by_name = {}
for _, key in ipairs(onscreen.keys) do key_by_name[key.name] = key end
function onscreen.key(name) return key_by_name[name] end

-- x and y are fractions of the window (its edges, so the bars of a letterboxed picture count), the size 1
-- is the normal one.
local default_buttons = {
    up = {x = 0.175, y = 0.528}, down = {x = 0.175, y = 0.850},
    left = {x = 0.084, y = 0.689}, right = {x = 0.266, y = 0.689},
    attack = {x = 0.903, y = 0.817}, jump = {x = 0.825, y = 0.617}, defend = {x = 0.728, y = 0.828},
}

function onscreen.defaults()
    local buttons = {}
    for name, place in pairs(default_buttons) do buttons[name] = {key = "auto", x = place.x, y = place.y, size = 1} end
    return {show = true, opacity = {pad = 7, action = 7, functions = 7, menu = 7}, buttons = buttons}
end

local function number(value, default, low, high)
    if type(value) ~= "number" or value ~= value then return default end
    return math.max(low, math.min(high, value))
end

-- The saved settings with anything missing or invalid replaced by its default.
function onscreen.normalize(saved)
    local result = onscreen.defaults()
    if type(saved) ~= "table" then return result end
    if type(saved.show) == "boolean" then result.show = saved.show end
    if type(saved.opacity) == "table" then
        for _, group in ipairs(onscreen.groups) do
            result.opacity[group] = math.floor(number(saved.opacity[group], result.opacity[group], 1, 10))
        end
    end
    if type(saved.buttons) == "table" then
        for name, spec in pairs(result.buttons) do
            local entry = saved.buttons[name]
            if type(entry) == "table" then
                if type(entry.key) == "string" and key_by_name[entry.key] then spec.key = entry.key end
                spec.x = number(entry.x, spec.x, 0, 1)
                spec.y = number(entry.y, spec.y, 0, 1)
                spec.size = number(entry.size, spec.size, 0.5, 2.5)
            end
        end
    end
    return result
end

return onscreen
