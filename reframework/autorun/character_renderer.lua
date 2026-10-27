--[[
    Resident Evil 2: Duo Mode — Claire Redfield Spawner, Locomotion & Portal Defense
    Script: character_renderer.lua
    Phase 1 Complete:
      - Day 1: Full 3D Character Rendering (Body + Face + Hair)
      - Day 2: NaN-Safe Companion Locomotion & Gliding Follow
      - Day 3: Room Portal Culling Defense, Kinematic Elevator Parenting & Cutscene Protection
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

-- Locomotion Configuration & State (Day 2)
spawner.follow_enabled = false
spawner.current_speed = 0.0
spawner.comp_yaw = 0.0
spawner.dist_to_leon = 0.0
spawner.loco_status = "Stationary in Viewport (Follow is OFF)"
spawner.last_time = nil
spawner.follow_distance = 1.4 -- 1.4m behind Leon
spawner.follow_flank = -0.7    -- 0.7m to Leon's left flank (companion over-the-shoulder view)

-- Day 3: Portal Defense, Elevator Parenting & Cutscene States
spawner.current_leader_room = 0
spawner.last_leader_room = 0
spawner.portal_defense_active = true
spawner.is_on_elevator = false
spawner.elevator_transform = nil
spawner.cutscene_active = false
spawner.portal_teleports_count = 0

-- Day 4: Companion Command FSM & Tactical Radial Wheel
spawner.fsm_state = "FOLLOW" -- "FOLLOW", "WAIT", "COVER"
spawner.command_wheel_open = false
spawner.command_wheel_key = 0x54 -- 'T' Key (0x54) - Rebound from Middle Mouse to prevent camera reset conflict!
spawner.key_names = { "T (Tactical / Orders)", "G (Guard)", "Q (Quick Command)", "Caps Lock", "Mouse 4 (Thumb)", "Mouse 5 (Thumb)" }
spawner.key_codes = { 0x54, 0x47, 0x51, 0x14, 0x05, 0x06 }
spawner.key_names_lookup = { "T", "G", "Q", "Capital", "XButton1", "XButton2" }
spawner.selected_key_idx = 1
spawner.wheel_mode = "HOLD" -- "HOLD" or "TOGGLE"
spawner.wheel_modes = { "Hold Key (Release to Close)", "Toggle Key (Press to Open / Close)" }
spawner.selected_wheel_mode_idx = 1

-- Follow Tuning Parameters
local STOP_DIST     = 0.35 -- Arrival tolerance at target waypoint
local WALK_SPEED    = 2.2  -- Walking gliding speed (m/s)
local RUN_SPEED     = 4.5  -- Catch-up speed (m/s)
local RUN_THRESHOLD = 2.6  -- Distance from target that triggers catch-up speed
local RUBBER_BAND_DIST = 10.0 -- Rubber-band distance catch-up
local VERTICAL_DESYNC_DIST = 3.2 -- Vertical elevation desync catch-up (e.g. staircases/drops)

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
-- 3. Day 3: Room Portal, Cutscene & Elevator Helpers
-- =========================================================================

local room_probed = false

-- Probe and detect RE2's Room / Area system
local function probe_room_system(player_go)
    if room_probed then return end
    room_probed = true

    log_debug("=== Probing RE2 Room / Area Management Types ===")
    local candidate_types = {
        "app.ropeway.RoomArea",
        "app.ropeway.RoomManager",
        "app.ropeway.AreaManager",
        "app.ropeway.gamemaster.RoomManager",
        "app.ropeway.gamemaster.AreaManager",
        "app.ropeway.ScenarioManager",
        "app.ropeway.MapManager",
        "app.ropeway.StageManager"
    }

    for _, name in ipairs(candidate_types) do
        local td = sdk.find_type_definition(name)
        if td then
            log_debug("  [TYPE FOUND] " .. name)
            local sing = sdk.get_managed_singleton(name)
            if sing then
                log_debug("    [SINGLETON ACTIVE] " .. name)
                -- Dump methods on singleton
                pcall(function()
                    local methods = td:get_methods()
                    for _, m in ipairs(methods) do
                        local mname = m:get_name()
                        if string.find(string.lower(mname), "room") or string.find(string.lower(mname), "area") or string.find(string.lower(mname), "stage") then
                            log_debug("      Method: " .. mname)
                        end
                    end
                end)
            end
        end
    end

    if player_go and player_go.call then
        pcall(function()
            local p_fsm = player_go:call("getComponent(System.Type)", sdk.typeof("via.motion.MotionFsm2"))
            if p_fsm then
                log_debug("  Leon MotionFsm2 present.")
            end
            local p_mot = player_go:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion"))
            if p_mot then
                log_debug("  Leon via.motion.Motion present.")
            end
        end)
    end
end

-- Query current room/area ID from StayAreaController, RoomArea or Managers
local function get_room_id(game_obj)
    if not game_obj then return 0 end

    -- Strategy A: app.ropeway.StayAreaController (verified present on Leon)
    local r1 = 0
    pcall(function()
        local t = sdk.typeof("app.ropeway.StayAreaController")
        if t and game_obj.call then
            local comp = game_obj:call("getComponent(System.Type)", t)
            if comp then
                r1 = comp:call("get_CurrentAreaNo")
                   or comp:call("get_CurrentAreaID")
                   or comp:call("get_AreaNo")
                   or comp:call("get_AreaID") or 0
            end
        end
    end)
    if r1 and r1 ~= 0 then return r1 end

    -- Strategy B: via.GameObject RoomArea component
    local r2 = 0
    pcall(function()
        local t = sdk.typeof("app.ropeway.RoomArea")
        if t and game_obj.call then
            local comp = game_obj:call("getComponent(System.Type)", t)
            if comp then
                r2 = comp:call("get_CurrentRoomID") or 0
            end
        end
    end)
    if r2 and r2 ~= 0 then return r2 end

    -- Strategy B: app.ropeway.RoomManager singleton
    local r2 = 0
    pcall(function()
        local rm = sdk.get_managed_singleton("app.ropeway.RoomManager")
                or sdk.get_managed_singleton("app.ropeway.gamemaster.RoomManager")
        if rm then
            r2 = rm:call("get_CurrentRoomID")
               or rm:call("getCurrentRoomID")
               or rm:call("get_CurrentRoom")
               or rm:call("get_RoomID") or 0
        end
    end)
    if r2 and r2 ~= 0 then return r2 end

    -- Strategy C: app.ropeway.AreaManager singleton
    local r3 = 0
    pcall(function()
        local am = sdk.get_managed_singleton("app.ropeway.AreaManager")
        if am then
            r3 = am:call("get_CurrentAreaID")
               or am:call("getCurrentAreaID")
               or am:call("get_AreaID") or 0
        end
    end)
    if r3 and r3 ~= 0 then return r3 end

    return 0
end

-- Update environment and room telemetry on every frame
local function update_environment_telemetry()
    local player = spawner.get_master_player()
    local player_go = spawner.get_player_game_object(player)
    if player_go then
        probe_room_system(player_go)
        local rid = get_room_id(player_go)
        if rid and rid ~= 0 then
            spawner.current_leader_room = rid
        end
    end
end

-- Query active cutscene status from CutsceneManager
local function check_cutscenes()
    local is_playing = false
    pcall(function()
        local cutscene_man = sdk.get_managed_singleton("app.ropeway.cutscene.CutsceneManager")
        if cutscene_man then
            is_playing = cutscene_man:call("isCutscenePlaying") or false
        end
    end)

    if is_playing and not spawner.cutscene_active then
        spawner.cutscene_active = true
        log_debug("Cutscene detected: hiding Claire meshes to protect timeline.")
        for _, ent in ipairs(spawner.spawned_entities) do
            pcall(function() ent:call("set_DrawSelf", false) end)
        end
        spawner.loco_status = "In Cutscene (Hidden)"
    elseif not is_playing and spawner.cutscene_active then
        spawner.cutscene_active = false
        log_debug("Cutscene ended: restoring Claire meshes and catching up.")
        for _, ent in ipairs(spawner.spawned_entities) do
            pcall(function() ent:call("set_DrawSelf", true) end)
        end
        -- Auto-catch up Claire to Leon in post-cutscene area
        local player = spawner.get_master_player()
        local player_go = spawner.get_player_game_object(player)
        local player_tf = player_go and player_go:call("get_Transform")
        local body_obj = spawner.spawned_entities and spawner.spawned_entities[1]
        local body_tf = body_obj and body_obj:call("get_Transform")
        if player_tf and body_tf then
            local ppos = player_tf:call("get_Position")
            local pyaw = get_yaw_from_transform(player_tf)
            local target_x = ppos.x - math.sin(pyaw) * (spawner.follow_distance or 1.4)
            local target_z = ppos.z - math.cos(pyaw) * (spawner.follow_distance or 1.4)
            move_transform_safely(body_tf, body_obj, target_x, ppos.y, target_z)
            rotate_transform_safely(body_tf, body_obj, pyaw)
        end
        spawner.loco_status = "Resumed Post-Cutscene"
    end

    return is_playing
end

-- Manage Kinematic Elevator / Platform Parenting
local function update_elevator_parenting(player_tf, body_tf)
    if not player_tf or not body_tf then return end

    local player_parent = nil
    pcall(function() player_parent = player_tf:call("get_Parent") end)

    if player_parent and not spawner.is_on_elevator then
        -- Leon stepped onto a moving elevator or tram! Parent Claire to the same platform
        local ok = pcall(function()
            body_tf:call("set_Parent", player_parent)
        end)
        if ok then
            spawner.is_on_elevator = true
            spawner.elevator_transform = player_parent
            log_debug("Elevator entered: Claire parented to kinematic platform.")
        end
    elseif not player_parent and spawner.is_on_elevator then
        -- Leon stepped off the elevator! Restore root scene parenting
        pcall(function()
            body_tf:call("set_Parent", nil)
        end)
        spawner.is_on_elevator = false
        spawner.elevator_transform = nil
        log_debug("Elevator exited: Claire unparented from platform.")
    end
end

-- =========================================================================
-- 4. Player Resolution
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
-- 5. Despawn Logic
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
    spawner.spawned_body = nil
    spawner.spawned_head = nil
    spawner.spawned_hair = nil
    spawner.body_pfb = nil
    spawner.head_pfb = nil
    spawner.hair_pfb = nil
    spawner.streaming = false
    spawner.stream_frames = 0
    spawner.follow_enabled = false
    spawner.current_speed = 0.0
    spawner.dist_to_leon = 0.0
    spawner.is_on_elevator = false
    spawner.elevator_transform = nil
    spawner.fsm_state = "FOLLOW"
    if spawner.command_wheel_open then
        spawner.command_wheel_open = false
        pcall(function()
            local time_man = sdk.get_managed_singleton("app.ropeway.TimeManager")
            if time_man then time_man:call("setTimeScale", 1.0) end
        end)
    end
    spawner.cutscene_active = false
    spawner.loco_status = "Stationary in Viewport (Follow is OFF)"
    spawner.last_status = "Despawned - Standing by"
    log_debug("Despawn executed cleanly.")
end

-- =========================================================================
-- 6. Initiate Spawner Pipeline
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
-- 7. Companion Locomotion Controller (Runs In-Script)
-- =========================================================================

local function update_companion_locomotion(delta_time)
    if not spawner.follow_enabled then
        spawner.loco_status = "Stationary in Viewport (Follow is OFF)"
        return
    end

    local body_obj = spawner.spawned_entities and spawner.spawned_entities[1]
    if not body_obj then return end

    -- Day 3: Cutscene Protection
    if check_cutscenes() then
        return
    end

    local player = spawner.get_master_player()
    local player_go = spawner.get_player_game_object(player)
    local player_tf = player_go and player_go:call("get_Transform")
    local body_tf = nil
    pcall(function() body_tf = body_obj:call("get_Transform") end)
    if not player_tf or not body_tf then return end

    -- Day 3: Kinematic Elevator / Platform Parenting
    update_elevator_parenting(player_tf, body_tf)

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

    -- =========================================================================
    -- Day 4 FSM: HOLD POSITION / WAIT ORDER
    -- =========================================================================
    if spawner.fsm_state == "WAIT" then
        spawner.current_speed = 0.0
        spawner.loco_status = string.format("Holding Position / Stay Order (%.2fm from Leon)", dist_leon)
        -- Emergency fallback: if Leon runs over 28m away, snap to prevent falling into unloaded chunks
        if dist_leon > 28.0 then
            local fallback_x = leon_pos.x - math.sin(leon_yaw) * 2.0
            local fallback_z = leon_pos.z - math.cos(leon_yaw) * 2.0
            move_transform_safely(body_tf, body_obj, fallback_x, leon_pos.y, fallback_z)
            rotate_transform_safely(body_tf, body_obj, leon_yaw)
            spawner.loco_status = "Emergency Catch-up from Stay"
        end
        return
    end

    -- Compute companion target waypoint:
    -- follow_distance behind Leon, and follow_flank along Leon's side (over-the-shoulder view)
    local follow_dist = spawner.follow_distance or 1.4
    local flank_offset = spawner.follow_flank or -0.7

    -- Day 4 FSM: Tighter tether in COVER state
    if spawner.fsm_state == "COVER" then
        follow_dist = 0.95
        flank_offset = -0.5
    end

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

    -- =========================================================================
    -- Day 3: Room Portal Culling Defense
    -- =========================================================================
    local leader_room = get_room_id(player_go)
    if leader_room ~= 0 then
        spawner.current_leader_room = leader_room
        if spawner.last_leader_room ~= 0 and spawner.last_leader_room ~= leader_room then
            -- Leon transitioned into a new room!
            -- If Claire is separated across the room boundary, instantly catch her up!
            if dist_leon > 2.2 then
                spawner.portal_teleports_count = spawner.portal_teleports_count + 1
                log_debug(string.format("Portal Catch-Up triggered: Room %d -> %d (Dist: %.2fm)", spawner.last_leader_room, leader_room, dist_leon))
                move_transform_safely(body_tf, body_obj, target_x, target_y, target_z)
                spawner.current_speed = 0.0
                spawner.comp_yaw = leon_yaw
                rotate_transform_safely(body_tf, body_obj, spawner.comp_yaw)
                spawner.loco_status = string.format("Portal Catch-Up (Room %d)", leader_room)
                spawner.last_leader_room = leader_room
                return
            end
        end
        spawner.last_leader_room = leader_room
    end

    -- =========================================================================
    -- Day 3: Rubber-Band & Elevation Desync Catch-up
    -- =========================================================================
    local dy = math.abs(leon_pos.y - comp_pos.y)
    if (dist_leon > RUBBER_BAND_DIST or dy > VERTICAL_DESYNC_DIST) and not spawner.is_on_elevator then
        spawner.portal_teleports_count = spawner.portal_teleports_count + 1
        log_debug(string.format("Rubber-Band catch-up: dist=%.1fm, dy=%.1fm. Snapping behind Leon.", dist_leon, dy))
        move_transform_safely(body_tf, body_obj, target_x, target_y, target_z)
        spawner.current_speed = 0.0
        spawner.comp_yaw = leon_yaw
        rotate_transform_safely(body_tf, body_obj, spawner.comp_yaw)
        spawner.loco_status = "Elevation/Distance Catch-up"
        return
    end

    local target_speed = 0.0
    local target_yaw = spawner.comp_yaw

    if dist_target < STOP_DIST or dist_leon < 1.0 then
        target_speed = 0.0
        if spawner.fsm_state == "COVER" then
            target_yaw = leon_yaw + math.pi * 0.7 -- Orient outward to guard rear flank
            spawner.loco_status = string.format("In Cover / Guarding Flank (%.2fm)", dist_leon)
        else
            target_yaw = leon_yaw -- Face forward with Leon when idle
            spawner.loco_status = string.format("Idle Alongside Leon (%.2fm)", dist_leon)
        end
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
-- Day 4: Multi-Layer Native HID & REFramework Input Engine
-- =========================================================================

local input = {
    initialized = false,
    kb_device = nil,
    gp_device = nil,
    kb_keys = {},        -- string name -> int data
    gp_buttons = {},     -- string name -> int data
    last_detected_key = "None",
    last_order_issued = "None",
    wheel_trigger_down = false,
    prev_wheel_trigger = false,
}

local function init_input_engine()
    if input.initialized then
        -- Fast re-verify device pointers if nil
        if not input.kb_device then
            pcall(function()
                local kb_singleton = sdk.get_native_singleton("via.hid.Keyboard")
                local kb_type = sdk.find_type_definition("via.hid.Keyboard")
                if kb_singleton and kb_type then
                    input.kb_device = sdk.call_native_func(kb_singleton, kb_type, "get_Device")
                end
            end)
        end
        if not input.gp_device then
            pcall(function()
                local gp_singleton = sdk.get_native_singleton("via.hid.GamePad")
                local gp_type = sdk.find_type_definition("via.hid.GamePad")
                if gp_singleton and gp_type then
                    input.gp_device = sdk.call_native_func(gp_singleton, gp_type, "getMergedDevice", 0)
                        or sdk.call_native_func(gp_singleton, gp_type, "get_MergedDevice")
                        or sdk.call_native_func(gp_singleton, gp_type, "get_Device")
                end
            end)
        end
        return
    end

    input.initialized = true
    pcall(function()
        -- 1. Native Keyboard Singleton & Key Enums
        local kb_singleton = sdk.get_native_singleton("via.hid.Keyboard")
        local kb_type = sdk.find_type_definition("via.hid.Keyboard")
        local kb_key_type = sdk.find_type_definition("via.hid.KeyboardKey")

        if kb_singleton and kb_type then
            input.kb_device = sdk.call_native_func(kb_singleton, kb_type, "get_Device")
        end

        if kb_key_type then
            for _, field in ipairs(kb_key_type:get_fields()) do
                if field:is_static() then
                    input.kb_keys[field:get_name()] = field:get_data(nil)
                end
            end
        end

        -- 2. Native Gamepad Singleton & Button Enums
        local gp_singleton = sdk.get_native_singleton("via.hid.GamePad")
        local gp_type = sdk.find_type_definition("via.hid.GamePad")
        local gp_btn_type = sdk.find_type_definition("via.hid.GamePadButton")

        if gp_singleton and gp_type then
            input.gp_device = sdk.call_native_func(gp_singleton, gp_type, "getMergedDevice", 0)
                or sdk.call_native_func(gp_singleton, gp_type, "get_MergedDevice")
                or sdk.call_native_func(gp_singleton, gp_type, "get_Device")
        end

        if gp_btn_type then
            for _, field in ipairs(gp_btn_type:get_fields()) do
                if field:is_static() then
                    input.gp_buttons[field:get_name()] = field:get_data(nil)
                end
            end
        end

        local kb_cnt = 0; for _ in pairs(input.kb_keys) do kb_cnt = kb_cnt + 1 end
        local gp_cnt = 0; for _ in pairs(input.gp_buttons) do gp_cnt = gp_cnt + 1 end
        log_debug(string.format("Input Engine initialized. KB keys cached: %d | GP buttons cached: %d", kb_cnt, gp_cnt))
    end)
end

local function is_key_down(key_name, vk_code)
    -- Layer 1: Native RE Engine via.hid.Keyboard (Hardware poll directly in engine tick)
    if input.kb_device and key_name and input.kb_keys[key_name] ~= nil then
        local down = false
        pcall(function()
            down = input.kb_device:call("isDown", input.kb_keys[key_name])
        end)
        if down then return true end
    end

    -- Layer 2: REFramework colon method (uses Win32 Virtual Key code)
    if reframework and reframework.is_key_down and vk_code then
        local down = false
        pcall(function()
            down = reframework:is_key_down(vk_code)
        end)
        if down then return true end
    end

    -- Layer 3: REFramework get_keyboard_state array check
    if reframework and reframework.get_keyboard_state and vk_code then
        local down = false
        pcall(function()
            local kb_state = reframework:get_keyboard_state() or reframework.get_keyboard_state()
            if kb_state and kb_state[vk_code] and kb_state[vk_code] ~= 0 then
                down = true
            end
        end)
        if down then return true end
    end

    return false
end

local function is_gamepad_down(btn_name)
    if input.gp_device and btn_name and input.gp_buttons[btn_name] ~= nil then
        local down = false
        pcall(function()
            down = input.gp_device:call("isDown", input.gp_buttons[btn_name])
        end)
        if down then return true end
    end
    return false
end

local function check_wheel_trigger()
    local name = spawner.key_names_lookup[spawner.selected_key_idx] or "T"
    local vk = spawner.key_codes[spawner.selected_key_idx] or 0x54

    local kb_down = is_key_down(name, vk)
    -- Fallback key names for special keys
    if not kb_down and name == "Capital" then
        kb_down = is_key_down("CapsLock", vk)
    end

    -- Check Gamepad triggers (RB / RShoulder / RTrig)
    local gp_down = is_gamepad_down("RShoulder") 
        or is_gamepad_down("RB") 
        or is_gamepad_down("RTrig")

    return kb_down or gp_down
end

local function open_command_wheel()
    if spawner.command_wheel_open then return end
    spawner.command_wheel_open = true
    pcall(function()
        local time_man = sdk.get_managed_singleton("app.ropeway.TimeManager")
        if time_man then time_man:call("setTimeScale", 0.4) end
    end)
    log_debug("Tactical Command Wheel opened. Timescale set to 0.4x.")
end

local function close_command_wheel()
    if not spawner.command_wheel_open then return end
    spawner.command_wheel_open = false
    pcall(function()
        local time_man = sdk.get_managed_singleton("app.ropeway.TimeManager")
        if time_man then time_man:call("setTimeScale", 1.0) end
    end)
    log_debug("Tactical Command Wheel closed. Timescale restored to 1.0x.")
end

local function update_command_wheel_input()
    init_input_engine()

    local is_trigger_down = check_wheel_trigger()
    input.wheel_trigger_down = is_trigger_down

    -- Global key detection monitor for live UI feedback
    pcall(function()
        if reframework and reframework.get_first_key_down then
            local k = reframework:get_first_key_down()
            if k then
                input.last_detected_key = string.format("0x%02X (%d)", k, k)
            end
        end
    end)

    if spawner.wheel_mode == "HOLD" then
        if is_trigger_down and not spawner.command_wheel_open then
            open_command_wheel()
        elseif not is_trigger_down and spawner.command_wheel_open then
            close_command_wheel()
        end
    else -- "TOGGLE" mode
        -- On rising edge (just pressed)
        if is_trigger_down and not input.prev_wheel_trigger then
            if spawner.command_wheel_open then
                close_command_wheel()
            else
                open_command_wheel()
            end
        end
    end
    input.prev_wheel_trigger = is_trigger_down

    -- Check order selection hotkeys while wheel is open
    if spawner.command_wheel_open then
        -- 1. FOLLOW ME
        local press_1 = is_key_down("D1", 0x31) 
            or is_key_down("Alpha1", 0x31) 
            or is_key_down("Num1", 0x31) 
            or is_key_down("One", 0x31)
            or is_key_down("NumPad1", 0x61) 
            or is_gamepad_down("LUp") 
            or is_gamepad_down("Up")
        if press_1 then
            spawner.fsm_state = "FOLLOW"
            spawner.follow_enabled = true
            input.last_order_issued = "FOLLOW ME [1]"
            log_debug("Order selected via hotkey: FOLLOW ME")
            if spawner.wheel_mode == "TOGGLE" then close_command_wheel() end
        end

        -- 2. HOLD POSITION (STAY)
        local press_2 = is_key_down("D2", 0x32) 
            or is_key_down("Alpha2", 0x32) 
            or is_key_down("Num2", 0x32) 
            or is_key_down("Two", 0x32)
            or is_key_down("NumPad2", 0x62) 
            or is_gamepad_down("LLeft") 
            or is_gamepad_down("LRight") 
            or is_gamepad_down("Left")
            or is_gamepad_down("Right")
        if press_2 then
            spawner.fsm_state = "WAIT"
            input.last_order_issued = "HOLD POSITION [2]"
            log_debug("Order selected via hotkey: HOLD POSITION (STAY)")
            if spawner.wheel_mode == "TOGGLE" then close_command_wheel() end
        end

        -- 3. TAKE COVER
        local press_3 = is_key_down("D3", 0x33) 
            or is_key_down("Alpha3", 0x33) 
            or is_key_down("Num3", 0x33) 
            or is_key_down("Three", 0x33)
            or is_key_down("NumPad3", 0x63) 
            or is_gamepad_down("LDown") 
            or is_gamepad_down("Down")
        if press_3 then
            spawner.fsm_state = "COVER"
            spawner.follow_enabled = true
            input.last_order_issued = "TAKE COVER [3]"
            log_debug("Order selected via hotkey: TAKE COVER")
            if spawner.wheel_mode == "TOGGLE" then close_command_wheel() end
        end
    end
end

local function draw_command_wheel()
    if not spawner.command_wheel_open then return end

    local display_size = (imgui and imgui.get_display_size and imgui.get_display_size()) or (Vector2f and Vector2f.new and Vector2f.new(1920, 1080)) or { x = 1920, y = 1080 }
    local center = (Vector2f and Vector2f.new and Vector2f.new(display_size.x * 0.5, display_size.y * 0.5)) or { x = display_size.x * 0.5, y = display_size.y * 0.5 }

    pcall(function()
        if imgui.set_next_window_pos then
            local pivot = (Vector2f and Vector2f.new and Vector2f.new(0.5, 0.5)) or { x = 0.5, y = 0.5 }
            imgui.set_next_window_pos(center, 1, pivot)
        end
    end)
    pcall(function()
        if imgui.set_next_window_size then
            local wsize = (Vector2f and Vector2f.new and Vector2f.new(380, 270)) or { x = 380, y = 270 }
            imgui.set_next_window_size(wsize, 1)
        end
    end)

    local opened = false
    pcall(function()
        opened = imgui.begin_window("Tactical Orders##wheel", true, 1 | 2 | 4 | 32)
    end)

    if opened then
        imgui.text_colored("=== TACTICAL COMMAND WHEEL ===", 0.3, 0.9, 1.0, 1.0)
        imgui.text_colored("Timescale: 0.4x (Bullet-Time Slowdown Active)", 1.0, 0.8, 0.2, 1.0)
        imgui.separator()
        imgui.spacing()

        -- Option 1: FOLLOW
        local is_follow = (spawner.fsm_state == "FOLLOW")
        if is_follow then
            imgui.text_colored(">>> [ACTIVE] [1] FOLLOW ME <<<", 0.2, 1.0, 0.4, 1.0)
        else
            imgui.text("    [1] FOLLOW ME")
        end
        local btn_w = (Vector2f and Vector2f.new and Vector2f.new(340, 32)) or { x = 340, y = 32 }
        if imgui.button("Select [1]: Follow Me##btn_follow", btn_w) then
            spawner.fsm_state = "FOLLOW"
            spawner.follow_enabled = true
            input.last_order_issued = "FOLLOW ME [UI]"
            close_command_wheel()
        end
        imgui.spacing()

        -- Option 2: HOLD POSITION (STAY)
        local is_wait = (spawner.fsm_state == "WAIT")
        if is_wait then
            imgui.text_colored(">>> [ACTIVE] [2] HOLD POSITION (STAY) <<<", 1.0, 0.8, 0.2, 1.0)
        else
            imgui.text("    [2] HOLD POSITION (STAY)")
        end
        if imgui.button("Select [2]: Hold Position##btn_wait", btn_w) then
            spawner.fsm_state = "WAIT"
            input.last_order_issued = "HOLD POSITION [UI]"
            close_command_wheel()
        end
        imgui.spacing()

        -- Option 3: TAKE COVER
        local is_cover = (spawner.fsm_state == "COVER")
        if is_cover then
            imgui.text_colored(">>> [ACTIVE] [3] TAKE COVER / DEFEND <<<", 0.4, 0.8, 1.0, 1.0)
        else
            imgui.text("    [3] TAKE COVER / DEFEND")
        end
        if imgui.button("Select [3]: Take Cover##btn_cover", btn_w) then
            spawner.fsm_state = "COVER"
            spawner.follow_enabled = true
            input.last_order_issued = "TAKE COVER [UI]"
            close_command_wheel()
        end

        imgui.separator()
        local prompt_str = (spawner.wheel_mode == "HOLD") 
            and "Press [1], [2], [3] or click order. Release hotkey to resume."
            or  "Press [1], [2], [3] or click order to confirm (or tap hotkey to close)."
        imgui.text_colored(prompt_str, 0.7, 0.7, 0.7, 1.0)
        imgui.end_window()
    end
end

-- =========================================================================
-- 8. Master Frame Loop (re.on_frame)
-- =========================================================================
re.on_frame(function()
    local now = os.clock()
    local dt = spawner.last_time and (now - spawner.last_time) or 0.0166
    spawner.last_time = now
    if dt <= 0.0 or dt > 0.1 then dt = 0.0166 end

    -- Day 4: Tactical Command Wheel Input
    pcall(update_command_wheel_input)

    -- A. Asset Streaming Pipeline
    if spawner.streaming and spawner.body_pfb then
        spawner.stream_frames = spawner.stream_frames + 1

        local player = spawner.get_master_player()
        local player_go = spawner.get_player_game_object(player)
        local player_tf = player_go and player_go:call("get_Transform")
        local front_pos = player_tf and get_front_spawn_position(player_tf, 2.0) or { x = 0, y = 0, z = 0 }
        local vpos = (Vector3f and Vector3f.new and Vector3f.new(front_pos.x, front_pos.y, front_pos.z)) or front_pos

        -- 1. Instantiate Body if not yet done
        if not spawner.spawned_body and spawner.body_pfb then
            local body_obj = nil
            pcall(function() body_obj = spawner.body_pfb:call("instantiate(via.vec3)", vpos) end)
            if body_obj then
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
                spawner.spawned_body = body_obj
                log_debug(string.format("Body instantiated at frame %d at (%.2f, %.2f, %.2f)", spawner.stream_frames, front_pos.x, front_pos.y, front_pos.z))

                -- Set initial facing direction to face Leon directly
                if player_tf and b_tf then
                    local leon_yaw = get_yaw_from_transform(player_tf)
                    spawner.comp_yaw = leon_yaw + math.pi
                    rotate_transform_safely(b_tf, body_obj, spawner.comp_yaw)
                end
            end
        end

        local b_obj = spawner.spawned_body
        local b_tf = b_obj and b_obj:call("get_Transform")

        -- 2. Instantiate Head if not yet done
        if b_obj and not spawner.spawned_head and spawner.head_pfb then
            local head_obj = nil
            pcall(function() head_obj = spawner.head_pfb:call("instantiate(via.vec3)", vpos) end)
            if head_obj then
                pcall(function() head_obj:add_ref() end)
                pcall(function()
                    local h_tf = head_obj:call("get_Transform")
                    if h_tf and b_tf then h_tf:call("set_Parent", b_tf) end
                    head_obj:call("set_DrawSelf", true)
                    head_obj:call("set_UpdateSelf", true)
                end)
                table.insert(spawner.spawned_entities, head_obj)
                spawner.spawned_head = head_obj
                log_debug(string.format("Head instantiated and attached to Body at frame %d.", spawner.stream_frames))
            end
        end

        -- 3. Instantiate Hair if not yet done (retries across frames so hair is never missed!)
        if b_obj and not spawner.spawned_hair and spawner.hair_pfb then
            local hair_obj = nil
            pcall(function() hair_obj = spawner.hair_pfb:call("instantiate(via.vec3)", vpos) end)
            if hair_obj then
                pcall(function() hair_obj:add_ref() end)
                pcall(function()
                    local hr_tf = hair_obj:call("get_Transform")
                    if hr_tf and b_tf then hr_tf:call("set_Parent", b_tf) end
                    hair_obj:call("set_DrawSelf", true)
                    hair_obj:call("set_UpdateSelf", true)
                end)
                table.insert(spawner.spawned_entities, hair_obj)
                spawner.spawned_hair = hair_obj
                log_debug(string.format("Hair instantiated and attached to Body at frame %d.", spawner.stream_frames))
            end
        end

        -- 4. Check completion
        local all_done = spawner.spawned_body and (spawner.mode ~= "full" or (spawner.spawned_head and spawner.spawned_hair))
        if all_done then
            spawner.last_status = "SUCCESS: CLAIRE FULLY RENDERED (Body + Head + Hair)!"
            log_debug(string.format("Spawn completed! Total parts active: %d", #spawner.spawned_entities))
            spawner.streaming = false
            spawner.body_pfb = nil
            spawner.head_pfb = nil
            spawner.hair_pfb = nil
        else
            spawner.last_status = string.format("Streaming assets... (Frame %d/300, active parts %d/3)", spawner.stream_frames, #spawner.spawned_entities)
            if spawner.stream_frames > 300 then
                spawner.streaming = false
                spawner.body_pfb = nil
                spawner.head_pfb = nil
                spawner.hair_pfb = nil
                spawner.last_status = "Streaming timed out. Active parts: " .. tostring(#spawner.spawned_entities)
                log_debug(spawner.last_status)
            end
        end
    end

    -- B. Environment & Room Telemetry (Runs continuously every frame)
    pcall(update_environment_telemetry)

    -- C. Active Locomotion (Only runs when Claire is spawned)
    if #spawner.spawned_entities > 0 then
        pcall(function()
            update_companion_locomotion(dt)
        end)
    end
end)

-- Initial scan on script load
pcall(spawner.scan_all_candidates)

-- =========================================================================
-- 9. Clean, Minimalist ImGui Spawner UI (Day 1 - 3 Dashboard)
-- =========================================================================
local function draw_spawner_ui(suffix)
    suffix = suffix or ""
    imgui.text_colored("=== RE2 DUO MODE: CLAIRE REDFIELD CONTROLLER ===", 0.3, 0.9, 1.0, 1.0)
    imgui.text("Status: " .. tostring(spawner.last_status))

    if #spawner.spawned_entities > 0 then
        imgui.text_colored("Claire: ACTIVE IN VIEWPORT (3D Model Rendered)", 0.2, 1.0, 0.4, 1.0)
        imgui.text("Locomotion: " .. tostring(spawner.loco_status))
        imgui.text(string.format("Distance to Leon: %.2f m | Speed: %.1f m/s", spawner.dist_to_leon, spawner.current_speed))

        -- Day 3 Status Indicators
        imgui.spacing()
        imgui.text_colored("--- Day 3: Portal & Environment Defense ---", 1.0, 0.8, 0.2, 1.0)
        local room_str = spawner.current_leader_room ~= 0 and string.format("Room ID: %d", spawner.current_leader_room) or "Room ID: Querying..."
        imgui.text(room_str .. " | Portal Snaps: " .. tostring(spawner.portal_teleports_count))

        if spawner.is_on_elevator then
            imgui.text_colored("Elevator Platform: KINEMATIC LINKED [Active]", 0.2, 1.0, 0.4, 1.0)
        else
            imgui.text("Elevator Platform: Ground Level")
        end

        if spawner.cutscene_active then
            imgui.text_colored("Cinematic Status: IN CUTSCENE (Actor Hidden)", 1.0, 0.4, 0.2, 1.0)
        else
            imgui.text("Cinematic Status: Gameplay Active")
        end

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

        -- =====================================================================
        -- Day 4: Companion Tactical Orders (FSM Dashboard)
        -- =====================================================================
        imgui.spacing()
        imgui.separator()
        imgui.text_colored("--- Day 4: Tactical Orders & FSM Dashboard ---", 1.0, 0.8, 0.2, 1.0)

        -- State display with color coding
        if spawner.fsm_state == "FOLLOW" then
            imgui.text_colored("Current Order: [FOLLOW ME] (Standard Flank Tether)", 0.2, 1.0, 0.4, 1.0)
        elseif spawner.fsm_state == "WAIT" then
            imgui.text_colored("Current Order: [HOLD POSITION / STAY] (Anchored in place)", 1.0, 0.8, 0.2, 1.0)
        elseif spawner.fsm_state == "COVER" then
            imgui.text_colored("Current Order: [TAKE COVER] (Tight 0.95m Tether / Guard Flank)", 0.4, 0.8, 1.0, 1.0)
        end

        if imgui.button("Order: Follow Me##btn_fsm_follow" .. suffix) then
            spawner.fsm_state = "FOLLOW"
            spawner.follow_enabled = true
            log_debug("FSM State changed to FOLLOW via UI")
        end
        imgui.same_line()
        if imgui.button("Order: Hold Position (Stay)##btn_fsm_wait" .. suffix) then
            spawner.fsm_state = "WAIT"
            log_debug("FSM State changed to WAIT via UI")
        end
        imgui.same_line()
        if imgui.button("Order: Take Cover##btn_fsm_cover" .. suffix) then
            spawner.fsm_state = "COVER"
            spawner.follow_enabled = true
            log_debug("FSM State changed to COVER via UI")
        end

        imgui.spacing()
        imgui.text("Command Wheel Trigger Behavior:")
        local changed_m, new_m = imgui.combo("Trigger Mode##wheel_mode" .. suffix, spawner.selected_wheel_mode_idx, spawner.wheel_modes)
        if changed_m then
            spawner.selected_wheel_mode_idx = new_m
            spawner.wheel_mode = (new_m == 1 and "HOLD") or "TOGGLE"
            log_debug("Wheel trigger mode changed to: " .. spawner.wheel_mode)
        end

        imgui.text("Command Wheel Hotkey (Bullet-Time 0.4x Slowdown):")
        local changed_k, new_k = imgui.combo("Wheel Hotkey##wheel_key" .. suffix, spawner.selected_key_idx, spawner.key_names)
        if changed_k then
            spawner.selected_key_idx = new_k
            spawner.command_wheel_key = spawner.key_codes[new_k]
            log_debug(string.format("Command wheel hotkey changed to: %s (0x%X)", spawner.key_names[new_k], spawner.command_wheel_key))
        end

        -- Live Hardware Input Diagnostics
        imgui.spacing()
        imgui.text_colored("--- Live Input & Hardware Diagnostics ---", 0.4, 0.8, 1.0, 1.0)
        local trig_status = input.wheel_trigger_down and "ACTIVE (HELD)" or "IDLE"
        if input.wheel_trigger_down then
            imgui.text_colored("Trigger Status: ACTIVE (HELD)", 0.2, 1.0, 0.4, 1.0)
        else
            imgui.text("Trigger Status: IDLE")
        end
        imgui.text("Last Key Detected: " .. tostring(input.last_detected_key))
        imgui.text("Last Order Executed: " .. tostring(input.last_order_issued))
        if input.kb_device then
            imgui.text_colored("Native Keyboard Hardware Hook: CONNECTED", 0.2, 1.0, 0.4, 1.0)
        else
            imgui.text_colored("Native Keyboard Hardware Hook: Connecting...", 1.0, 0.8, 0.2, 1.0)
        end
        if input.gp_device then
            imgui.text_colored("Native Gamepad Hardware Hook: CONNECTED", 0.2, 1.0, 0.4, 1.0)
        end

        if imgui.button(spawner.command_wheel_open and "Close Tactical Wheel##test_wheel" .. suffix or "Open Tactical Wheel (Test Slowdown)##test_wheel" .. suffix) then
            if spawner.command_wheel_open then
                close_command_wheel()
            else
                open_command_wheel()
            end
        end
        imgui.separator()

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

-- Dedicated Standalone Floating Window & Command Wheel Overlay
re.on_frame(function()
    pcall(function()
        if imgui.begin_window("Claire Redfield Controller (Duo Mode)", true, 0) then
            draw_spawner_ui("##win")
            imgui.end_window()
        end
    end)
    pcall(draw_command_wheel)
end)

-- REFramework Menu entry
re.on_draw_ui(function()
    draw_spawner_ui("##menu")
end)

-- Reset hook to ensure normal timescale on script reset
re.on_script_reset(function()
    pcall(function()
        local time_man = sdk.get_managed_singleton("app.ropeway.TimeManager")
        if time_man then time_man:call("setTimeScale", 1.0) end
    end)
end)
