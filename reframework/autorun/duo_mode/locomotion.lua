--[[
    Resident Evil 2: Duo Mode
    locomotion.lua - Day 2: Synthetic Analog Stick Locomotion & Root-Motion Controller
    Author: AryanTechie-007
]]

local config = require("duo_mode/config")

local locomotion = {}

-- State variables for locomotion smoothing
locomotion.current_stick_x = 0.0
locomotion.current_stick_y = 0.0
locomotion.current_magnitude = 0.0
locomotion.smoothed_yaw = 0.0

-- Utility: Clamp value between min and max
local function clamp(val, min_val, max_val)
    if val < min_val then return min_val end
    if val > max_val then return max_val end
    return val
end

-- Utility: Linear interpolation
local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Utility: Normalize angle to [-pi, pi]
local function normalize_angle(rad)
    while rad > math.pi do rad = rad - (2.0 * math.pi) end
    while rad < -math.pi do rad = rad + (2.0 * math.pi) end
    return rad
end

--[[
    calculate_synthetic_stick
    Computes local analog stick tilt (X, Y) and magnitude from companion world position
    and yaw relative to the target destination.
]]
function locomotion.calculate_synthetic_stick(comp_pos, comp_yaw_rad, target_pos)
    local dx = target_pos.x - comp_pos.x
    local dz = target_pos.z - comp_pos.z
    local dist = math.sqrt(dx * dx + dz * dz)

    -- Inside idle deadzone: stop all stick input
    if dist < config.follow_distance_min then
        return 0.0, 0.0, dist, 0.0
    end

    -- Calculate absolute world-space direction to destination
    local world_angle = math.atan(dx, dz)

    -- Transform delta angle into companion's local yaw coordinate space
    -- This prevents the "donut-spinning" trap when the camera rotates!
    local local_angle = normalize_angle(world_angle - comp_yaw_rad)

    -- Determine target analog stick magnitude based on distance brackets
    local target_magnitude = 0.5 -- Default: Walk
    if dist >= config.follow_distance_run then
        target_magnitude = 1.0   -- Sprint to catch up
    elseif dist <= config.follow_distance_walk then
        -- Smooth deceleration into walk
        target_magnitude = lerp(0.35, 0.6, (dist - config.follow_distance_min) / (config.follow_distance_walk - config.follow_distance_min))
    end

    local stick_x = math.sin(local_angle) * target_magnitude
    local stick_y = math.cos(local_angle) * target_magnitude

    return stick_x, stick_y, dist, local_angle
end

--[[
    get_leader_anchor_point
    Computes the target waypoint behind the leader based on leader forward vector.
]]
function locomotion.get_leader_anchor_point(leader_transform)
    if not leader_transform then return nil end

    local leader_pos = leader_transform:call("get_Position")
    local leader_rot = leader_transform:call("get_Rotation")
    local euler = leader_rot:call("get_EulerAngles")
    local leader_yaw = euler.y

    -- Project offset backwards in direction of leader facing
    local offset_x = -math.sin(leader_yaw) * config.rear_offset
    local offset_z = -math.cos(leader_yaw) * config.rear_offset

    local target_x = leader_pos.x + offset_x
    local target_y = leader_pos.y
    local target_z = leader_pos.z + offset_z

    if Vector3f and Vector3f.new then
        return Vector3f.new(target_x, target_y, target_z)
    end
    return { x = target_x, y = target_y, z = target_z }
end

--[[
    apply_acoustic_damping
    Clamps companion stick tilt to silent walk when unalerted Lickers are in proximity.
]]
function locomotion.apply_acoustic_damping(stick_x, stick_y, is_stealth_required)
    if not is_stealth_required then
        return stick_x, stick_y
    end

    local mag = math.sqrt(stick_x * stick_x + stick_y * stick_y)
    if mag > config.licker_max_stick_magnitude then
        local scale = config.licker_max_stick_magnitude / mag
        return stick_x * scale, stick_y * scale
    end
    return stick_x, stick_y
end

--[[
    update_locomotion
    Called every frame from duo_mode.lua to calculate and inject locomotion.
]]
function locomotion.update_locomotion(companion_obj, leader_obj, delta_time, is_stealth_zone)
    if not companion_obj or not leader_obj then return 0.0, 0.0, 0.0 end

    local leader_transform = leader_obj:call("get_Transform")
    local comp_transform = companion_obj:call("get_Transform")
    if not leader_transform or not comp_transform then return 0.0, 0.0, 0.0 end

    local comp_pos = comp_transform:call("get_Position")
    local comp_rot = comp_transform:call("get_Rotation")
    local comp_euler = comp_rot:call("get_EulerAngles")
    local comp_yaw = comp_euler.y

    -- 1. Compute target waypoint behind leader
    local target_pos = locomotion.get_leader_anchor_point(leader_transform)
    if not target_pos then return 0.0, 0.0, 0.0 end

    -- 2. Compute raw synthetic stick inputs in local yaw space
    local raw_sx, raw_sy, dist, local_angle = locomotion.calculate_synthetic_stick(comp_pos, comp_yaw, target_pos)

    -- 3. Apply stealth acoustic damping if needed
    local damped_sx, damped_sy = locomotion.apply_acoustic_damping(raw_sx, raw_sy, is_stealth_zone)

    -- 4. Apply input acceleration smoothing to prevent jerky start/stop animations
    local smooth_speed = 8.0 * delta_time
    locomotion.current_stick_x = lerp(locomotion.current_stick_x, damped_sx, smooth_speed)
    locomotion.current_stick_y = lerp(locomotion.current_stick_y, damped_sy, smooth_speed)
    locomotion.current_magnitude = math.sqrt(locomotion.current_stick_x * locomotion.current_stick_x + locomotion.current_stick_y * locomotion.current_stick_y)

    -- 5. Smooth rotation alignment toward motion vector
    if locomotion.current_magnitude > 0.05 then
        local target_turn = comp_yaw + local_angle
        local new_yaw = lerp(comp_yaw, target_turn, 6.0 * delta_time)
        pcall(function()
            local new_rot = Quaternion.new(0, 0, 0, 1)
            -- Apply smoothed yaw rotation to transform if character controller allows
        end)
    end

    return locomotion.current_stick_x, locomotion.current_stick_y, dist
end

return locomotion
