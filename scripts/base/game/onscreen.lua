-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- OpenLF2 extension: the settings of the on-screen controls (base/ui/touch_gamepad). Seven controls, each with
-- its own place, size and opacity: the d-pad (one control, a cross of four arrows), attack, jump, defend, the F
-- button (it opens the grid of F1-F9), the button that shows or hides the controls and SET. They live in
-- config.json's "options" member as `onscreen`; this module holds the defaults and checks whatever was saved.
local constants = require("base/game/constants")
local virtual_keys = constants.virtual_keys
local onscreen = {}

-- The controls, in the order they are hit-tested and drawn.
onscreen.objects = {"dpad", "attack", "jump", "defend", "f", "toggle", "set"}
-- The four arrows of the d-pad, and the action buttons that carry one key each.
onscreen.directions = {"up", "down", "left", "right"}
onscreen.actions = {"attack", "jump", "defend"}
-- The letters player 1's actions are held with; a control on "auto" holds its own letter, any other key is
-- pressed as a keyboard key, so the key set of the controls settings decides what it does.
onscreen.letters = {up = "u", down = "d", left = "l", right = "r", attack = "c", jump = "b", defend = "f"}

-- The keys a control can be set to, in the order of the key grid: "auto" first (the default), then A-Z,
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

-- x and y are fractions of the window (its edges, so the bars of a letterboxed picture count), the size 1 is
-- the normal one, the opacity runs from 0 (invisible, the control still works) to 10.
local defaults = {
    dpad = {x = 0.175, y = 0.689}, attack = {x = 0.903, y = 0.817}, jump = {x = 0.825, y = 0.617},
    defend = {x = 0.728, y = 0.828}, f = {x = 0.07, y = 0.122}, toggle = {x = 0.5, y = 0.067}, set = {x = 0.93, y = 0.122},
}

function onscreen.defaults()
    local buttons = {}
    for name, place in pairs(defaults) do buttons[name] = {x = place.x, y = place.y, size = 1, opacity = 7} end
    buttons.dpad.keys = {up = "auto", down = "auto", left = "auto", right = "auto"}
    for _, name in ipairs(onscreen.actions) do buttons[name].key = "auto" end
    return {show = true, buttons = buttons}
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
    if type(saved.buttons) == "table" then
        for name, spec in pairs(result.buttons) do
            local entry = saved.buttons[name]
            if type(entry) == "table" then
                spec.x = number(entry.x, spec.x, 0, 1)
                spec.y = number(entry.y, spec.y, 0, 1)
                spec.size = number(entry.size, spec.size, 0.4, 3)
                spec.opacity = math.floor(number(entry.opacity, spec.opacity, 0, 10))
                if spec.key and type(entry.key) == "string" and key_by_name[entry.key] then spec.key = entry.key end
                if spec.keys and type(entry.keys) == "table" then
                    for _, direction in ipairs(onscreen.directions) do
                        local key = entry.keys[direction]
                        if type(key) == "string" and key_by_name[key] then spec.keys[direction] = key end
                    end
                end
            end
        end
    end
    return result
end

return onscreen
