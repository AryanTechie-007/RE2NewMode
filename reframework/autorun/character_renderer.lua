--[[
    Resident Evil 2: Duo Mode — Claire Redfield Spawner & Companion Locomotion
    Script: character_renderer.lua
    Purpose: Single unified script that renders Claire Redfield in 3D and provides smooth gliding companion locomotion.
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
spawner.follow_enabled = false
spawner.current_speed = 0.0
spawner.comp_yaw = 0.0
spawner.dist_to_leon = 0.0
spawner.loco_status = "Stationary in Viewport (Follow is OFF)"
spawner.last_time = nil
spawner.follow_distance = 1.4 -- 1.4m behind Leon
spawner.follow_flank = -0.7    -- 0.7m to Leon's left flank (companion over-the-shoulder view)

-- Follow Tuning Parameters
local STOP_DIST     = 0.35 -- Arrival tolerance at target waypoint
local WALK_SPEED    = 2.2  -- Walking gliding speed (m/s)
local RUN_SPEED     = 4.5  -- Catch-up speed (m/s)
local RUN_THRESHOLD = 2.6  -- Distance from target that triggers catch-up speed
local TELEPORT_DIST = 25.0 -- Snap if separated by cutscene or elevator

local rotation_initialized = false
local rotation_method = nil

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
-- 2. Helper Math & Safe Transform Utilities
-- =========================================================================
local function lerp(a, b, t)
    if not a or not b or a ~= a or b ~= b then return b or 0.0 end
    return a + (b - a) * math.max(0.0, math.min(1.0, t))
end

local function lerp_angle(from_rad, to_rad, t)
    if not from_rad or not to_rad or from_rad ~= from_rad or to_rad ~= to_rad then return to_rad or 0.0 end
    local diff = to_rad - from_rad
    while diff > math.pi do diff = diff - 2.0 * math.pi end
    while diff < -math.pi do diff = diff + 2.0 * math.pi end
    return from_rad + diff * math.max(0.0, math.min(1.0, t))
end

local function distance_2d(p1, p2)
    if not p1 or not p2 or not p1.x or not p2.x or not p1.z or not p2.z then return 0.0 end
    local dx = p1.x - p2.x
    local dz = p1.z - p2.z
    local d = math.sqrt(dx * dx + dz * dz)
    if d ~= d then return 0.0 end
    return d
end

local function get_yaw_from_transform(tf)
    if not tf or not tf.call then return 0.0 end
    local ok1, euler = pcall(function() return tf:call("get_EulerAngles") end)
    if ok1 and euler and euler.y and euler.y == euler.y then return euler.y end

    local ok2, euler2 = pcall(function() return tf:call("get_EulerAngle") end)
    if ok2 and euler2 and euler2.y and euler2.y == euler2.y then return euler2.y end

    local ok3, rot = pcall(function() return tf:call("get_Rotation") end)
    if ok3 and rot then
        local x = rot.x or 0.0
        local y = rot.y or 0.0
        local z = rot.z or 0.0
        local w = rot.w or 1.0
        local siny_cosp = 2.0 * (w * y + x * z)
        local cosy_cosp = 1.0 - 2.0 * (y * y + z * z)
        local y_val = math.atan(siny_cosp, cosy_cosp)
        if y_val == y_val then return y_val end
    end
    return 0.0
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

-- Safely translates transform without invalid marshalling or matrix corruption
local function move_transform_safely(tf, game_obj, x, y, z)
    if not x or not y or not z then return end
    if x ~= x or y ~= y or z ~= z then return end -- Guard against IEEE 754 NaN

    local v3 = (Vector3f and Vector3f.new and Vector3f.new(x, y, z))

    -- Primary: via.Transform ManagedObject:set_Position(Vector3f)
    if tf and v3 then
        local ok1 = pcall(function() tf:call("set_Position", v3) end)
        if not ok1 then
            pcall(function() tf:call("set_Position(via.vec3)", v3) end)
        end
    end

    -- Secondary: RETransform:set_position(Vector4f) if game_obj exposes get_transform
    if game_obj and game_obj.get_transform and Vector4f and Vector4f.new then
        pcall(function()
            local retf = game_obj:get_transform()
            if retf and retf.set_position then
                retf:set_position(Vector4f.new(x, y, z, 1.0))
            end
        end)
    end
end

-- Safely sets rotation without passing Lua tables to IL2CPP
local function rotate_transform_safely(tf, game_obj, yaw_rad)
    if not yaw_rad or yaw_rad ~= yaw_rad then return end -- Guard against NaN

    -- 1. Try RETransform:set_rotation via REFramework Quaternion
    if game_obj and game_obj.get_transform and Quaternion then
        local ok1 = pcall(function()
            local retf = game_obj:get_transform()
            if retf and retf.set_rotation then
                local half = yaw_rad * 0.5
                local qy = math.sin(half)
                local qw = math.cos(half)
                if qy == qy and qw == qw then
                    local q = nil
                    pcall(function() q = Quaternion.new(0, qy, 0, qw) end)
                    if not q and Vector3f and Vector3f.new then
                        pcall(function() q = Quaternion.new(Vector3f.new(0, yaw_rad, 0)) end)
                    end
                    if q then
                        retf:set_rotation(q)
                        if not rotation_initialized then
                            rotation_initialized = true
                            rotation_method = "RETransform:set_rotation(Quaternion)"
                            log_debug("Rotation mechanism: " .. rotation_method)
                        end
                        return true
                    end
                end
            end
            return false
        end)
        if ok1 then return end
    end

    -- 2. Try via.Transform EulerAngle / EulerAngles setters
    if tf and Vector3f and Vector3f.new then
        local ok2 = pcall(function()
            local euler = Vector3f.new(0, yaw_rad, 0)
            tf:call("set_EulerAngles", euler)
            if not rotation_initialized then
                rotation_initialized = true
                rotation_method = "via.Transform:set_EulerAngles"
                log_debug("Rotation mechanism: " .. rotation_method)
            end
        end)
        if ok2 then return end

        pcall(function()
            local euler = Vector3f.new(0, yaw_rad, 0)
            tf:call("set_EulerAngle", euler)
            if not rotation_initialized then
                rotation_initialized = true
                rotation_method = "via.Transform:set_EulerAngle"
                log_debug("Rotation mechanism: " .. rotation_method)
            end
        end)
    end
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
    spawner.follow_enabled = false
    spawner.current_speed = 0.0
    spawner.dist_to_leon = 0.0
    spawner.loco_status = "Stationary in Viewport (Follow is OFF)"
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

    -- NaN Auto-Recovery: if comp_pos became corrupted from a previous bug, recover cleanly
    if comp_pos.x ~= comp_pos.x or comp_pos.y ~= comp_pos.y or comp_pos.z ~= comp_pos.z then
        log_debug("WARNING: comp_pos was NaN. Auto-recovering Claire in front of Leon.")
        local fp = get_front_spawn_position(player_tf, 2.0)
        move_transform_safely(body_tf, body_obj, fp.x, fp.y, fp.z)
        spawner.dist_to_leon = 2.0
        return
    end
    if leon_pos.x ~= leon_pos.x or leon_pos.y ~= leon_pos.y or leon_pos.z ~= leon_pos.z then
        return
    end

    local leon_yaw = get_yaw_from_transform(player_tf)
    local dist_leon = distance_2d(leon_pos, comp_pos)
    spawner.dist_to_leon = dist_leon

    -- Compute companion target waypoint:
    -- follow_distance behind Leon, and follow_flank along Leon's side (over-the-shoulder view)
    local follow_dist = spawner.follow_distance or 1.4
    local flank_offset = spawner.follow_flank or -0.7

    local fwd_x = math.sin(leon_yaw)
    local fwd_z = math.cos(leon_yaw)
    local right_x = math.cos(leon_yaw)
    local right_z = -math.sin(leon_yaw)

    local target_x = leon_pos.x - fwd_x * follow_dist + right_x * flank_offset
    local target_z = leon_pos.z - fwd_z * follow_dist + right_z * flank_offset
    local target_y = leon_pos.y

    local dx = target_x - comp_pos.x
    local dz = target_z - comp_pos.z
    local dist_target = math.sqrt(dx * dx + dz * dz)
    if dist_target ~= dist_target then dist_target = 0.0 end

    -- Catch-up teleport if Leon runs far ahead (e.g. cutscene / elevator)
    if dist_leon > TELEPORT_DIST then
        move_transform_safely(body_tf, body_obj, target_x, target_y, target_z)
        spawner.current_speed = 0.0
        spawner.comp_yaw = leon_yaw
        rotate_transform_safely(body_tf, body_obj, spawner.comp_yaw)
        spawner.loco_status = "Catch-up Teleported"
        return
    end

    local target_speed = 0.0
    local target_yaw = spawner.comp_yaw

    if dist_target < STOP_DIST or dist_leon < 1.0 then
        target_speed = 0.0
        target_yaw = leon_yaw -- Face forward with Leon when idle
        spawner.loco_status = string.format("Idle Alongside Leon (%.2fm)", dist_leon)
    elseif dist_target >= RUN_THRESHOLD then
        target_speed = RUN_SPEED
        target_yaw = math.atan(dx, dz) -- Face gliding direction
        spawner.loco_status = string.format("Gliding to Catch Up (%.2fm)", dist_leon)
    else
        target_speed = WALK_SPEED
        target_yaw = math.atan(dx, dz) -- Face gliding direction
        spawner.loco_status = string.format("Gliding with Leon (%.2fm)", dist_leon)
    end

    spawner.current_speed = lerp(spawner.current_speed, target_speed, math.min(1.0, 5.0 * delta_time))
    spawner.comp_yaw = lerp_angle(spawner.comp_yaw, target_yaw, math.min(1.0, 6.0 * delta_time))

    -- Safe Rotation
    rotate_transform_safely(body_tf, body_obj, spawner.comp_yaw)

    -- Smooth Gliding Translation
    if spawner.current_speed > 0.05 and dist_target > 0.05 then
        local move_dist = spawner.current_speed * delta_time
        if move_dist > dist_target then move_dist = dist_target end -- Prevent overshooting

        local nx = dx / (dist_target > 0.001 and dist_target or 1.0)
        local nz = dz / (dist_target > 0.001 and dist_target or 1.0)

        local new_x = comp_pos.x + nx * move_dist
        local new_z = comp_pos.z + nz * move_dist
        local new_y = lerp(comp_pos.y, target_y, math.min(1.0, 8.0 * delta_time))

        if new_x == new_x and new_y == new_y and new_z == new_z then
            move_transform_safely(body_tf, body_obj, new_x, new_y, new_z)
        end
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

            -- Set initial facing direction to face Leon directly
            if player_tf and b_tf then
                local leon_yaw = get_yaw_from_transform(player_tf)
                spawner.comp_yaw = leon_yaw + math.pi
                rotate_transform_safely(b_tf, body_obj, spawner.comp_yaw)
            end

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
        if rotation_method then
            imgui.text_colored("Rotation Engine: " .. rotation_method, 0.6, 0.8, 1.0, 1.0)
        end
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
                    move_transform_safely(b_tf, body_obj, fp.x, fp.y, fp.z)
                    spawner.follow_enabled = false
                    spawner.comp_yaw = get_yaw_from_transform(player_tf) + math.pi
                    rotate_transform_safely(b_tf, body_obj, spawner.comp_yaw)
                    log_debug("Claire brought in front of Leon.")
                end
            end
        end

        imgui.spacing()
        imgui.text("Follow Positioning Options:")
        local flanks = { "Left Flank (-0.7m)", "Directly Behind (0.0m)", "Right Flank (+0.7m)" }
        local current_flank_idx = (spawner.follow_flank == 0.0 and 2) or (spawner.follow_flank > 0 and 3) or 1
        local changed_f, new_f_idx = imgui.combo("Position##flank" .. suffix, current_flank_idx, flanks)
        if changed_f then
            if new_f_idx == 1 then spawner.follow_flank = -0.7
            elseif new_f_idx == 2 then spawner.follow_flank = 0.0
            else spawner.follow_flank = 0.7 end
        end

        local changed_d, new_d = imgui.slider_float("Follow Distance##dist" .. suffix, spawner.follow_distance, 1.0, 3.5, "%.1f m")
        if changed_d then spawner.follow_distance = new_d end

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
