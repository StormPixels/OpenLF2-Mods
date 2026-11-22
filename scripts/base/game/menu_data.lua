-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren's data\menu.dat: where the pictures of the two menus sit and the author texts under them.
--   <menu1>  the launch menu, <menu2> the title menu: one `layer:` per picture, always in the same order
--            menu1: logo, option base, start, network, control, recording, website
--            menu2: logo, option base (`pic:` normal, `pic2:` network), vs, stage, 1 on 1, 2 on 2, battle, demo,
--                   recording, quit
--            fields: pic, pic2, transparency (1 = black is clear), respond, x, y, dx/dvx/dy/dvy (the pointer area)
--   <menu1_name>, <menu2_name>  up to 30 text layers: name (`_` is a space), facing (a link), bound (0 = hidden), hexf/hexb
--            (text/background colour, 0xBBGGRR), type (0 text, 1 shown only under the pointer and opens `facing`),
--            x, y, dx/dvx/dy/dvy
-- Everything answers nil when the file or a block is missing, so a game without it keeps the built-in layout.
-- [UNCERTAIN] `respond:` (kept, ignored) and `hexb:` (the port draws text without a box). Lua 5.1/LuaJIT compatible.
local sd_text = require("base/game/sd_text")
local wide_menu = require("base/ui/wide_menu")
local menu_data = {}

local max_text_layers = 30
local numbers = {layer = true, respond = true, transparency = true, x = true, y = true, dx = true, dvx = true, dy = true,
    dvy = true, bound = true, hexf = true, hexb = true, type = true}
local strings = {pic = true, pic2 = true, name = true, facing = true}

-- The known `key: value` pairs of a line. A value runs to the next known key, so an address (`http://...`) is not split at
-- its own colon the way sd_text.pairs_of_line would.
local function fields_of(line)
    local found, position = {}, 1
    while true do
        local first, last, key = line:find("([%a_][%w_]*)%s*:", position)
        if not first then break end
        if (numbers[key] or strings[key]) and (first == 1 or line:sub(first - 1, first - 1):match("%s")) then
            found[#found + 1] = {first = first, last = last, key = key}
        end
        position = last + 1
    end
    local out = {}
    for index, item in ipairs(found) do
        local stop = found[index + 1] and found[index + 1].first - 1 or #line
        out[#out + 1] = {item.key, sd_text.trim(line:sub(item.last + 1, stop))}
    end
    return out
end

-- The layers of a block in file order; a layer starts at `layer:` (or at a `pic:`/`name:` with none open).
local function layers_of(block, limit)
    local layers, current = {}, nil
    for _, line in ipairs(block.lines) do
        if line:match("^layer_end") then current = nil end
        for _, pair in ipairs(fields_of(line)) do
            local key, value = pair[1], pair[2]
            if key == "layer" or (not current and (key == "pic" or key == "name")) then
                if #layers < limit then
                    current = {index = key == "layer" and sd_text.int(value) or nil}
                    layers[#layers + 1] = current
                else current = nil end
            end
            if current and key ~= "layer" then
                current[key] = numbers[key] and sd_text.int(value) or value
            end
        end
    end
    return layers
end

local function picture_of(raw, index)
    local layer = {pic = raw.pic, pic2 = raw.pic2, x = raw.x, y = raw.y, respond = raw.respond or 0}
    if raw.transparency then layer.keyed = raw.transparency ~= 0 end
    if raw.dx and raw.dvx and raw.dy and raw.dvy then layer.hit = {raw.dx, raw.dvx, raw.dy, raw.dvy} end
    return layer
end

-- A Windows COLORREF (0xBBGGRR) as 0xRRGGBB.
local function colour(value)
    if not value then return nil end
    return (value % 256) * 65536 + (math.floor(value / 256) % 256) * 256 + math.floor(value / 65536) % 256
end

-- Only plain http(s) links; the host checks the address once more before it opens it.
local function link(value)
    if type(value) ~= "string" or #value > 512 or value:find("[%c%s]") then return nil end
    if value:match("^https?://%S+$") then return value end
    return nil
end

local function text_of(raw)
    if not raw.name or raw.x == nil or raw.y == nil then return nil end
    return {name = raw.name:gsub("_", " "):sub(1, 100), url = link(raw.facing), bound = raw.bound == nil and 1 or raw.bound,
        color = colour(raw.hexf) or 0x5077d0, kind = raw.type or 0, x = raw.x, y = raw.y,
        hit = raw.dx and raw.dvx and raw.dy and raw.dvy and {raw.dx, raw.dvx, raw.dy, raw.dvy} or nil}
end

-- Parses the text of menu.dat into {menu1 = {[n] = picture}, menu2 = {...}, names1 = {text...}, names2 = {...}}; a block
-- without a usable layer is absent. The first usable block of a name wins.
function menu_data.parse(text)
    local result = {}
    for _, block in ipairs(sd_text.scan(text).blocks) do
        local number = block.name:match("^menu([12])$")
        local names = block.name:match("^menu([12])_name$")
        if number and not result["menu" .. number] then
            local pictures, any = {}, false
            for position, raw in ipairs(layers_of(block, 100)) do
                if raw.pic then pictures[raw.index or position] = picture_of(raw); any = true end
            end
            if any then result["menu" .. number] = pictures end
        elseif names and not result["names" .. names] then
            local texts = {}
            for _, raw in ipairs(layers_of(block, max_text_layers)) do
                local entry = text_of(raw)
                if entry then texts[#texts + 1] = entry end
            end
            if #texts > 0 then result["names" .. names] = texts end
        end
    end
    return result
end

local parsed, settled = nil, false
-- Replaces the data (tests). nil forgets it so the next read loads again.
function menu_data.set_text(text)
    parsed, settled = text and menu_data.parse(text) or nil, text ~= nil
end

local function data()
    if settled then return parsed end
    local text, message = sd_text.read("data/menu.dat")
    if text then
        parsed, settled = menu_data.parse(text), true
    elseif not sd_text.not_ready(message) then
        settled = true  -- no menu.dat: the built-in layout
    end
    return parsed
end

-- The picture layers of menu `index` (1 launch, 2 title) or nil; layer n is `[n]`.
function menu_data.pictures(index)
    local all = data()
    return all and all["menu" .. index] or nil
end

-- The text layers under menu `index` or nil.
function menu_data.names(index)
    local all = data()
    return all and all["names" .. index] or nil
end

local readable = {}
-- The resource of a layer's `pic:` when the game has that picture, else nil (the built-in picture is drawn).
function menu_data.picture(path)
    if type(path) ~= "string" or path == "" then return nil end
    local resource = path:gsub("\\", "/"):lower()
    if readable[resource] == nil then readable[resource] = wide_menu.picture_width(resource) ~= nil end
    return readable[resource] and resource or nil
end

-- What to draw for the text layers with the pointer at (pointer_x, pointer_y); `measure(text)` is the text's width.
-- A type 0 layer is always shown, a type 1 layer only while the pointer is over it. Each result is
-- {value, x, y, color, url, hover}.
function menu_data.texts(layers, pointer_x, pointer_y, measure)
    local out = {}
    for _, layer in ipairs(layers) do
        if layer.bound ~= 0 then
            local hit = layer.hit or {layer.x, layer.x + measure(layer.name), layer.y, layer.y + 15}
            local hover = pointer_x >= hit[1] and pointer_x <= hit[2] and pointer_y >= hit[3] and pointer_y <= hit[4]
            if layer.kind == 0 or hover then
                out[#out + 1] = {value = layer.name, x = layer.x, y = layer.y, color = layer.color,
                    url = layer.kind == 1 and layer.url or nil, hover = hover}
            end
        end
    end
    return out
end

return menu_data
