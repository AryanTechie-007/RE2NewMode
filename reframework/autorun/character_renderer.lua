--[[
    Resident Evil 2: Duo Mode — Claire Redfield Spawner & Companion Locomotion
    Script: character_renderer.lua
    Purpose: Dedicated harness to spawn Claire Redfield (PL1000) and drive companion locomotion (follow Leon).
    Author: AryanTechie-007
]]

local spawner = {}
spawner.spawned_entities = {}
spawner.last_status = "Ready - Standing by (Click button to spawn)"
spawner.click_count = 0

-- Prefab candidates to scan on startup
local BODY_CANDIDATES = {
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_a.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_1.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_0.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_2.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_body.pfb",
    "objectroot/prefab/character/survivor/pl1000.pfb",
    "objectroot/prefab/character/player/pl1000.pfb"
}

local HEAD_CANDIDATES = {
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_face_costume_a.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_face_costume_1.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_head_costume_a.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_face.pfb"
}

local HAIR_CANDIDATES = {
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_hair_costume_a.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_hair_costume_1.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_hair.pfb"
}

spawner.best_body = nil
spawner.best_head = nil
spawner.best_hair = nil

-- Streaming State
spawner.body_pfb = nil
spawner.head_pfb = nil
spawner.hair_pfb = nil
spawner.streaming = false
spawner.stream_frames = 0
spawner.mode = "full"

-- Locomotion Configuration & State
spawner.follow_enabled = true
spawner.comp_body_obj = nil
spawner.comp_yaw = 0.0
spawner.current_speed = 0.0
spawner.last_time = nil
spawner.loco_status = "Idle"
spawner.dist_to_leon = 0.0

-- Follow Tuning Parameters
local FOLLOW_REAR_DIST = 1.8   -- 1.8 meters behind Leon
local FOLLOW_SIDE_DIST = 0.8   -- 0.8 meters to Leon's right
local STOP_DIST        = 0.7   -- Stop when within 0.7m of anchor point
local WALK_SPEED       = 1.9   -- Walking speed (m/s)
local RUN_SPEED        = 4.3   -- Running speed (m/s)
local RUN_THRESHOLD    = 3.2   -- Sprint if anchor is > 3.2m away
local TELEPORT_DIST    = 22.0  -- Catch-up teleport if > 22m away
local ROTATE_SPEED     = 7.0   -- Rotation slerp speed
local ACCEL_SPEED      = 5.5   -- Velocity lerp speed

local function log_debug(msg)
    pcall(function()
        local f = io.open("spawner_debug.txt", "a")
        if f then
            f:write(os.date("[%H:%M:%S] ") .. tostring(msg) .. "\n")
            f:close()
        end
    end)
    if log and log.info then
        log.info("[Spawner] " .. tostring(msg))
    end
end

-- =========================================================================
-- 1. Scan and Resolve Valid Paths
-- =========================================================================
function spawner.scan_all_candidates()
    log_debug("=== Scanning RE2 Pak Archives for Claire Parts ===")

    for _, path in ipairs(BODY_CANDIDATES) do
        local exists = false
        pcall(function()
            local pfb = sdk.create_instance("via.Prefab"):add_ref()
            pfb:call("set_Path", path)
            exists = pfb:call("get_Exist")
        end)
        if exists then
            log_debug("  [BODY: TRUE]  " .. path)
            if not spawner.best_body then spawner.best_body = path end
        else
            log_debug("  [BODY: FALSE] " .. path)
        end
    end

    for _, path in ipairs(HEAD_CANDIDATES) do
        local exists = false
        pcall(function()
            local pfb = sdk.create_instance("via.Prefab"):add_ref()
            pfb:call("set_Path", path)
            exists = pfb:call("get_Exist")
        end)
        if exists then
            log_debug("  [HEAD: TRUE]  " .. path)
            if not spawner.best_head then spawner.best_head = path end
        else
            log_debug("  [HEAD: FALSE] " .. path)
        end
    end

    for _, path in ipairs(HAIR_CANDIDATES) do
        local exists = false
        pcall(function()
            local pfb = sdk.create_instance("via.Prefab"):add_ref()
            pfb:call("set_Path", path)
            exists = pfb:call("get_Exist")
        end)
        if exists then
            log_debug("  [HAIR: TRUE]  " .. path)
            if not spawner.best_hair then spawner.best_hair = path end
        else
            log_debug("  [HAIR: FALSE] " .. path)
        end
    end

    log_debug("=== Resolution Complete ===")
    log_debug("  Selected Body: " .. tostring(spawner.best_body))
    log_debug("  Selected Head: " .. tostring(spawner.best_head))
    log_debug("  Selected Hair: " .. tostring(spawner.best_hair))
end

-- =========================================================================
-- 2. Helper: Safe Yaw and Forward Vector Extraction
-- =========================================================================
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

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function lerp_angle(from_rad, to_rad, t)
    local diff = to_rad - from_rad
    while diff > math.pi do diff = diff - (2.0 * math.pi) end
    while diff < -math.pi do diff = diff + (2.0 * math.pi) end
    return from_rad + diff * t
end

local function get_front_spawn_position(player_tf, dist)
    dist = dist or 2.0
    local fx, fy, fz = 0.0, 0.0, 0.0
    pcall(function()
        local pos = player_tf:call("get_Position")
        local yaw = get_yaw_from_transform(player_tf)
        fx = pos.x + math.sin(yaw) * dist
        fy = pos.y
        fz = pos.z + math.cos(yaw) * dist
    end)
    return (Vector3f and Vector3f.new and Vector3f.new(fx, fy, fz)) or { x = fx, y = fy, z = fz }
end

-- Compute dynamic companion tactical anchor point relative to Leon
local function get_companion_anchor_point(player_tf)
    local ax, ay, az = 0.0, 0.0, 0.0
    local ok = pcall(function()
        local pos = player_tf:call("get_Position")
        local yaw = get_yaw_from_transform(player_tf)
        -- Forward and Right unit vectors
        local fx = math.sin(yaw)
        local fz = math.cos(yaw)
        local rx = math.cos(yaw)
        local rz = -math.sin(yaw)
        -- Rear + Right shoulder offset
        ax = pos.x - fx * FOLLOW_REAR_DIST + rx * FOLLOW_SIDE_DIST
        ay = pos.y
        az = pos.z - fz * FOLLOW_REAR_DIST + rz * FOLLOW_SIDE_DIST
    end)
    if not ok then return nil end
    return (Vector3f and Vector3f.new and Vector3f.new(ax, ay, az)) or { x = ax, y = ay, z = az }
end

-- =========================================================================
-- 3. Player Resolution
-- =========================================================================
function spawner.get_master_player()
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

function spawner.get_player_game_object(player)
    player = player or spawner.get_master_player()
    if not player then return nil end
    local go = nil
    pcall(function() if player.get_game_object then go = player:get_game_object() end end)
    if not go then pcall(function() go = player:call("get_GameObject") end) end
    return go or player
end

-- =========================================================================
-- 4. Despawn Logic
-- =========================================================================
function spawner.execute_despawn()
    pcall(function()
        local scene_man = nil
        pcall(function() scene_man = sdk.get_native_singleton("via.SceneManager") end)
        local cur_scene = nil
        pcall(function() cur_scene = scene_man and scene_man:call("get_CurrentScene") end)

        for _, entity in ipairs(spawner.spawned_entities) do
            pcall(function()
                if entity and entity.call then
                    pcall(function() entity:call("set_DrawSelf", false) end)
                    pcall(function() entity:call("set_UpdateSelf", false) end)
                    if cur_scene then
                        pcall(function() cur_scene:call("destroyGameObject(via.GameObject)", entity) end)
                        pcall(function() cur_scene:call("destroyGameObject", entity) end)
                    end
                end
            end)
        end
    end)
    spawner.spawned_entities = {}
    spawner.comp_body_obj = nil
    spawner.body_pfb = nil
    spawner.head_pfb = nil
    spawner.hair_pfb = nil
    spawner.streaming = false
    spawner.stream_frames = 0
    spawner.current_speed = 0.0
    spawner.loco_status = "Idle"
    spawner.last_status = "Despawned - Standing by"
    log_debug("Despawn executed cleanly.")
end

-- =========================================================================
-- 5. Initiate Spawner Pipeline
-- =========================================================================
function spawner.start_spawn(mode)
    spawner.execute_despawn()
    spawner.mode = mode or "full"

    if not spawner.best_body then
        spawner.scan_all_candidates()
    end

    local body_path = spawner.best_body or "objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_a.pfb"
    local head_path = spawner.best_head or "objectroot/prefab/character/survivor/parts/pl1000/pl1000_face_costume_a.pfb"
    local hair_path = spawner.best_hair or "objectroot/prefab/character/survivor/parts/pl1000/pl1000_hair_costume_a.pfb"

    log_debug("Starting Claire Spawn Pipeline (Mode: " .. spawner.mode .. "):")
    log_debug("  Body: " .. tostring(body_path))
    if spawner.mode == "full" then
        log_debug("  Head: " .. tostring(head_path))
        log_debug("  Hair: " .. tostring(hair_path))
    end

    pcall(function()
        local b = sdk.create_instance("via.Prefab"):add_ref()
        b:call("set_Path", body_path)
        b:call("set_Standby", true)
        spawner.body_pfb = b
    end)

    if spawner.mode == "full" and head_path then
        pcall(function()
            local h = sdk.create_instance("via.Prefab"):add_ref()
            h:call("set_Path", head_path)
            h:call("set_Standby", true)
            spawner.head_pfb = h
        end)
    end
    if spawner.mode == "full" and hair_path then
        pcall(function()
            local hr = sdk.create_instance("via.Prefab"):add_ref()
            hr:call("set_Path", hair_path)
            hr:call("set_Standby", true)
            spawner.hair_pfb = hr
        end)
    end

    spawner.streaming = true
    spawner.stream_frames = 0
    spawner.last_status = "Streaming Claire assets into memory... (Frame 0)"
end

-- =========================================================================
-- 6. Companion Locomotion Controller (Follows Leon Dynamically)
-- =========================================================================
local function update_companion_locomotion(delta_time)
    if not spawner.follow_enabled or not spawner.comp_body_obj then
        return
    end

    local player = spawner.get_master_player()
    local player_go = spawner.get_player_game_object(player)
    local player_tf = player_go and player_go:call("get_Transform")
    if not player_tf then return end

    local body_tf = nil
    pcall(function() body_tf = spawner.comp_body_obj:call("get_Transform") end)
    if not body_tf then return end

    local leon_pos = nil
    pcall(function() leon_pos = player_tf:call("get_Position") end)
    local comp_pos = nil
    pcall(function() comp_pos = body_tf:call("get_Position") end)
    if not leon_pos or not comp_pos then return end

    local leon_yaw = get_yaw_from_transform(player_tf)
    local anchor_pos = get_companion_anchor_point(player_tf)
    if not anchor_pos then return end

    -- Distance calculations
    local dx_anchor = anchor_pos.x - comp_pos.x
    local dz_anchor = anchor_pos.z - comp_pos.z
    local dist_anchor = math.sqrt(dx_anchor * dx_anchor + dz_anchor * dz_anchor)

    local dx_leon = leon_pos.x - comp_pos.x
    local dz_leon = leon_pos.z - comp_pos.z
    local dist_leon = math.sqrt(dx_leon * dx_leon + dz_leon * dz_leon)
    spawner.dist_to_leon = dist_leon

    -- Case A: Catch-up Teleport if Leon moved very far (elevator, door warp, sprint)
    if dist_leon > TELEPORT_DIST then
        pcall(function()
            local teleport_pos = (Vector3f and Vector3f.new and Vector3f.new(anchor_pos.x, anchor_pos.y, anchor_pos.z)) or anchor_pos
            body_tf:call("set_Position", teleport_pos)
            spawner.current_speed = 0.0
            spawner.loco_status = "Catch-up Teleported"
            log_debug("Catch-up teleport executed (Leon > 22m away).")
        end)
        return
    end

    -- Case B: Determine Target Speed & Direction
    local target_speed = 0.0
    local target_yaw = spawner.comp_yaw

    if dist_anchor < STOP_DIST or dist_leon < (FOLLOW_REAR_DIST * 0.7) then
        -- Within comfort zone: Claire idles and turns to face Leon's heading
        target_speed = 0.0
        target_yaw = leon_yaw
        spawner.loco_status = "Idle (Alongside Leon)"
    elseif dist_anchor >= RUN_THRESHOLD then
        -- Far behind: Claire runs to catch up
        target_speed = RUN_SPEED
        target_yaw = math.atan(dx_anchor, dz_anchor)
        spawner.loco_status = string.format("Running to Catch Up (%.1fm)", dist_anchor)
    else
        -- Moderate distance: Claire walks naturally
        target_speed = WALK_SPEED
        target_yaw = math.atan(dx_anchor, dz_anchor)
        spawner.loco_status = string.format("Walking with Leon (%.1fm)", dist_anchor)
    end

    -- Smooth acceleration / deceleration
    local accel = math.min(1.0, ACCEL_SPEED * delta_time)
    spawner.current_speed = lerp(spawner.current_speed, target_speed, accel)

    -- Smooth yaw rotation
    local rot_speed = math.min(1.0, ROTATE_SPEED * delta_time)
    spawner.comp_yaw = lerp_angle(spawner.comp_yaw, target_yaw, rot_speed)

    -- Apply new rotation
    pcall(function()
        local half_yaw = spawner.comp_yaw * 0.5
        local qy = math.sin(half_yaw)
        local qw = math.cos(half_yaw)
        local rot = (Quaternion and Quaternion.new and Quaternion.new(0, qy, 0, qw)) or { x = 0, y = qy, z = 0, w = qw }
        body_tf:call("set_Rotation", rot)
    end)

    -- Physical translation if moving
    if spawner.current_speed > 0.05 then
        local move_dist = spawner.current_speed * delta_time
        local dir_len = math.sqrt(dx_anchor * dx_anchor + dz_anchor * dz_anchor)
        if dir_len > 0.001 then
            local nx = dx_anchor / dir_len
            local nz = dz_anchor / dir_len

            local new_x = comp_pos.x + nx * move_dist
            local new_z = comp_pos.z + nz * move_dist
            local new_y = lerp(comp_pos.y, anchor_pos.y, math.min(1.0, 10.0 * delta_time))

            pcall(function()
                local new_vpos = (Vector3f and Vector3f.new and Vector3f.new(new_x, new_y, new_z)) or { x = new_x, y = new_y, z = new_z }
                body_tf:call("set_Position", new_vpos)
            end)
        end
    end

    -- Drive motion animation if available
    pcall(function()
        local motion = spawner.comp_body_obj:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion"))
        if motion then
            local play_spd = spawner.current_speed > 0.1 and 1.0 or 0.0
            pcall(function() motion:call("set_PlaySpeed", play_spd) end)
        end
    end)
end

-- =========================================================================
-- 7. Master Frame Loop (re.on_frame)
-- =========================================================================
re.on_frame(function()
    -- Calculate precise delta time
    local now = os.clock()
    local dt = spawner.last_time and (now - spawner.last_time) or 0.0166
    spawner.last_time = now
    if dt <= 0.0 or dt > 0.1 then dt = 0.0166 end

    -- A. Asynchronous Spawning Pipeline
    if spawner.streaming and spawner.body_pfb then
        spawner.stream_frames = spawner.stream_frames + 1

        local player = spawner.get_master_player()
        local player_go = spawner.get_player_game_object(player)
        local player_tf = player_go and player_go:call("get_Transform")
        local front_pos = player_tf and get_front_spawn_position(player_tf, 2.0) or { x = 0, y = 0, z = 0 }
        local vpos = (Vector3f and Vector3f.new and Vector3f.new(front_pos.x, front_pos.y, front_pos.z)) or front_pos

        local body_obj = nil
        local ok_b = pcall(function()
            body_obj = spawner.body_pfb:call("instantiate(via.vec3)", vpos)
        end)

        if ok_b and body_obj then
            pcall(function() body_obj:add_ref() end)
            local b_tf = nil
            pcall(function() b_tf = body_obj:call("get_Transform") end)
            if b_tf then
                pcall(function() b_tf:call("set_Position", front_pos) end)
            end
            pcall(function()
                body_obj:call("set_DrawSelf", true)
                body_obj:call("set_UpdateSelf", true)
            end)
            table.insert(spawner.spawned_entities, body_obj)
            spawner.comp_body_obj = body_obj
            spawner.comp_yaw = player_tf and get_yaw_from_transform(player_tf) or 0.0
            log_debug(string.format("Body instantiated at frame %d at (%.2f, %.2f, %.2f)", spawner.stream_frames, front_pos.x, front_pos.y, front_pos.z))

            -- Dump components for diagnostic inspection
            pcall(function()
                local ccount = body_obj:call("get_ComponentCount") or 0
                log_debug(string.format("Spawned body component count: %d", ccount))
                for i = 0, math.min(ccount - 1, 15) do
                    local comp = body_obj:call("getComponent(System.Int32)", i)
                    local td = comp and comp:get_type_definition()
                    log_debug(string.format("  [Comp %d] %s", i, td and td:get_full_name() or "nil"))
                end
            end)

            -- If Full mode, instantiate and attach Head & Hair
            if spawner.mode == "full" then
                if spawner.head_pfb then
                    local head_obj = nil
                    pcall(function() head_obj = spawner.head_pfb:call("instantiate(via.vec3)", vpos) end)
                    if head_obj then
                        pcall(function() head_obj:add_ref() end)
                        pcall(function()
                            local h_tf = head_obj:call("get_Transform")
                            if h_tf and b_tf then
                                h_tf:call("set_Parent", b_tf)
                            end
                            head_obj:call("set_DrawSelf", true)
                            head_obj:call("set_UpdateSelf", true)
                        end)
                        table.insert(spawner.spawned_entities, head_obj)
                        log_debug("Head instantiated and attached to Body.")
                    end
                end

                if spawner.hair_pfb then
                    local hair_obj = nil
                    pcall(function() hair_obj = spawner.hair_pfb:call("instantiate(via.vec3)", vpos) end)
                    if hair_obj then
                        pcall(function() hair_obj:add_ref() end)
                        pcall(function()
                            local hr_tf = hair_obj:call("get_Transform")
                            if hr_tf and b_tf then
                                hr_tf:call("set_Parent", b_tf)
                            end
                            hair_obj:call("set_DrawSelf", true)
                            hair_obj:call("set_UpdateSelf", true)
                        end)
                        table.insert(spawner.spawned_entities, hair_obj)
                        log_debug("Hair instantiated and attached to Body.")
                    end
                end
            end

            local total_parts = #spawner.spawned_entities
            if total_parts >= 3 then
                spawner.last_status = "SUCCESS: CLAIRE FULLY RENDERED & FOLLOW ACTIVE!"
            else
                spawner.last_status = "SUCCESS: CLAIRE BODY RENDERED & FOLLOW ACTIVE!"
            end
            log_debug(string.format("Spawn completed! Total parts: %d", total_parts))

            spawner.streaming = false
            spawner.body_pfb = nil
            spawner.head_pfb = nil
            spawner.hair_pfb = nil
        else
            spawner.last_status = string.format("Streaming assets... (Frame %d/300)", spawner.stream_frames)
            if spawner.stream_frames > 300 then
                spawner.streaming = false
                spawner.body_pfb = nil
                spawner.head_pfb = nil
                spawner.hair_pfb = nil
                spawner.last_status = "Streaming timed out at frame 300"
                log_debug("Streaming timed out at frame 300.")
            end
        end
    end

    -- B. Active Companion Locomotion Update
    if spawner.comp_body_obj then
        pcall(function()
            update_companion_locomotion(dt)
        end)
    end
end)

-- Initial scan on script load
pcall(spawner.scan_all_candidates)

-- =========================================================================
-- 8. Clean, Minimalist ImGui Spawner UI
-- =========================================================================
local function draw_spawner_ui(suffix)
    suffix = suffix or ""
    imgui.text_colored("=== RE2 DUO MODE: COMPANION CONTROLLER ===", 0.3, 0.9, 1.0, 1.0)
    imgui.text("Status: " .. tostring(spawner.last_status))
    
    if spawner.comp_body_obj then
        imgui.text_colored("Companion: ACTIVE (Claire Redfield)", 0.2, 1.0, 0.4, 1.0)
        imgui.text("Locomotion: " .. tostring(spawner.loco_status))
        imgui.text(string.format("Distance to Leon: %.2f m | Speed: %.1f m/s", spawner.dist_to_leon, spawner.current_speed))
    else
        imgui.text_colored("Companion: NOT SPAWNED", 1.0, 0.6, 0.2, 1.0)
    end
    imgui.separator()

    local player = spawner.get_master_player()
    if player then
        imgui.text_colored("Player (Leon): ACTIVE IN SCENE", 0.2, 1.0, 0.4, 1.0)
        imgui.spacing()

        if imgui.button(">>> SPAWN CLAIRE REDFIELD (Full Character) <<<##btn_full" .. suffix) then
            spawner.click_count = spawner.click_count + 1
            log_debug("UI BUTTON CLICKED: Full Character Spawn")
            spawner.start_spawn("full")
        end

        imgui.spacing()
        local follow_label = spawner.follow_enabled and "Follow Leon: [ON]##toggle_loco" .. suffix or "Follow Leon: [OFF]##toggle_loco" .. suffix
        if imgui.button(follow_label) then
            spawner.follow_enabled = not spawner.follow_enabled
            log_debug("Follow toggled: " .. tostring(spawner.follow_enabled))
        end

        imgui.same_line()
        if imgui.button("Despawn Claire##btn_desp" .. suffix) then
            log_debug("UI BUTTON CLICKED: Despawn")
            pcall(spawner.execute_despawn)
        end
    else
        imgui.text_colored("Waiting for game scene / Leon to load...", 1.0, 0.8, 0.2, 1.0)
        imgui.text("Please load your game save or start a new game first.")
    end
end

-- Dedicated Standalone Floating Window
re.on_frame(function()
    pcall(function()
        if imgui.begin_window("Claire Redfield Companion (Duo Mode)", true, 0) then
            draw_spawner_ui("##win")
            imgui.end_window()
        end
    end)
end)

-- REFramework Menu entry
re.on_draw_ui(function()
    draw_spawner_ui("##menu")
end)
