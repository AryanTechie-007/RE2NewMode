--[[
    Resident Evil 2: Duo Mode — Claire Redfield Spawner & Companion Locomotion
    Script: character_renderer.lua
    Purpose: Single unified script that spawns Claire in the 3D viewport and drives smooth companion gliding.
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

-- Locomotion Configuration & State (Single-Script Architecture)
spawner.follow_enabled = false -- Starts OFF so Claire stays right in front of Leon in full view!
spawner.current_speed = 0.0
spawner.comp_yaw = 0.0
spawner.dist_to_leon = 0.0
spawner.loco_status = "Stationary in Viewport (Follow is OFF)"
spawner.last_time = nil

-- Follow Tuning Parameters
local FOLLOW_DIST   = 1.6  -- Claire targets ~1.6m behind Leon
local STOP_DIST     = 1.1  -- Stops when close to Leon
local WALK_SPEED    = 2.0  -- Walking gliding speed (m/s)
local RUN_SPEED     = 4.2  -- Running catch-up speed (m/s)
local RUN_THRESHOLD = 3.2  -- Catch up when Leon is > 3.2m away
local TELEPORT_DIST = 20.0 -- Snap if separated by cutscene or elevator

local function log_debug(msg)
    pcall(function()
        local f = io.open("reframework/data/spawner_debug.txt", "a")
        if f then
            f:write(os.date("[%H:%M:%S] ") .. tostring(msg) .. "\n")
            f:close()
        end
    end)
    pcall(function()
        local f2 = io.open("spawner_debug.txt", "a")
        if f2 then
            f2:write(os.date("[%H:%M:%S] ") .. tostring(msg) .. "\n")
            f2:close()
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
-- 2. Helper Math & Rotation Utilities
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

local function get_front_spawn_position(player_tf, dist)
    dist = dist or 2.0 -- 2 meters directly IN FRONT of player
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

local function move_transform_safely(tf, x, y, z)
    if not tf then return end
    -- Method A: via.vec3 native invocation
    local ok1 = pcall(function()
        local v = sdk.create_instance("via.vec3")
        if v then
            v:call("set_x", x)
            v:call("set_y", y)
            v:call("set_z", z)
            tf:call("set_Position(via.vec3)", v)
        end
    end)
    if ok1 then return end

    -- Method B: Vector3f call
    pcall(function()
        local vpos = (Vector3f and Vector3f.new and Vector3f.new(x, y, z)) or { x = x, y = y, z = z }
        tf:call("set_Position", vpos)
    end)
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
    spawner.body_pfb = nil
    spawner.head_pfb = nil
    spawner.hair_pfb = nil
    spawner.streaming = false
    spawner.stream_frames = 0
    spawner.current_speed = 0.0
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

    -- Create Body Prefab
    pcall(function()
        local b = sdk.create_instance("via.Prefab"):add_ref()
        b:call("set_Path", body_path)
        b:call("set_Standby", true)
        spawner.body_pfb = b
    end)

    -- Create Head and Hair Prefabs if full mode
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
-- 6. Companion Locomotion Controller (Runs In-Script)
-- =========================================================================
local function update_companion_locomotion(delta_time)
    if not spawner.follow_enabled then
        spawner.loco_status = "Stationary in Viewport (Follow is OFF)"
        return
    end

    local body_obj = spawner.spawned_entities and spawner.spawned_entities[1]
    if not body_obj then return end

    local player = spawner.get_master_player()
    local player_go = spawner.get_player_game_object(player)
    local player_tf = player_go and player_go:call("get_Transform")
    local body_tf = nil
    pcall(function() body_tf = body_obj:call("get_Transform") end)
    if not player_tf or not body_tf then return end

    local leon_pos = nil
    pcall(function() leon_pos = player_tf:call("get_Position") end)
    local comp_pos = nil
    pcall(function() comp_pos = body_tf:call("get_Position") end)
    if not leon_pos or not comp_pos then return end

    local leon_yaw = get_yaw_from_transform(player_tf)
    local dist_leon = distance_2d(leon_pos, comp_pos)
    spawner.dist_to_leon = dist_leon

    -- Target: 1.6m behind Leon
    local target_x = leon_pos.x - math.sin(leon_yaw) * FOLLOW_DIST
    local target_z = leon_pos.z - math.cos(leon_yaw) * FOLLOW_DIST
    local target_y = leon_pos.y

    local dx = target_x - comp_pos.x
    local dz = target_z - comp_pos.z
    local dist_target = math.sqrt(dx * dx + dz * dz)

    -- Catch-up teleport if Leon runs far ahead
    if dist_leon > TELEPORT_DIST then
        move_transform_safely(body_tf, target_x, target_y, target_z)
        spawner.current_speed = 0.0
        spawner.loco_status = "Catch-up Teleported"
        return
    end

    local target_speed = 0.0
    local target_yaw = spawner.comp_yaw

    if dist_target < STOP_DIST or dist_leon < 1.2 then
        target_speed = 0.0
        target_yaw = leon_yaw
        spawner.loco_status = string.format("Idle Alongside Leon (%.2fm)", dist_leon)
    elseif dist_target >= RUN_THRESHOLD then
        target_speed = RUN_SPEED
        target_yaw = math.atan(dx, dz)
        spawner.loco_status = string.format("Gliding to Catch Up (%.2fm)", dist_leon)
    else
        target_speed = WALK_SPEED
        target_yaw = math.atan(dx, dz)
        spawner.loco_status = string.format("Gliding with Leon (%.2fm)", dist_leon)
    end

    spawner.current_speed = lerp(spawner.current_speed, target_speed, math.min(1.0, 5.0 * delta_time))
    spawner.comp_yaw = lerp_angle(spawner.comp_yaw, target_yaw, math.min(1.0, 6.0 * delta_time))

    -- Smooth facing rotation
    pcall(function()
        local half = spawner.comp_yaw * 0.5
        local qy = math.sin(half)
        local qw = math.cos(half)
        local rot = (Quaternion and Quaternion.new and Quaternion.new(0, qy, 0, qw)) or { x = 0, y = qy, z = 0, w = qw }
        body_tf:call("set_Rotation", rot)
    end)

    -- Smooth gliding translation
    if spawner.current_speed > 0.05 and dist_target > 0.1 then
        local move_dist = spawner.current_speed * delta_time
        local nx = dx / (dist_target > 0.001 and dist_target or 1.0)
        local nz = dz / (dist_target > 0.001 and dist_target or 1.0)

        local new_x = comp_pos.x + nx * move_dist
        local new_z = comp_pos.z + nz * move_dist
        local new_y = lerp(comp_pos.y, target_y, math.min(1.0, 8.0 * delta_time))

        move_transform_safely(body_tf, new_x, new_y, new_z)
    end
end

-- =========================================================================
-- 7. Master Frame Loop (re.on_frame)
-- =========================================================================
re.on_frame(function()
    local now = os.clock()
    local dt = spawner.last_time and (now - spawner.last_time) or 0.0166
    spawner.last_time = now
    if dt <= 0.0 or dt > 0.1 then dt = 0.0166 end

    -- A. Asset Streaming Pipeline
    if spawner.streaming and spawner.body_pfb then
        spawner.stream_frames = spawner.stream_frames + 1

        local player = spawner.get_master_player()
        local player_go = spawner.get_player_game_object(player)
        local player_tf = player_go and player_go:call("get_Transform")
        local front_pos = player_tf and get_front_spawn_position(player_tf, 2.0) or { x = 0, y = 0, z = 0 }
        local vpos = (Vector3f and Vector3f.new and Vector3f.new(front_pos.x, front_pos.y, front_pos.z)) or front_pos

        -- Attempt instantiation of Body on every frame
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
            log_debug(string.format("Body instantiated at frame %d at (%.2f, %.2f, %.2f)", spawner.stream_frames, front_pos.x, front_pos.y, front_pos.z))

            -- If Full mode, instantiate and attach Head & Hair
            if spawner.mode == "full" then
                -- Head
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
                    else
                        log_debug("Head instantiate returned nil at frame " .. tostring(spawner.stream_frames))
                    end
                end

                -- Hair
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
                    else
                        log_debug("Hair instantiate returned nil at frame " .. tostring(spawner.stream_frames))
                    end
                end
            end

            local total_parts = #spawner.spawned_entities
            if total_parts >= 3 then
                spawner.last_status = "SUCCESS: CLAIRE FULLY RENDERED (Body + Head + Hair)!"
            else
                spawner.last_status = "SUCCESS: CLAIRE RENDERED IN VIEWPORT!"
            end
            log_debug(string.format("Spawn completed! Total parts active: %d", total_parts))

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

    -- B. Active Locomotion (Only runs when Claire is spawned)
    if #spawner.spawned_entities > 0 then
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
    imgui.text_colored("=== RE2 DUO MODE: CLAIRE REDFIELD CONTROLLER ===", 0.3, 0.9, 1.0, 1.0)
    imgui.text("Status: " .. tostring(spawner.last_status))

    if #spawner.spawned_entities > 0 then
        imgui.text_colored("Claire: ACTIVE IN VIEWPORT (3D Model Rendered)", 0.2, 1.0, 0.4, 1.0)
        imgui.text("Locomotion: " .. tostring(spawner.loco_status))
        imgui.text(string.format("Distance to Leon: %.2f m | Speed: %.1f m/s", spawner.dist_to_leon, spawner.current_speed))
    else
        imgui.text_colored("Claire: NOT SPAWNED", 1.0, 0.6, 0.2, 1.0)
    end
    imgui.separator()

    local player = spawner.get_master_player()
    if player then
        imgui.text_colored("Player (Leon): ACTIVE IN SCENE", 0.2, 1.0, 0.4, 1.0)
        imgui.spacing()

        if imgui.button(">>> SPAWN CLAIRE IN FRONT OF LEON <<<##btn_full" .. suffix) then
            spawner.click_count = spawner.click_count + 1
            spawner.follow_enabled = false
            log_debug("UI BUTTON CLICKED: Full Character Spawn")
            spawner.start_spawn("full")
        end

        imgui.spacing()
        local follow_label = spawner.follow_enabled
            and "Follow Leon & Glide: [ON] (Click to Pause)##toggle_loco" .. suffix
            or  "Follow Leon & Glide: [OFF] (Click to Start Gliding)##toggle_loco" .. suffix

        if spawner.follow_enabled then
            imgui.push_style_color(21, 0.2, 0.7, 0.3, 1.0)
        end
        if imgui.button(follow_label) then
            spawner.follow_enabled = not spawner.follow_enabled
            log_debug("Follow toggled: " .. tostring(spawner.follow_enabled))
        end
        if spawner.follow_enabled then
            imgui.pop_style_color(1)
        end

        imgui.same_line()
        if imgui.button("Bring In Front of Me##snap_front" .. suffix) then
            local body_obj = spawner.spawned_entities and spawner.spawned_entities[1]
            local player_go = spawner.get_player_game_object()
            local player_tf = player_go and player_go:call("get_Transform")
            if body_obj and player_tf then
                local b_tf = body_obj:call("get_Transform")
                local fp = get_front_spawn_position(player_tf, 2.0)
                if b_tf and fp then
                    move_transform_safely(b_tf, fp.x, fp.y, fp.z)
                    spawner.follow_enabled = false
                    log_debug("Claire brought in front of Leon.")
                end
            end
        end

        imgui.spacing()
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
        if imgui.begin_window("Claire Redfield Controller (Duo Mode)", true, 0) then
            draw_spawner_ui("##win")
            imgui.end_window()
        end
    end)
end)

-- REFramework Menu entry
re.on_draw_ui(function()
    draw_spawner_ui("##menu")
end)
