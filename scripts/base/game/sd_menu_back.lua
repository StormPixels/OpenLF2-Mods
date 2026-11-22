-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren menu backgrounds (system.dat `<menu_back_N>`, readme "system dat.txt"): which picture(s) and which colour a
-- menu screen shows. Block 1 is the launch and network screens', block 2 the title screen's (the colours 0x10206C and
-- 0x122565 those screens always drew). Without a block (original LF2) the screens keep their own picture and colour.
-- The screens call view() and paint() / commands(); nothing here draws by itself. Kept compatible with Lua 5.1/LuaJIT.
local system_data = require("base/game/system_data")
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
    return view
end

-- Is the layer shown at this tick? `cc`, `c1`, `c2` blink it like a bg.dat layer: visible c1..c2 of every cc ticks. No tick
-- (nil) or no cc: always.
local function visible(layer, tick)
    if not tick or not layer.cc or layer.cc <= 0 then return true end
    local phase = tick % layer.cc
    return phase >= (layer.c1 or 0) and phase <= (layer.c2 or layer.cc)
end

-- The draw commands of a view: {"image", resource, x, y, keyed}, a picture with `loop:` repeated every loop pixels to the
-- right edge (at most 20 times). `y_offset` moves everything down (the title screen's vertical offset).
function sd_menu_back.commands(view, tick, y_offset)
    local commands = {}
    for _, layer in ipairs(view.layers) do
        if visible(layer, tick) then
            local copies = 1
            if layer.loop and layer.loop > 0 then copies = math.min(repeat_limit, math.floor(794 / layer.loop) + 1) end
            for copy = 0, copies - 1 do
                commands[#commands + 1] = {"image", layer.resource, layer.x + copy * (layer.loop or 0), layer.y + (y_offset or 0), layer.keyed}
            end
        end
    end
    return commands
end

function sd_menu_back.paint(context, view, tick, y_offset)
    for _, command in ipairs(sd_menu_back.commands(view, tick, y_offset)) do
        context.image(command[2], command[3], command[4], command[5])
    end
end
return sd_menu_back
