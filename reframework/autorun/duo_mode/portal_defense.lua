--[[
    Resident Evil 2: Duo Mode
    portal_defense.lua - Day 3: Room Portal Culling Defense & Elevator Kinematic Parenting
    Author: AryanTechie-007
]]

local config = require("duo_mode/config")
local utils = require("duo_mode/utils")

local portal_defense = {}
portal_defense.is_on_elevator = false
portal_defense.parented_elevator = nil
portal_defense.last_leader_room = 0
portal_defense.last_comp_room = 0

local function log_msg(msg)
    if config.log_verbose then
        if log and log.info then
            log.info("[DuoMode:Portal] " .. tostring(msg))
        end
        local f = io.open("reframework/data/duo_mode/test_log.txt", "a")
        if f then
            f:write(os.date("[%Y-%m-%d %H:%M:%S] [DuoMode:Portal] ") .. tostring(msg) .. "\n")
            f:close()
        end
    end
end

-- Get current room ID from a character GameObject via app.ropeway.RoomArea
function portal_defense.get_room_id(game_obj)
    if not game_obj then return 0 end
    local room_id = 0
    pcall(function()
        local room_area = utils.get_component(game_obj, "app.ropeway.RoomArea")
        if room_area then
            room_id = room_area:call("get_CurrentRoomID") or 0
        end
    end)
    return room_id
end

-- Check if leader and companion are in different rooms after a door closes
function portal_defense.check_room_transition(leader_room_id, comp_room_id, is_door_closed)
    if leader_room_id ~= 0 and comp_room_id ~= 0 and leader_room_id ~= comp_room_id and is_door_closed then
        return true -- Must trigger instant teleport
    end
    return false
end

-- Teleport companion safely behind leader
function portal_defense.teleport_to_leader(companion_obj, leader_obj, offset_dist)
    if not companion_obj or not leader_obj then return end
    offset_dist = offset_dist or 2.0

    pcall(function()
        local leader_transform = leader_obj:call("get_Transform")
        if not leader_transform then return end
        local leader_pos = leader_transform:call("get_Position")
        if not leader_pos then return end

        local leader_yaw = utils.get_transform_yaw(leader_transform)

        local safe_x = leader_pos.x - math.sin(leader_yaw) * offset_dist
        local safe_y = leader_pos.y
        local safe_z = leader_pos.z - math.cos(leader_yaw) * offset_dist

        local safe_pos = (Vector3f and Vector3f.new and Vector3f.new(safe_x, safe_y, safe_z)) or { x = safe_x, y = safe_y, z = safe_z }

        -- Warp physics character controller to safe position
        local char_ctrl = utils.get_component(companion_obj, "via.physics.CharacterController")
        if char_ctrl then
            pcall(function() char_ctrl:call("warp", safe_pos) end)
        else
            pcall(function()
                local comp_tf = companion_obj:call("get_Transform")
                if comp_tf then comp_tf:call("set_Position", safe_pos) end
            end)
        end
        log_msg(string.format("Portal catch-up: companion teleported to safe room pos (%.2f, %.2f, %.2f)", safe_x, safe_y, safe_z))
    end)
end

-- Parent companion to kinematic elevator platform to prevent falling through floor
function portal_defense.enter_elevator(companion_obj, elevator_game_object)
    if not companion_obj or not elevator_game_object then return end

    log_msg("Elevator entered: parenting companion transform and disabling capsule collision.")
    pcall(function()
        local comp_collider = utils.get_component(companion_obj, "via.physics.CharacterController")
        if comp_collider then
            pcall(function() comp_collider:set_field("Enabled", false) end)
        end

        local comp_transform = companion_obj:call("get_Transform")
        local elevator_transform = elevator_game_object:call("get_Transform")
        if comp_transform and elevator_transform then
            pcall(function() comp_transform:call("set_Parent", elevator_transform) end)
        end

        portal_defense.is_on_elevator = true
        portal_defense.parented_elevator = elevator_game_object
    end)
end

-- Unparent companion when exiting elevator
function portal_defense.exit_elevator(companion_obj)
    if not companion_obj or not portal_defense.is_on_elevator then return end

    log_msg("Elevator exited: restoring companion transform parent and capsule collision.")
    pcall(function()
        local comp_transform = companion_obj:call("get_Transform")
        if comp_transform then
            pcall(function() comp_transform:call("set_Parent", nil) end)
        end

        local comp_collider = utils.get_component(companion_obj, "via.physics.CharacterController")
        if comp_collider then
            pcall(function() comp_collider:set_field("Enabled", true) end)
        end

        portal_defense.is_on_elevator = false
        portal_defense.parented_elevator = nil
    end)
end

-- Update portal culling checks every frame
function portal_defense.update(companion_obj, leader_obj)
    if not companion_obj or not leader_obj or portal_defense.is_on_elevator then return end

    local leader_room = portal_defense.get_room_id(leader_obj)
    local comp_room = portal_defense.get_room_id(companion_obj)

    portal_defense.last_leader_room = leader_room
    portal_defense.last_comp_room = comp_room

    -- Check Euclidean distance fallback
    pcall(function()
        local leader_tf = leader_obj:call("get_Transform")
        local comp_tf = companion_obj:call("get_Transform")
        if not leader_tf or not comp_tf then return end

        local leader_pos = leader_tf:call("get_Position")
        local comp_pos = comp_tf:call("get_Position")
        if not leader_pos or not comp_pos then return end

        local dx = leader_pos.x - comp_pos.x
        local dy = leader_pos.y - comp_pos.y
        local dz = leader_pos.z - comp_pos.z
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

        -- If distance exceeds rubber-band threshold or vertical desync occurs
        if dist > config.rubber_band_distance or math.abs(dy) > 4.5 then
            log_msg(string.format("Rubber-band triggered: distance=%.1fm, dy=%.1fm. Catching up...", dist, dy))
            portal_defense.teleport_to_leader(companion_obj, leader_obj, 2.0)
        end
    end)
end

return portal_defense
