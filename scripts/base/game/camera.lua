-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local constants = require("base/game/constants")
local camera_motion_facing_lookahead = constants.camera_motion.facing_lookahead
local camera_motion_fallback_focus_x = constants.camera_motion.fallback_focus_x
local camera_motion_previous_step_weight = constants.camera_motion.previous_step_weight
local camera_motion_step_weight_divisor = constants.camera_motion.step_weight_divisor
local camera_motion_target_distance_divisor = constants.camera_motion.target_distance_divisor
local state_lying = constants.frame_states.lying
local item_id_beer = constants.item_ids.beer
local item_id_milk = constants.item_ids.milk
local item_slots = constants.item_slots
local mode_stage = constants.modes.stage
local screen_width = constants.screen.width

-- LF2 Darkfiren: the width of the view is the layout's (1333 or 1018 when AI 5's background.window_width() says so, else 794).
local background_module
local function view_width()
    if background_module == nil then
        local ok, module = pcall(require, "base/game/background")
        background_module = ok and module or false
    end
    local width = background_module and background_module.window_width and background_module.window_width()
    return width or screen_width
end
local stage_group_survival = constants.stage_groups.survival
local team_enemies = constants.teams.enemies
local world_edge_ball_margin = constants.world_edges.ball_margin
local world_edge_drink_margin = constants.world_edges.drink_margin
local world_edge_enemy_character_left_margin = constants.world_edges.enemy_character_left_margin
local world_edge_spawned_character_margin = constants.world_edges.spawned_character_margin
local record_kinds = constants.record_kinds
local record_kinds = constants.record_kinds
local objects = require("base/game/objects")
local st_camera = require("base/game/st_camera")
local camera = {}

local function cdiv(a, b)
    local q = a / b
    if q >= 0 then return math.floor(q) end
    return math.ceil(q)
end
local function truncate(value)
    if value >= 0 then return math.floor(value) end
    return math.ceil(value)
end

-- Keeps items inside the stage depth and width; the last-rendered-width rules by kind.
local function clamp(state)
    local stage = state.stage
    local near, far, width = stage.zboundary[1] or 0, stage.zboundary[2] or 0, stage.width or screen_width
    for index = 0, item_slots - 1 do
        local value = state.items[index]
        if value then
            local kind = value.record.kind
            if kind == record_kinds.character then
                if near > value.z then value.z = near end
                if far < value.z then value.z = far end
            else
                if near - 1.0 > value.z then value.z = near - 1.0 end
                if far + 1.0 < value.z then value.z = far + 1.0 end
            end
            value.z_int = truncate(value.z)
            if kind == record_kinds.ball then
                if value.x < -world_edge_ball_margin or width + world_edge_ball_margin < value.x then objects.remove(state, index) end
            elseif kind == record_kinds.character then
                if index >= 20 then
                    if value.x < -world_edge_spawned_character_margin then value.x = -world_edge_spawned_character_margin end
                    if width + world_edge_spawned_character_margin < value.x then value.x = width + world_edge_spawned_character_margin end
                else
                    if value.team == team_enemies then
                        if value.x < -world_edge_enemy_character_left_margin then value.x = -world_edge_enemy_character_left_margin end
                    elseif value.x < 0.0 then
                        value.x = 0.0
                    end
                    if width < value.x then value.x = width end
                end
                if state.stage_bound > 0 and state.stage_bound < value.x and value.team ~= team_enemies and value.blink == 0 then
                    value.x = state.stage_bound
                end
            elseif (value.record.id == item_id_milk or value.record.id == item_id_beer)
                   and (value.battle_side > 0 or (state.mode == mode_stage and math.floor(state.stage_run.id / 10) == stage_group_survival)) then
                if value.x < world_edge_drink_margin then value.x = world_edge_drink_margin end
                if width - world_edge_drink_margin < value.x then value.x = width - world_edge_drink_margin end
            elseif (value.x < 0.0 or width < value.x) and value.y_int == (value.floor_y or 0) then
                objects.remove(state, index)
            end
            value.x_int = truncate(value.x)
        end
    end
end

-- LF2 Darkfiren vertical camera (bg mode tags `zcam` and `zcamera`, AI 5 puts them in state.bg_area as 0/1; Darkfiren developer: "when
-- the background's zboundary is greater than the window height use zcam: 1 for parallel scroll, or zcamera: like xcamera but it
-- follows the z of all the characters selected in the menu, human and computer"). `state.camera_z` (integer >= 0, 0 without a tag or
-- when the background fits) is how far the picture is scrolled down: the renderer subtracts it from every screen y (AI 4).
-- The scrollable range is the feet line (zboundary far + 24) minus the viewport height (550, constants.screen.height), so it is 0
-- for every background that fits.
-- [BELUM PASTI] (no source): the parallel formula of zcam (here: range * camera_x / (width - view width), i.e. it scrolls with the horizontal
-- camera), the focus of zcamera (here: the object of a 99XXX frame when there is one, else the mean z of the live fighters of slots 0..9), its smoothing (the xcamera's) and that `zcamera` is a <mode> key.
local function z_range(state)
    local stage = state.stage
    local zb = stage and stage.zboundary
    local far = type(zb) == "table" and tonumber(zb[2]) or nil
    local view = constants.screen.height
    if not far then return 0, view end
    local range = far + 24 - view
    if range < 0 then range = 0 end
    return range, view
end

local function step_z(state)
    local area = state.bg_area
    local zcamera, zcam = area and area.zcamera == 1, area and area.zcam == 1
    if not zcamera and not zcam then state.camera_z, state.camera_z_step = 0, 0 return end
    local range, view = z_range(state)
    if range == 0 then state.camera_z, state.camera_z_step = 0, 0 return end
    local current = state.camera_z or 0
    if zcamera then
        local sum, count = 0, 0
        -- A 99XXX frame (camera follow, st_camera) is the focus when there is one, like for the horizontal camera.
        local follow = state.st and state.st.camera_follow
        local focus_item = follow and state.items[follow.index]
        if focus_item then
            sum, count = focus_item.z_int, 1
        else
            for index = 0, 9 do
                local value = state.items[index]
                if value and value.record.kind == record_kinds.character and value.hp > 0 then
                    sum = sum + value.z_int
                    count = count + 1
                end
            end
        end
        local target = current
        if count > 0 then
            target = cdiv(sum, count) - view / 2
            if target < 0 then target = 0 end
            if target > range then target = range end
        end
        local step = cdiv(cdiv(target - current, camera_motion_target_distance_divisor) + (state.camera_z_step or 0) * camera_motion_previous_step_weight, camera_motion_step_weight_divisor)
        if step == 0 then
            if current < target then step = 1 elseif target < current then step = -1 end
        end
        state.camera_z_step = step
        current = current + step
    else
        local width = (state.stage.width or screen_width) - view_width()
        local fraction = width > 0 and (state.camera or 0) / width or 0
        current = truncate(range * fraction)
        state.camera_z_step = 0
    end
    if current < 0 then current = 0 end
    if current > range then current = range end
    state.camera_z = current
end

function camera.step(state)
    clamp(state)
    local sum, count = 0, 0
    local network = state.held and state.held.network
    for index = 0, 7 do
        local value = state.items[index]
        if value and value.human and value.hp > 0 and (network or index < 4) then
            if value.record.frame(value.frame).state == state_lying then sum = sum + value.x_int
            else sum = sum + camera_motion_facing_lookahead + value.x_int - value.facing * (camera_motion_facing_lookahead * 2) end
            count = count + 1
        end
    end
    if count == 0 then
        for index = 0, item_slots - 1 do
            local value = state.items[index]
            if value and value.record.kind == record_kinds.character and value.hp > 0 then
                sum = sum + value.x_int
                count = count + 1
            end
        end
        if count == 0 then sum, count = camera_motion_fallback_focus_x, 1 end
    end
    local focus = st_camera.focus(state)
    if focus then sum, count = focus, 1 end
    local width = state.stage.width or screen_width
    local view = view_width()
    local target = cdiv(sum, count) - view / 2
    if target < 0 then target = 0 end
    if target > width - view then target = width - view end
    if state.camera_limit ~= 0 and target > state.camera_limit then target = state.camera_limit end
    state.camera_step = cdiv(cdiv(target - state.camera, camera_motion_target_distance_divisor) + state.camera_step * camera_motion_previous_step_weight, camera_motion_step_weight_divisor)
    if state.camera_step == 0 then
        if state.camera < target then state.camera_step = 1
        elseif target < state.camera then state.camera_step = -1 end
    end
    state.camera = state.camera + state.camera_step
    local pan = state.replay_pan
    if pan and pan.active then state.camera = pan.x end
    if state.camera < 0 then state.camera = 0 end
    if state.camera > width - view then state.camera = width - view end
    if pan and pan.active then pan.x = state.camera end
    step_z(state)
end
return camera
