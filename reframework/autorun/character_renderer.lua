--[[
    Resident Evil 2: Duo Mode — Claire Redfield Spawner & Multi-Part Assembler
    Script: character_renderer.lua
    Purpose: Dedicated harness to assemble and render Claire Redfield (Body, Head/Face, Hair) into the 3D viewport.
    Author: AryanTechie-007
]]

local spawner = {}
spawner.spawned_entities = {}
spawner.last_status = "Ready - Standing by"
spawner.pending_action = nil

-- Multi-part streaming state
spawner.streaming = false
spawner.stream_frames = 0
spawner.stream_body = nil
spawner.stream_head = nil
spawner.stream_hair = nil
spawner.target_costume = 0

-- Resolved part paths
spawner.resolved_body = "objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_0.pfb"
spawner.resolved_head = nil
spawner.resolved_hair = nil

local REPORT_FILE = "reframework/autorun/claire_assembly_report.txt"

local function log_msg(str)
    if log and log.info then
        log.info("[Spawner] " .. tostring(str))
    end
end

-- =========================================================================
-- 1. Candidate Prefab Paths (RE Engine Taxonomy)
-- =========================================================================
local HEAD_CANDIDATES = {
    -- pl1050: RE2 Remake standard identifier for Claire's Head/Face
    "objectroot/prefab/character/survivor/parts/pl1050/pl1050_head_costume_0.pfb",
    "objectroot/prefab/character/survivor/parts/pl1050/pl1050_face_costume_0.pfb",
    "objectroot/prefab/character/survivor/parts/pl1050/pl1050_head.pfb",
    "objectroot/prefab/character/survivor/parts/pl1050/pl1050_face.pfb",
    "objectroot/prefab/character/survivor/parts/pl1050/pl1050.pfb",
    "objectroot/prefab/character/survivor/parts/pl1050/pl1050_costume_0.pfb",
    "objectroot/prefab/character/survivor/parts/pl1050/pl1050_head_costume_a.pfb",
    "objectroot/prefab/character/survivor/parts/pl1050/pl1050_face_costume_a.pfb",
    "objectroot/prefab/character/survivor/parts/pl1050/pl1050_costume_a.pfb",
    "objectroot/prefab/character/survivor/parts/pl1050/pl1050_head_costume_1.pfb",
    "objectroot/prefab/character/survivor/parts/pl1050/pl1050_face_costume_1.pfb",
    "objectroot/prefab/character/survivor/pl1050.pfb",

    -- pl1000: alternate placement in main character parts directory
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_head_costume_0.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_face_costume_0.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_head.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_face.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_head_costume_a.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_face_costume_a.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_head_costume_1.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_face_costume_1.pfb"
}

local HAIR_CANDIDATES = {
    -- pl1070: RE2 Remake standard identifier for Claire's Hair
    "objectroot/prefab/character/survivor/parts/pl1070/pl1070_hair_costume_0.pfb",
    "objectroot/prefab/character/survivor/parts/pl1070/pl1070_hair_costume_a.pfb",
    "objectroot/prefab/character/survivor/parts/pl1070/pl1070_hair.pfb",
    "objectroot/prefab/character/survivor/parts/pl1070/pl1070.pfb",
    "objectroot/prefab/character/survivor/parts/pl1070/pl1070_costume_0.pfb",
    "objectroot/prefab/character/survivor/parts/pl1070/pl1070_costume_a.pfb",
    "objectroot/prefab/character/survivor/parts/pl1070/pl1070_hair_costume_1.pfb",
    "objectroot/prefab/character/survivor/pl1070.pfb",

    -- pl1000: alternate placement in main character parts directory
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_hair_costume_0.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_hair_costume_a.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_hair.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_hair_costume_1.pfb"
}

local LEON_CANDIDATES = {
    "objectroot/prefab/character/survivor/parts/pl0000/pl0000_body_costume_0.pfb",
    "objectroot/prefab/character/survivor/parts/pl0000/pl0000_head_costume_0.pfb",
    "objectroot/prefab/character/survivor/parts/pl0000/pl0000_face_costume_0.pfb",
    "objectroot/prefab/character/survivor/parts/pl0000/pl0000_hair_costume_0.pfb",
    "objectroot/prefab/character/survivor/parts/pl0050/pl0050_head_costume_0.pfb",
    "objectroot/prefab/character/survivor/parts/pl0050/pl0050_face_costume_0.pfb",
    "objectroot/prefab/character/survivor/parts/pl0050/pl0050_head.pfb",
    "objectroot/prefab/character/survivor/parts/pl0050/pl0050_face.pfb",
    "objectroot/prefab/character/survivor/parts/pl0050/pl0050.pfb",
    "objectroot/prefab/character/survivor/parts/pl0070/pl0070_hair_costume_0.pfb",
    "objectroot/prefab/character/survivor/parts/pl0070/pl0070_hair_costume_a.pfb",
    "objectroot/prefab/character/survivor/parts/pl0070/pl0070_hair.pfb",
    "objectroot/prefab/character/survivor/parts/pl0070/pl0070.pfb"
}

-- =========================================================================
-- 2. Helper: Transform & Math Utilities
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

local function get_front_spawn_position(player_tf, dist)
    dist = dist or 2.0 -- 2 meters directly IN FRONT of player
    local pos = player_tf:call("get_Position")
    local yaw = get_yaw_from_transform(player_tf)
    local fx = pos.x + math.sin(yaw) * dist
    local fy = pos.y
    local fz = pos.z + math.cos(yaw) * dist
    return (Vector3f and Vector3f.new and Vector3f.new(fx, fy, fz)) or { x = fx, y = fy, z = fz }
end

-- =========================================================================
-- 3. Player Resolution
-- =========================================================================
function spawner.get_master_player()
    local player_man = sdk.get_managed_singleton("app.ropeway.PlayerManager")
                    or sdk.get_managed_singleton(sdk.game_namespace("PlayerManager"))
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
-- 4. Deep Inspection & Archive Scan Engine
-- =========================================================================
function spawner.scan_archives_and_inspect()
    local report = {}
    table.insert(report, "=======================================================")
    table.insert(report, "RE2 DUO MODE: CLAIRE REDFIELD ASSET SCAN & REPORT")
    table.insert(report, "Generated at: " .. os.date())
    table.insert(report, "=======================================================\n")

    -- SECTION A: Check Claire Head Candidates
    table.insert(report, "--- [1] SCANNING CLAIRE HEAD / FACE PREFABS ---")
    local found_head = nil
    for _, path in ipairs(HEAD_CANDIDATES) do
        local pfb = nil
        pcall(function()
            pfb = sdk.create_instance("via.Prefab"):add_ref()
            pfb:call("set_Path", path)
        end)
        local exists = false
        if pfb then pcall(function() exists = pfb:call("get_Exist") end) end
        if exists == true then
            table.insert(report, "  [EXISTS: TRUE]  " .. path)
            if not found_head then found_head = path end
        else
            table.insert(report, "  [EXISTS: FALSE] " .. path)
        end
    end

    -- SECTION B: Check Claire Hair Candidates
    table.insert(report, "\n--- [2] SCANNING CLAIRE HAIR PREFABS ---")
    local found_hair = nil
    for _, path in ipairs(HAIR_CANDIDATES) do
        local pfb = nil
        pcall(function()
            pfb = sdk.create_instance("via.Prefab"):add_ref()
            pfb:call("set_Path", path)
        end)
        local exists = false
        if pfb then pcall(function() exists = pfb:call("get_Exist") end) end
        if exists == true then
            table.insert(report, "  [EXISTS: TRUE]  " .. path)
            if not found_hair then found_hair = path end
        else
            table.insert(report, "  [EXISTS: FALSE] " .. path)
        end
    end

    -- SECTION C: Check Leon Baseline
    table.insert(report, "\n--- [3] SCANNING LEON BASELINE PREFABS ---")
    for _, path in ipairs(LEON_CANDIDATES) do
        local pfb = nil
        pcall(function()
            pfb = sdk.create_instance("via.Prefab"):add_ref()
            pfb:call("set_Path", path)
        end)
        local exists = false
        if pfb then pcall(function() exists = pfb:call("get_Exist") end) end
        if exists == true then
            table.insert(report, "  [EXISTS: TRUE]  " .. path)
        else
            table.insert(report, "  [EXISTS: FALSE] " .. path)
        end
    end

    -- SECTION D: Inspect Leon Hierarchy in Scene
    table.insert(report, "\n--- [4] ACTIVE SCENE: LEON GAMEOBJECT HIERARCHY ---")
    local player = spawner.get_master_player()
    local pgo = spawner.get_player_game_object(player)
    if pgo then
        local pname = "unknown"
        pcall(function() pname = pgo:call("get_Name") end)
        table.insert(report, "Player GameObject Name: " .. tostring(pname))
        
        -- Components on player
        local ccount = 0
        pcall(function() ccount = pgo:call("get_ComponentCount") or 0 end)
        table.insert(report, "Player Component Count: " .. tostring(ccount))
        for i = 0, math.min(ccount - 1, 30) do
            pcall(function()
                local comp = pgo:call("getComponent(System.Int32)", i)
                local td = comp and comp:get_type_definition()
                table.insert(report, string.format("  Comp [%d]: %s", i, td and td:get_full_name() or "nil"))
            end)
        end

        -- Child Transforms
        local tf = nil
        pcall(function() tf = pgo:call("get_Transform") end)
        if tf then
            local child_count = 0
            pcall(function() child_count = tf:call("get_ChildCount") or 0 end)
            table.insert(report, "Player Child Count: " .. tostring(child_count))
            for i = 0, math.min(child_count - 1, 20) do
                pcall(function()
                    local ch_tf = tf:call("get_Child(System.Int32)", i) or tf:call("get_Child", i)
                    if ch_tf then
                        local ch_go = ch_tf:call("get_GameObject")
                        local ch_name = ch_go and ch_go:call("get_Name") or "unnamed"
                        local pjoint = nil
                        pcall(function() pjoint = ch_tf:call("get_ParentJoint") end)
                        local pj_name = pjoint and pjoint.call and pjoint:call("get_Name") or "none"
                        table.insert(report, string.format("  Child [%d]: name='%s', parent_joint='%s'", i, tostring(ch_name), tostring(pj_name)))
                    end
                end)
            end
        end
    else
        table.insert(report, "Leon GameObject not currently active in scene.")
    end

    table.insert(report, "\n=======================================================")
    table.insert(report, "ASSET SCAN COMPLETE")
    table.insert(report, "Resolved Head: " .. tostring(found_head or "NOT FOUND IN ARCHIVES"))
    table.insert(report, "Resolved Hair: " .. tostring(found_hair or "NOT FOUND IN ARCHIVES"))
    table.insert(report, "=======================================================")

    -- Cache resolved paths
    spawner.resolved_head = found_head
    spawner.resolved_hair = found_hair

    -- Write to disk report file
    local report_text = table.concat(report, "\n")
    pcall(function()
        local f = io.open(REPORT_FILE, "w")
        if f then
            f:write(report_text .. "\n")
            f:close()
        end
    end)

    log_msg("Asset scan completed. Best Head: " .. tostring(found_head) .. ", Best Hair: " .. tostring(found_hair))
    return report_text
end

-- =========================================================================
-- 5. Multi-Part Child Attachment
-- =========================================================================
local function attach_child_part(child_go, body_go)
    if not child_go or not body_go then return end
    pcall(function()
        local body_tf = body_go:call("get_Transform")
        local child_tf = child_go:call("get_Transform")
        if body_tf and child_tf then
            child_tf:call("set_Parent", body_tf)

            -- Align local origin
            local zero_vec = (Vector3f and Vector3f.new and Vector3f.new(0, 0, 0)) or { x = 0, y = 0, z = 0 }
            pcall(function() child_tf:call("set_LocalPosition", zero_vec) end)

            local identity_rot = (Quaternion and Quaternion.new and Quaternion.new(0, 0, 0, 1)) or { x = 0, y = 0, z = 0, w = 1 }
            pcall(function() child_tf:call("set_LocalRotation", identity_rot) end)
        end
    end)
    pcall(function()
        child_go:call("set_DrawSelf", true)
        child_go:call("set_UpdateSelf", true)
    end)
end

-- =========================================================================
-- 6. Despawn Logic
-- =========================================================================
function spawner.execute_despawn()
    local scene_man = sdk.get_native_singleton("via.SceneManager")
    local cur_scene = scene_man and scene_man:call("get_CurrentScene")

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
    spawner.spawned_entities = {}
    spawner.streaming = false
    spawner.stream_body = nil
    spawner.stream_head = nil
    spawner.stream_hair = nil
    spawner.last_status = "Despawned"
    log_msg("All Claire entities despawned cleanly.")
end

-- =========================================================================
-- 7. Multi-Part Claire Spawning Pipeline
-- =========================================================================
function spawner.spawn_claire(costume_index)
    costume_index = costume_index or 0
    spawner.execute_despawn()
    spawner.target_costume = costume_index

    -- Run asset scan if not already done
    if not spawner.resolved_head or not spawner.resolved_hair then
        spawner.scan_archives_and_inspect()
    end

    local body_path = string.format("objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_%d.pfb", costume_index)
    local head_path = spawner.resolved_head or "objectroot/prefab/character/survivor/parts/pl1050/pl1050_head_costume_0.pfb"
    local hair_path = spawner.resolved_hair or "objectroot/prefab/character/survivor/parts/pl1070/pl1070_hair_costume_0.pfb"

    log_msg("Initiating multi-part streaming:")
    log_msg("  Body: " .. body_path)
    log_msg("  Head: " .. tostring(head_path))
    log_msg("  Hair: " .. tostring(hair_path))

    -- Stream Body
    local b_pfb = sdk.create_instance("via.Prefab"):add_ref()
    b_pfb:call("set_Path", body_path)
    b_pfb:call("set_Standby", true)
    spawner.stream_body = b_pfb

    -- Stream Head (if path exists)
    if head_path then
        local h_pfb = sdk.create_instance("via.Prefab"):add_ref()
        h_pfb:call("set_Path", head_path)
        h_pfb:call("set_Standby", true)
        spawner.stream_head = h_pfb
    end

    -- Stream Hair (if path exists)
    if hair_path then
        local hr_pfb = sdk.create_instance("via.Prefab"):add_ref()
        hr_pfb:call("set_Path", hair_path)
        hr_pfb:call("set_Standby", true)
        spawner.stream_hair = hr_pfb
    end

    spawner.streaming = true
    spawner.stream_frames = 0
    spawner.last_status = "Streaming Claire parts from archives..."
end

-- =========================================================================
-- 8. Master Frame Loop (re.on_frame)
-- =========================================================================
re.on_frame(function()
    -- Asynchronous Streaming Tick
    if spawner.streaming then
        spawner.stream_frames = spawner.stream_frames + 1

        local body_ready = false
        pcall(function() body_ready = spawner.stream_body and spawner.stream_body:call("get_Ready") end)

        local head_ready = true
        if spawner.stream_head then
            pcall(function() head_ready = spawner.stream_head:call("get_Ready") end)
        end

        local hair_ready = true
        if spawner.stream_hair then
            pcall(function() hair_ready = spawner.stream_hair:call("get_Ready") end)
        end

        -- Check if all parts ready OR if body ready and timeout reached
        if (body_ready and head_ready and hair_ready) or (body_ready and spawner.stream_frames > 180) then
            local player = spawner.get_master_player()
            local player_go = spawner.get_player_game_object(player)
            local player_tf = player_go and player_go:call("get_Transform")
            local front_pos = player_tf and get_front_spawn_position(player_tf, 2.0) or { x = 0, y = 0, z = 0 }
            local vpos = (Vector3f and Vector3f.new and Vector3f.new(front_pos.x, front_pos.y, front_pos.z)) or front_pos

            -- 1. Instantiate Body
            local body_go = nil
            pcall(function()
                body_go = spawner.stream_body:call("instantiate(via.vec3)", vpos)
            end)

            if body_go then
                pcall(function() body_go:add_ref() end)
                local b_tf = body_go.call and body_go:call("get_Transform")
                if b_tf then
                    pcall(function() b_tf:call("set_Position", front_pos) end)
                end
                pcall(function()
                    body_go:call("set_DrawSelf", true)
                    body_go:call("set_UpdateSelf", true)
                end)
                table.insert(spawner.spawned_entities, body_go)

                -- 2. Instantiate Head
                if spawner.stream_head and head_ready then
                    local head_go = nil
                    pcall(function()
                        head_go = spawner.stream_head:call("instantiate(via.vec3)", vpos)
                    end)
                    if head_go then
                        pcall(function() head_go:add_ref() end)
                        attach_child_part(head_go, body_go)
                        table.insert(spawner.spawned_entities, head_go)
                        log_msg("Head part assembled and attached.")
                    end
                end

                -- 3. Instantiate Hair
                if spawner.stream_hair and hair_ready then
                    local hair_go = nil
                    pcall(function()
                        hair_go = spawner.stream_hair:call("instantiate(via.vec3)", vpos)
                    end)
                    if hair_go then
                        pcall(function() hair_go:add_ref() end)
                        attach_child_part(hair_go, body_go)
                        table.insert(spawner.spawned_entities, hair_go)
                        log_msg("Hair part assembled and attached.")
                    end
                end

                local part_count = #spawner.spawned_entities
                if part_count >= 3 then
                    spawner.last_status = "SUCCESS: CLAIRE FULLY RENDERED (Body + Head + Hair)!"
                elseif part_count == 2 then
                    spawner.last_status = "CLAIRE RENDERED (Body + 1 Modular Part Attached)"
                else
                    spawner.last_status = "CLAIRE BODY RENDERED IN VIEWPORT"
                end
                log_msg("Spawning completed with " .. tostring(part_count) .. " parts assembled.")
            else
                spawner.last_status = "Body instantiation failed."
                log_msg("Body instantiation failed or returned nil.")
            end

            spawner.streaming = false
            spawner.stream_body = nil
            spawner.stream_head = nil
            spawner.stream_hair = nil
        elseif spawner.stream_frames > 240 then
            spawner.last_status = "Streaming timed out waiting for assets."
            spawner.streaming = false
            spawner.stream_body = nil
            spawner.stream_head = nil
            spawner.stream_hair = nil
        end
    end

    -- Process pending action
    if spawner.pending_action == "spawn_default" then
        spawner.pending_action = nil
        pcall(function() spawner.spawn_claire(0) end)
    elseif spawner.pending_action == "spawn_tank" then
        spawner.pending_action = nil
        pcall(function() spawner.spawn_claire(1) end)
    elseif spawner.pending_action == "despawn" then
        spawner.pending_action = nil
        pcall(spawner.execute_despawn)
    end
end)

-- Initial archive scan on script startup
pcall(function()
    spawner.scan_archives_and_inspect()
end)

-- =========================================================================
-- 9. Clean, Minimalist ImGui Spawner UI (No Diagnostic Clutter)
-- =========================================================================
local function draw_spawner_ui()
    imgui.text_colored("=== RE2 DUO MODE: CLAIRE REDFIELD SPAWNER ===", 0.3, 0.9, 1.0, 1.0)
    imgui.text("Status: " .. tostring(spawner.last_status))
    
    local h_status = spawner.resolved_head and "Found" or "Scanning"
    local hr_status = spawner.resolved_hair and "Found" or "Scanning"
    imgui.text(string.format("Assets: Body=OK | Head=%s | Hair=%s", h_status, hr_status))
    imgui.separator()

    local player = spawner.get_master_player()
    if player then
        imgui.text_colored("Player (Leon): ACTIVE IN SCENE", 0.2, 1.0, 0.4, 1.0)
        imgui.spacing()

        if imgui.button(">>> SPAWN CLAIRE REDFIELD (Full Character) <<<") then
            spawner.pending_action = "spawn_default"
        end

        imgui.spacing()
        if imgui.button("Spawn Claire (Tank Top)") then
            spawner.pending_action = "spawn_tank"
        end

        imgui.same_line()
        if imgui.button("Despawn Claire") then
            spawner.pending_action = "despawn"
        end
    else
        imgui.text_colored("Waiting for game scene / Leon to load...", 1.0, 0.8, 0.2, 1.0)
        imgui.text("Please load your game save or start a new game first.")
    end
end

-- Embedded in REFramework Main Menu
re.on_draw_ui(function()
    draw_spawner_ui()
end)

-- Dedicated Standalone Floating Window
re.on_frame(function()
    pcall(function()
        if imgui.begin_window("Claire Redfield Spawner (Duo Mode)", true, 0) then
            draw_spawner_ui()
            imgui.end_window()
        end
    end)
end)
