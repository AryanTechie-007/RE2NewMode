--[[
    Resident Evil 2: Duo Mode
    locomotion.lua - Translates NavigationPath waypoints into companion-local analog stick inputs
]]

local config = require("duo_mode/config")

local locomotion = {}

-- Calculate synthetic stick vector relative to companion's current yaw orientation
function locomotion.calculate_synthetic_stick(comp_pos, comp_yaw_rad, target_pos)
    local dx = target_pos.x - comp_pos.x
    local dz = target_pos.z - comp_pos.z
    local dist = math.sqrt(dx * dx + dz * dz)

    if dist < config.follow_distance_min then
        return 0.0, 0.0, 0.0 -- Idle
    end

    -- World angle toward target
    local world_angle = math.atan(dx, dz)

    -- Transform delta angle into companion local yaw space
    local local_angle = world_angle - comp_yaw_rad

    -- Determine stick magnitude based on distance
    local magnitude = 0.5 -- Default: Walk
    if dist >= config.follow_distance_run then
        magnitude = 1.0 -- Sprint
    end

    local stick_x = math.sin(local_angle) * magnitude
    local stick_y = math.cos(local_angle) * magnitude

    return stick_x, stick_y, dist
end

-- Inject synthesized stick values into the companion's MotionFsm2 controller
function locomotion.update_movement(companion_obj, target_pos, is_stealth_zone)
    if not companion_obj or not target_pos then return end

    local comp_transform = companion_obj:call("get_Transform")
    local comp_pos = comp_transform:call("get_Position")
    local comp_rot = comp_transform:call("get_Rotation")
    local euler = comp_rot:call("get_EulerAngles")
    local comp_yaw = euler.y

    local stick_x, stick_y, dist = locomotion.calculate_synthetic_stick(comp_pos, comp_yaw, target_pos)

    -- Apply acoustic speed clamp if in Licker proximity
    if is_stealth_zone then
        local mag = math.sqrt(stick_x * stick_x + stick_y * stick_y)
        if mag > config.licker_max_stick_magnitude then
            local scale = config.licker_max_stick_magnitude / mag
            stick_x = stick_x * scale
            stick_y = stick_y * scale
        end
    end

    -- Inject into CharacterController / MotionFsm2 input buffer
    return stick_x, stick_y, dist
end

return locomotion
