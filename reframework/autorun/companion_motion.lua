--[[
    Resident Evil 2: Duo Mode — Companion Motion Controller
    Script: companion_motion.lua
    Purpose: Dedicated locomotion & trail gliding controller treating the rendered Claire as a singular OOP entity.
    Author: AryanTechie-007
]]

local motion = {}
motion.enabled = true
motion.status = "Idle - Standing by"
motion.current_speed = 0.0
motion.verified_velocity = 0.0
motion.comp_yaw = 0.0
motion.dist_to_leon = 0.0
motion.comp_pos = { x = 0.0, y = 0.0, z = 0.0 }
motion.leon_pos = { x = 0.0, y = 0.0, z = 0.0 }
motion.last_time = nil

-- Trail / Breadcrumb Navigation
motion.trail = {}
local MAX_TRAIL_POINTS = 40
local TRAIL_RECORD_DIST = 0.30  -- Record a point every 30cm moved by Leon
local TARGET_FOLLOW_DIST = 1.60 -- Target point along trail behind Leon
local STOP_DIST = 1.20          -- Idle if within 1.20m of Leon
local WALK_SPEED = 2.0          -- Natural gliding walk speed (m/s)
local RUN_SPEED = 4.2           -- Gliding catch-up speed (m/s)
local RUN_THRESHOLD = 3.2       -- Start jogging if Leon is > 3.2m away
local TELEPORT_DIST = 18.0      -- Snap-teleport if separated by elevator/door

local function log_debug(msg)
    pcall(function()
        local f = io.open("reframework/data/motion_debug.txt", "a")
        if f then
            f:write(os.date("[%H:%M:%S] ") .. tostring(msg) .. "\n")
            f:close()
        end
    end)
    pcall(function()
        local f2 = io.open("motion_debug.txt", "a")
        if f2 then
            f2:write(os.date("[%H:%M:%S] ") .. tostring(msg) .. "\n")
            f2:close()
        end
    end)
    if log and log.info then
        log.info("[Motion] " .. tostring(msg))
    end
end

log_debug("=== Companion Motion Controller Initialized (Singular OOP Mode) ===")

-- =========================================================================
-- 1. Helper Math & Transform Utilities
-- =========================================================================
local function lerp(a, b, t)
    return a + (b - a) * t
end

local function lerp_angle(from_rad, to_rad, t)
    local diff = to_rad - from_rad
    while diff > math.pi do diff = diff - 2.0 * math.pi end
    while diff < -math.pi do diff = diff + 2.0 * math.pi end
    return from_rad + diff * t
end

local function distance_2d(p1, p2)
    local dx = p1.x - p2.x
    local dz = p1.z - p2.z
    return math.sqrt(dx * dx + dz * dz)
end

local function get_transform_position(tf)
    if not tf then return nil end
    if tf.get_position then
        local ok, p = pcall(function() return tf:get_position() end)
        if ok and p and p.x then return { x = p.x, y = p.y, z = p.z } end
    end
    if tf.call then
        local ok, p = pcall(function() return tf:call("get_Position") end)
        if ok and p and p.x then return { x = p.x, y = p.y, z = p.z } end
    end
    return nil
end

local function set_transform_position(tf, x, y, z)
    if not tf then return false end
    local v4 = Vector4f and Vector4f.new and Vector4f.new(x, y, z, 1.0)
    local v3 = Vector3f and Vector3f.new and Vector3f.new(x, y, z)

    -- 1. Native RETransform:set_position
    if v4 and tf.set_position then
        local ok1 = pcall(function() tf:set_position(v4) end)
        if ok1 then return true end
    end
    if v3 and tf.set_position then
        local ok2 = pcall(function() tf:set_position(v3) end)
        if ok2 then return true end
    end

    -- 2. Managed call
    if tf.call then
        if v3 then
            local ok3 = pcall(function() tf:call("set_Position(via.vec3)", v3) end)
            if ok3 then return true end
            local ok4 = pcall(function() tf:call("set_Position", v3) end)
            if ok4 then return true end
        end
        if v4 then
            local ok5 = pcall(function() tf:call("set_Position(via.vec3)", v4) end)
            if ok5 then return true end
            local ok6 = pcall(function() tf:call("set_Position", v4) end)
            if ok6 then return true end
        end
    end
    return false
end

local function get_yaw_from_transform(tf)
    if not tf then return 0.0 end
    if tf.get_rotation then
        local ok, rot = pcall(function() return tf:get_rotation() end)
        if ok and rot and rot.w then
            local x = rot.x or 0.0
            local y = rot.y or 0.0
            local z = rot.z or 0.0
            local w = rot.w or 1.0
            local siny = 2.0 * (w * y + x * z)
            local cosy = 1.0 - 2.0 * (y * y + z * z)
            return math.atan(siny, cosy)
        end
    end
    if tf.call then
        local ok1, euler = pcall(function() return tf:call("get_EulerAngles") end)
        if ok1 and euler and euler.y then return euler.y end
        local ok2, rot = pcall(function() return tf:call("get_Rotation") end)
        if ok2 and rot and rot.w then
            local x = rot.x or 0.0
            local y = rot.y or 0.0
            local z = rot.z or 0.0
            local w = rot.w or 1.0
            local siny = 2.0 * (w * y + x * z)
            local cosy = 1.0 - 2.0 * (y * y + z * z)
            return math.atan(siny, cosy)
        end
    end
    return 0.0
end

local function set_transform_rotation(tf, yaw_rad)
    if not tf then return false end
    local half = yaw_rad * 0.5
    local qy = math.sin(half)
    local qw = math.cos(half)
    local q = Quaternion and Quaternion.new and Quaternion.new(0.0, qy, 0.0, qw)
    if not q then return false end

    if tf.set_rotation then
        local ok1 = pcall(function() tf:set_rotation(q) end)
        if ok1 then return true end
    end
    if tf.call then
        local ok2 = pcall(function() tf:call("set_Rotation(via.Quaternion)", q) end)
        if ok2 then return true end
        local ok3 = pcall(function() tf:call("set_Rotation", q) end)
        if ok3 then return true end
    end
    return false
end

-- =========================================================================
-- 2. Player Resolution
-- =========================================================================
local function get_master_player()
    local player_man = nil
    pcall(function()
        player_man = sdk.get_managed_singleton("app.ropeway.PlayerManager")
                  or sdk.get_managed_singleton(sdk.game_namespace("PlayerManager"))
    end)
    if not player_man then return nil end

    local p = nil
    pcall(function() p = player_man:call("get_CurrentPlayer") end)
    if not p then pcall(function() p = player_man:call("getMasterPlayerCharacter") end) end
    if not p then pcall(function() p = player_man:call("get_CurrentPlayerCharacter") end) end
    if not p then pcall(function() p = player_man:call("get_MasterPlayerCharacter") end) end
    return p
end

local function get_player_transform(player)
    player = player or get_master_player()
    if not player then return nil end
    local tf = nil
    pcall(function()
        if player.get_Transform then tf = player:get_Transform() end
    end)
    if not tf then
        pcall(function()
            local go = player.get_game_object and player:get_game_object() or player:call("get_GameObject")
            if go then tf = go:call("get_Transform") end
        end)
    end
    return tf
end

-- =========================================================================
-- 3. Breadcrumb Trail Navigation Engine (Corridor & Hallway Safe)
-- =========================================================================
local function update_leon_trail(leon_pos)
    if not leon_pos then return end

    local count = #motion.trail
    if count == 0 then
        table.insert(motion.trail, 1, { x = leon_pos.x, y = leon_pos.y, z = leon_pos.z })
        return
    end

    local last_pt = motion.trail[1]
    local dist_from_last = distance_2d(last_pt, leon_pos)

    if dist_from_last >= TRAIL_RECORD_DIST then
        table.insert(motion.trail, 1, { x = leon_pos.x, y = leon_pos.y, z = leon_pos.z })
        if #motion.trail > MAX_TRAIL_POINTS then
            table.remove(motion.trail)
        end
    end
end

local function get_target_waypoint_along_trail(leon_pos, comp_pos)
    if #motion.trail == 0 then
        return leon_pos
    end

    local accumulated_dist = 0.0
    local prev_pt = leon_pos

    for _, pt in ipairs(motion.trail) do
        local segment_len = distance_2d(prev_pt, pt)
        accumulated_dist = accumulated_dist + segment_len
        if accumulated_dist >= TARGET_FOLLOW_DIST then
            return pt
        end
        prev_pt = pt
    end

    return motion.trail[#motion.trail] or leon_pos
end

-- =========================================================================
-- 4. Companion Gliding Execution Loop (Treats Entire Model as Singular Unit)
-- =========================================================================
local function update_companion_motion(delta_time)
    if not motion.enabled then
        motion.status = "Disabled via toggle"
        return
    end

    -- Query the singular unified companion object created by character_renderer.lua
    local companion = _G.DuoMode and _G.DuoMode.get_companion and _G.DuoMode.get_companion()
    if not companion then
        motion.status = "Waiting for Claire to be rendered..."
        motion.trail = {}
        return
    end

    local player_tf = get_player_transform()
    local comp_tf = nil
    pcall(function() comp_tf = companion:call("get_Transform") end)
    if not player_tf or not comp_tf then return end

    local leon_pos = get_transform_position(player_tf)
    local comp_pos = get_transform_position(comp_tf)
    if not leon_pos or not comp_pos then return end

    motion.leon_pos = leon_pos
    motion.comp_pos = comp_pos

    local leon_yaw = get_yaw_from_transform(player_tf)
    local dist_leon = distance_2d(leon_pos, comp_pos)
    motion.dist_to_leon = dist_leon

    -- 1. Update corridor breadcrumbs
    update_leon_trail(leon_pos)

    -- 2. Catch-up teleport if separated by door or elevator
    if dist_leon > TELEPORT_DIST then
        set_transform_position(comp_tf, leon_pos.x, leon_pos.y, leon_pos.z)
        motion.trail = {}
        motion.current_speed = 0.0
        motion.status = "Catch-up Teleported"
        log_debug(string.format("Catch-up teleport executed (Leon %.1fm away).", dist_leon))
        return
    end

    -- 3. Waypoint along trail
    local target_wp = get_target_waypoint_along_trail(leon_pos, comp_pos)
    local dx = target_wp.x - comp_pos.x
    local dz = target_wp.z - comp_pos.z
    local dist_wp = math.sqrt(dx * dx + dz * dz)

    -- 4. Speed brackets
    local target_speed = 0.0
    local target_yaw = motion.comp_yaw

    if dist_leon <= STOP_DIST then
        target_speed = 0.0
        target_yaw = leon_yaw
        motion.status = string.format("Idle (Alongside Leon, %.2fm)", dist_leon)
    elseif dist_leon >= RUN_THRESHOLD then
        target_speed = RUN_SPEED
        target_yaw = math.atan(dx, dz)
        motion.status = string.format("Gliding to catch up (%.2fm)", dist_leon)
    else
        target_speed = WALK_SPEED
        target_yaw = math.atan(dx, dz)
        motion.status = string.format("Gliding along trail (%.2fm)", dist_leon)
    end

    -- 5. Smooth Speed
    motion.current_speed = lerp(motion.current_speed, target_speed, math.min(1.0, 6.0 * delta_time))

    -- 6. Smooth Facing Rotation
    motion.comp_yaw = lerp_angle(motion.comp_yaw, target_yaw, math.min(1.0, 7.5 * delta_time))
    set_transform_rotation(comp_tf, motion.comp_yaw)

    -- 7. Physical Translation of Singular Model Unit
    if motion.current_speed > 0.05 and dist_wp > 0.1 then
        local move_dist = motion.current_speed * delta_time
        local nx = dx / (dist_wp > 0.001 and dist_wp or 1.0)
        local nz = dz / (dist_wp > 0.001 and dist_wp or 1.0)

        local new_x = comp_pos.x + nx * move_dist
        local new_z = comp_pos.z + nz * move_dist
        local new_y = lerp(comp_pos.y, target_wp.y or comp_pos.y, math.min(1.0, 8.0 * delta_time))

        set_transform_position(comp_tf, new_x, new_y, new_z)

        local p_after = get_transform_position(comp_tf)
        if p_after then
            local actual_delta = distance_2d(comp_pos, p_after)
            motion.verified_velocity = actual_delta / (delta_time > 0 and delta_time or 0.016)
            motion.comp_pos = p_after
        end
    else
        motion.verified_velocity = 0.0
    end
end

-- =========================================================================
-- 5. Master Frame Loop (re.on_frame)
-- =========================================================================
re.on_frame(function()
    local now = os.clock()
    local dt = motion.last_time and (now - motion.last_time) or 0.0166
    motion.last_time = now
    if dt <= 0.0 or dt > 0.1 then dt = 0.0166 end

    pcall(function()
        update_companion_motion(dt)
    end)
end)

-- =========================================================================
-- 6. ImGui UI Panel
-- =========================================================================
local function draw_motion_ui(suffix)
    suffix = suffix or ""
    imgui.text_colored("=== RE2 DUO MODE: COMPANION MOTION ===", 0.3, 0.9, 1.0, 1.0)
    imgui.text("Status: " .. tostring(motion.status))
    imgui.text(string.format("Distance to Leon: %.2f m | Speed: %.1f m/s (Live: %.1f m/s)",
        motion.dist_to_leon, motion.current_speed, motion.verified_velocity))

    imgui.text(string.format("Claire Pos: (%.2f, %.2f, %.2f)", motion.comp_pos.x, motion.comp_pos.y, motion.comp_pos.z))
    imgui.text(string.format("Leon Pos:   (%.2f, %.2f, %.2f)", motion.leon_pos.x, motion.leon_pos.y, motion.leon_pos.z))
    imgui.separator()

    local toggle_label = motion.enabled and "Motion Controller: [ACTIVE]##toggle_mot" .. suffix or "Motion Controller: [PAUSED]##toggle_mot" .. suffix
    if imgui.button(toggle_label) then
        motion.enabled = not motion.enabled
        log_debug("Motion enabled toggled: " .. tostring(motion.enabled))
    end

    imgui.same_line()
    if imgui.button("Clear Trail##clear_trail" .. suffix) then
        motion.trail = {}
        log_debug("Breadcrumb trail cleared.")
    end
end

-- Dedicated Standalone Floating Window
re.on_frame(function()
    pcall(function()
        if imgui.begin_window("Claire Motion (Duo Mode)", true, 0) then
            draw_motion_ui("##win")
            imgui.end_window()
        end
    end)
end)

-- Embedded in REFramework Main Menu
re.on_draw_ui(function()
    draw_motion_ui("##menu")
end)
