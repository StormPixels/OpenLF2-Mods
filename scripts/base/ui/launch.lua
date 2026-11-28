-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local controls = require("base/ui/controls")
local font = require("base/ui/font")
local i18n = require("base/i18n/i18n")
local sounds = require("base/game/sounds")
local options = require("base/game/options")
local ui_modes = require("base/game/ui_modes")
local ui_hud = require("base/game/ui_hud")
local navigation = require("base/ui/navigation")
local constants = require("base/game/constants")
local sd_menu_back = require("base/game/sd_menu_back")  -- HOOK(AI5): system.dat <menu_back_N>
local tipe_game = require("base/game/tipe_game")
local menu_data = require("base/game/menu_data")  -- HOOK(AI5): data\\menu.dat
local virtual_keys = constants.virtual_keys
local screen = {}

local menu_clip = {[7] = {535, 105, 256, 26}, [8] = {535, 137, 256, 26},
    [9] = {535, 168, 256, 29}, [12] = {643, 426, 151, 26}, [13] = {489, 426, 151, 26}}
local menu_clip2 = {[0] = {0, 0, 704, 353}, {0, 354, 494, 23}, {0, 379, 494, 23}}
local menu_clip5 = {[0] = {0, 0, 282, 181}, {285, 0, 240, 27}, {285, 32, 240, 27}}
local devices = {[constants.input_devices.keyboard] = "pe/cs6",
    [constants.input_devices.controller_one] = "pe/cs2", [constants.input_devices.controller_two] = "pe/cs3",
    [constants.input_devices.controller_three] = "pe/cs4", [constants.input_devices.controller_four] = "pe/cs5"}
local menu_clip6 = {[0] = {0, 0, 704, 312}, {0, 360, 439, 23}, {0, 385, 439, 23}, {0, 411, 704, 258},
    {0, 673, 543, 24}, {548, 363, 19, 19}, {572, 363, 19, 19}, {443, 388, 343, 22}}

-- Recording page on the compact MENU_CLIP6 sheet of the mod (794 x 264, as in u17): no e-mail field, no "recorded" notice page, no help
-- links; dialog 704 x 236, tick sprites at y 244, hover of "open folder" at x 51, y 244. Everything below the info box sits 76 px higher
-- than on the vanilla sheet (704 x 312). The kind of game decides (tipe_game): true for Darkfiren. [MEASURED on the sheet, not read from the exe]
local compact_sheet = tipe_game.get("compact_sheet", false)  -- per game kind, see base/game/tipe_game.lua
local compact_clip6 = {[0] = {0, 0, 704, 236}, [5] = {0, 244, 19, 19}, [6] = {24, 244, 19, 19}, [7] = {51, 244, 343, 19}}

local function note(message) return message and i18n.clip(message, 96) or nil end

-- options: menu_seed (background choice, like the title), problem (why config was ignored).
function screen.create(options)
    -- Four lines; each is a list of pieces {text, action, gap}: a piece with an action is a link (as in the original,
    -- the authors' names link to their sites), `gap` is the space after it.
    local credits = {
        {{"by "}, {"Marti Wong", "open_marti_website"}, {", "}, {"Starsky Wong", "open_starsky_website"},
            {" & OpenLF2 team"}},
        {{"1999-2008, all rights reserved"}},
        {{"2026+, MIT licensed"}},
        {{"lf2.net", "open_original_website", 16}, {"openlf2.github.io/OpenLF2", "open_website"}},
    }
    return {page = "menu", background = (options.menu_seed or 0) % 13 + 1, menu_seed = options.menu_seed or 0, nav = navigation.create(), keyboard = false,
        display = {}, capture = nil, name_player = 0, previous_keys = {}, credits = credits,
        message = options.problem and note(i18n.tr("Configuration ignored: %s", options.problem))}
end

local function add(state, command) state.display[#state.display + 1] = command end
local function sprite(state, sheet, rectangle, x, y, keyed, mirrored, flipped)
    add(state, {"sprite", sheet, rectangle, x, y, keyed, mirrored, flipped})
end
local function image(state, path, x, y, keyed) add(state, {"image", path, x, y, keyed}) end
-- The whole logo, with the "ver 2.0a" in its bottom-right corner.
local function logo(state, y)
    sprite(state, "pe/menu_clip", {0, 41, 496, 80}, 0x9b, y, true)
end
-- GDI text (an entry with a fifth field, the variant, is the original's bitmap font instead).
local function text(state, value, x, y, color, background) add(state, {"text", value, x, y, nil, color, background}) end
-- A name or key on the controls page: the original draws it on a box as wide as its text, at `left`. A
-- translated language centers it in the page's dark box of the whole column (`x`, as wide as the device picture).
local function field(state, value, x, left, y, color, box)
    if not i18n.active() then return text(state, value, left, y, color, box) end
    add(state, {"text", value, x + 0x35, y, nil, color, nil, "center"})
end
local function inside(input, left, top, right, bottom)
    return input.pointer_x >= left and input.pointer_x <= right and input.pointer_y >= top and input.pointer_y <= bottom
end

local function background(state)
    local back = sd_menu_back.view(1, state.menu_seed)  -- HOOK(AI5): block <menu_back_1> of system.dat (nil without one)
    local color = back and back.color or {0x10, 0x20, 0x6c}
    add(state, {"fill", 0, 0, constants.screen.width, constants.screen.height, color[1], color[2], color[3]})
    if back then for _, command in ipairs(sd_menu_back.commands(back, state.menu_ticks)) do add(state, command) end
    else image(state, "pe/menu_back" .. state.background, 0, 0, true) end
end

-- One picture of menu.dat's <menu1>: its place (the built-in one when unset), its own picture when the game has it (else the
-- built-in sprite of `sheet`) and whether black is clear.
local function menu_picture(state, data, sheet, rectangle, x, y, keyed)
    x, y = data and data.x or x, data and data.y or y
    if data and data.keyed ~= nil then keyed = data.keyed end
    local custom = data and menu_data.picture(data.pic)
    if custom then image(state, custom, x, y, keyed) else sprite(state, sheet, rectangle, x, y, keyed) end
end
-- The five entries under the base picture: the picture shown while the pointer is over one, its place and its pointer area
-- {left, right, top, bottom} (menu.dat's dx, dvx, dy, dvy).
local menu_entries = {
    {"pe/menu_clip", menu_clip[7], 0x115, 0xca + 0xd, {0x114, 0x208, 0xca + 0xf, 0xca + 0x27}},
    {"pe/menu_clip", menu_clip[8], 0x115, 0xca + 0x2d, {0x114, 0x208, 0xca + 0x2d, 0xca + 0x46}},
    {"pe/menu_clip", menu_clip[9], 0x115, 0xca + 0x4c, {0x114, 0x208, 0xca + 0x4d, 0xca + 0x66}},
    {"pe/menu_clip5", menu_clip5[1], 0x117, 0xca + 0x6b, {0x114, 0x208, 0xca + 0x6b, 0xca + 0x84}},
    {"pe/menu_clip5", menu_clip5[2], 0x117, 0xca + 0x8b, {0x114, 0x208, 0xca + 0x89, 0xca + 0xa2}},
}
local function activate_entry(state, input, context, index)
    sounds.direct(state, "ok")
    if index == 1 then
        state.page = "waiting"
    elseif index == 2 then
        state.page = "network"
    elseif index == 3 then
        state.page = "controls"
        -- The original keeps the edited name between visits; the port starts idle.
        state.name_player = 0
        state.editing = controls.copy(controls.current())
        state.previous_keys = input.keys
    elseif index == 4 then
        local settings = controls.current()
        state.page = "recording"
        state.record = {record = settings.record, author = settings.author, email = settings.email, info = settings.info}
        state.previous_keys = input.keys
    else
        -- OpenLF2's project site; the credits link opens the original game's site.
        context.action("open_website")
    end
end

local function menu(state, input, context)
    background(state)
    text(state, engine.build_label, 790 - font.gdi_width(engine.build_label), 4, 0x5077d0)
    local names = menu_data.names(1)
    if names then
        -- menu.dat's <menu1_name>: the game's own text lines and links replace the built-in credits.
        for _, item in ipairs(menu_data.texts(names, input.pointer_x, input.pointer_y, font.gdi_width)) do
            text(state, item.value, item.x, item.y, item.color)
            if item.hover and item.url and input.click then
                sounds.direct(state, "ok")
                context.open_url(item.url)
            end
        end
    else
        -- The block is left-aligned, as far right as its widest line allows; the last line (the links) sits a little
        -- apart from the others.
        local widest = 0
        for _, line in ipairs(state.credits) do
            local width = 0
            for _, entry in ipairs(line) do width = width + font.gdi_width(entry[1]) + (entry[3] or 0) end
            widest = math.max(widest, width - (line[#line][3] or 0))
        end
        local left = math.min(0x24f, 790 - widest)
        for index, line in ipairs(state.credits) do
            local y = 0x213 - (#state.credits - index) * 0x14 - (index < #state.credits and 6 or 0)
            local x = left
            for _, entry in ipairs(line) do
                local value, action = entry[1], entry[2]
                local width = font.gdi_width(value)
                local hover = action and inside(input, x, y, x + width, y + 15)
                text(state, value, x, y, hover and 0xffffff or 0x5077d0)
                if hover and input.click then
                    sounds.direct(state, "ok")
                    context.action(action)
                end
                x = x + width + (entry[3] or 0)
            end
        end
    end
    -- The pictures: menu.dat's <menu1> moves them, and swaps in its own pictures when the game has them.
    local layers = menu_data.pictures(1) or {}
    menu_picture(state, layers[1], "pe/menu_clip", {0, 41, 496, 80}, 0x9b, 0x60, true)
    menu_picture(state, layers[2], "pe/menu_clip5", menu_clip5[0], 0x107, 0xca, true)
    for index, entry in ipairs(menu_entries) do
        local data = layers[index + 2]
        local hit = data and data.hit or entry[5]
        if input.pointer_x >= hit[1] and input.pointer_x <= hit[2] and input.pointer_y >= hit[3] and input.pointer_y <= hit[4] then
            menu_picture(state, data, entry[1], entry[2], entry[3], entry[4], true)
            if input.click then activate_entry(state, input, context, index) end
            break
        end
    end
end

-- OpenLF2's options entry (not in the original), spelled from the menu art's own letters;
-- 'p' is 'b' flipped vertically.
local options_row = {top = 0xca + 0xa7, bottom = 0xca + 0xc0, baseline = 0xca + 157 + 31}
local letters = {
    normal = {o = {20, 147, 10, 11}, t = {149, 144, 7, 14}, i = {144, 143, 2, 15}, s = {133, 147, 8, 11},
        n = {133, 116, 8, 11}, b = {122, 142, 9, 16}},
    pointed = {o = {289, 40, 10, 11}, t = {418, 37, 7, 14}, i = {413, 36, 2, 15}, s = {402, 40, 8, 11},
        n = {402, 9, 8, 11}, b = {391, 35, 9, 16}},
}
local function spell_options(state, set)
    local x = 363
    for letter in ("options"):gmatch(".") do
        if letter == "p" then
            local b = set.b
            sprite(state, "pe/menu_clip5", b, x, options_row.baseline - 10, true, false, true)
            x = x + b[3] + 3
        else
            local glyph = set[letter]
            sprite(state, "pe/menu_clip5", glyph, x, options_row.baseline - glyph[4] + 1, true)
            x = x + glyph[3] + 3
        end
    end
end
local function options_entry(state, input)
    local pointed = input.pointer_x >= 0x114 and input.pointer_x <= 0x208
        and input.pointer_y >= options_row.top and input.pointer_y <= options_row.bottom
    if i18n.active() then
        -- The letters only spell "options": a translated language draws the label as text like the other captions
        -- (size and colors of their baked text), centered in the row.
        local size = 18
        add(state, {"text", i18n.tr("options"), 398, math.floor((options_row.top + options_row.bottom) / 2 - 0.63 * size + 0.5),
            nil, pointed and 0xffffff or 0x5a77d8, nil, "center", size})
    else
        spell_options(state, pointed and letters.pointed or letters.normal)
    end
    if pointed and input.click then
        sounds.direct(state, "ok")
        state.page = "options"
        state.options_focus = nil
        state.options = options.current()
    end
end

-- One ordered list drives visibility, layout, drawing, and navigation.
-- `available` gets the host's features and the values being edited; a dropdown's `display` turns a
-- value into its text (default: translated).
local option_rows = {
    -- The game folders of LF2_ENGINE (Android); the app restarts to open the pick. Hidden where the host lists none.
    {key = "game", label = "Game", choices = options.game_names, display = options.game_label, grid = true,
        available = function() return #options.game_names() > 0 end},
    -- Only hosts that can draw TrueType text have another language to offer; elsewhere the page stays as it was.
    {key = "language", label = "Language", choices = options.available_languages, display = i18n.language_label,
        available = function(features) return features.text end},
    {key = "font_antialiasing", label = "Font antialiasing",
        available = function(_, values) return values.language ~= "default" end},
    {key = "unlock_characters", label = "Unlock hidden characters"},
    {key = "upscaling_filter", label = "Upscaling filter", choices = options.available_filters},
    -- classic and expand are built in; every other layout is a mode of the game's data/mode.dat (named as it names it).
    {key = "battlefield_layout", label = "Battlefield layout", choices = options.battlefield_layouts, display = options.layout_label},
    -- The HUD styles of the game (data/frame.dat); the row is only there when the game has a frame.dat.
    {key = "hud_style", label = "HUD style", choices = ui_hud.names, display = function(value) return value end,
        available = function() return #ui_hud.entries() > 0 end},
    {key = "fullscreen", label = "Fullscreen", available = function(features) return features.window end},
    {key = "show_fps", label = "Show FPS"},
    {key = "rumble", label = "Rumble"},
    {key = "character_shading", label = "Character shading"},
    {key = "projected_shadows", label = "Projected shadows"},
}
local function options_layout(features, values)
    local visible = {}
    for _, option in ipairs(option_rows) do
        if not option.available or option.available(features or {}, values or {}) then visible[#visible + 1] = option end
    end
    -- With more rows than the screen has room for (the page is 10 rows high at most as it was), the panel moves up.
    local panel = {x = 0x93, y = 0x90 - math.max(0, #visible - 10) * 0x1a, width = 0x1f4}
    local rows = {}
    for _, option in ipairs(visible) do
        do
            local y = panel.y + 0x46 + #rows * 0x1a
            local box = option.choices
                and {x = panel.x + 0xf3, y = y, width = 0xc0, height = 18}
                or {x = panel.x + 0x1e, y = y, size = 19}
            rows[#rows + 1] = {option = option, box = box}
        end
    end
    local button_y = panel.y + 0x46 + #rows * 0x1a + 7
    panel.height = button_y - panel.y + 0x1a + 0x1d
    return {panel = panel, rows = rows,
        ok = {x = panel.x + 0x5a, y = button_y, width = 0x78, height = 0x1a},
        cancel = {x = panel.x + 0x104, y = button_y, width = 0x78, height = 0x1a}}
end
local function bold(state, value, x, y, variant, align)
    for _, offset in ipairs({{-1, 1}, {-1, 0}, {0, 1}, {0, 0}}) do
        add(state, {"text", value, x + offset[1], y + offset[2], variant, nil, nil, align})
    end
end
-- `blocked`: something drawn over the button (the open dropdown list) takes the pointer.
local function button(state, input, area, label, blocked)
    local pointed = not blocked and inside(input, area.x, area.y, area.x + area.width, area.y + area.height)
    add(state, {"fill", area.x, area.y, area.width, area.height, 0xa0, 0xa0, 0xc0})
    add(state, {"fill", area.x + 1, area.y + 1, area.width - 2, area.height - 2,
        pointed and 0x32 or 0x10, pointed and 0x4d or 0x20, pointed and 0x9a or 0x50})
    bold(state, label, area.x + math.floor(area.width / 2), area.y + 5, pointed and constants.font_variants.blue or constants.font_variants.white, "center")
    return pointed and input.click
end
local function option_dropdown(state, input, values, row, focus, was_open)
    local box, option = row.box, row.option
    local choices = option.choices(input.filters)
    if input.click and (not was_open or was_open == option.key) then
        if inside(input, box.x, box.y, box.x + box.width, box.y + box.height) then
            state.option_open = state.option_open ~= option.key and option.key or nil
            state.options_focus = focus
        elseif state.option_open == option.key then
            for index, filter in ipairs(choices) do
                local y = box.y + index * box.height
                if inside(input, box.x, y, box.x + box.width, y + box.height) then
                    values[option.key] = filter
                    sounds.direct(state, "ok")
                    break
                end
            end
            state.option_open = false
            state.options_focus = focus
        end
    end
    bold(state, i18n.tr(option.label), box.x - 0xd5, box.y + 1, constants.font_variants.white)
    add(state, {"fill", box.x, box.y, box.width, box.height, 0xa0, 0xa0, 0xc0})
    add(state, {"fill", box.x + 2, box.y + 2, box.width - 4, box.height - 4, 0x10, 0x20, 0x50})
    bold(state, (option.display or i18n.tr)(values[option.key]), box.x + 9, box.y + 1, constants.font_variants.blue)
    bold(state, state.option_open == option.key and "^" or "v", box.x + box.width - 18, box.y + 1, constants.font_variants.blue)
end
-- The open list draws last, so it can reach over the OK/Cancel buttons.
local function option_list(state, input, row)
    local box = row.box
    for index, filter in ipairs(row.option.choices(input.filters)) do
        local y = box.y + index * box.height
        local pointed = inside(input, box.x, y, box.x + box.width, y + box.height)
        add(state, {"fill", box.x, y, box.width, box.height, 0xa0, 0xa0, 0xc0})
        add(state, {"fill", box.x + 2, y + 2, box.width - 4, box.height - 4,
            pointed and 0x32 or 0x10, pointed and 0x4d or 0x20, pointed and 0x9a or 0x50})
        bold(state, (row.option.display or i18n.tr)(filter), box.x + 9, y + 1, pointed and constants.font_variants.blue or constants.font_variants.white)
    end
end
-- `blocked`: like button()'s, the open dropdown list takes the pointer.
local function checkbox(state, input, box, label, checked, blocked)
    local label_x = box.x + box.size + 12
    local pointed = not blocked and inside(input, box.x, box.y, label_x + font.width(label), box.y + box.size)
    add(state, {"fill", box.x, box.y, box.size, box.size, 0xa0, 0xa0, 0xc0})
    add(state, {"fill", box.x + 2, box.y + 2, box.size - 4, box.size - 4, pointed and 0x32 or 0x08,
        pointed and 0x4d or 0x10, pointed and 0x9a or 0x30})
    if checked then bold(state, "x", box.x + 6, box.y + 1, constants.font_variants.blue) end
    bold(state, label, label_x, box.y + 1, pointed and constants.font_variants.blue or constants.font_variants.white)
    return pointed and input.click
end
-- The game picker (Android): one cell per game folder of LF2_ENGINE, 6 across and 5 down, the first game at the top left and
-- the rest left to right, row by row. A cell is the executable's icon (resource "game/icon/<n>", n from 0) with the folder name
-- below; OK takes the marked game into the options page, Cancel leaves the pick as it was. More than 30 games add page buttons.
local grid_columns, grid_rows, grid_cell = 6, 5, {width = 118, height = 78, icon = 48}
local function grid_layout(state)
    local names = options.game_names()
    local per_page = grid_columns * grid_rows
    local pages = math.max(1, math.ceil(#names / per_page))
    local page = math.max(0, math.min(state.grid.page, pages - 1))
    local panel = {x = 24, y = 14, width = 746}
    local left = panel.x + math.floor((panel.width - grid_columns * grid_cell.width) / 2)
    local top = panel.y + 52
    local cells = {}
    for slot = 0, per_page - 1 do
        local index = page * per_page + slot + 1
        if index > #names then break end
        cells[#cells + 1] = {index = index, name = names[index],
            x = left + (slot % grid_columns) * grid_cell.width, y = top + math.floor(slot / grid_columns) * grid_cell.height}
    end
    local button_y = top + grid_rows * grid_cell.height + 10
    panel.height = button_y - panel.y + 0x1a + 14
    local middle = panel.x + math.floor(panel.width / 2)
    return {panel = panel, cells = cells, pages = pages, page = page,
        ok = {x = middle - 0x78 - 12, y = button_y, width = 0x78, height = 0x1a},
        cancel = {x = middle + 12, y = button_y, width = 0x78, height = 0x1a},
        previous = {x = panel.x + 20, y = button_y, width = 0x3c, height = 0x1a},
        next = {x = panel.x + panel.width - 20 - 0x3c, y = button_y, width = 0x3c, height = 0x1a}}
end
-- The folder name cut to the width of a cell.
local function grid_name(name)
    local room = grid_cell.width - 8
    if font.width(name) <= room then return name end
    while #name > 1 and font.width(name .. "..") > room do name = name:sub(1, -2) end
    return name .. ".."
end
local function open_game_picker(state)
    local selected = 1
    for index, name in ipairs(options.game_names()) do
        if name == options.game_label(state.options.game) then selected = index end
    end
    state.grid = {selected = selected, page = math.floor((selected - 1) / (grid_columns * grid_rows))}
    state.page = "game_grid"
end
local function game_grid_page(state, input, context)
    background(state)
    local layout = grid_layout(state)
    local panel = layout.panel
    add(state, {"fill", panel.x, panel.y, panel.width, panel.height, 0xa0, 0xa0, 0xc0})
    add(state, {"fill", panel.x + 2, panel.y + 2, panel.width - 4, panel.height - 4, 0x10, 0x20, 0x50})
    bold(state, i18n.tr("Select game"), panel.x + 20, panel.y + 18, constants.font_variants.blue)
    if layout.pages > 1 then
        bold(state, string.format("%d/%d", layout.page + 1, layout.pages), panel.x + panel.width - 20, panel.y + 18,
            constants.font_variants.white, "right")
    end
    for _, cell in ipairs(layout.cells) do
        local pointed = inside(input, cell.x, cell.y, cell.x + grid_cell.width - 1, cell.y + grid_cell.height - 1)
        local marked = cell.index == state.grid.selected
        if marked or pointed then
            -- Only the border changes: the icon is drawn on the panel's own blue, so the cell keeps that color.
            local r, g, b = marked and 0xff or 0x70, marked and 0xd0 or 0x80, marked and 0x40 or 0xd0
            add(state, {"fill", cell.x + 1, cell.y + 1, grid_cell.width - 2, grid_cell.height - 2, r, g, b})
            add(state, {"fill", cell.x + 3, cell.y + 3, grid_cell.width - 6, grid_cell.height - 6, 0x10, 0x20, 0x50})
        end
        add(state, {"icon", "game/icon/" .. (cell.index - 1), cell.x + math.floor((grid_cell.width - grid_cell.icon) / 2),
            cell.y + 6, grid_cell.icon, grid_cell.icon})
        bold(state, grid_name(cell.name), cell.x + math.floor(grid_cell.width / 2), cell.y + 6 + grid_cell.icon + 5,
            marked and constants.font_variants.yellow or constants.font_variants.white, "center")
        if pointed and input.click then
            state.grid.selected = cell.index
            sounds.direct(state, "ok")
        end
    end
    if layout.pages > 1 then
        if layout.page > 0 and button(state, input, layout.previous, "<") then state.grid.page = layout.page - 1 end
        if layout.page < layout.pages - 1 and button(state, input, layout.next, ">") then state.grid.page = layout.page + 1 end
    end
    if button(state, input, layout.ok, i18n.tr("OK")) then
        sounds.direct(state, "ok")
        state.options.game = options.game_names()[state.grid.selected] or state.options.game
        state.page, state.grid = "options", nil
    elseif button(state, input, layout.cancel, i18n.tr("Cancel")) or input.nav.cancel then
        sounds.direct(state, "cancel")
        state.page, state.grid = "options", nil
    end
end

local function options_page(state, input, context)
    background(state)
    logo(state, 0x37)
    local layout = options_layout(input.filters, state.options)
    local panel = layout.panel
    add(state, {"fill", panel.x, panel.y, panel.width, panel.height, 0xa0, 0xa0, 0xc0})
    add(state, {"fill", panel.x + 2, panel.y + 2, panel.width - 4, panel.height - 4, 0x10, 0x20, 0x50})
    bold(state, i18n.tr("Options"), panel.x + 0x1e, panel.y + 0x14, constants.font_variants.blue)
    local values = state.options
    -- The player cannot read the log: a wide layout that runs on OpenLF2's own layout data (the game's mode file could
    -- not be read) says so here.
    if ui_modes.layout_source(values.battlefield_layout) == "builtin" then
        bold(state, i18n.tr("Wide layout: the game's mode2.dat was not read, built-in layout used"), panel.x + 0x1e, panel.y + 0x2e, constants.font_variants.yellow)
    end
    -- Alt+Enter (handled by the flow) changed the saved option: the page follows.
    if input.fullscreen_set ~= nil then values.fullscreen = input.fullscreen_set end
    local was_open = state.option_open
    local open_focus
    for index, row in ipairs(layout.rows) do
        local option = row.option
        if option.grid then
            -- The game row: a button that opens the picker (no dropdown).
            local box = row.box
            local pointed = not was_open and inside(input, box.x, box.y, box.x + box.width, box.y + box.height)
            bold(state, i18n.tr(option.label), box.x - 0xd5, box.y + 1, constants.font_variants.white)
            add(state, {"fill", box.x, box.y, box.width, box.height, 0xa0, 0xa0, 0xc0})
            add(state, {"fill", box.x + 2, box.y + 2, box.width - 4, box.height - 4,
                pointed and 0x32 or 0x10, pointed and 0x4d or 0x20, pointed and 0x9a or 0x50})
            bold(state, i18n.tr("Select"), box.x + math.floor(box.width / 2), box.y + 1,
                pointed and constants.font_variants.white or constants.font_variants.blue, "center")
            if pointed and input.click then
                sounds.direct(state, "ok")
                state.options_focus = index
                open_game_picker(state)
            end
        elseif option.choices then
            if was_open == option.key then open_focus = index end
            option_dropdown(state, input, values, row, index, was_open)
        elseif checkbox(state, input, row.box, i18n.tr(option.label), values[option.key], was_open) then
            values[option.key] = not values[option.key]
        end
    end
    if button(state, input, layout.ok, i18n.tr("OK"), was_open) and not was_open then
        sounds.direct(state, "ok")
        local saved, problem = options.save(values)
        state.message = not saved and note(i18n.tr("Options not saved: %s", tostring(problem))) or nil
        state.page, state.options, state.option_open = "menu", nil, false
        -- Another game was picked: the host restarts the app, which then opens it.
        if saved and options.game_differs(values.game) then context.action("restart_game") end
    elseif button(state, input, layout.cancel, i18n.tr("Cancel"), was_open) and not was_open then
        sounds.direct(state, "cancel")
        state.page, state.options, state.option_open = "menu", nil, false
    elseif input.nav.cancel and state.page == "options" then
        -- Escape or B closes the list, or else cancels like the button.
        sounds.direct(state, "cancel")
        if state.option_open then
            state.option_open, state.options_focus = false, open_focus
        else
            state.page, state.options = "menu", nil
        end
    end
    if state.page == "options" and state.option_open then
        for _, row in ipairs(layout.rows) do
            if row.option.key == state.option_open then option_list(state, input, row) end
        end
    end
end

-- Arrow keys move focus; the original treated them as numpad digits, so text fields ignore them.
local function typed_character(input, code)
    if code >= virtual_keys.left and code <= virtual_keys.down then return nil end
    return controls.key_character(code, input.keys[virtual_keys.shift] == true)
end

local function type_name(state, input)
    local name = state.editing.names[state.name_player]
    for code = 0, 255 do
        if input.keys[code] and not state.previous_keys[code] then
            local character = typed_character(input, code)
            if character and code ~= virtual_keys.backspace then
                if #name < constants.text_limits.player_name_bytes and code ~= virtual_keys.enter then name = name .. character end
            elseif code == virtual_keys.backspace and #name > 0 then
                name = name:sub(1, -2)
            end
        end
    end
    name = (name .. input.text):sub(1, constants.text_limits.player_name_bytes)
    state.editing.names[state.name_player] = name
end

-- Escape, Tab or B end editing; so do Enter/A unless Enter adds a line (`multiline`).
local function leaves_field(state, input, multiline)
    return input.nav.cancel or (input.nav.ok and not multiline)
        or (input.keys[virtual_keys.tab] and not state.previous_keys[virtual_keys.tab])
end

-- Four player columns: name, device picture, seven key rows, and the OK/Cancel buttons.
local function control_settings(state, input, context)
    background(state)
    logo(state, 0x23)
    sprite(state, "pe/menu_clip2", menu_clip2[0], 0x2e, 0x79, true)
    -- The link bar opens the original game's special-move table.
    local link = inside(input, 0x2e, 0x1db, 0x21c, 0x1f2) and 2 or 1
    sprite(state, "pe/menu_clip2", menu_clip2[link], 0x2e, 0x1db, true)
    if link == 2 and input.click then
        sounds.direct(state, "ok")
        context.action("open_special_moves")
    end
    local editing = state.editing
    -- A pending assignment takes the lowest held key/button; Escape cancels a keyboard set
    -- (reserved for Back) but is just a button on joystick sets. The opening button is
    -- ignored until released.
    if state.capture then
        local set = editing.sets[state.capture.player]
        if set.device == constants.input_devices.keyboard then
            if input.nav.cancel then
                state.capture = nil
            else
                for code = 0, 249 do
                    if input.keys[code] then
                        set.keys[state.capture.row] = code
                        state.capture = nil
                        break
                    end
                end
            end
        elseif input.keys[virtual_keys.escape] and not state.previous_keys[virtual_keys.escape] then
            state.capture = nil
        else
            local pad, lowest = input.pads[set.device], nil
            for button = 0, 31 do
                if pad and pad.buttons[button] then lowest = button; break end
            end
            if not lowest then state.capture.armed = true
            elseif state.capture.armed then
                set.buttons[state.capture.row - 4] = lowest
                state.capture = nil
            end
        end
    end
    if state.name_player > 0 then
        if leaves_field(state, input, false) then state.name_player = 0 else type_name(state, input) end
    end
    local finished
    for player = 1, 4 do
        local x = 0xc2 + (player - 1) * 0x8b
        local set = editing.sets[player]
        local name = editing.names[player]
        if input.click and inside(input, x, 0xb6, x + 0x69, 0xb6 + 0x5a) then
            state.capture = nil
            set.device = (set.device + 1) % (constants.input_devices.controller_four + 1)
        end
        -- The original draws every name and key on a dark box, white, and blue (COLORREF 0xff4619) while it is edited.
        local box, edited = 0x00092c, 0x1946ff
        if state.name_player == player then field(state, #name < constants.text_limits.player_name_bytes and name .. "_" or name, x, x + 0x15, 0x9f, edited, box)
        else field(state, name, x, x + 0x15, 0x9f, 0xffffff, box) end
        if input.click and inside(input, x, 0x9c, x + 0x69, 0x9c + 0x11) then
            state.capture = nil
            state.name_player = player
        end
        for row = 1, 7 do
            local y = 0x11b + (row - 1) * 0x16
            if input.click and inside(input, x, y - 3, x + 0x69, y + 0xf) then
                if set.device == constants.input_devices.keyboard or row > 4 then state.capture = {player = player, row = row} end
                state.name_player = 0
            end
            local capturing = state.capture and state.capture.player == player and state.capture.row == row
            if set.device == constants.input_devices.keyboard then
                local label, kind = controls.key_label(set.keys[row])
                field(state, label, x, x + 0x29 - kind, y, capturing and edited or 0xffffff, box)
            elseif row <= 4 then
                field(state, "-", x, x + 0x30, y, 0xffffff, box)
            else
                field(state, i18n.tr("Button: %d", set.buttons[row - 4] + 1), x, x + 0x22, y, capturing and edited or 0xffffff, box)
            end
        end
        image(state, devices[set.device], x, 0xb6, false)
    end
    if input.pointer_y >= 0x1b9 then
        if input.pointer_y <= 0x1d1 and input.pointer_x >= 0x246 and input.pointer_x <= 0x246 + 0x9b then
            sprite(state, "pe/menu_clip", menu_clip[12], 0x244, 0x1b9, true)
            if input.click then finished = "cancel" end
        end
        if input.pointer_y <= 0x1b9 + 0x18 and input.pointer_x >= 0x195 and input.pointer_x <= 0x195 + 0x9b then
            sprite(state, "pe/menu_clip", menu_clip[13], 0x198, 0x1b9, true)
            if input.click then finished = "ok" end
        end
    end
    -- Escape or a controller's B is the Cancel button (unless it just ended a capture or a name).
    if not finished and input.nav.cancel and not input.locked then finished = "cancel" end
    if finished == "cancel" then
        -- Cancel reloads the stored settings.
        sounds.direct(state, "cancel")
        controls.load()
        state.page, state.editing, state.capture = "menu", nil, nil
    elseif finished == "ok" then
        -- OK saves into config.json.
        sounds.direct(state, "ok")
        local saved, problem = controls.save(editing)
        state.message = not saved and note(i18n.tr("Controls not saved: %s", tostring(problem))) or nil
        state.page, state.editing, state.capture = "menu", nil, nil
    end
end

local function field_text(state, text, x, y, lines, selected)
    local row = 0
    for part in (text .. "\n"):gmatch("([^\n]*)\n") do
        repeat
            if row >= lines then return end
            for _, offset in ipairs({{-1, 1}, {-1, 0}, {0, 1}, {0, 0}}) do
                add(state, {"text", part:sub(1, 64), x + offset[1], y + row * 16 + offset[2], selected and constants.font_variants.blue or constants.font_variants.white})
            end
            part = part:sub(65)
            row = row + 1
        until part == ""
    end
end

-- The recording page (author, info, e-mail, record checkbox); OK saves and shows the notice page.
local function recording_page(state, input, context)
    background(state)
    logo(state, 0x37)
    local sheet = compact_sheet and compact_clip6 or menu_clip6
    local lift = compact_sheet and 76 or 0
    sprite(state, "pe/menu_clip6", sheet[0], 0x2c, 0x93, true)
    local values = state.record
    -- Escape, Tab or B (and Enter or A, except in the multi-line info) end the editing.
    if state.field and leaves_field(state, input, state.field == "info") then state.field = nil end
    if input.click then
        local x, y = input.pointer_x, input.pointer_y
        state.field = nil
        if x >= 0xd2 and x < 0x2db then
            if y >= 0xcf and y < 0xe2 then state.field = "author"
            elseif y >= 0xe8 and y < 0x12f then state.field = "info"
            elseif not compact_sheet and y >= 0x135 and y < 0x148 then state.field = "email" end
        end
    end
    if state.field then
        -- Each key appends; Enter adds a line (not first); Backspace deletes; capped at 99 chars.
        local text = values[state.field]
        for code = 0, 249 do
            if input.keys[code] and not state.previous_keys[code] then
                local character = code == virtual_keys.enter and "\n" or typed_character(input, code)
                if character and code ~= virtual_keys.backspace then
                    if (#text > 0 or character ~= "\n") and #text < constants.text_limits.recording_field_bytes then text = text .. character end
                elseif code == virtual_keys.backspace and #text > 0 then
                    text = text:sub(1, -2)
                end
            end
        end
        text = (text .. input.text):sub(1, constants.text_limits.recording_field_bytes)
        values[state.field] = text
    end
    field_text(state, values.author, 0xd5, 0xd1, 1, state.field == "author")
    field_text(state, values.info, 0xd5, 0xea, 4, state.field == "info")
    if not compact_sheet then field_text(state, values.email, 0xd5, 0x137, 1, state.field == "email") end
    -- Checkbox: sprite 19 x 19 at (0x11f, 0x185 - lift).
    local box_y = 0x185 - lift
    if values.record ~= 0 then sprite(state, "pe/menu_clip6", sheet[6], 0x11f, box_y, true) end
    if inside(input, 0x11f, box_y + 1, 0x132, box_y + 0x14) then
        sprite(state, "pe/menu_clip6", sheet[5], 0x11f, box_y, true)
        if input.click then values.record = 1 - values.record end
    end
    -- "Open the recording folder" asks the host to open it in the system file manager.
    local folder_x, folder_y = 0x185, 0x184 - lift
    if compact_sheet then folder_y = 0x13a end -- same x as the vanilla sheet, sprite 3 px shorter
    if inside(input, folder_x, folder_y, folder_x + 0x157, folder_y + 0x16) then
        sprite(state, "pe/menu_clip6", sheet[7], folder_x, folder_y, true)
        if input.click then
            sounds.direct(state, "ok")
            context.action("open_recordings")
        end
    end
    if not compact_sheet then
        local link = inside(input, 0x2c, 0x1cd, 0x1e3, 0x1e4) and 2 or 1
        sprite(state, "pe/menu_clip6", menu_clip6[link], 0x2c, 0x1cd, true)
        if link == 2 and input.click then
            sounds.direct(state, "ok")
            context.action("open_recording_help")
        end
    end
    local button_y = 0x1a0 - lift
    if input.pointer_y >= button_y and input.pointer_y <= button_y + 0x18 then
        if input.pointer_x >= 0x193 and input.pointer_x <= 0x22e then
            sprite(state, "pe/menu_clip", menu_clip[12], 0x193, button_y, true)
            if input.click then
                sounds.direct(state, "cancel")
                state.page, state.record = "menu", nil
            end
        elseif input.pointer_x >= 0xe7 and input.pointer_x <= 0x182 then
            sprite(state, "pe/menu_clip", menu_clip[13], 0xe7, button_y, true)
            if input.click then
                sounds.direct(state, "ok")
                local saved, problem = controls.save_recording(values.record, values.author, values.email, values.info)
                state.message = not saved and note(i18n.tr("Settings not saved: %s", tostring(problem))) or nil
                -- The compact sheet has no "recorded" notice picture: straight back to the menu.
                state.page, state.record = compact_sheet and "menu" or "recorded", nil
            end
        end
    end
    -- Escape or B goes back (a field being edited takes it first).
    if state.page == "recording" and input.nav.cancel and not input.locked then
        sounds.direct(state, "cancel")
        state.page, state.record = "menu", nil
    end
end
-- The notice after the recording page; OK returns to the menu.
local function recorded_page(state, input, context)
    background(state)
    logo(state, 0x4b)
    sprite(state, "pe/menu_clip6", menu_clip6[3], 0x2c, 0xa7, true)
    if inside(input, 0x60, 0x15c, 0x27f, 0x174) then
        sprite(state, "pe/menu_clip6", menu_clip6[4], 0x60, 0x15c, true)
        if input.click then
            sounds.direct(state, "ok")
            context.action("open_recording_help")
        end
    end
    if inside(input, 0x13e, 0x17e, 0x1d8, 0x196) then
        sprite(state, "pe/menu_clip", menu_clip[13], 0x13e, 0x17e, true)
        if input.click then
            sounds.direct(state, "ok")
            state.page = "menu"
        end
    end
    if state.page == "recorded" and input.nav.cancel then
        sounds.direct(state, "cancel")
        state.page = "menu"
    end
end

-- Navigation targets for the current page: the pointer-test rectangles above, in reading order.
local target = navigation.target
local function navigation_page(state)
    local page = state.page
    if page == "controls" then
        local list = {}
        for player = 1, 4 do
            local x = 0xc2 + (player - 1) * 0x8b
            list[#list + 1] = target(x, 0x9c, x + 0x69, 0x9c + 0x11)
            list[#list + 1] = target(x, 0xb6, x + 0x69, 0xb6 + 0x5a)
            for row = 1, 7 do
                local y = 0x11b + (row - 1) * 0x16
                list[#list + 1] = target(x, y - 3, x + 0x69, y + 0xf)
            end
        end
        list[#list + 1] = target(0x195, 0x1b9, 0x195 + 0x9b, 0x1b9 + 0x18)
        list[#list + 1] = target(0x246, 0x1b9, 0x246 + 0x9b, 0x1b9 + 0x18)
        list[#list + 1] = target(0x2e, 0x1db, 0x21c, 0x1f2)
        return {page = page, targets = list, locked = state.capture ~= nil or state.name_player > 0}
    elseif page == "recording" then
        return {page = page, locked = state.field ~= nil,
            targets = {target(0xd2, 0xcf, 0x2da, 0xe1), target(0xd2, 0xe8, 0x2da, 0x12e), target(0xd2, 0x135, 0x2da, 0x147),
                target(0x11f, 0x186, 0x132, 0x199), target(0x185, 0x184, 0x2dc, 0x19a),
                target(0xe7, 0x1a0, 0x182, 0x1b8), target(0x193, 0x1a0, 0x22e, 0x1b8),
                target(0x2c, 0x1cd, 0x1e3, 0x1e4)}}
    elseif page == "recorded" then
        return {page = page, targets = {target(0x13e, 0x17e, 0x1d8, 0x196),
            target(0x60, 0x15c, 0x27f, 0x174)}, autofocus = true}
    elseif page == "game_grid" then
        local layout = grid_layout(state)
        local list, default = {}, nil
        for _, cell in ipairs(layout.cells) do
            list[#list + 1] = target(cell.x, cell.y, cell.x + grid_cell.width - 1, cell.y + grid_cell.height - 1)
            if cell.index == state.grid.selected then default = #list end
        end
        for _, area in ipairs({layout.ok, layout.cancel}) do
            list[#list + 1] = target(area.x, area.y, area.x + area.width, area.y + area.height)
        end
        if layout.pages > 1 then
            for _, area in ipairs({layout.previous, layout.next}) do
                list[#list + 1] = target(area.x, area.y, area.x + area.width, area.y + area.height)
            end
        end
        return {page = page, targets = list, default = default}
    elseif page == "options" then
        local layout = options_layout(state.features, state.options)
        local list, dropdown = {}
        for _, row in ipairs(layout.rows) do
            local box, option = row.box, row.option
            local area
            if option.choices then
                area = target(box.x, box.y, box.x + box.width, box.y + box.height)
                if state.option_open == option.key then dropdown = row end
            else
                area = target(box.x, box.y, box.x + box.size + 12 + font.width(i18n.tr(option.label)), box.y + box.size)
            end
            list[#list + 1] = area
        end
        if state.option_open then
            -- The list: the box (closes it) and one entry per filter, starting on the current one.
            local box = dropdown.box
            local list, current = {target(box.x, box.y, box.x + box.width, box.y + box.height)}, 1
            for index, filter in ipairs(dropdown.option.choices(state.features)) do
                local y = box.y + index * box.height
                list[#list + 1] = target(box.x, y, box.x + box.width, y + box.height)
                if filter == state.options[dropdown.option.key] then current = index end
            end
            return {page = "options_list", targets = list, default = current + 1}
        end
        for _, area in ipairs({layout.ok, layout.cancel}) do
            list[#list + 1] = target(area.x, area.y, area.x + area.width, area.y + area.height)
        end
        return {page = page, targets = list, default = state.options_focus}
    end
    -- Menu targets: Game Start, Network Game, Controls, Recording, Official Website,
    -- Options, and Exit.
    local top = 0xca
    return {page = "menu", remember = true, targets = {target(0x114, top + 0xf, 0x208, top + 0x27), target(0x114, top + 0x2d, 0x208, top + 0x46),
        target(0x114, top + 0x4d, 0x208, top + 0x66), target(0x114, top + 0x6b, 0x208, top + 0x84),
        target(0x114, top + 0x89, 0x208, top + 0xa2),
        target(0x114, options_row.top, 0x208, options_row.bottom), target(0, 0x202, 0x3e, 0x217)}}
end

function screen.update(state, flow_input, context)
    -- The Game Start frame (page "waiting") draws nothing of its own, and the launch screen is drawn once more when the title goes back
    -- to it before it has updated: both showed a bare screen of the menu colour for a moment (a blue flash between the menus), so the
    -- last picture of the menu is kept for those frames.
    if state.page ~= "waiting" or not state.display then state.display = {} end
    state.menu_ticks = (state.menu_ticks or 0) + 1  -- HOOK(AI5)
    state.features = flow_input.filters
    local input = flow_input
    if state.page ~= "waiting" then
        input = navigation.apply(state.nav, flow_input, navigation_page(state))
    end
    if state.page == "waiting" then
        -- The Game Start frame: straight to the title (no wait image: a game may not have it).
        context.action("game_start")
    elseif state.page == "controls" then
        control_settings(state, input, context)
    elseif state.page == "recording" then
        recording_page(state, input, context)
    elseif state.page == "recorded" then
        recorded_page(state, input, context)
    elseif state.page == "options" then
        options_page(state, input, context)
    elseif state.page == "game_grid" then
        game_grid_page(state, input, context)
    else
        menu(state, input, context)
        options_entry(state, input)
    end
    if state.page == "network" then state.page = "menu"; context.action("network") end
    if state.message then text(state, state.message, 10, 530) end
    state.previous_keys = input.keys
    -- The on-screen keyboard follows the text fields.
    local typing = (state.page == "controls" and state.name_player > 0) or (state.page == "recording" and state.field ~= nil)
    if typing ~= state.keyboard then
        state.keyboard = typing
        context.text_input(typing)
    end
    for _, sound in ipairs(sounds.flush(state)) do context.sound(sound.resource, sound.volume, sound.pan) end
    if state.page ~= "waiting" then
        local exit_pointed = inside(input, 0, 0x202, 0x3e, 0x217)
        text(state, i18n.tr("Exit"), 12, 0x205, exit_pointed and 0xffffff or 0x5077d0)
        -- The cursor sprite, clamped to stay on screen.
        image(state, "pe/lf2_cursor", math.min(input.pointer_x, 0x307), math.min(input.pointer_y + 2, 0x217), true)
        -- The bottom-left Exit shortcut is shared by the launch screen's pages.
        if input.click and input.pointer_x < 0x3f and input.pointer_y >= 0x202 then context.action("quit") end
    end
end

function screen.draw(state, context)
    local back = sd_menu_back.view(1, state.menu_seed)  -- HOOK(AI5)
    local color = back and back.color or {16, 32, 108}
    context.viewport(constants.screen.width, constants.screen.height, color[1], color[2], color[3])
    for _, command in ipairs(state.display or {}) do
        local kind = command[1]
        if kind == "sprite" then
            context.sprite(command[2], command[3], command[4], command[5], command[6], command[7], command[8])
        elseif kind == "image" then context.image(command[2], command[3], command[4], command[5])
        elseif kind == "icon" then context.icon(command[2], command[3], command[4], command[5], command[6])
        elseif kind == "backdrop" then sd_menu_back.draw_command(context, command)
        elseif kind == "fill" then context.fill(command[2], command[3], command[4], command[5], command[6], command[7], command[8])
        -- Entries with a variant are the original's bitmap-font fields; the rest is GDI text.
        elseif command[5] then font.draw(context, command[2], command[3], command[4], command[5], nil, command[8])
        else font.gdi(context, command[2], command[3], command[4], command[6], command[7], command[8], command[9]) end
    end
end

function screen.describe(state)
    local parts = {"launch_page=" .. state.page}
    local settings = state.editing or controls.current()
    for player = 1, 4 do
        local set = settings.sets[player]
        parts[#parts + 1] = string.format("p%d{name=%s device=%d keys=%s%s}", player, settings.names[player],
            set.device, table.concat(set.keys, ","),
            set.device > constants.input_devices.keyboard and " buttons=" .. table.concat(set.buttons, ",") or "")
    end
    if state.capture then parts[#parts + 1] = string.format("capture=%d:%d", state.capture.player, state.capture.row) end
    if state.name_player > 0 then parts[#parts + 1] = "editing_name=" .. state.name_player end
    if state.nav.mode == "focus" then parts[#parts + 1] = "focus=" .. state.nav.page .. ":" .. state.nav.focus end
    parts[#parts + 1] = "source=" .. tostring(settings.source)
    local shown = state.options or options.current()
    parts[#parts + 1] = "unlock_characters=" .. tostring(shown.unlock_characters)
    parts[#parts + 1] = "upscaling_filter=" .. shown.upscaling_filter
    parts[#parts + 1] = "fullscreen=" .. tostring(shown.fullscreen)
    parts[#parts + 1] = "show_fps=" .. tostring(shown.show_fps)
    local current = controls.current()
    parts[#parts + 1] = "record=" .. tostring(state.record and state.record.record or current.record)
    if state.field then parts[#parts + 1] = "field=" .. state.field end
    if state.record then parts[#parts + 1] = "author=" .. state.record.author end
    if state.message then parts[#parts + 1] = "message=" .. state.message end
    return table.concat(parts, " ")
end
return screen
