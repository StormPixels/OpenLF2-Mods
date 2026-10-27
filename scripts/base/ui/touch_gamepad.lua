-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- OpenLF2 extension: on-screen controls, shown only when the last input was touch-driven (other pages
-- already handle direct taps). Like the controls of PPSSPP:
--   * the d-pad is ONE control, a cross of four arrow icons; where a finger lies on it decides the directions
--     (a corner of the cross holds two), and the whole d-pad is moved, resized and made transparent as one;
--   * attack, jump and defend are icons of their own, each with its own place, size and opacity;
--   * the F button opens a 3x3 grid of F1-F9 beside it, a round button at the top centre shows or hides the
--     controls and SET opens the editor. These three have a place, a size and an opacity too.
-- SET: drag any control to move it (the grid follows the F button), choose its size and opacity (0 is
-- invisible, the control still works) and give it a keyboard key. The settings are saved (base/game/onscreen).
--
-- C++ only reports held fingers in viewport coordinates, plus the window's edges (letterbox bars lie beyond
-- the 794x550 picture); this module owns all hit-testing and draws as an overlay so it can sit in the bars.
-- Sizes are in units of u = a ninth of the window's height. The icons are the images under mods/base/onscreen
-- (stretched with a size and an alpha: context.icon).
--
-- Every finger gets a zone the first frame it is seen and keeps it until it lifts: "buttons" (holds what is
-- under it each frame, so one finger can slide from one control to the next), "functions" (the F grid), "drag"
-- (moves a control in edit mode), a one-shot "toggle"/"gear"/"ftoggle"/"widget", "blocked" (edit mode swallows
-- the rest) or "mouse": a finger on empty screen stays the page's pointer. Fingers of the other zones never
-- reach the page behind (`claims`).
local constants = require("base/game/constants")
local font = require("base/ui/font")
local onscreen = require("base/game/onscreen")
local gamepad = {}

local floor, ceil, max, min, sqrt, abs = math.floor, math.ceil, math.max, math.min, math.sqrt, math.abs
local default_screen = {left = 0, top = 0, right = constants.screen.width, bottom = constants.screen.height}

local names = {dpad = "D-PAD", attack = "ATTACK", jump = "JUMP", defend = "DEFEND", f = "F BUTTON", toggle = "SHOW/HIDE", set = "SET"}
local arrows = {up = "^", down = "v", left = "<", right = ">"}
local action_labels = {attack = "A", jump = "J", defend = "D"}
local pressed_tint = 0xffd940

local function icon_path(name) return "mods/base/onscreen/" .. name .. ".bmp" end

-- The host takes whole numbers only (a fraction is an invalid frame field), so text goes through here.
local function label(context, text, x, y, align, tint)
    font.draw(context, text, floor(x + 0.5), floor(y + 0.5), nil, tint, align)
end

local function clamp(value, low, high) return max(low, min(high, value)) end
local function contains(rect, x, y) return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h end
local function within(circle, x, y, factor) return sqrt((x - circle.x) ^ 2 + (y - circle.y) ^ 2) <= circle.r * factor end

-- Computes the fixed measures from the window's edges (again when they move: resize, fullscreen).
local function fit(state, screen)
    local old = state.screen
    if old and state.l and old.left == screen.left and old.top == screen.top and old.right == screen.right
       and old.bottom == screen.bottom then
        return
    end
    state.screen = screen
    local width, height = screen.right - screen.left, screen.bottom - screen.top
    state.l = {left = screen.left, top = screen.top, w = width, h = height, u = height / 9}
end

-- `config`: the saved settings (base/game/onscreen), checked here.
function gamepad.create(config)
    local state = {config = onscreen.normalize(config), zones = {}, held = {}, functions_held = {}, visible = false,
        functions_open = false, editing = false, picking = nil, dirty = false}
    state.shown = state.config.show
    fit(state, default_screen)
    return state
end

-- The chords of the old gamepad no longer exist; kept so callers need no change.
function gamepad.set_available() end

-- Geometry of the controls. The centre of a control, then its shape.
local function center_of(state, name)
    local spec, l = state.config.buttons[name], state.l
    return l.left + spec.x * l.w, l.top + spec.y * l.h
end
local menu_radius = {f = 0.5, toggle = 0.4, set = 0.5}
local function circle_of(state, name)
    local x, y = center_of(state, name)
    return {x = x, y = y, r = menu_radius[name] * state.l.u * state.config.buttons[name].size}
end
local function action_box(state, name)
    local x, y = center_of(state, name)
    local side = 1.5 * state.l.u * state.config.buttons[name].size
    return {x = x - side / 2, y = y - side / 2, w = side, h = side}
end
-- The d-pad is a 3x3 cross of `cell` sized arrows around its centre.
local function dpad_cell(state) return state.l.u * state.config.buttons.dpad.size end
local function dpad_box(state)
    local x, y = center_of(state, "dpad")
    local cell = dpad_cell(state)
    return {x = x - 1.5 * cell, y = y - 1.5 * cell, w = 3 * cell, h = 3 * cell}
end
-- The arrows' squares, by direction.
local function dpad_cells(state)
    local x, y = center_of(state, "dpad")
    local cell = dpad_cell(state)
    return {up = {x = x - cell / 2, y = y - 1.5 * cell, w = cell, h = cell}, down = {x = x - cell / 2, y = y + 0.5 * cell, w = cell, h = cell},
        left = {x = x - 1.5 * cell, y = y - cell / 2, w = cell, h = cell}, right = {x = x + 0.5 * cell, y = y - cell / 2, w = cell, h = cell}}
end
-- The directions a finger holds: it counts over the whole cross and a little beyond; a corner holds two.
local function dpad_directions(state, x, y)
    local cx, cy = center_of(state, "dpad")
    local cell = dpad_cell(state)
    local dx, dy = x - cx, y - cy
    if abs(dx) > 1.65 * cell or abs(dy) > 1.65 * cell then return nil end
    local dead = 0.5 * cell
    return {left = dx < -dead, right = dx > dead, up = dy < -dead, down = dy > dead}
end
-- The grid of F1-F9 hangs to the right of the F button and moves and grows with it.
local function grid_cells(state)
    local circle = circle_of(state, "f")
    local cell, gap = 1.6 * circle.r, 0.2 * circle.r
    local x0, y0 = circle.x + 1.4 * circle.r, circle.y - 0.9 * circle.r
    local cells = {}
    for number = 1, 9 do
        local index = number - 1
        cells[number] = {number = number, rect = {x = x0 + (index % 3) * (cell + gap), y = y0 + floor(index / 3) * (cell + gap), w = cell, h = cell}}
    end
    return cells
end
local function bounds_of(state, name)
    if name == "dpad" then return dpad_box(state) end
    if menu_radius[name] then
        local c = circle_of(state, name)
        return {x = c.x - c.r, y = c.y - c.r, w = 2 * c.r, h = 2 * c.r}
    end
    return action_box(state, name)
end

-- The edit panel (or the key grid while picking): its frame, its widgets (tappable rectangles) and its texts.
local function panel(state)
    local l = state.l
    local u = l.u
    local items, texts = {}, {}
    if state.picking then
        local cols, cell, gap = 11, 0.72 * u, 0.08 * u
        local rows = ceil(#onscreen.keys / cols)
        local grid_w, grid_h = cols * (cell + gap) - gap, rows * (cell + gap) - gap
        local frame_w, frame_h = grid_w + 0.8 * u, grid_h + 1.5 * u
        local frame_x, frame_y = l.left + (l.w - frame_w) / 2, l.top + (l.h - frame_h) / 2
        texts[#texts + 1] = {"PICK A KEY", frame_x + 0.4 * u, frame_y + 0.55 * u, "left"}
        for index, key in ipairs(onscreen.keys) do
            local number = index - 1
            items[#items + 1] = {widget = "pick:" .. key.name, label = key.label,
                rect = {x = frame_x + 0.4 * u + (number % cols) * (cell + gap),
                    y = frame_y + 1.0 * u + floor(number / cols) * (cell + gap), w = cell, h = cell}}
        end
        return {frame = {x = frame_x, y = frame_y, w = frame_w, h = frame_h}, items = items, texts = texts}
    end
    local frame_w, frame_h, row_h, button = 6.6 * u, 5.2 * u, 0.8 * u, 0.65 * u
    local selected = state.selected
    local frame_x = l.left + (l.w - frame_w) / 2
    if selected then -- beside the control being edited, on the other half of the window
        frame_x = center_of(state, selected) > l.left + l.w / 2 and l.left + 0.3 * u or l.left + l.w - frame_w - 0.3 * u
    end
    local frame_y = l.top + 1.2 * u
    local function row_center(row) return frame_y + 0.3 * u + row * row_h + row_h / 2 end
    local function stepper(row, widget, text)
        local center = row_center(row)
        items[#items + 1] = {widget = widget .. "-", label = "-", rect = {x = frame_x + 3.5 * u, y = center - button / 2, w = button, h = button}}
        items[#items + 1] = {widget = widget .. "+", label = "+", rect = {x = frame_x + 5.6 * u, y = center - button / 2, w = button, h = button}}
        texts[#texts + 1] = {text, frame_x + 4.95 * u, center - 8, "center"}
    end
    if selected then
        local spec = state.config.buttons[selected]
        texts[#texts + 1] = {"SET: " .. names[selected], frame_x + 0.4 * u, row_center(0) - 8, "left"}
        texts[#texts + 1] = {"SIZE", frame_x + 0.4 * u, row_center(1) - 8, "left"}
        stepper(1, "size", string.format("%.1f", spec.size))
        texts[#texts + 1] = {"OPACITY", frame_x + 0.4 * u, row_center(2) - 8, "left"}
        stepper(2, "opacity", tostring(spec.opacity))
        if spec.keys then
            texts[#texts + 1] = {"KEYS", frame_x + 0.4 * u, row_center(3) - 8, "left"}
            for index, direction in ipairs(onscreen.directions) do
                local key = onscreen.key(spec.keys[direction])
                items[#items + 1] = {widget = "key:" .. direction, label = spec.keys[direction] == "auto" and arrows[direction] or key.label,
                    rect = {x = frame_x + 2.2 * u + (index - 1) * 1.1 * u, y = row_center(3) - button / 2, w = 1.0 * u, h = button}}
            end
        elseif spec.key then
            texts[#texts + 1] = {"KEY", frame_x + 0.4 * u, row_center(3) - 8, "left"}
            local key = onscreen.key(spec.key)
            items[#items + 1] = {widget = "key", label = spec.key == "auto" and action_labels[selected] or key.label,
                rect = {x = frame_x + 2.2 * u, y = row_center(3) - button / 2, w = 4.0 * u, h = button}}
        end
    else
        texts[#texts + 1] = {"SET: TAP A CONTROL", frame_x + 0.4 * u, row_center(0) - 8, "left"}
        texts[#texts + 1] = {"DRAG IT TO MOVE", frame_x + 0.4 * u, row_center(1) - 8, "left"}
    end
    items[#items + 1] = {widget = "reset", label = "RESET", rect = {x = frame_x + 0.4 * u, y = frame_y + frame_h - 1.0 * u, w = 2.6 * u, h = 0.75 * u}}
    items[#items + 1] = {widget = "done", label = "DONE", rect = {x = frame_x + frame_w - 3.0 * u, y = frame_y + frame_h - 1.0 * u, w = 2.6 * u, h = 0.75 * u}}
    return {frame = {x = frame_x, y = frame_y, w = frame_w, h = frame_h}, items = items, texts = texts}
end
gamepad.panel = panel -- the edit panel's widgets and texts, for tests
gamepad.grid = grid_cells -- the F grid's cells, for tests

local function release(state)
    for _, zone in pairs(state.zones) do
        if zone.kind == "drag" then state.dirty = true end
    end
    state.zones, state.held, state.functions_held = {}, {}, {}
end

-- Does what a tapped widget says; edits are saved (state.dirty) by `take_changes`.
local function perform(state, widget)
    local config = state.config
    local selected = state.selected and config.buttons[state.selected]
    if widget == "done" then
        state.editing, state.picking, state.selected = false, nil, nil
    elseif widget == "reset" then
        local show = config.show
        state.config = onscreen.defaults()
        state.config.show = show
    elseif widget == "key" then
        if selected and selected.key then state.picking = {} end
    elseif widget:sub(1, 4) == "key:" then
        local direction = widget:sub(5)
        if selected and selected.keys and selected.keys[direction] then state.picking = {direction = direction} end
    elseif widget == "closepicker" then
        state.picking = nil
    elseif widget == "size-" or widget == "size+" then
        if selected then selected.size = clamp(floor((selected.size + (widget == "size+" and 0.1 or -0.1)) * 10 + 0.5) / 10, 0.4, 3) end
    elseif widget == "opacity-" or widget == "opacity+" then
        if selected then selected.opacity = clamp(selected.opacity + (widget == "opacity+" and 1 or -1), 0, 10) end
    elseif widget:sub(1, 5) == "pick:" then
        local name = widget:sub(6)
        if selected and onscreen.key(name) and state.picking then
            if state.picking.direction then selected.keys[state.picking.direction] = name else selected.key = name end
        end
        state.picking = nil
    end
    state.dirty = true
end

-- The zone a finger starts in, or nil when it touches the empty screen.
local function hit(state, x, y, mode)
    if state.editing then
        local p = panel(state)
        for _, item in ipairs(p.items) do
            if contains(item.rect, x, y) then return {kind = "widget", widget = item.widget} end
        end
        if state.picking then return {kind = "widget", widget = "closepicker"} end
        if contains(p.frame, x, y) then return {kind = "blocked"} end
        for _, name in ipairs({"set", "f", "toggle", "dpad", "attack", "jump", "defend"}) do
            local box = bounds_of(state, name)
            local pad = 0.1 * max(box.w, box.h)
            if contains({x = box.x - pad, y = box.y - pad, w = box.w + 2 * pad, h = box.h + 2 * pad}, x, y) then
                local cx, cy = center_of(state, name)
                return {kind = "drag", name = name, dx = cx - x, dy = cy - y}
            end
        end
        return {kind = "blocked"}
    end
    if within(circle_of(state, "set"), x, y, 1.5) then return {kind = "gear"} end
    if within(circle_of(state, "toggle"), x, y, 2) then return {kind = "toggle"} end
    if within(circle_of(state, "f"), x, y, 1.5) then return {kind = "ftoggle"} end
    if state.functions_open then
        local pad = 0.05 * state.l.u
        for _, cell in ipairs(grid_cells(state)) do
            local rect = cell.rect
            if contains({x = rect.x - pad, y = rect.y - pad, w = rect.w + 2 * pad, h = rect.h + 2 * pad}, x, y) then
                return {kind = "functions"}
            end
        end
    end
    if state.shown and mode ~= "pause" then
        if dpad_directions(state, x, y) then return {kind = "buttons"} end
        for _, name in ipairs(onscreen.actions) do
            local box = action_box(state, name)
            local pad = 0.075 * box.w
            if contains({x = box.x - pad, y = box.y - pad, w = box.w + 2 * pad, h = box.h + 2 * pad}, x, y) then
                return {kind = "buttons"}
            end
        end
    end
    return nil
end

local function begin(state, touch, mode, has_mouse)
    local zone = hit(state, touch.x, touch.y, mode)
    if not zone then return {kind = has_mouse and "ignored" or "mouse"} end
    if zone.kind == "gear" then
        state.editing = true
        state.picking, state.selected = nil, nil
        state.dirty = true
    elseif zone.kind == "toggle" then
        state.shown = not state.shown
    elseif zone.kind == "ftoggle" then
        state.functions_open = not state.functions_open
    elseif zone.kind == "widget" then
        perform(state, zone.widget)
    elseif zone.kind == "drag" then
        state.selected = zone.name
    end
    return zone
end

-- state: from `create`. input: the frame's input; pass touch_active=false to release every finger and
-- hide (other screens). `mode`: "full" (menus), "match" or "pause" (paused or replaying: the d-pad and the
-- action buttons are inert, the F button and the menu buttons stay to resume).
-- Returns the held letters of player 1 ("udlrcbf" subset, for controls on their default key), the F-key
-- digits held ("1"-"9") and the set of virtual keys held (controls set to a key).
function gamepad.update(state, input, mode)
    mode = mode or "full"
    fit(state, input.screen or default_screen)
    state.mode = mode
    state.visible = input.touch_active == true
    if not state.visible then
        release(state)
        return "", "", {}
    end
    local touches = input.touches or {}
    local by_id = {}
    for _, touch in ipairs(touches) do by_id[touch.id] = touch end
    local has_mouse = false
    for id, zone in pairs(state.zones) do
        if not by_id[id] then
            if zone.kind == "drag" then state.dirty = true end
            state.zones[id] = nil
        elseif zone.kind == "mouse" then
            has_mouse = true
        end
    end
    for _, touch in ipairs(touches) do
        if not state.zones[touch.id] then
            local zone = begin(state, touch, mode, has_mouse)
            state.zones[touch.id] = zone
            if zone.kind == "mouse" then has_mouse = true end
        end
    end

    local l = state.l
    local held, functions_held = {}, {}
    for _, touch in ipairs(touches) do
        local zone = state.zones[touch.id]
        if zone.kind == "drag" then
            local spec = state.config.buttons[zone.name]
            spec.x = clamp((touch.x + zone.dx - l.left) / l.w, 0.02, 0.98)
            spec.y = clamp((touch.y + zone.dy - l.top) / l.h, 0.02, 0.98)
        elseif zone.kind == "buttons" and not state.editing and state.shown and mode ~= "pause" then
            local directions = dpad_directions(state, touch.x, touch.y)
            if directions then
                for direction, on in pairs(directions) do
                    if on then held[direction] = true end
                end
            end
            for _, name in ipairs(onscreen.actions) do
                local box = action_box(state, name)
                local pad = 0.075 * box.w
                if contains({x = box.x - pad, y = box.y - pad, w = box.w + 2 * pad, h = box.h + 2 * pad}, touch.x, touch.y) then
                    held[name] = true
                end
            end
        elseif zone.kind == "functions" and state.functions_open and not state.editing then
            for _, cell in ipairs(grid_cells(state)) do
                if contains(cell.rect, touch.x, touch.y) then functions_held[cell.number] = true end
            end
        end
    end
    state.held, state.functions_held = held, functions_held

    local letters, keys = {}, {}
    local function press(name, key_name)
        local key = onscreen.key(key_name)
        if key and key.code then keys[key.code] = true else letters[onscreen.letters[name]] = true end
    end
    for _, direction in ipairs(onscreen.directions) do
        if held[direction] then press(direction, state.config.buttons.dpad.keys[direction]) end
    end
    for _, name in ipairs(onscreen.actions) do
        if held[name] then press(name, state.config.buttons[name].key) end
    end
    local text = {}
    for _, letter in ipairs({"u", "d", "l", "r", "c", "b", "f"}) do
        if letters[letter] then text[#text + 1] = letter end
    end
    local digits = {}
    for number = 1, 9 do
        if functions_held[number] then digits[#digits + 1] = tostring(number) end
    end
    return table.concat(text), table.concat(digits), keys
end

-- Whether a finger belongs to the controls: it started on a control, the F grid or in the edit panel. The page
-- behind must not take such a finger as its pointer. Valid after `update` on the same frame.
function gamepad.claims(state, touch)
    if not state.visible then return false end
    local zone = state.zones[touch.id]
    return zone ~= nil and zone.kind ~= "mouse" and zone.kind ~= "ignored"
end

-- The settings to save once something changed (a drag ended, a widget was tapped, edit mode opened), else nil.
function gamepad.take_changes(state)
    if not state.dirty then return nil end
    state.dirty = false
    return state.config
end

-- A disc or a ring (`inner` > 0) in horizontal strips (each strip is one command, so they are kept few),
-- drawn with alpha so overlapping controls blend once.
local function disc(context, cx, cy, radius, inner, color, alpha)
    if alpha <= 0 then return end
    local step = max(2, floor(radius / 6))
    for top = -floor(radius), floor(radius) - 1, step do
        local mid = abs(top + step / 2)
        if mid < radius then
            local outer = sqrt(radius * radius - mid * mid)
            if inner > 0 and mid < inner then
                local hollow = sqrt(inner * inner - mid * mid)
                local width = floor(outer - hollow + 0.5)
                if width > 0 then
                    context.fill(floor(cx - outer + 0.5), floor(cy + top), width, step, color[1], color[2], color[3], alpha)
                    context.fill(floor(cx + hollow + 0.5), floor(cy + top), width, step, color[1], color[2], color[3], alpha)
                end
            else
                context.fill(floor(cx - outer + 0.5), floor(cy + top), floor(outer * 2 + 0.5), step, color[1], color[2], color[3], alpha)
            end
        end
    end
end

local function rect(context, x, y, width, height, color, alpha)
    context.fill(floor(x), floor(y), ceil(width), ceil(height), color[1], color[2], color[3], alpha)
end

local function outline(context, box, color, alpha)
    local thick = 2
    rect(context, box.x, box.y, box.w, thick, color, alpha)
    rect(context, box.x, box.y + box.h - thick, box.w, thick, color, alpha)
    rect(context, box.x, box.y + thick, thick, box.h - 2 * thick, color, alpha)
    rect(context, box.x + box.w - thick, box.y + thick, thick, box.h - 2 * thick, color, alpha)
end

local white, yellow, blue = {255, 255, 255}, {255, 217, 64}, {76, 141, 255}
local dark, grey = {11, 15, 26}, {51, 66, 94}

-- Call only while state.visible; the caller hides it on screens the controls do not drive.
function gamepad.draw(state, context)
    if not state.visible then return end
    local l, config = state.l, state.config
    local editing = state.editing
    -- The alpha (0-255) of a control; in edit mode even an invisible one shows faintly, so it can be found.
    local function alpha_of(name, strength)
        local value = floor(config.buttons[name].opacity / 10 * 255 * (strength or 1))
        return editing and max(value, 70) or value
    end
    local function tint_of(name)
        local level = floor(clamp(alpha_of(name) , 0, 255))
        return level * 0x10101
    end
    context.overlay(true)

    -- Round buttons: the show/hide button, SET and the F button.
    local toggle = circle_of(state, "toggle")
    disc(context, toggle.x, toggle.y, toggle.r, toggle.r * 0.8, white, alpha_of("toggle", 0.8))
    if state.shown then disc(context, toggle.x, toggle.y, toggle.r * 0.5, 0, white, alpha_of("toggle", 0.5)) end
    local gear = circle_of(state, "set")
    disc(context, gear.x, gear.y, gear.r, gear.r * 0.88, white, alpha_of("set", 0.8))
    if editing then disc(context, gear.x, gear.y, gear.r * 0.88, 0, yellow, alpha_of("set", 0.6)) end
    if alpha_of("set") > 0 then label(context, "SET", gear.x, gear.y - 8, "center", tint_of("set")) end
    local ftoggle = circle_of(state, "f")
    disc(context, ftoggle.x, ftoggle.y, ftoggle.r, ftoggle.r * 0.88, white, alpha_of("f", 0.8))
    if state.functions_open then disc(context, ftoggle.x, ftoggle.y, ftoggle.r * 0.88, 0, blue, alpha_of("f", 0.6)) end
    if alpha_of("f") > 0 then label(context, "F", ftoggle.x, ftoggle.y - 8, "center", tint_of("f")) end

    if state.functions_open or (editing and state.selected == "f") then
        for _, cell in ipairs(grid_cells(state)) do
            local box = cell.rect
            local on = state.functions_held[cell.number]
            rect(context, box.x, box.y, box.w, box.h, on and blue or dark, alpha_of("f", on and 1 or 0.7))
            if alpha_of("f") > 0 then label(context, "F" .. cell.number, box.x + box.w / 2, box.y + box.h / 2 - 8, "center", tint_of("f")) end
        end
    end

    -- The d-pad and the action buttons: the icons, lit while held.
    if (state.shown or editing) and state.mode ~= "pause" then
        local alpha = alpha_of("dpad")
        local cells = dpad_cells(state)
        for _, direction in ipairs(onscreen.directions) do
            local box = cells[direction]
            if alpha > 0 then context.icon(icon_path(direction), floor(box.x + 0.5), floor(box.y + 0.5), floor(box.w + 0.5), floor(box.h + 0.5),
                alpha, state.held[direction] and pressed_tint or 0xffffff) end
        end
        for _, name in ipairs(onscreen.actions) do
            local box = action_box(state, name)
            if alpha_of(name) > 0 then
                context.icon(icon_path(name), floor(box.x + 0.5), floor(box.y + 0.5), floor(box.w + 0.5), floor(box.h + 0.5),
                    alpha_of(name), state.held[name] and pressed_tint or 0xffffff)
            end
        end
    end

    if editing and state.selected then outline(context, bounds_of(state, state.selected), yellow, 220) end

    if editing then
        local p = panel(state)
        rect(context, p.frame.x, p.frame.y, p.frame.w, p.frame.h, dark, 225)
        for _, item in ipairs(p.items) do
            local current = false
            if state.picking and state.selected then
                local spec = config.buttons[state.selected]
                local active = state.picking.direction and spec.keys[state.picking.direction] or spec.key
                current = item.widget == "pick:" .. tostring(active)
            end
            rect(context, item.rect.x, item.rect.y, item.rect.w, item.rect.h, current and blue or grey, 240)
            label(context, item.label, item.rect.x + item.rect.w / 2, item.rect.y + item.rect.h / 2 - 8, "center")
        end
        for _, text in ipairs(p.texts) do label(context, text[1], text[2], text[3], text[4]) end
    end
    context.overlay(false)
end

return gamepad
