-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local constants = require("base/game/constants")

local background = {}
local cache = {}
local screen_width = constants.screen.width
local window_width  -- set by set_window_width; nil = the classic width
-- The painter's fixed replacements for four converted rect: colors.
local remapped = {[0x175317] = 0x104f10, [0x575347] = 0x5a4e4b, [0x977757] = 0x9a6e5a, [0x473f1f] = 0x423818}
local function canonical(path)
    path = path:gsub("\\", "/"):lower()
    assert(path:match("^[a-z0-9_./-]+$"), "unsupported original resource path: " .. path)
    return path
end
function background.load(path)
    path = canonical(path)
    local data = cache[path]
    if not data then
        data = engine.read_background_data(path)
        for _, layer in ipairs(data.layers) do layer.resource = canonical(layer.path) end
        cache[path] = data
    end
    return data
end
-- A copy of a background that keeps the layers and opoints a background mode lets through (LF2 Darkfiren: a layer's
-- respond and an opoint's arest must be listed by the mode; filters = {respond = set|nil, arest = set|nil}).
-- Layers are copied one by one because drawing writes their grouping into them. Without a filter the very same
-- data comes back.
function background.filtered(data, filters)
    if not filters or data == nil or data.layers == nil then return data end
    local area = filters.area
    if filters.respond == nil and filters.arest == nil then
        if not (area and (area.width or area.zboundary or area.shadow or area.shadow_size)) then return data end
        -- Only the area changes: the layers and opoints stay the original's own, as without any filter.
        local same = {}
        for key, value in pairs(data) do same[key] = value end
        return background.with_area(same, area)
    end
    local copy = {}
    for key, value in pairs(data) do copy[key] = value end
    copy.layers, copy.opoints, copy.team_frames = {}, {}, {}
    for _, layer in ipairs(data.layers) do
        if filters.respond == nil or filters.respond[layer.respond or 0] == true then
            local entry = {}
            for key, value in pairs(layer) do
                if key ~= "group" and key ~= "stands_still" then entry[key] = value end
            end
            copy.layers[#copy.layers + 1] = entry
        end
    end
    for _, opoint in ipairs(data.opoints or {}) do
        if filters.arest == nil or filters.arest[opoint.arest or 0] == true then copy.opoints[#copy.opoints + 1] = opoint end
    end
    -- A team HP bar image follows its `respond:` like a layer does.
    for _, frame in ipairs(data.team_frames or {}) do
        if filters.respond == nil or filters.respond[frame.respond or 0] == true then copy.team_frames[#copy.team_frames + 1] = frame end
    end
    copy.groups_ready = nil
    return background.with_area(copy, area)
end

-- The width a background mode's `width: -1` stands for (the window's width): 1333 or 1018 for those layouts, nil
-- (the classic 794) otherwise. Idempotent; nil, 0, a negative number or a non-number goes back to the default.
-- Call it before the round is created (background.filtered / background.switch read it).
function background.set_window_width(width)
    width = tonumber(width)
    window_width = (width and width > 0) and math.floor(width) or nil
end

function background.window_width()
    return window_width
end

-- LF2 Darkfiren team HP bar (bg.dat `frame:` blocks, data.team_frames). The part of a bar image to paint for a team
-- that has `value` of `maximum` (the caller adds up the team: [UNCERTAIN] the readme does not say how): returns
-- {sx, sy, sw, sh, x, y}, the source rectangle of the image and the screen position, or nil when nothing is to be
-- painted. Frames (type 0) are painted whole. Bars (type 1 hp, 2 dark hp) fill from the left (facing 0) or, facing 1,
-- from the right; `dx`, `dy` are where the image is read from.
function background.team_bar_rect(frame, value, maximum)
    if type(frame) ~= "table" or (frame.w or 0) <= 0 or (frame.h or 0) <= 0 then return nil end
    local width = frame.w
    if frame.type == 1 or frame.type == 2 then
        local fraction = (tonumber(maximum) and maximum > 0) and (tonumber(value) or 0) / maximum or 0
        fraction = math.max(0, math.min(1, fraction))
        width = math.floor(frame.w * fraction)
        if width <= 0 then return nil end
    end
    local shift = frame.facing == 1 and (frame.w - width) or 0
    return {sx = (frame.dx or 0) + shift, sy = frame.dy or 0, sw = width, sh = frame.h, x = frame.x + shift, y = frame.y}
end

-- Is the frame shown at this tick? `cc`, `c1`, `c2` blink it like a layer (hidden outside c1..c2 of every cc ticks).
function background.team_frame_visible(frame, tick)
    local period = frame.cc or 0
    if period <= 0 then return true end
    local phase = (tonumber(tick) or 0) % period
    return phase >= (frame.c1 or 0) and phase <= (frame.c2 or 0)
end

-- LF2 Darkfiren: a background mode's `width`, `zboundary` take priority over the same tags of the bg.dat, and
-- width -1 means the window width. Changes and returns `copy` (never the cached original).
function background.with_area(copy, area)
    if not area then return copy end
    if area.width then copy.width = area.width == -1 and (window_width or screen_width) or area.width end
    if area.zboundary then copy.zboundary = {area.zboundary[1], area.zboundary[2]} end
    if area.shadow then copy.shadow = area.shadow end
    if area.shadow_size then copy.shadow_size = {area.shadow_size[1], area.shadow_size[2]} end
    return copy
end
-- Mutable per-view state: the original keeps one animation counter per layer slot.
function background.create_state(data)
    local counters = {}
    for index = 1, #data.layers do counters[index] = 0 end
    return {counters = counters, phase = 0, front_drawn = false}
end

-- LF2 Darkfiren layer `state:`: 1 is shown only while the round starts, 2 only after it ends. The round sets the
-- phase of the view (0 = playing). Layers without `state:` are always shown.
function background.set_phase(view, phase)
    if type(view) == "table" then view.phase = tonumber(phase) and math.floor(phase) or 0 end
end

-- Does this pass paint the layer? `state:` layers need the matching phase; `transparency: -1` layers (drawn above
-- the characters) are left to background.paint_front once the screen has said it paints that pass
-- (view.front_drawn), so a screen that does not call it keeps them in the ordinary pass.
local function shown(layer, view, front)
    local own = layer.state or 0
    if own ~= 0 and own ~= (view.phase or 0) then return false end
    local above = layer.transparency == -1
    if front then return above end
    return not (above and view.front_drawn)
end
-- C integer division truncates toward zero.
local function truncate(value)
    if value >= 0 then return math.floor(value) end
    return math.ceil(value)
end
local function parallax(layer, stage_width, camera_x)
    return -truncate((layer.width - screen_width) * camera_x / (stage_width - screen_width))
end
-- Advances the counter on every paint call; hidden outside c1..c2.
local function visible(layer, state, index)
    if layer.cc <= 0 then return true end
    local counter = (state.counters[index] + 1) % layer.cc
    state.counters[index] = counter
    return counter >= layer.c1 and counter <= layer.c2
end
local function image(context, layer, x)
    context.image(layer.resource, x, layer.y, layer.transparency ~= 0)
end
-- Widescreen ("expand" layout). `wide` = {left, right, camera}: a window of the full screen width in
-- viewport coordinates, showing the battlefield from world x `camera` (always inside the stage, so the stage's
-- edges are the screen's edges). Nothing is scaled or
-- repeated. A layer's `width` is its scroll width (its bitmaps, often a pair side by side, are narrower), and a
-- layer wider than the window moves so that it covers the window at both ends of the stage; for a layer as wide as
-- the stage this is exactly the classic movement, so the ground stays with the fighters.
local function classic_x(layer, stage_width, wide)
    -- The classic camera that would have put the window where it is (the window is not always at the game's own
    -- camera): scenery moves with the window, so it stands still when the window does.
    local camera = math.floor(wide.camera * (stage_width - screen_width) / (stage_width - (wide.right - wide.left)))
    local x = layer.x
    if stage_width > screen_width then x = x + parallax(layer, stage_width, camera) end
    return x + camera - (wide.camera - wide.left)
end
local function wide_x(layer, stage_width, wide)
    local view_width = wide.right - wide.left
    -- A stage narrower than the window is centred, and every layer stays fixed to it.
    if stage_width <= view_width then return layer.x + wide.left - wide.camera end
    if layer.width >= view_width then
        return layer.x + wide.left - truncate((layer.width - view_width) * wide.camera / (stage_width - view_width))
    end
    -- Narrower than the window: scenery keeps its classic movement; an opaque backdrop (sky, ground) stands still, as
    -- moving it would uncover the window's left side at the end of the stage.
    if layer.transparency ~= 0 or layer.stands_still == false then return classic_x(layer, stage_width, wide) end
    return layer.x + wide.left
end
-- True for a layer that covers the whole classic screen at every camera position (a background, not a decoration).
local function spans_screen(layer)
    return layer.x <= 0 and layer.width >= screen_width
end
-- Width of an original bitmap, read from its header (nil if it cannot be read).
local bitmap_widths = {}
local function bitmap_width(resource)
    local width = bitmap_widths[resource]
    if width == nil then
        width = false
        local ok, bytes = pcall(engine.read_resource, resource)
        if ok and type(bytes) == "string" and #bytes >= 26 and bytes:sub(1, 2) == "BM" then
            local b1, b2, b3, b4 = bytes:byte(19, 22)
            width = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
        end
        bitmap_widths[resource] = width
    end
    return width or nil
end
-- Opaque layers that sit at the same height with the same scroll width (a sky or ground made of several bitmaps)
-- form a group, and the group's extent is how far its bitmaps reach together.
local function prepare_groups(data)
    local group, previous
    for _, layer in ipairs(data.layers) do
        if layer.color == 0 and layer.loop == 0 then
            layer.bitmap_width = bitmap_width(layer.resource) or layer.width
            if previous and previous.y == layer.y and previous.width == layer.width
               and previous.transparency == layer.transparency then
                group.extent = math.max(group.extent, layer.x + layer.bitmap_width)
                group.first = math.min(group.first, layer.x)
            else
                group = {extent = layer.x + layer.bitmap_width, first = layer.x}
            end
            layer.group = group
            previous = layer
        else
            previous = nil
        end
    end
    -- Layers that share a scroll width belong together and must move together. Opaque layers (sky, ground) stand
    -- still when the window is wider than they scroll, unless scenery shares their scroll width, which then moves
    -- the classic way and takes them along.
    local scenery = {}
    for _, layer in ipairs(data.layers) do
        if layer.group and layer.transparency ~= 0 then scenery[layer.width] = true end
    end
    for _, layer in ipairs(data.layers) do
        if layer.group and layer.transparency == 0 then layer.stands_still = not scenery[layer.width] end
    end
    data.groups_ready = true
end
-- A layer's bitmaps cover only a range: from 0 (or from where its first bitmap starts, if that is further left) to
-- its scroll width (or its group's extent, if that reaches further), which can be narrower than the window. Beyond
-- the range the layer continues as its mirror image (a mirror joins without a seam; this also carries scenery such
-- as a mountain or a hedge on, and hides the gaps between layers), then as the original again, and so on.
local function continue_layer(context, layer, origin, wide)
    local low = math.min(0, layer.group.first)
    local range = math.max(layer.width, layer.group.extent) - low
    if range < 1 then return end
    local keyed = layer.transparency ~= 0
    local first = math.floor((wide.left - origin - low) / range)
    local last = math.floor((wide.right - 1 - origin - low) / range)
    for copy = math.max(first, -4), math.min(last, 4) do
        if copy % 2 ~= 0 then
            context.sprite(layer.resource, {0, 0, 0, 0},
                origin + 2 * low + (copy + 1) * range - layer.x - layer.bitmap_width, layer.y, keyed, true)
        elseif copy ~= 0 then
            context.sprite(layer.resource, {0, 0, 0, 0}, origin + copy * range + layer.x, layer.y, keyed)
        end
    end
end
-- Paints every layer in file order for a camera at world x `camera_x`; `bounds` (the visible part of the window on
-- the battlefield) and `wide` are given together for the widescreen layout.
local function paint_layers(context, data, state, camera_x, bounds, wide, front)
    local stage_width = assert(data.width, "background has no width")
    for index, layer in ipairs(data.layers) do
        if not shown(layer, state, front) then
            -- left out of this pass
        elseif layer.color == 0 and layer.loop == 0 then
            if visible(layer, state, index) then
                if wide then
                    if not data.groups_ready then prepare_groups(data) end
                    local x = wide_x(layer, stage_width, wide)
                    image(context, layer, x)
                    continue_layer(context, layer, x - layer.x, wide)
                else
                    local offset = 0
                    if stage_width > screen_width then offset = parallax(layer, stage_width, camera_x) end
                    image(context, layer, layer.x + offset)
                end
            end
        elseif layer.color == 0 then
            if visible(layer, state, index) then
                -- The original divides by zero or never terminates in these cases.
                assert(layer.loop > 0, "negative background layer loop step")
                assert(stage_width ~= screen_width, "looped layer on a screen-wide background")
                local offset
                local extend = false
                if not wide then offset = parallax(layer, stage_width, camera_x)
                else
                    offset = wide_x(layer, stage_width, wide) - layer.x
                    extend = layer.width >= stage_width or spans_screen(layer)
                end
                local first, last = layer.x, layer.width - 1
                -- Only a layer that covers the classic screen repeats beyond its own range; a narrower one (a fence
                -- along part of the arena) stays where it is.
                if extend then
                    local loops = math.floor((wide.left - offset - layer.x) / layer.loop)
                    first = math.min(first, layer.x + loops * layer.loop)
                    last = math.max(last, wide.right - offset)
                end
                for x = first, last, layer.loop do
                    image(context, layer, offset + x)
                end
            end
        elseif layer.width > 0 and layer.height > 0 then
            local color = (remapped[layer.color] or layer.color) % 16777216
            local x, width = layer.x, layer.width
            if bounds and x <= 0 and x + width >= screen_width then
                x, width = bounds.left, bounds.right - bounds.left
            end
            context.fill(x, layer.y, width, layer.height,
                math.floor(color / 65536), math.floor(color / 256) % 256, color % 256)
        end
    end
end
function background.paint(context, data, state, camera_x, bounds, wide)
    paint_layers(context, data, state, camera_x, bounds, wide, false)
end

-- The second pass, painted after the characters and objects: only the layers marked `transparency: -1` (an image or
-- colour above them). A screen that calls it sets view.front_drawn = true (background.enable_front) before
-- the first ordinary pass.
function background.paint_front(context, data, state, camera_x, bounds, wide)
    paint_layers(context, data, state, camera_x, bounds, wide, true)
end

function background.enable_front(view)
    if type(view) == "table" then view.front_drawn = true end
end
background.lee_on_road = {name = "Lee On Road", width = 2400, zboundary = {350, 470},
    shadow = "pe/shadow1", shadow_size = {37, 9}, layers = {}}
local function cmod(a, b) return a - (a / b >= 0 and math.floor(a / b) or math.ceil(a / b)) * b end
local function rgb(context, x, y, width, height, color)
    context.fill(x, y, width, height, math.floor(color / 65536), math.floor(color / 256) % 256, color % 256)
end
function background.paint_lee_on_road(context, camera_x, bounds)
    local left = bounds and bounds.left or 0
    local width = bounds and bounds.right - bounds.left or screen_width
    context.image("pe/back99_2", 250 - math.floor(camera_x / 100), 120, false)
    for x = 0, 3999, 500 do
        context.image("pe/back99_3", x - math.floor(camera_x * 7 / 10) + 30, 175, true)
    end
    rgb(context, left, 326, width, 20, 0x3f3f3f)
    rgb(context, left, 345, width, 156, 0x575757)
    rgb(context, left, 471, width, 30, 0x3f3f3f)
    rgb(context, left, 328, width, 2, 0x373737)
    local first, last = cmod(900 - camera_x, 70), 792
    if bounds then
        first = first + math.floor((bounds.left - first) / 70) * 70
        last = bounds.right
    end
    for x = first, last, 70 do
        rgb(context, x, 292, 1, 37, 0x577fa7)
        rgb(context, x + 1, 292, 1, 37, 0x2f4357)
    end
    rgb(context, left, 310, width, 1, 0x577fa7)
    rgb(context, left, 311, width, 1, 0x2f4357)
    rgb(context, left, 290, width, 1, 0x577fa7)
    rgb(context, left, 291, width, 1, 0x2f4357)
    for x = 0, 3199, 320 do
        context.image("pe/back99_1", x - camera_x + 10, 390, false)
    end
end
-- LF2 Darkfiren background changing states (st9xx / st9xxyy) and bg mode changing states (st7xx / st7xxyy).
-- The unfiltered description of row `row`, or nil when the game has no such background. Row 99 is Lee on Road.
local function description_of(row)
    if row == constants.background_rows.lee_on_road then return background.lee_on_road end
    local ok, catalog = pcall(require, "base/game/catalog")
    if not ok then return nil end
    local entry = catalog.backgrounds()[row + 1]
    return entry and background.load(entry.path) or nil
end

-- The mode `index` (0 = the background's first mode) of row `row` as a parsed mode table, or nil.
local function mode_of(row, index)
    local ok, text = pcall(engine.read_resource, "game/bg_modes/" .. row)
    if not ok then return nil end
    return require("base/game/bg_modes").parse(text)[index + 1]
end

-- Changes the running round's background and/or background mode (interface I3). `row` (0-99) loads that background,
-- `mode_index` (0-99, 0 = the first mode of the background's mode list) picks the mode of the (new) background; nil
-- leaves that part alone. A row or mode the game does not have changes nothing. A new row without a mode keeps the
-- fighters' mode effects (hurtable, recmp, ...) but takes the new background's first-mode filters. Updates
-- state.stage (width and zboundary follow), state.view, state.bg_area, state.background_row, state.bg_mode and
-- state.bg_mode_index. Objects the old background's opoints created stay; the new opoints are not spawned.
-- [UNCERTAIN] whether mode numbers start at 0 or 1 is not documented; 0 is assumed. Returns true when something changed.
function background.switch(state, row, mode_index)
    if type(state) ~= "table" or type(state.stage) ~= "table" then return false end
    local bg_modes = require("base/game/bg_modes")
    row = tonumber(row) and math.floor(row) or nil
    mode_index = tonumber(mode_index) and math.floor(mode_index) or nil
    local target = row or state.background_row
    local base = description_of(target)
    if not base then return false end
    local filters
    if mode_index ~= nil then
        local mode = target ~= constants.background_rows.lee_on_road and mode_of(target, mode_index) or nil
        if not mode then return false end
        filters = bg_modes.filters(mode)
    elseif row ~= nil and row ~= state.background_row then
        filters = target ~= constants.background_rows.lee_on_road and bg_modes.default_filters(target) or nil
    else
        return false
    end
    local effects = {}
    for key, value in pairs(state.bg_mode or {}) do effects[key] = value end
    effects.filters = filters
    state.bg_mode = effects
    if row ~= nil then state.background_row = row end
    state.bg_mode_index = mode_index or (row ~= nil and 0 or state.bg_mode_index)
    state.stage = background.filtered(base, filters)
    state.view = background.create_state(state.stage)
    state.bg_area = filters and filters.area or nil
    return true
end

-- Applies one of the states 9xx, 9xxyy, 7xx, 7xxyy by its number (what a frame's `state:` holds):
--   9xx    (900..999)      background xx
--   9xxyy  (90000..98999)  if the current background is xx, change to yy
--   7xx    (700..799)      background mode xx
--   7xxyy  (70000..79999)  if the current mode is xx, change to yy
-- 99xxx is the camera state and is not handled here. Returns true when the round changed. A mode never chosen counts as 0.
function background.switch_state(state, value)
    value = tonumber(value)
    if not value or type(state) ~= "table" then return false end
    value = math.floor(value)
    if value >= 900 and value <= 999 then return background.switch(state, value - 900, nil) end
    if value >= 700 and value <= 799 then return background.switch(state, nil, value - 700) end
    if value >= 90000 and value <= 98999 then
        local from, to = math.floor(value / 100) % 100, value % 100
        if state.background_row == from then return background.switch(state, to, nil) end
        return false
    end
    if value >= 70000 and value <= 79999 then
        local from, to = math.floor(value / 100) % 100, value % 100
        if (state.bg_mode_index or 0) == from then return background.switch(state, nil, to) end
        return false
    end
    return false
end
return background
