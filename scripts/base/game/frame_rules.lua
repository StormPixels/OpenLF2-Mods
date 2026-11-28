-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 OpenLF2 contributors

local constants = require("base/game/constants")
local record_kinds = constants.record_kinds
local objects = require("base/game/objects")
local merge = require("base/game/merge")
local cost = require("base/game/cost")
local unlock = require("base/game/unlock")
local st_states = require("base/game/st_states")
local timestop = require("base/game/timestop")
local frame_rules = {}

local function cdiv(a, b)
    local q = a / b
    if q >= 0 then return math.floor(q) end
    return math.ceil(q)
end
local function random(range) return engine.random(range) end
local function state_of(value) return value.record.frame(value.frame).state end

-- Followers (+0x2f4 = index) that are alive take the new record, airborne ones in frame 212.
local function pass_record(state, index, record)
    for other = 0, constants.item_slots - 1 do
        local follower = state.items[other]
        if follower and follower.follow == index and follower.hp > 0 then
            follower.record = record
            follower.frame = follower.y_int < (follower.floor_y or 0) and constants.character_frames.jump + 2 or constants.character_frames.standing
        end
    end
end

local function teleport(state, index, mode)
    local me = state.items[index]
    local best, distance = -1, mode == constants.teleport_modes.nearest_enemy and constants.teleport.nearest_enemy_distance_limit or -1
    for other = 0, constants.item_slots - 1 do
        local value = state.items[other]
        if other ~= index and value and value.record.kind == record_kinds.character and value.hp > 0
           and ((mode == constants.teleport_modes.nearest_enemy and value.team ~= me.team) or (mode == constants.teleport_modes.farthest_ally and value.team == me.team)) then
            local next = math.abs(value.z_int - me.z_int) + math.abs(value.x_int - me.x_int)
            if (mode == constants.teleport_modes.nearest_enemy and next < distance) or (mode == constants.teleport_modes.farthest_ally and next > distance) then
                best, distance = other, next
            end
        end
    end
    me.y_int = 0
    if best == -1 then
        me.y = me.y_int
    else
        local target = state.items[best]
        local offset = mode == constants.teleport_modes.nearest_enemy and constants.teleport.enemy_x_offset or constants.teleport.ally_x_offset
        me.z_int = target.z_int + 1
        if me.facing == constants.facings.right then me.x_int = target.x_int - offset else me.x_int = target.x_int + offset end
        me.x, me.y, me.z = me.x_int, me.y_int, me.z_int
    end
    me.vz, me.vy, me.vx = 0.0, 0.0, 0.0
end

-- True while a time stop freezes the item (LF2 Darkfiren state 3xxyzzz).
function frame_rules.frozen(state, index, value)
    return timestop.frozen(state, index, value)
end

function frame_rules.round_end(state)
    for index = 0, constants.item_slots - 1 do
        local value = state.items[index]
        if value then
            if value.transform > -1 then
                local record = objects.record(state, value.transform)
                if record then
                    value.record = record
                    value.transform = -1
                end
            elseif value.record.id == constants.fighter_ids.louis_ex and unlock.flags.characters == 0 then
                value.record = objects.record(state, constants.fighter_ids.louis) or value.record
            elseif value.twin > constants.fusion_states.unmerged then
                merge.split_at_round_end(state, value)
            end
        end
    end
end

-- After each item's control step.
function frame_rules.after_control(state, index, value)
    local current = state_of(value)
    if current == constants.frame_states.teleport_to_enemy and state.shake == 0 then teleport(state, index, constants.teleport_modes.nearest_enemy) end
    if state_of(value) == constants.frame_states.teleport_to_ally and state.shake == 0 then teleport(state, index, constants.teleport_modes.farthest_ally) end
    if state_of(value) == constants.frame_states.transform_start and (value.transformed_to == -1 or value.transform > -1) then value.frame = 0 end
    if state_of(value) == constants.frame_states.transform_complete and value.transformed_to > -1 then
        local record = objects.record(state, value.transformed_to)
        if record then
            value.transform = value.record.id
            value.record = record
            value.frame = 0
            pass_record(state, index, record)
        end
    end
    st_states.after_control(state, index, value)
end

-- A fighter comes back near its teammates (the original's way of using up a life), with `part` (0 to 1) of its hp and mp.
function frame_rules.drop_in(state, index, value, part)
    local sum_x, sum_z, mates = 0, 0, 0
    for other = 0, constants.item_slots - 1 do
        local mate = state.items[other]
        if mate and other ~= index and mate.record.kind == record_kinds.character and mate.team == value.team then
            sum_x = sum_x + mate.x_int
            sum_z = sum_z + mate.z_int
            mates = mates + 1
        end
    end
    -- The original divides by the mate count unguarded; without mates the port keeps x/z.
    if mates > 0 then
        value.x = cdiv(sum_x, mates) + random(constants.revival.x_random_range) - constants.revival.x_offset
        value.z = cdiv(sum_z, mates) + random(constants.revival.z_random_range) - constants.revival.z_offset
    end
    value.mp = part >= 1 and constants.points.full or math.max(1, math.floor(constants.points.full * part))
    value.dark_hp = part >= 1 and value.max_hp or math.max(1, math.floor(value.max_hp * part))
    value.hp = value.dark_hp
    value.blink = constants.blink.spawn_frames
    value.frame = constants.character_frames.jump + 2
    local drop_y = state.bg_area and state.bg_area.centery  -- LF2 Darkfiren: the mode's drop height (< 0)
    value.y_int = (drop_y and drop_y < 0) and drop_y or constants.revival.initial_y
    value.y = value.y_int
    value.vy = 0.0
end

-- Cost mode (u17 video): a beaten fighter whose team still has cost does not drop from the sky, it gets up where it fell, on its
-- feet and blinking (`part`, 0 to 1, is the share of hp and mp it comes back with).
function frame_rules.revive_in_place(state, value, part)
    value.mp = part >= 1 and constants.points.full or math.max(1, math.floor(constants.points.full * part))
    value.dark_hp = part >= 1 and value.max_hp or math.max(1, math.floor(value.max_hp * part))
    value.hp = value.dark_hp
    value.blink = constants.blink.spawn_frames
    -- The fighter gets up the way the dat says: it stays in its lying frame and that frame's wait is used up, so the next tick goes on to the
    -- frame's own `next` (a normal dat: 230 lying, next 219, the crouch, next 999, standing). Before, it was put on its feet at once.
    local lying_frame = value.record.frame(value.frame)
    if state_of(value) == constants.frame_states.lying and lying_frame then
        value.wait_counter = lying_frame.wait
    else
        value.frame = constants.character_frames.standing
        value.wait_counter = 0
    end
    value.vx, value.vy, value.vz = 0.0, 0.0, 0.0
end

-- Cost mode `team: 1`: when a team's pool is spent, its fighters still on their feet go down at once.
local function drop_team(state, team)
    for other = 0, constants.item_slots - 1 do
        local mate = state.items[other]
        if mate and mate.team == team and mate.record.kind == record_kinds.character and mate.hp > 0 then
            mate.hp, mate.dark_hp = 0, 0
            local kind = state_of(mate)
            if kind ~= constants.frame_states.lying and kind ~= constants.frame_states.falling then
                mate.frame = constants.character_frames.falling
            end
        end
    end
end

-- After each item's physics step (the item may be removed; returns false then).
function frame_rules.after_physics(state, index, value)
    -- bg mode `etc_mode: 1`: the ETC message (the team order marker) sticks to the player who gave the order (p1..p8): it follows that
    -- player's x and z while it lives. [BELUM PASTI] only x and z follow; the marker keeps its own height (ground).
    if value.etc_owner and state.bg_area and state.bg_area.etc_mode == 1 then
        local owner = state.items[value.etc_owner]
        if owner and owner.hp > 0 then
            value.x, value.z = owner.x, owner.z
            value.x_int, value.z_int = owner.x_int, owner.z_int
        end
    end
    -- Cost mode: the highest price a fighter has had (a transformation to a cheaper fighter keeps the dearer price).
    if state.cost and value.record.kind == record_kinds.character and value.cost_seen_id ~= value.record.id then
        value.cost_seen_id = value.record.id
        local price = cost.price(state.cost, value.record.id, value.record)
        if price > (value.cost_price or 0) then value.cost_price = price end
    end
    -- LF2 Darkfiren's cost mode: a beaten fighter (hp 0, lying) is paid for from its team's pool on the first tick it lies
    -- there; if the pool lasts it blinks for blink.defeated_frames and comes back once blink is below 5 (u17 exe: 0x40D211,
    -- 0x40D230, 0x41E6F1, 0x45FA20), which is 27 ticks after it was paid for. Once the team is out its body stays.
    if value.cost_pending and value.hp > 0 then value.cost_pending, value.cost_part = nil, nil end
    if state.cost and value.record.kind == record_kinds.character and value.hp <= 0 and not value.cost_paid
       and state_of(value) == constants.frame_states.lying and state.cost.pool[value.team] ~= nil then
        if not value.cost_pending then
            local result, part = cost.beaten(state.cost, value.team, value.record.id, value.record, value.cost_price)
            if result == "respawn" then
                -- animation.advance starts the blink (it holds a pending fighter down, like a beaten stage enemy).
                value.cost_pending, value.cost_part = true, part
            else
                value.cost_paid = true
                if state.cost.kill_team then drop_team(state, value.team) end
            end
        elseif value.blink > 0 and value.blink < 5 then
            -- COM backup: a human fighter comes back as the next fighter of the computers marked as backup in its team
            -- (it comes before the shuffle: with a backup the shuffle is skipped).
            local backup = state.cost.shuffle and state.mode == constants.modes.versus
                and cost.backup_for(state.cost, index, value.team) or nil
            local backup_record = backup and objects.record(state, backup.id)
            if backup_record then
                value.record, value.pic_offset = backup_record, 0
                value.cost_price, value.cost_seen_id = nil, nil -- the new fighter has its own price
            -- Respawn shuffle: a fighter that was chosen with Random comes back as another one.
            elseif not backup and state.cost.shuffle and value.random_pick then
                local taken = {}
                for other = 0, constants.item_slots - 1 do
                    local mate = state.items[other]
                    if mate and other ~= index and mate.record.kind == record_kinds.character and mate.hp > 0 then taken[mate.record.id] = true end
                end
                local id = cost.shuffle_id(state.cost, value.record.id, taken, random)
                local record = id and objects.record(state, id)
                if record then
                    value.record, value.pic_offset = record, 0
                    value.cost_price, value.cost_seen_id = nil, nil -- the new fighter has its own price
                end
            end
            local part = value.cost_part or 1
            value.cost_pending, value.cost_part = nil, nil
            frame_rules.revive_in_place(state, value, part)
        end
        return true
    end
    if state_of(value) == constants.frame_states.lying and value.hp <= 0 and (value.follow >= 0 or value.team == constants.teams.enemies or index >= 20
           or (value.st ~= nil and value.st.reserve == true and value.lives >= 2))
       and value.blink > 0 and value.blink < 5 then
        if value.join_hp > 0 then
            -- A beaten stage enemy with `join:` hp gets up for the players' team 1.
            value.lives = value.join_lives
            value.mp = 0
            value.max_hp = value.join_hp
            value.dark_hp = value.max_hp
            value.hp = value.dark_hp
            value.join_hp, value.join_lives = 0, 0
            value.team = constants.teams.player_one
            if value.record.id >= constants.fighter_ids.bandit and value.record.id <= constants.fighter_ids.jan then value.pic_offset = 140 end
            value.frame = constants.character_frames.crouch_alternate
            value.wait_counter = 0
            value.hit_lag = 10
            local slot = objects.free_slot(state)
            if slot ~= -1 and objects.record(state, constants.record_ids.team_order_marker) then
                local marker = objects.place(state, slot, constants.record_ids.team_order_marker)
                marker.x_int, marker.y_int, marker.z_int = value.x_int, value.y_int, value.z_int + 1
                marker.team = value.team
                marker.x, marker.y, marker.z = value.x, value.y, value.z
                marker.frame = 6
                marker.vx, marker.vy, marker.vz = 0.0, 0.0, 0.0
                marker.facing = constants.facings.right
            end
        elseif value.lives < 2 then
            objects.remove(state, index)
            return false
        else
            -- One of its lives: it drops in again near its teammates.
            value.lives = value.lives - 1
            frame_rules.drop_in(state, index, value, 1)
        end
    end
    if value.transform > -1 and value.sequences[constants.combo_indices.jump_attack] == constants.combo_states.complete and value.y_int == (value.floor_y or 0) and value.hp > 0 then
        value.sequences[constants.combo_indices.jump_attack] = constants.combo_states.idle
        local record = objects.record(state, value.transform)
        if record then
            value.record = record
            value.frame = 245
            value.transform = -1
            pass_record(state, index, record)
        end
    end
    return true
end

-- Before each item's regeneration and frame advance.
function frame_rules.before_advance(state, index, value)
    st_states.before_advance(state, index, value)
    if value.record.kind == record_kinds.character
       and state_of(value) == constants.frame_states.transform_louis_ex then
        -- The Transform option (LF2 Darkfiren, off): Louis stays Louis.
        if not state.no_transform then
            value.record = objects.record(state, constants.fighter_ids.louis_ex) or value.record
        end
        value.frame = 0
    end
    local current = state_of(value)
    if current >= constants.frame_state_ranges.record_transform_start
       and current < constants.frame_state_ranges.record_transform_end_exclusive then
        value.record = objects.record(state,
            current - constants.frame_state_ranges.record_transform_start) or value.record
        value.frame = 0
        value.pic_offset = 140
    end
    if value.record.kind == record_kinds.character
       and state_of(value) == constants.frame_states.louis_transform_shards
       and value.wait_counter == 1 then
        -- Five pieces (records 217, the last 218) burst away from the fighter.
        for piece = 0, 4 do
            local slot = objects.free_slot(state)
            if slot == -1 then break end
            local part = objects.place(state, slot,
                piece == 4 and constants.item_ids.louis_armour_two or constants.item_ids.louis_armour)
            if not part then break end
            part.x_int = random(7) - 3 + value.x_int
            part.y_int = random(7) - 9 + value.y_int
            part.z_int = value.z_int + 1
            part.z, part.y, part.x = part.z_int, part.y_int, part.x_int
            part.vy = -cdiv(random(15), 2) - 5.0
            part.timer_ec = 6
            if piece == 0 or piece == 2 then part.vz = random(2) + 3.0
            elseif piece == 1 or piece == 3 then part.vz = -3.0 - random(2)
            else part.vz = 1.0 end
            if piece < 2 then part.vx = -10.0 - random(3)
            elseif piece < 4 then part.vx = random(3) + 10.0
            else part.vx = random(7) - 3.0 end
            part.frame = random(4)
            part.facing = random(2)
        end
    end
end

-- A living player's last four key presses can command their team (defend=9, jump=0, attack=5):
-- defend-jump-defend-jump spawns an order marker (record 998, +/-40px); four defends makes the
-- team follow; defend-attack-defend-attack cancels that.
function frame_rules.team_orders(state, index, value)
    if index >= 10 or value.hp <= 0 or value.record.kind ~= record_kinds.character then return end
    local h = value.key_history
    local code = constants.team_order_codes.none
    if h[2] == constants.key_history_codes.defend then
        if h[3] == constants.key_history_codes.jump and h[4] == constants.key_history_codes.defend
           and h[5] == constants.key_history_codes.jump then code = constants.team_order_codes.move_to_marker end
        if h[3] == constants.key_history_codes.defend and h[4] == constants.key_history_codes.defend
           and h[5] == constants.key_history_codes.defend then code = constants.team_order_codes.follow end
        if h[3] == constants.key_history_codes.attack and h[4] == constants.key_history_codes.defend
           and h[5] == constants.key_history_codes.attack then code = constants.team_order_codes.cancel_follow end
    end
    if code == constants.team_order_codes.none then return end
    value.key_history = {0, 0, 0, 0, 0}
    local slot = objects.free_slot(state)
    if slot == -1 or not objects.record(state, constants.record_ids.team_order_marker) then return end
    local marker = objects.place(state, slot, constants.record_ids.team_order_marker)
    marker.x_int, marker.y_int, marker.z_int = value.x_int, 0, value.z_int
    marker.frame = code - constants.team_order_codes.move_to_marker
    marker.z, marker.y, marker.x = marker.z_int, marker.y_int, marker.x_int
    marker.vx, marker.vy = 0.0, 0.0
    if index <= 7 then marker.etc_owner = index end   -- etc_mode 1: the message sticks to player p1..p8 (see after_physics)
    for other = 0, constants.item_slots - 1 do
        local member = state.items[other]
        if member and member.hp > 0 and member.record.kind == record_kinds.character and member.team == value.team then
            if code == constants.team_order_codes.move_to_marker then
                member.order_x = random(81) - 40 + marker.x_int
                member.order_z = random(81) - 40 + marker.z_int
            elseif code == constants.team_order_codes.follow then
                member.follow_order = 1
            else
                member.follow_order = 0
            end
        end
    end
end
return frame_rules
