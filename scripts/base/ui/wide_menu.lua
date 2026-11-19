-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- The launch menu and the title menu are laid out for the original 794 x 550 client area. On a wider window they get a viewport
-- as wide as the window (at the same 550 high) instead of a 794 one with bars at its sides: what the screens draw is moved to
-- the middle (everything by the same amount, the menu_back picture by its own width so a wider picture, e.g. 1018 x 550, is
-- seen whole), and the pointer is moved back the same way for them.
local constants = require("base/game/constants")

local wide_menu = {}
local base_width, base_height = constants.screen.width, constants.screen.height
local widest = 4096

-- The viewport width that has the window's shape at 550 high. `bounds` are the window's edges in viewport coordinates (the
-- host's `screen`); the ratio of its two sides is the window's whatever viewport they were taken in. Never narrower than 794:
-- a taller window keeps the 794 x 550 viewport and its bars above and below.
function wide_menu.viewport_width(bounds)
    if type(bounds) ~= "table" then return base_width end
    local width = (bounds.right or 0) - (bounds.left or 0)
    local height = (bounds.bottom or 0) - (bounds.top or 0)
    if not (width > 0 and height > 0) then return base_width end
    local wanted = math.floor(base_height * width / height + 0.5)
    if wanted <= base_width then return base_width end
    return math.min(wanted, widest)
end

-- Where the 794 wide layout starts in a viewport of `width`.
function wide_menu.shift(width)
    if width <= base_width then return 0 end
    return math.floor((width - base_width) / 2)
end

-- The width of a picture, read from its BMP (bytes 19 to 22, little endian) or PNG (bytes 17 to 20, big endian) header; nil
-- when it cannot be read.
local known = {}
function wide_menu.picture_width(resource)
    if known[resource] == nil then
        local width = false
        local ok, data = pcall(engine.read_resource, resource)
        if ok and type(data) == "string" then
            if #data >= 24 and data:sub(2, 4) == "PNG" then
                local a, b, c, d = data:byte(17, 20)
                width = ((a * 256 + b) * 256 + c) * 256 + d
            elseif #data >= 22 and data:sub(1, 2) == "BM" then
                local a, b, c, d = data:byte(19, 22)
                width = ((d * 256 + c) * 256 + b) * 256 + a
            end
        end
        known[resource] = (width and width >= 1 and width < 8192) and width or false
    end
    return known[resource] or nil
end

-- A menu_back picture is centred by its own width and drawn as it is; what is left of the viewport keeps the viewport colour.
local function background(context, width, resource, y, keyed)
    local picture = wide_menu.picture_width(resource) or base_width
    context.image(resource, math.floor((width - picture) / 2), y, keyed)
end

-- `context` as the menu screens see it: 794 wide coordinates, moved into a viewport `width` wide.
function wide_menu.wrap(context, width)
    local dx = wide_menu.shift(width)
    local wrapped = {}
    for name, command in pairs(context) do wrapped[name] = command end   -- what is not moved passes through as it is
    function wrapped.viewport(_, height, red, green, blue) return context.viewport(width, height, red, green, blue) end
    function wrapped.sprite(resource, source, x, y, ...) return context.sprite(resource, source, x + dx, y, ...) end
    function wrapped.image(resource, x, y, keyed)
        if type(resource) == "string" and resource:find("^pe/menu_back") then return background(context, width, resource, y, keyed) end
        return context.image(resource, x + dx, y, keyed)
    end
    function wrapped.icon(resource, x, y, ...) return context.icon(resource, x + dx, y, ...) end
    function wrapped.fill(x, y, ...) return context.fill(x + dx, y, ...) end
    function wrapped.text(value, x, y, ...) return context.text(value, x + dx, y, ...) end
    function wrapped.clip(x, ...)
        if x == nil then return context.clip() end
        return context.clip(x + dx, ...)
    end
    return wrapped
end

return wide_menu
