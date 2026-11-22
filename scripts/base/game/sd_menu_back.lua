-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren menu backgrounds (system.dat `<menu_back_N>`, readme "system dat.txt"): which picture(s) and which colour a
-- menu screen shows. Block 1 is the launch and network screens', block 2 the title screen's (the colours 0x10206C and
-- 0x122565 those screens always drew). Without a block (original LF2) the screens keep their own picture and colour.
-- The screens call view() and paint() / commands(); nothing here draws by itself. Kept compatible with Lua 5.1/LuaJIT.
local system_data = require("base/game/system_data")
local wide_menu = require("base/ui/wide_menu")
local sd_menu_back = {}

local default_pictures = 13  -- pe/menu_back1 .. pe/menu_back13, sprite/menu/1.bmp .. 13.bmp
local repeat_limit = 20

-- The resource a layer's `pic:` is drawn as: the known menu pictures keep their pe/menu_back<N> name (their size and the
-- translations drawn over them are known by it), any other picture is drawn by its path.
local function resource_of(pic)
    local path = pic:lower():gsub("\\", "/"):gsub("^%s+", ""):gsub("%s+$", "")
    local number = path:match("^sprite/menu/(%d+)%.bmp$")
    if number and tonumber(number) >= 1 and tonumber(number) <= default_pictures then return "pe/menu_back" .. tonumber(number) end
    return path
end
sd_menu_back.resource_of = resource_of

-- The picture(s) of block `index` for the menu seed `seed` (0 .. n-1 picks like the screens' old `seed % 13 + 1`), or nil when
-- system.dat has no such block. {color = {r, g, b} or nil, layers = {{resource, x, y, keyed, loop, cc, c1, c2}}}.
function sd_menu_back.view(index, seed)
    local shown = system_data.menu_back_choose(index, function(count) return (seed or 0) % count end)
    if not shown then return nil end
    local view = {layers = {}}
    if shown.color then
        view.color = {math.floor(shown.color / 65536) % 256, math.floor(shown.color / 256) % 256, shown.color % 256}
    end
    for _, layer in ipairs(shown.layers) do
        view.layers[#view.layers + 1] = {resource = resource_of(layer.pic), x = layer.x or 0, y = layer.y or 0,
            keyed = layer.transparency ~= 0, loop = layer.loop, cc = layer.cc, c1 = layer.c1, c2 = layer.c2}
    end
    -- The width the pictures span (never under the classic 794): the wide menu viewport (wide_menu.wrap `backdrop`) starts a
    -- wider scene at its left edge and centres a narrower one. Looped layers are tiled, not measured.
    view.left, view.right = 0, 794
    for _, layer in ipairs(view.layers) do
        if not (layer.loop and layer.loop > 0) then
            local width = wide_menu.picture_width(layer.resource)
            if width then
                view.left = math.min(view.left, layer.x)
                view.right = math.max(view.right, layer.x + width)
            end
        end
    end
    -- The sky: of the opaque, unlooped layers on the top row the one reaching furthest right. On a viewport wider than the
    -- scene the wide menu stretches it to the right edge, so no bare viewport colour is left beside it.
    local top
    for _, layer in ipairs(view.layers) do
        if not layer.keyed and not (layer.loop and layer.loop > 0) and (not top or layer.y < top) then top = layer.y end
    end
    local reach = -1
    for index, layer in ipairs(view.layers) do
        if top and not layer.keyed and not (layer.loop and layer.loop > 0) and layer.y == top then
            local width = wide_menu.picture_width(layer.resource)
            if width and layer.x + width > reach then view.sky, reach = index, layer.x + width end
        end
    end
    return view
end

-- Is the layer shown at this tick? `cc`, `c1`, `c2` blink it like a bg.dat layer: visible c1..c2 of every cc ticks. No tick
-- (nil) or no cc: always.
local function visible(layer, tick)
    if not tick or not layer.cc or layer.cc <= 0 then return true end
    local phase = tick % layer.cc
    return phase >= (layer.c1 or 0) and phase <= (layer.c2 or layer.cc)
end

-- The draw commands of a view, one per shown layer: {"backdrop", resource, x, y, keyed, loop, left, right, sky}. `y_offset` moves
-- everything down (the title screen's vertical offset). Draw them with draw_command.
function sd_menu_back.commands(view, tick, y_offset)
    local commands = {}
    for index, layer in ipairs(view.layers) do
        if visible(layer, tick) then
            commands[#commands + 1] = {"backdrop", layer.resource, layer.x, layer.y + (y_offset or 0), layer.keyed,
                layer.loop or 0, view.left, view.right, index == view.sky}
        end
    end
    return commands
end

-- Draws one backdrop command. The wide menu context tiles a `loop:` picture across its whole viewport and centres a scene
-- wider than 794; a plain 794 context repeats it every loop pixels to the right edge (at most 20 times).
function sd_menu_back.draw_command(context, command)
    local resource, x, y, keyed, loop = command[2], command[3], command[4], command[5], command[6] or 0
    if context.backdrop then return context.backdrop(resource, x, y, keyed, loop, command[7], command[8], command[9]) end
    local copies = 1
    if loop > 0 then copies = math.min(repeat_limit, math.floor(794 / loop) + 1) end
    for copy = 0, copies - 1 do context.image(resource, x + copy * loop, y, keyed) end
end

function sd_menu_back.paint(context, view, tick, y_offset)
    for _, command in ipairs(sd_menu_back.commands(view, tick, y_offset)) do sd_menu_back.draw_command(context, command) end
end
return sd_menu_back
