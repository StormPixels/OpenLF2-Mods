-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- The launch menu and the title menu are laid out for the original 794 x 550 client area. They get a viewport that follows
-- their menu_back picture and the window instead: as tall as the picture (never below 550) and as wide as the window's
-- shape makes it at that height (never below 794), instead of a 794 x 550 one with bars at its sides. What the screens draw
-- is moved to the middle (everything by the same amount, the menu_back picture by its own size so a wider picture, e.g.
-- 1018 x 550, or a taller one is seen whole), and the pointer is moved back the same way for them.
local constants = require("base/game/constants")

local wide_menu = {}
local base_width, base_height = constants.screen.width, constants.screen.height
local widest, tallest = 4096, 4096

-- The size of a picture, read from its BMP (width at bytes 19 to 22, height at 23 to 26, little endian; a negative height
-- is a top-down bitmap) or PNG (bytes 17 to 20 and 21 to 24, big endian) header; nil when it cannot be read.
local known = {}
local function picture_size(resource)
    if known[resource] == nil then
        local width, height = false, false
        local ok, data = pcall(engine.read_resource, resource)
        if ok and type(data) == "string" then
            if #data >= 24 and data:sub(2, 4) == "PNG" then
                local a, b, c, d, e, f, g, h = data:byte(17, 24)
                width = ((a * 256 + b) * 256 + c) * 256 + d
                height = ((e * 256 + f) * 256 + g) * 256 + h
            elseif #data >= 26 and data:sub(1, 2) == "BM" then
                local a, b, c, d, e, f, g, h = data:byte(19, 26)
                width = ((d * 256 + c) * 256 + b) * 256 + a
                height = ((h * 256 + g) * 256 + f) * 256 + e
                if height >= 2147483648 then height = 4294967296 - height end
            end
        end
        if width and height and width >= 1 and width < 8192 and height >= 1 and height < 8192 then
            known[resource] = {width, height}
        else
            known[resource] = false
        end
    end
    local size = known[resource]
    if size then return size[1], size[2] end
    return nil, nil
end

function wide_menu.picture_width(resource)
    local width = picture_size(resource)
    return width
end

function wide_menu.picture_height(resource)
    local _, height = picture_size(resource)
    return height
end

-- The viewport height: the menu picture's, never below the classic 550 (the screens are laid out for that).
function wide_menu.viewport_height(picture_height)
    if not picture_height or picture_height <= base_height then return base_height end
    return math.min(picture_height, tallest)
end

-- The viewport width that has the window's shape at `height` (550 without one). `bounds` are the window's edges in viewport
-- coordinates (the host's `screen`); the ratio of its two sides is the window's whatever viewport they were taken in. The host
-- rounds every edge outward, so each side is up to 2 too long, 1 on average: that is taken off, or the width would change
-- with the viewport it was measured in. Never narrower than 794: a taller window keeps the bars above and below.
function wide_menu.viewport_width(bounds, height)
    if type(bounds) ~= "table" then return base_width end
    local width = (bounds.right or 0) - (bounds.left or 0) - 1
    local window_height = (bounds.bottom or 0) - (bounds.top or 0) - 1
    if not (width > 0 and window_height > 0) then return base_width end
    local wanted = math.floor((height or base_height) * width / window_height + 0.5)
    if wanted <= base_width then return base_width end
    return math.min(wanted, widest)
end

-- Where the 794 wide layout starts in a viewport of `width`, and the 550 high one in a viewport of `height`.
function wide_menu.shift(width)
    if width <= base_width then return 0 end
    return math.floor((width - base_width) / 2)
end

function wide_menu.shift_y(height)
    if height <= base_height then return 0 end
    return math.floor((height - base_height) / 2)
end

-- A menu_back picture is centred by its own size and drawn as it is; what is left of the viewport keeps the viewport colour.
local function background(context, width, height, resource, y, keyed)
    local picture_width, picture_height = picture_size(resource)
    picture_width, picture_height = picture_width or base_width, picture_height or base_height
    context.image(resource, math.floor((width - picture_width) / 2), y + math.floor((height - picture_height) / 2), keyed)
end

-- `context` as the menu screens see it: 794 x 550 coordinates, moved into a viewport `width` x `height`.
function wide_menu.wrap(context, width, height)
    height = height or base_height
    local dx, dy = wide_menu.shift(width), wide_menu.shift_y(height)
    local wrapped = {}
    for name, command in pairs(context) do wrapped[name] = command end   -- what is not moved passes through as it is
    -- Where the viewport's own top-left corner is in the 794 x 550 coordinates (negative: the layout sits in the middle), for
    -- what is anchored to the window's edge instead of the layout (a mode file's <frame> and <name> on the title menu).
    wrapped.origin = {x = -dx, y = -dy}
    function wrapped.viewport(_, _, red, green, blue) return context.viewport(width, height, red, green, blue) end
    function wrapped.sprite(resource, source, x, y, ...) return context.sprite(resource, source, x + dx, y + dy, ...) end
    function wrapped.image(resource, x, y, keyed)
        if type(resource) == "string" and resource:find("^pe/menu_back") then return background(context, width, height, resource, y, keyed) end
        return context.image(resource, x + dx, y + dy, keyed)
    end
    -- A menu_back layer of system.dat (sd_menu_back): the scene spans left..right in its own coordinates. Like a stage at camera
    -- 0 it starts at the viewport's left edge (what is wider is cut off on the right); a scene narrower than the viewport is
    -- centred. A `loop` picture is repeated across the whole viewport, to its left edge too.
    function wrapped.backdrop(resource, x, y, keyed, loop, left, right, sky, scene_height, foot, backing)
        left, right = left or 0, right or base_width
        local scene_width = math.max(1, right - left)
        local shift = math.max(0, math.floor((width - scene_width) / 2)) - left
        -- A scene taller than 550 sets the viewport's height (it starts at the top); otherwise the 550 high layout's place.
        local top = scene_height and scene_height > base_height and math.floor((height - scene_height) / 2) or dy
        local picture_width, picture_height = picture_size(resource)
        -- OpenLF2 change (no bare viewport colour): the lowest opaque layer (`foot`) is stretched down to the viewport's bottom
        -- edge where the scene ends above it, and a scene narrower than the viewport is repeated to the left and to the right.
        -- [BELUM DIUJI] written without a way to run the game: the stretch uses `icon` like the sky does.
        -- `backing`: a copy drawn behind the scene to fill its holes; nothing outside the viewport, no stretch, no repeats.
        if backing and x + shift >= width then return end
        local drop = 0
        if foot and not keyed and picture_height then
            drop = math.max(0, height - (y + top + picture_height))
        end
        local function put(at, stretch_width)
            local w = stretch_width or picture_width
            if (drop > 0 or stretch_width) and w and picture_height then
                return context.icon(resource, at, y + top, w, picture_height + drop)
            end
            return context.image(resource, at, y + top, keyed)
        end
        if loop and loop > 0 then
            local at, copies = (x + shift) % loop - loop, 0
            while at < width and copies < 200 do
                put(at)
                at, copies = at + loop, copies + 1
            end
            return
        end
        local at = x + shift
        -- OpenLF2 change: a transparent picture of a scene narrower than the viewport that sits against the scene's left (or
        -- right) edge, such as a portrait bleeding off the side, keeps that edge on the screen's edge instead of floating in
        -- the middle with a cut-off edge; every other layer stays centred.
        if keyed and not backing and picture_width and scene_width < width then
            if x <= left then
                at = x - left
            elseif x + picture_width >= right then
                at = x - left + (width - scene_width)
            end
        end
        if sky and picture_width and at + picture_width < width then
            put(at, width - at)   -- the sky picture ends short of the viewport's right edge: it is stretched to reach it
        else
            put(at)
        end
        if scene_width < width and not backing and not keyed then
            -- copies of the whole scene to the left and right until the viewport is covered (at most 20 each side)
            local reach = picture_width or scene_width
            local k = 1
            while not sky and at + k * scene_width < width and k <= 20 do
                put(at + k * scene_width)
                k = k + 1
            end
            k = 1
            while at - k * scene_width + reach > 0 and k <= 20 do
                put(at - k * scene_width)
                k = k + 1
            end
        end
    end
    function wrapped.icon(resource, x, y, ...) return context.icon(resource, x + dx, y + dy, ...) end
    function wrapped.fill(x, y, ...) return context.fill(x + dx, y + dy, ...) end
    function wrapped.text(value, x, y, ...) return context.text(value, x + dx, y + dy, ...) end
    function wrapped.clip(x, y, ...)
        if x == nil then return context.clip() end
        return context.clip(x + dx, y + dy, ...)
    end
    return wrapped
end

return wide_menu
