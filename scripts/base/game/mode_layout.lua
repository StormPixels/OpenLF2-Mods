-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

-- LF2 Darkfiren's mode4.dat as a layout: the text of "game/mode_file" is read for the blocks whose positions and
-- sizes the character menu draws with (<menu_control>, <grid_char>, <grid_bg>, <grid_bg_mode>, <grid_stage>, <misc>). A value the file
-- does not give, or gives in the wrong form, leaves the built-in one in place. Compatible with Lua 5.1/LuaJIT.
local mode_layout = {}

-- {tag = {key = value}}: the first block of each tag, the first line of each key. Numbers become numbers; the
-- `pic` and `small` paths are lower case with forward slashes, as the game's resources are named.
function mode_layout.blocks(text)
    local blocks, current = {}, nil
    for line in (text or ""):gmatch("[^\r\n]+") do
        local tag = line:match("^%s*<([%w_]+)>%s*$")
        if tag then
            if tag:sub(-4) == "_end" then current = nil
            elseif blocks[tag] == nil then current = {}; blocks[tag] = current
            else current = nil end
        elseif current then
            local key, value = line:match("^%s*([%w_]+)%s*:%s*(.-)%s*$")
            if key and current[key] == nil then
                if key == "pic" or key == "small" then
                    value = value:gsub("\\", "/"):lower()
                else
                    value = tonumber(value:match("^(-?%d+)")) or value
                end
                current[key] = value
            end
        end
    end
    return blocks
end

-- target key <- block key, per target table of the menu; keys that must be at least 1 are listed apart.
local maps = {
    menu = {tag = "menu_control", pic = "pic", x = "start_x", y = "start_y", row = "row", step_x = "centerx", step_y = "centery"},
    roster = {tag = "grid_char", panel_pic = "pic", small_pic = "small", panel_x = "pic_x", panel_y = "pic_y",
        x = "start_x", y = "start_y", columns = "row", step_x = "centerx", step_y = "centery", width = "w", height = "h",
        human_x = "human_x", human_y = "human_y", com_x = "com_x", com_y = "com_y"},
    grid_bg = {tag = "grid_bg", panel_pic = "pic", random_pic = "small", panel_x = "pic_x", panel_y = "pic_y",
        x = "start_x", y = "start_y", w = "w", h = "h", step = "centery", name_x = "name_x", name_y = "name_y"},
    misc = {tag = "misc", music_x = "music_x", music_y = "music_y", frame_x = "frame_x", frame_y = "frame_y",
        small_x = "small_x", small_y = "small_y", show_small = "background_small", frame_pic = "pic",
        music_title = "hexf", music_hint = "hexb"},
    grid_stage = {tag = "grid_stage", panel_pic = "pic", panel_x = "pic_x", panel_y = "pic_y", x = "start_x", y = "start_y",
        w = "w", h = "h", step_x = "centerx", name_x = "name_x", name_y = "name_y"},
    grid_mode = {tag = "grid_bg_mode", panel_pic = "pic", panel_x = "pic_x", panel_y = "pic_y",
        x = "start_x", y = "start_y", w = "w", h = "h", step_x = "centerx", step_y = "centery", columns = "row",
        name_x = "name_x", name_y = "name_y"},
}
local at_least_one = {row = true, columns = true, w = true, h = true, width = true, height = true, step = true,
    step_x = true, step_y = true}

-- Overwrites the built-in values of targets = {menu = t, roster = t, grid_bg = t, grid_mode = t, grid_stage = t, misc = t} (tables the
-- caller owns) with what the text gives. Returns how many values were taken.
function mode_layout.apply(text, targets)
    local blocks, taken = mode_layout.blocks(text), 0
    for name, map in pairs(maps) do
        local target, block = targets[name], blocks[map.tag]
        if target and block then
            for to, from in pairs(map) do
                local value = block[from]
                if to ~= "tag" and value ~= nil and type(value) == type(target[to]) and
                   not (type(value) == "number" and at_least_one[to] and value < 1) then
                    -- hexf / hexb are Windows colours (blue * 65536 + green * 256 + red); the menu draws 0xRRGGBB.
                    if (to == "music_title" or to == "music_hint") and type(value) == "number" then
                        value = (value % 256) * 65536 + (math.floor(value / 256) % 256) * 256 + math.floor(value / 65536) % 256
                    end
                    target[to] = value
                    taken = taken + 1
                end
            end
        end
    end
    return taken
end

-- The <time> block (LF2 Darkfiren, time limit): `type:` says who wins when the time is up (1 highest hp, 2 highest
-- dhp, 3 most damage, 4 most kills) and each `time:` is a choice in seconds, up to 100. Returns type, list.
function mode_layout.time_limits(text)
    local kind, list, inside = 1, {}, false
    for line in (text or ""):gmatch("[^\r\n]+") do
        local tag = line:match("^%s*<([%w_]+)>%s*$")
        if tag == "time" then inside = true
        elseif tag == "time_end" then break
        elseif inside then
            local key, value = line:match("^%s*([%w_]+)%s*:%s*(%-?%d+)")
            value = tonumber(value)
            if key == "type" and value and value >= 1 and value <= 4 then kind = value
            elseif key == "time" and value and value > 0 and #list < 100 then list[#list + 1] = value end
        end
    end
    return kind, list
end

-- The <cost> block (LF2 Darkfiren cost mode): `kind:` is the price of a fighter no `cost:` group lists, `respond:` each
-- a choice of pool for the menu (up to 100), `cost: N` followed by `id:` lines the price N of those fighters (the
-- `random:` ... `random_end:` blocks of respawn ids are skipped). Returns {kind, pools, groups}.
function mode_layout.cost_settings(text)
    local settings = {kind = 100, pools = {}, groups = {}}
    local words = {}
    for word in (text or ""):gmatch("%S+") do words[#words + 1] = word end
    local inside, group, skipping = false, nil, false
    for index, word in ipairs(words) do
        if word == "<cost>" then inside = true
        elseif word == "<cost_end>" then break
        elseif inside then
            local number = tonumber((words[index + 1] or ""):match("^(-?%d+)$"))
            if word == "random:" then skipping = true
            elseif word == "random_end:" then skipping = false
            elseif word == "kind:" and number and number > 0 then settings.kind = number
            elseif word == "respond:" and number and number > 0 and #settings.pools < 100 then settings.pools[#settings.pools + 1] = number
            elseif word == "cost:" and number and number > 0 then group = number
            elseif word == "id:" and number and group and not skipping then settings.groups[number] = group end
        end
    end
    return settings
end

-- The <battle> block of a mode file (LF2 Darkfiren): exactly nine `id:` lines, the soldiers of Battle mode in the order
-- of the troop picker. Anything else gives nil (the built-in soldiers stay).
function mode_layout.battle_ids(text)
    local ids, inside = {}, false
    for line in (text or ""):gmatch("[^\r\n]+") do
        local tag = line:match("^%s*<([%w_]+)>%s*$")
        if tag == "battle" then inside = true
        elseif tag == "battle_end" then break
        elseif inside then
            local id = tonumber(line:match("^%s*id%s*:%s*(%d+)"))
            if id and id > 0 then ids[#ids + 1] = id end
        end
    end
    return #ids == 9 and ids or nil
end

return mode_layout
