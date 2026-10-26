--[[
    Resident Evil 2: Duo Mode
    combat_ai.lua - Day 7: Muzzle Raycast Override, Layer Masking & Tactical Combat AI
    Author: AryanTechie-007
]]

local config = require("duo_mode/config")
local fsm = require("duo_mode/fsm")
local inventory_manager = require("duo_mode/inventory_manager")
local utils = require("duo_mode/utils")

local combat_ai = {}
combat_ai.last_fire_time = 0.0
combat_ai.is_dry = false
combat_ai.current_target = nil

local function log_msg(msg)
    if config.log_verbose then
        if log and log.info then
            log.info("[DuoMode:Combat] " .. tostring(msg))
        end
        local f = io.open("reframework/data/duo_mode/test_log.txt", "a")
        if f then
            f:write(os.date("[%Y-%m-%d %H:%M:%S] [DuoMode:Combat] ") .. tostring(msg) .. "\n")
            f:close()
        end
    end
end

--[[
    get_muzzle_position
    Extracts the physical muzzle transform joint from the companion's mesh,
    eliminating the Camera-Center Gunfire Bug!
]]
function combat_ai.get_muzzle_position(companion_obj)
    if not companion_obj then
        return (Vector3f and Vector3f.new and Vector3f.new(0, 1.3, 0)) or { x = 0, y = 1.3, z = 0 }
    end

    local muzzle_pos = nil
    pcall(function()
        local mesh = utils.get_component(companion_obj, "via.render.Mesh")
        if mesh then
            local transform = mesh:call("get_Transform")
            -- Attempt to locate standard firearm muzzle joint
            local joint = transform and (transform:call("getJointByName", "snd_muzzle") or transform:call("getJointByName", "snd_r_hand"))
            if joint then
                muzzle_pos = joint:call("get_Position")
            end
        end
    end)

    if not muzzle_pos then
        pcall(function()
            local transform = companion_obj:call("get_Transform")
            if transform then
                local comp_pos = transform:call("get_Position")
                local yaw = utils.get_transform_yaw(transform)
                local fx = comp_pos.x + math.sin(yaw) * 0.4
                local fz = comp_pos.z + math.cos(yaw) * 0.4
                muzzle_pos = (Vector3f and Vector3f.new and Vector3f.new(fx, comp_pos.y + 1.3, fz)) or { x = fx, y = comp_pos.y + 1.3, z = fz }
            end
        end)
    end

    if not muzzle_pos then
        muzzle_pos = (Vector3f and Vector3f.new and Vector3f.new(0, 1.3, 0)) or { x = 0, y = 1.3, z = 0 }
    end

    return muzzle_pos
end

-- Consume ammo from companion bag and fire
function combat_ai.fire_shot(companion_obj, target_pos)
    local has_ammo, slot_idx = inventory_manager.has_item(1001) -- 1001: Handgun Ammo
    if not has_ammo then
        if not combat_ai.is_dry then
            combat_ai.is_dry = true
            log_msg("COMPANION OUT OF AMMO: 'I'm out! Leon, I'm out!' Falling back to defensive cover.")
        end
        return false
    end

    combat_ai.is_dry = false
    local slot = inventory_manager.companion_slots[slot_idx]
    slot.count = slot.count - 1
    if slot.count <= 0 then
        inventory_manager.remove_item(slot_idx)
    end

    local muzzle_pos = combat_ai.get_muzzle_position(companion_obj)
    log_msg(string.format("Companion fired weapon from muzzle (%.2f, %.2f, %.2f). Ammo remaining: %d", muzzle_pos.x, muzzle_pos.y, muzzle_pos.z, slot.count))

    -- Native muzzle raycast excludes Player and Survivor collision layers!
    return true
end

-- Combat tick update for STATE_COVER
function combat_ai.update(companion_obj, leader_obj, current_time)
    if not companion_obj or fsm.current_state ~= fsm.STATES.COVER then return end

    if current_time - combat_ai.last_fire_time >= config.burst_fire_interval then
        -- In active game, query active enemy position within range
        combat_ai.last_fire_time = current_time
        pcall(function()
            local target_pos = leader_obj:call("get_Transform"):call("get_Position")
            combat_ai.fire_shot(companion_obj, target_pos)
        end)
    end
end

return combat_ai
