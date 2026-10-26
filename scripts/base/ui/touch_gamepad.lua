-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- OpenLF2 extension: on-screen controls, shown only when the last input was touch-driven (other pages
-- already handle direct taps). Seven round buttons (up, down, left, right, attack, jump, defend), an "F"
-- button that opens a 3x3 grid of F1-F9, a round button at the top centre that shows or hides the buttons,
-- and "SET" at the top right: drag the buttons, resize them, give each a key, set the opacity of each
-- group. The settings are saved (base/game/onscreen, config.json).
--
-- C++ only reports held fingers in viewport coordinates, plus the window's edges (letterbox bars lie
-- beyond the 794x550 picture); this module owns all hit-testing and draws as an overlay so it can sit in
-- the bars. Sizes are in units of u = a ninth of the window's height.
--
-- Every finger gets a zone the first frame it is seen and keeps it until it lifts: "buttons" (holds every
-- button under it, so one finger can slide between two, or press two overlapping ones for a diagonal),
-- "functions" (the F grid), "drag" (moves a button in edit mode), a one-shot "toggle"/"widget", "blocked"
-- (edit mode swallows the rest) or "mouse": a finger on empty screen stays the page's pointer. Fingers of
-- the other zones never reach the page behind (`claims`).
local constants = require("base/game/constants")
local font = require("base/ui/font")
local onscreen = require("base/game/onscreen")
local gamepad = {}

local floor, ceil, max, min, sqrt = math.floor, math.ceil, math.max, math.min, math.sqrt
local default_screen = {left = 0, top = 0, right = constants.screen.width, bottom = constants.screen.height}

local labels = {up = "UP", down = "DOWN", left = "LEFT", right = "RIGHT", attack = "ATTACK", jump = "JUMP", defend = "DEFEND"}
local default_labels = {up = "^", down = "v", left = "<", right = ">", attack = "A", jump = "J", defend = "D"}
local groups_of = {up = "pad", down = "pad", left = "pad", right = "pad", attack = "action", jump = "action", defend = "action"}
local group_labels = {pad = "PAD", action = "ACT", functions = "F", menu = "MENU"}

-- The host takes whole numbers only (a fraction is an invalid frame field), so text goes through here.
local function label(context, text, x, y, align)
    font.draw(context, text, floor(x + 0.5), floor(y + 0.5), nil, nil, align)
end
local function clamp(value, low, high) return max(low, min(high, value)) end
local function contains(rect, x, y) return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h end
local function within(circle, x, y, factor) return sqrt((x - circle.x) ^ 2 + (y - circle.y) ^ 2) <= circle.r * factor end

-- Computes the fixed places from the window's edges (again when they move: resize, fullscreen).
local function fit(state, screen)
    local old = state.screen
    if old and state.l and old.left == screen.left and old.top == screen.top and old.right == screen.right
       and old.bottom == screen.bottom then
        return
    end
    state.screen = screen
    local width, height = screen.right - screen.left, screen.bottom - screen.top
    local u = height / 9
    local l = {left = screen.left, top = screen.top, w = width, h = height, u = u}
    l.toggle = {x = screen.left + width / 2, y = screen.top + 0.6 * u, r = 0.4 * u}
    l.ftoggle = {x = screen.left + 1.1 * u, y = screen.top + 1.1 * u, r = 0.5 * u}
    l.gear = {x = screen.right - 1.1 * u, y = screen.top + 1.1 * u, r = 0.5 * u}
    l.cells = {}
    for number = 1, 9 do
        local index = number - 1
        l.cells[number] = {number = number, rect = {x = screen.left + 1.85 * u + (index % 3) * 0.9 * u,
            y = screen.top + 0.6 * u + floor(index / 3) * 0.9 * u, w = 0.8 * u, h = 0.8 * u}}
    end
    state.l = l
end

-- `config`: the saved settings (base/game/onscreen), checked here.
function gamepad.create(config)
    local state = {config = onscreen.normalize(config), zones = {}, held = {}, functions_held = {}, visible = false,
        functions_open = false, editing = false, picking = false, dirty = false}
    state.shown = state.config.show
    fit(state, default_screen)
    return state
end

-- The chords of the old gamepad no longer exist; kept so callers need no change.
function gamepad.set_available() end

local function circle_of(state, name)
    local spec, l = state.config.buttons[name], state.l
    return {x = l.left + spec.x * l.w, y = l.top + spec.y * l.h, r = 0.85 * l.u * spec.size}
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
    local frame_w, frame_h, row_h, button = 7.2 * u, 7.0 * u, 0.8 * u, 0.65 * u
    local frame_x, frame_y = l.left + (l.w - frame_w) / 2, l.top + 1.2 * u
    local function row_center(row) return frame_y + 0.3 * u + row * row_h + row_h / 2 end
    local function stepper(row, widget, text)
        local center = row_center(row)
        items[#items + 1] = {widget = widget .. "-", label = "-", rect = {x = frame_x + 4.2 * u, y = center - button / 2, w = button, h = button}}
        items[#items + 1] = {widget = widget .. "+", label = "+", rect = {x = frame_x + 6.2 * u, y = center - button / 2, w = button, h = button}}
        texts[#texts + 1] = {text, frame_x + 5.7 * u, center - 8, "center"}
    end
    texts[#texts + 1] = {"SET", frame_x + 0.4 * u, row_center(0) - 8, "left"}
    texts[#texts + 1] = {"DRAG A BUTTON TO MOVE IT", frame_x + 1.5 * u, row_center(0) - 8, "left"}
    local selected = state.selected
    if selected then
        local spec = state.config.buttons[selected]
        texts[#texts + 1] = {labels[selected], frame_x + 0.4 * u, row_center(1) - 8, "left"}
        texts[#texts + 1] = {"SIZE", frame_x + 0.4 * u, row_center(2) - 8, "left"}
        stepper(2, "size", string.format("%.1f", spec.size))
        local key = onscreen.key(spec.key)
        texts[#texts + 1] = {"KEY", frame_x + 0.4 * u, row_center(3) - 8, "left"}
        items[#items + 1] = {widget = "key", label = spec.key == "auto" and default_labels[selected] or key.label,
            rect = {x = frame_x + 4.2 * u, y = row_center(3) - button / 2, w = 2.65 * u, h = button}}
    else
        texts[#texts + 1] = {"TAP A BUTTON", frame_x + 0.4 * u, row_center(1) - 8, "left"}
    end
    for index, group in ipairs(onscreen.groups) do
        texts[#texts + 1] = {group_labels[group], frame_x + 0.4 * u, row_center(3 + index) - 8, "left"}
        stepper(3 + index, "op:" .. group .. ":", tostring(state.config.opacity[group]))
    end
    items[#items + 1] = {widget = "reset", label = "RESET", rect = {x = frame_x + 0.4 * u, y = frame_y + frame_h - 1.0 * u, w = 2.8 * u, h = 0.75 * u}}
    items[#items + 1] = {widget = "done", label = "DONE", rect = {x = frame_x + frame_w - 3.2 * u, y = frame_y + frame_h - 1.0 * u, w = 2.8 * u, h = 0.75 * u}}
    return {frame = {x = frame_x, y = frame_y, w = frame_w, h = frame_h}, items = items, texts = texts}
end

gamepad.panel = panel -- the edit panel's widgets and texts, for tests

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
        state.editing, state.picking, state.selected = false, false, nil
    elseif widget == "reset" then
        local show = config.show
        state.config = onscreen.defaults()
        state.config.show = show
    elseif widget == "key" then
        if selected then state.picking = true end
    elseif widget == "closepicker" then
        state.picking = false
    elseif widget == "size-" or widget == "size+" then
        if selected then selected.size = clamp(floor((selected.size + (widget == "size+" and 0.1 or -0.1)) * 10 + 0.5) / 10, 0.5, 2.5) end
    elseif widget:sub(1, 5) == "pick:" then
        if selected and onscreen.key(widget:sub(6)) then selected.key = widget:sub(6) end
        state.picking = false
    else
        local group, sign = widget:match("^op:(%a+):([%-+])$")
        if group and config.opacity[group] then
            config.opacity[group] = clamp(config.opacity[group] + (sign == "+" and 1 or -1), 1, 10)
        end
    end
    state.dirty = true
end

-- The zone a finger starts in, or nil when it touches the empty screen.
local function hit(state, x, y, mode)
    local l = state.l
    if within(l.gear, x, y, 1.5) then return {kind = "gear"} end
    if state.editing then
        local p = panel(state)
        for _, item in ipairs(p.items) do
            if contains(item.rect, x, y) then return {kind = "widget", widget = item.widget} end
        end
        if state.picking then return {kind = "widget", widget = "closepicker"} end
        if contains(p.frame, x, y) then return {kind = "blocked"} end
        if within(l.ftoggle, x, y, 1.5) then return {kind = "ftoggle"} end
        for _, name in ipairs(onscreen.controls) do
            if within(circle_of(state, name), x, y, 1.15) then return {kind = "drag", name = name} end
        end
        return {kind = "blocked"}
    end
    if within(l.toggle, x, y, 2) then return {kind = "toggle"} end
    if within(l.ftoggle, x, y, 1.5) then return {kind = "ftoggle"} end
    if state.functions_open then
        local pad = 0.05 * l.u
        for _, cell in ipairs(l.cells) do
            local rect = cell.rect
            if contains({x = rect.x - pad, y = rect.y - pad, w = rect.w + 2 * pad, h = rect.h + 2 * pad}, x, y) then
                return {kind = "functions"}
            end
        end
    end
    if state.shown and mode ~= "pause" then
        for _, name in ipairs(onscreen.controls) do
            if within(circle_of(state, name), x, y, 1.15) then return {kind = "buttons"} end
        end
    end
    return nil
end

local function begin(state, touch, mode, has_mouse)
    local zone = hit(state, touch.x, touch.y, mode)
    if not zone then return {kind = has_mouse and "ignored" or "mouse"} end
    if zone.kind == "gear" then
        state.editing = not state.editing
        state.picking, state.selected = false, nil
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
-- hide (other screens). `mode`: "full" (menus), "match" or "pause" (paused or replaying: the buttons are
-- hidden, the F button and the menu buttons stay to resume).
-- Returns the held letters of player 1 ("udlrcbf" subset, for buttons on their default key), the F-key
-- digits held ("1"-"9") and the set of virtual keys held (buttons set to a key).
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
            spec.x = clamp((touch.x - l.left) / l.w, 0.02, 0.98)
            spec.y = clamp((touch.y - l.top) / l.h, 0.02, 0.98)
        elseif zone.kind == "buttons" and not state.editing and state.shown and mode ~= "pause" then
            for _, name in ipairs(onscreen.controls) do
                if within(circle_of(state, name), touch.x, touch.y, 1.15) then held[name] = true end
            end
        elseif zone.kind == "functions" and state.functions_open and not state.editing then
            for _, cell in ipairs(l.cells) do
                if contains(cell.rect, touch.x, touch.y) then functions_held[cell.number] = true end
            end
        end
    end
    state.held, state.functions_held = held, functions_held

    local letters, keys = {}, {}
    for _, name in ipairs(onscreen.controls) do
        if held[name] then
            local key = onscreen.key(state.config.buttons[name].key)
            if key and key.code then keys[key.code] = true else letters[onscreen.letters[name]] = true end
        end
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

-- Whether a finger belongs to the controls: it started on a button, the F grid, a menu button or in the edit
-- panel. The page behind must not take such a finger as its pointer. Valid after `update` on the same frame.
function gamepad.claims(state, touch)
    if not state.visible then return false end
    local zone = state.zones[touch.id]
    return zone ~= nil and zone.kind ~= "mouse" and zone.kind ~= "ignored"
end

-- The settings to save once something changed (a drag ended, a widget was tapped, edit mode toggled), else nil.
function gamepad.take_changes(state)
    if not state.dirty then return nil end
    state.dirty = false
    return state.config
end

-- A disc or a ring (`inner` > 0) in horizontal strips, drawn with alpha so overlapping controls blend once.
local function disc(context, cx, cy, radius, inner, color, alpha)
    if alpha <= 0 then return end
    local step = max(2, floor(radius / 6))
    for top = -floor(radius), floor(radius) - 1, step do
        local mid = math.abs(top + step / 2)
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

-- A triangle pointing `direction`.
local function arrow(context, cx, cy, size, direction, color, alpha)
    local step = max(1, floor(size / 8))
    local count = ceil(size / step)
    for index = 0, count - 1 do
        local extent = (index + 1) / count * size
        if direction == "up" then
            rect(context, cx - extent / 2, cy - size / 2 + index * step, extent, step, color, alpha)
        elseif direction == "down" then
            rect(context, cx - extent / 2, cy + size / 2 - (index + 1) * step, extent, step, color, alpha)
        elseif direction == "left" then
            rect(context, cx - size / 2 + index * step, cy - extent / 2, step, extent, color, alpha)
        else
            rect(context, cx + size / 2 - (index + 1) * step, cy - extent / 2, step, extent, color, alpha)
        end
    end
end

local white, yellow, blue = {255, 255, 255}, {255, 217, 64}, {76, 141, 255}
local face, dark, grey = {184, 196, 214}, {11, 15, 26}, {51, 66, 94}

-- Call only while state.visible; the caller hides it on screens the controls do not drive.
function gamepad.draw(state, context)
    if not state.visible then return end
    local l, config = state.l, state.config
    local opacity = function(group) return config.opacity[group] / 10 end
    local function alpha(group, strength) return floor(clamp(opacity(group) * strength * 255, 0, 255)) end
    context.overlay(true)

    local menu = alpha("menu", 0.6)
    disc(context, l.toggle.x, l.toggle.y, l.toggle.r, l.toggle.r * 0.8, white, menu)
    if state.shown then disc(context, l.toggle.x, l.toggle.y, l.toggle.r * 0.5, 0, white, alpha("menu", 0.4)) end
    disc(context, l.gear.x, l.gear.y, l.gear.r, l.gear.r * 0.88, white, alpha("menu", 0.6))
    if state.editing then disc(context, l.gear.x, l.gear.y, l.gear.r * 0.88, 0, yellow, alpha("menu", 0.5)) end
    label(context, "SET", l.gear.x, l.gear.y - 8, "center")
    disc(context, l.ftoggle.x, l.ftoggle.y, l.ftoggle.r, l.ftoggle.r * 0.88, white, alpha("functions", 0.6))
    if state.functions_open then disc(context, l.ftoggle.x, l.ftoggle.y, l.ftoggle.r * 0.88, 0, blue, alpha("functions", 0.5)) end
    label(context, "F", l.ftoggle.x, l.ftoggle.y - 8, "center")

    if state.functions_open then
        for _, cell in ipairs(l.cells) do
            local box = cell.rect
            local on = state.functions_held[cell.number]
            rect(context, box.x, box.y, box.w, box.h, on and blue or dark, alpha("functions", on and 0.8 or 0.55))
            label(context, "F" .. cell.number, box.x + box.w / 2, box.y + box.h / 2 - 8, "center")
        end
    end

    if (state.shown or state.editing) and state.mode ~= "pause" then
        for _, name in ipairs(onscreen.controls) do
            local circle, spec = circle_of(state, name), state.config.buttons[name]
            local group = groups_of[name]
            local on = state.held[name]
            disc(context, circle.x, circle.y, circle.r, 0, on and white or face, alpha(group, on and 0.65 or 0.4))
            disc(context, circle.x, circle.y, circle.r, circle.r * 0.92, state.selected == name and yellow or white, alpha(group, 0.55))
            if spec.key == "auto" and group == "pad" then
                arrow(context, circle.x, circle.y, circle.r * 0.7, name, white, alpha(group, 0.9))
            else
                local text = spec.key == "auto" and default_labels[name] or onscreen.key(spec.key).label
                label(context, text, circle.x, circle.y - 8, "center")
            end
        end
    end

    if state.editing then
        local p = panel(state)
        rect(context, p.frame.x, p.frame.y, p.frame.w, p.frame.h, dark, 225)
        for _, item in ipairs(p.items) do
            local current = item.widget == "key" or (state.picking and state.selected
                and item.widget == "pick:" .. state.config.buttons[state.selected].key)
            rect(context, item.rect.x, item.rect.y, item.rect.w, item.rect.h, current and blue or grey, 240)
            label(context, item.label, item.rect.x + item.rect.w / 2, item.rect.y + item.rect.h / 2 - 8, "center")
        end
        for _, text in ipairs(p.texts) do label(context, text[1], text[2], text[3], text[4]) end
    end
    context.overlay(false)
end

return gamepad
