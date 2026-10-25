--[[
    Resident Evil 2: Duo Mode
    portal_defense.lua - Prevents void-fall on door closure and handles elevator kinematic parenting
]]

local config = require("duo_mode/config")

local portal_defense = {}
portal_defense.is_on_elevator = false
portal_defense.parented_elevator = nil

-- Check if leader and companion are in different rooms after a door closes
function portal_defense.check_room_transition(leader_room_id, comp_room_id, is_door_closed)
    if leader_room_id ~= comp_room_id and is_door_closed then
        return true -- Must trigger instant teleport
    end
    return false
end

-- Parent companion to kinematic elevator platform to prevent falling through floor
function portal_defense.enter_elevator(companion_obj, elevator_game_object)
    if not companion_obj or not elevator_game_object then return end

    local comp_collider = companion_obj:call("getComponent(System.Type)", sdk.find_type_definition("via.physics.CharacterController"))
    if comp_collider then
        comp_collider:set_field("Enabled", false)
    end

    local comp_transform = companion_obj:call("get_Transform")
    local elevator_transform = elevator_game_object:call("get_Transform")
    comp_transform:call("set_Parent", elevator_transform)

    portal_defense.is_on_elevator = true
    portal_defense.parented_elevator = elevator_game_object
end

-- Unparent companion when exiting elevator
function portal_defense.exit_elevator(companion_obj)
    if not companion_obj or not portal_defense.is_on_elevator then return end

    local comp_transform = companion_obj:call("get_Transform")
    comp_transform:call("set_Parent", nil)

    local comp_collider = companion_obj:call("getComponent(System.Type)", sdk.find_type_definition("via.physics.CharacterController"))
    if comp_collider then
        comp_collider:set_field("Enabled", true)
    end

    portal_defense.is_on_elevator = false
    portal_defense.parented_elevator = nil
end

return portal_defense
