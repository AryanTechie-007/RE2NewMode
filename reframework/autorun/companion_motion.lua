--[[
    Resident Evil 2: Duo Mode — Companion Motion Controller
    Script: companion_motion.lua
    Purpose: Dedicated locomotion & animation controller for Claire Redfield companion.
    Author: AryanTechie-007
]]

local motion = {}
motion.enabled = true
motion.status = "Idle - Standing by"
motion.current_speed = 0.0
motion.comp_yaw = 0.0
motion.dist_to_leon = 0.0
motion.last_time = nil
motion.inspected_companion = false

-- Trail / Breadcrumb Navigation
motion.trail = {}
local MAX_TRAIL_POINTS = 30
local TRAIL_RECORD_DIST = 0.35  -- Record a point every 35cm moved by Leon
local TARGET_FOLLOW_DIST = 1.65 -- Claire targets a point ~1.65m behind Leon along his trail
local STOP_DIST = 1.15          -- Claire idles if within 1.15m of Leon
local WALK_SPEED = 2.0          -- Natural walk speed (m/s)
local RUN_SPEED = 4.2           -- Catch-up jog speed (m/s)
local RUN_THRESHOLD = 3.5       -- Start jogging if Leon is > 3.5m away
local TELEPORT_DIST = 20.0      -- Teleport if separated by cutscene or elevator

local function log_debug(msg)
    pcall(function()
        local f = io.open("motion_debug.txt", "a")
        if f then
            f:write(os.date("[%H:%M:%S] ") .. tostring(msg) .. "\n")
            f:close()
        end
    end)
    if log and log.info then
        log.info("[Motion] " .. tostring(msg))
    end
end

log_debug("=== Companion Motion Controller Initialized ===")

-- =========================================================================
-- 1. Helper Math & Rotation Utilities
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

local function get_yaw_from_transform(tf)
    if not tf or not tf.call then return 0.0 end
    local ok1, euler = pcall(function() return tf:call("get_EulerAngles") end)
    if ok1 and euler and euler.y then return euler.y end

    local ok2, euler2 = pcall(function() return tf:call("get_EulerAngle") end)
    if ok2 and euler2 and euler2.y then return euler2.y end

    local ok3, rot = pcall(function() return tf:call("get_Rotation") end)
    if ok3 and rot then
        local x = rot.x or 0.0
        local y = rot.y or 0.0
        local z = rot.z or 0.0
        local w = rot.w or 1.0
        local siny_cosp = 2.0 * (w * y + x * z)
        local cosy_cosp = 1.0 - 2.0 * (y * y + z * z)
        return math.atan(siny_cosp, cosy_cosp)
    end
    return 0.0
end

local function distance_3d(p1, p2)
    local dx = p1.x - p2.x
    local dy = (p1.y or 0) - (p2.y or 0)
    local dz = p1.z - p2.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function distance_2d(p1, p2)
    local dx = p1.x - p2.x
    local dz = p1.z - p2.z
    return math.sqrt(dx * dx + dz * dz)
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
-- 3. Discover Companion Anatomy & Built-in Motion Packages
-- =========================================================================
local function inspect_companion_anatomy(body_go)
    if motion.inspected_companion or not body_go then return end
    motion.inspected_companion = true

    log_debug("--- DISCOVERING COMPANION ANATOMY & BUILT-IN PACKAGES ---")
    pcall(function()
        local name = body_go:call("get_Name") or "unnamed"
        log_debug("Companion Root Name: " .. tostring(name))

        -- Inspect components on body root
        local comp_count = body_go:call("get_ComponentCount") or 0
        log_debug(string.format("Root Component Count: %d", comp_count))
        for i = 0, comp_count - 1 do
            local comp = body_go:call("getComponent(System.Int32)", i)
            local td = comp and comp:get_type_definition()
            log_debug(string.format("  [Root Comp %d] %s", i, td and td:get_full_name() or "unknown"))
        end

        -- Inspect components on children
        local tf = body_go:call("get_Transform")
        if tf then
            local child_count = tf:call("get_ChildCount") or 0
            log_debug(string.format("Transform Children Count: %d", child_count))
            for i = 0, child_count - 1 do
                local ch_tf = tf:call("get_Child(System.Int32)", i) or tf:call("get_Child", i)
                if ch_tf then
                    local ch_go = ch_tf:call("get_GameObject")
                    local ch_name = ch_go and ch_go:call("get_Name") or "unnamed"
                    log_debug(string.format("  [Child %d] %s", i, tostring(ch_name)))

                    if ch_go then
                        local ch_ccount = ch_go:call("get_ComponentCount") or 0
                        for j = 0, ch_ccount - 1 do
                            local ch_comp = ch_go:call("getComponent(System.Int32)", j)
                            local ch_td = ch_comp and ch_comp:get_type_definition()
                            log_debug(string.format("    -> [Child Comp %d] %s", j, ch_td and ch_td:get_full_name() or "unknown"))
                        end
                    end
                end
            end
        end
    end)
    log_debug("---------------------------------------------------------")
end

-- =========================================================================
-- 4. Breadcrumb Trail Navigation Engine (Corridor & Hallway Safe)
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

    -- If Leon moved sufficiently, record new breadcrumb
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

    -- Walk back through the recorded trail until accumulated distance reaches TARGET_FOLLOW_DIST
    local accumulated_dist = 0.0
    local prev_pt = leon_pos

    for i, pt in ipairs(motion.trail) do
        local segment_len = distance_2d(prev_pt, pt)
        accumulated_dist = accumulated_dist + segment_len
        if accumulated_dist >= TARGET_FOLLOW_DIST then
            return pt
        end
        prev_pt = pt
    end

    -- If trail is short, return the oldest recorded point
    return motion.trail[#motion.trail] or leon_pos
end

-- =========================================================================
-- 5. Companion Locomotion Execution
-- =========================================================================
local function update_companion_motion(delta_time)
    if not motion.enabled then
        motion.status = "Disabled via toggle"
        return
    end

    -- Check if Claire is spawned by character_renderer.lua
    local body_go = _G.DuoMode and _G.DuoMode.get_companion_body and _G.DuoMode.get_companion_body()
    if not body_go then
        motion.status = "Waiting for Claire to spawn..."
        motion.inspected_companion = false
        motion.trail = {}
        return
    end

    -- Inspect anatomy once
    inspect_companion_anatomy(body_go)

    local player_tf = get_player_transform()
    local body_tf = nil
    pcall(function() body_tf = body_go:call("get_Transform") end)
    if not player_tf or not body_tf then return end

    local leon_pos = nil
    pcall(function() leon_pos = player_tf:call("get_Position") end)
    local comp_pos = nil
    pcall(function() comp_pos = body_tf:call("get_Position") end)
    if not leon_pos or not comp_pos then return end

    local leon_yaw = get_yaw_from_transform(player_tf)
    local dist_leon = distance_2d(leon_pos, comp_pos)
    motion.dist_to_leon = dist_leon

    -- 1. Update Leon's safe corridor breadcrumb trail
    update_leon_trail(leon_pos)

    -- 2. Catch-up teleport if Leon is far ahead (door wrap, elevator, cutscene)
    if dist_leon > TELEPORT_DIST then
        pcall(function()
            local snap_pos = (Vector3f and Vector3f.new and Vector3f.new(leon_pos.x, leon_pos.y, leon_pos.z)) or leon_pos
            body_tf:call("set_Position", snap_pos)
            motion.trail = {}
            motion.current_speed = 0.0
            motion.status = "Catch-up Teleported"
            log_debug("Catch-up teleport executed (Leon > 20m away).")
        end)
        return
    end

    -- 3. Determine target waypoint along Leon's trail
    local target_wp = get_target_waypoint_along_trail(leon_pos, comp_pos)
    local dx = target_wp.x - comp_pos.x
    local dz = target_wp.z - comp_pos.z
    local dist_wp = math.sqrt(dx * dx + dz * dz)

    -- 4. Speed & State Brackets
    local target_speed = 0.0
    local target_yaw = motion.comp_yaw

    if dist_leon <= STOP_DIST then
        -- Idle: Claire is close to Leon, stop and face Leon's heading
        target_speed = 0.0
        target_yaw = leon_yaw
        motion.status = string.format("Idle (Alongside Leon, %.2fm)", dist_leon)
    elseif dist_leon >= RUN_THRESHOLD then
        -- Sprint: Claire is falling behind, run to catch up
        target_speed = RUN_SPEED
        target_yaw = math.atan(dx, dz)
        motion.status = string.format("Jogging to catch up (%.2fm)", dist_leon)
    else
        -- Walk: Follow Leon's trail at normal walking pace
        target_speed = WALK_SPEED
        target_yaw = math.atan(dx, dz)
        motion.status = string.format("Walking on trail (%.2fm)", dist_leon)
    end

    -- 5. Smooth Velocity Acceleration / Deceleration
    motion.current_speed = lerp(motion.current_speed, target_speed, math.min(1.0, 5.0 * delta_time))

    -- 6. Smooth Facing Rotation
    motion.comp_yaw = lerp_angle(motion.comp_yaw, target_yaw, math.min(1.0, 6.5 * delta_time))
    pcall(function()
        local half = motion.comp_yaw * 0.5
        local qy = math.sin(half)
        local qw = math.cos(half)
        local rot = (Quaternion and Quaternion.new and Quaternion.new(0, qy, 0, qw)) or { x = 0, y = qy, z = 0, w = qw }
        body_tf:call("set_Rotation", rot)
    end)

    -- 7. Physical Translation along Safe Trail
    if motion.current_speed > 0.05 and dist_wp > 0.1 then
        local move_dist = motion.current_speed * delta_time
        local nx = dx / (dist_wp > 0.001 and dist_wp or 1.0)
        local nz = dz / (dist_wp > 0.001 and dist_wp or 1.0)

        local new_x = comp_pos.x + nx * move_dist
        local new_z = comp_pos.z + nz * move_dist
        local new_y = lerp(comp_pos.y, target_wp.y or comp_pos.y, math.min(1.0, 10.0 * delta_time))

        pcall(function()
            local vpos = (Vector3f and Vector3f.new and Vector3f.new(new_x, new_y, new_z)) or { x = new_x, y = new_y, z = new_z }
            body_tf:call("set_Position", vpos)
        end)
    end
end

-- =========================================================================
-- 6. Master Frame Loop (re.on_frame)
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
-- 7. ImGui UI Panel
-- =========================================================================
local function draw_motion_ui(suffix)
    suffix = suffix or ""
    imgui.text_colored("=== RE2 DUO MODE: COMPANION MOTION ===", 0.3, 0.9, 1.0, 1.0)
    imgui.text("Status: " .. tostring(motion.status))
    imgui.text(string.format("Distance to Leon: %.2f m | Current Speed: %.1f m/s", motion.dist_to_leon, motion.current_speed))
    imgui.separator()

    local toggle_label = motion.enabled and "Motion Controller: [ACTIVE]##toggle_mot" .. suffix or "Motion Controller: [PAUSED]##toggle_mot" .. suffix
    if imgui.button(toggle_label) then
        motion.enabled = not motion.enabled
        log_debug("Motion enabled toggled: " .. tostring(motion.enabled))
    end

    imgui.same_line()
    if imgui.button("Clear Breadcrumbs##clear_trail" .. suffix) then
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
