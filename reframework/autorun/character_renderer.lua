--[[
    Resident Evil 2: Duo Mode — Claire Redfield Spawner & Mesh Resolver
    Script: character_renderer.lua
    Author: AryanTechie-007
]]

local spawner = {}
spawner.spawned_entities = {}
spawner.last_status = "Ready - Standing by"

local function log_debug(msg)
    pcall(function()
        local f = io.open("reframework/data/spawner_debug.txt", "a")
        if f then
            f:write(os.date("[%H:%M:%S] ") .. tostring(msg) .. "\n")
            f:close()
        end
    end)
    pcall(function()
        local f2 = io.open("reframework/data/motion_debug.txt", "a")
        if f2 then
            f2:write(os.date("[%H:%M:%S] [Spawner] ") .. tostring(msg) .. "\n")
            f2:close()
        end
    end)
    if log and log.info then
        log.info("[Spawner] " .. tostring(msg))
    end
end

-- =========================================================================
-- 1. Deep Scan of Claire Prefabs & Mesh Validation
-- =========================================================================
local CANDIDATE_PATHS = {
    -- pl1000 (Claire Jacket)
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_1.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_a.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_0.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_2.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_body.pfb",
    -- pl1001 (Claire Tank Top)
    "objectroot/prefab/character/survivor/parts/pl1001/pl1001_body_costume_1.pfb",
    "objectroot/prefab/character/survivor/parts/pl1001/pl1001_body_costume_a.pfb",
    "objectroot/prefab/character/survivor/parts/pl1001/pl1001_body_costume_0.pfb",
    "objectroot/prefab/character/survivor/parts/pl1001/pl1001_body.pfb",
    -- pl1002 (Classic 1998)
    "objectroot/prefab/character/survivor/parts/pl1002/pl1002_body_costume_1.pfb",
    "objectroot/prefab/character/survivor/parts/pl1002/pl1002_body_costume_a.pfb",
    "objectroot/prefab/character/survivor/parts/pl1002/pl1002_body.pfb",
    -- Player root prefabs
    "objectroot/prefab/character/player/pl1000.pfb",
    "objectroot/prefab/character/player/pl1001.pfb",
    "objectroot/prefab/character/survivor/pl1000.pfb",
}

local FACE_PATHS = {
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_face_costume_1.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_face_costume_a.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_face.pfb",
    "objectroot/prefab/character/survivor/parts/pl1001/pl1001_face_costume_1.pfb",
    "objectroot/prefab/character/survivor/parts/pl1001/pl1001_face.pfb",
}

local HAIR_PATHS = {
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_hair_costume_1.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_hair_costume_a.pfb",
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_hair.pfb",
    "objectroot/prefab/character/survivor/parts/pl1001/pl1001_hair_costume_1.pfb",
    "objectroot/prefab/character/survivor/parts/pl1001/pl1001_hair.pfb",
}

spawner.valid_bodies = {}
spawner.valid_faces = {}
spawner.valid_hairs = {}

function spawner.scan_all()
    log_debug("=== SCANNING RE2 PAK ARCHIVES FOR CLAIRE MESH PREFABS ===")
    
    for _, path in ipairs(CANDIDATE_PATHS) do
        pcall(function()
            local pfb = sdk.create_instance("via.Prefab"):add_ref()
            pfb:call("set_Path", path)
            if pfb:call("get_Exist") then
                table.insert(spawner.valid_bodies, path)
                log_debug("  [BODY FOUND] " .. path)
            end
        end)
    end

    for _, path in ipairs(FACE_PATHS) do
        pcall(function()
            local pfb = sdk.create_instance("via.Prefab"):add_ref()
            pfb:call("set_Path", path)
            if pfb:call("get_Exist") then
                table.insert(spawner.valid_faces, path)
                log_debug("  [FACE FOUND] " .. path)
            end
        end)
    end

    for _, path in ipairs(HAIR_PATHS) do
        pcall(function()
            local pfb = sdk.create_instance("via.Prefab"):add_ref()
            pfb:call("set_Path", path)
            if pfb:call("get_Exist") then
                table.insert(spawner.valid_hairs, path)
                log_debug("  [HAIR FOUND] " .. path)
            end
        end)
    end
    log_debug("=========================================================")
end

pcall(spawner.scan_all)

-- =========================================================================
-- 2. Transform Math & Safe Position Setters
-- =========================================================================
local function set_transform_position(tf, x, y, z)
    if not tf then return false end
    local v4 = Vector4f and Vector4f.new and Vector4f.new(x, y, z, 1.0)
    local v3 = Vector3f and Vector3f.new and Vector3f.new(x, y, z)

    if v4 and tf.set_position then
        local ok1 = pcall(function() tf:set_position(v4) end)
        if ok1 then return true end
    end
    if v3 and tf.set_position then
        local ok2 = pcall(function() tf:set_position(v3) end)
        if ok2 then return true end
    end
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
    return 0.0
end

local function get_front_spawn_position(player_tf, dist)
    dist = dist or 2.0
    local p = get_transform_position(player_tf) or { x = 0.0, y = 0.0, z = 0.0 }
    local yaw = get_yaw_from_transform(player_tf)
    local fx = p.x + math.sin(yaw) * dist
    local fy = p.y
    local fz = p.z + math.cos(yaw) * dist
    return { x = fx, y = fy, z = fz }
end

-- =========================================================================
-- 3. In-Depth SurvivorMeshPartsController & Mesh Activator
-- =========================================================================
function spawner.activate_all_character_parts(body_go)
    if not body_go then return end
    log_debug("--- ACTIVATING ALL SURVIVOR MESH PARTS ---")

    -- 1. Inspect and activate SurvivorMeshPartsController
    local smpc = nil
    pcall(function()
        smpc = body_go:call("getComponent(System.Type)", sdk.typeof("app.ropeway.survivor.SurvivorMeshPartsController"))
    end)

    if smpc then
        pcall(function() smpc:call("set_Enabled", true) end)
        log_debug("  [SurvivorMeshPartsController] Active on body")

        -- Read Part Names
        pcall(function()
            local names = smpc:call("get_PartsNames")
            if names and names.get_elements then
                for idx, n in ipairs(names:get_elements()) do
                    local str = n and (n:call("ToString") or tostring(n))
                    log_debug(string.format("    PartName [%d]: %s", idx, tostring(str)))
                end
            end
        end)

        -- Inspect Parts Array
        pcall(function()
            local parts = smpc:call("get_Parts")
            if parts and parts.get_elements then
                for idx, p in ipairs(parts:get_elements()) do
                    local td = p and p:get_type_definition()
                    local tname = td and td:get_full_name() or "unknown"
                    log_debug(string.format("    Part [%d] Type: %s", idx, tname))

                    -- Print fields on part
                    if td then
                        for _, f in ipairs(td:get_fields() or {}) do
                            local val = p:get_field(f:get_name())
                            log_debug(string.format("      field %s = %s", f:get_name(), tostring(val)))
                        end
                    end

                    -- Enable part
                    pcall(function() p:call("set_Enable", true) end)
                    pcall(function() p:call("set_IsEnable", true) end)
                    pcall(function() p:set_field("mEnable", true) end)
                    pcall(function() p:set_field("mIsEnable", true) end)
                end
            end
        end)

        -- Test different PartsForm settings
        for form_id = 0, 3 do
            pcall(function()
                smpc:call("set_PartsForm", form_id)
                smpc:call("updateMeshPartsSettings")
                smpc:call("updateScenarioSettings")
                smpc:call("updateVariableSettings")
            end)
        end
    end

    -- 2. Inspect and activate via.render.Mesh on body and all children
    local function reveal_node(go)
        if not go or not go.call then return end
        pcall(function() go:call("set_DrawSelf", true) end)
        pcall(function() go:call("set_UpdateSelf", true) end)
        pcall(function() go:call("set_Draw", true) end)

        local comps = nil
        pcall(function() comps = go:call("get_Components") end)
        if comps and comps.get_elements then
            for _, c in ipairs(comps:get_elements()) do
                local td = c and c:get_type_definition()
                local tname = td and td:get_full_name() or ""

                pcall(function() c:call("set_Enabled", true) end)

                if tname:find("via.render.Mesh") then
                    pcall(function() c:call("set_Draw", true) end)
                    pcall(function() c:call("set_Enabled", true) end)
                    pcall(function() c:call("set_DrawMesh", true) end)

                    local m_count = c:call("get_MeshNum") or 0
                    local mat_count = c:call("get_MaterialNum") or 0
                    local go_name = go:call("get_Name") or "unnamed"
                    log_debug(string.format("    Mesh on [%s]: MeshNum=%d, MatNum=%d", go_name, m_count, mat_count))

                    for i = 0, m_count - 1 do
                        pcall(function() c:call("setMeshEnable(System.Int32, System.Boolean)", i, true) end)
                        pcall(function() c:call("setMeshEnable", i, true) end)
                    end
                    for j = 0, mat_count - 1 do
                        pcall(function() c:call("setMaterialsEnable(System.Int32, System.Boolean)", j, true) end)
                        pcall(function() c:call("setMaterialsEnable", j, true) end)
                    end
                end

                if tname:find("ComputeSkinning") then
                    pcall(function() c:call("set_Enabled", true) end)
                end
            end
        end

        local tf = nil
        pcall(function() tf = go:call("get_Transform") end)
        if tf then
            local child = nil
            pcall(function() child = tf:call("get_Child") end)
            while child do
                local ch_go = nil
                pcall(function() ch_go = child:call("get_GameObject") end)
                if ch_go then reveal_node(ch_go) end
                local nxt = nil
                pcall(function() nxt = child:call("get_Next") end)
                child = nxt
            end
        end
    end

    reveal_node(body_go)
    log_debug("-----------------------------------------------")
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
    spawner.body_pfb = nil
    spawner.head_pfb = nil
    spawner.hair_pfb = nil
    spawner.streaming = false
    spawner.stream_frames = 0
    spawner.last_status = "Despawned - Standing by"
    log_debug("Despawn executed cleanly.")
end

-- =========================================================================
-- 6. Spawner Execution Pipeline
-- =========================================================================
spawner.chosen_body_path = "objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_1.pfb"
spawner.chosen_face_path = "objectroot/prefab/character/survivor/parts/pl1000/pl1000_face_costume_1.pfb"
spawner.chosen_hair_path = "objectroot/prefab/character/survivor/parts/pl1000/pl1000_hair_costume_1.pfb"

function spawner.start_spawn()
    spawner.execute_despawn()

    log_debug("Starting Claire Spawn Pipeline:")
    log_debug("  Body: " .. tostring(spawner.chosen_body_path))
    log_debug("  Face: " .. tostring(spawner.chosen_face_path))
    log_debug("  Hair: " .. tostring(spawner.chosen_hair_path))

    -- Body Prefab
    pcall(function()
        local b = sdk.create_instance("via.Prefab"):add_ref()
        b:call("set_Path", spawner.chosen_body_path)
        b:call("set_Standby", true)
        spawner.body_pfb = b
    end)

    -- Head Prefab
    pcall(function()
        local h = sdk.create_instance("via.Prefab"):add_ref()
        h:call("set_Path", spawner.chosen_face_path)
        h:call("set_Standby", true)
        spawner.head_pfb = h
    end)

    -- Hair Prefab
    pcall(function()
        local hr = sdk.create_instance("via.Prefab"):add_ref()
        hr:call("set_Path", spawner.chosen_hair_path)
        hr:call("set_Standby", true)
        spawner.hair_pfb = hr
    end)

    spawner.streaming = true
    spawner.stream_frames = 0
    spawner.last_status = "Streaming Claire assets... (Frame 0)"
end

-- =========================================================================
-- 7. Master Frame Loop (re.on_frame)
-- =========================================================================
re.on_frame(function()
    if spawner.streaming and spawner.body_pfb then
        spawner.stream_frames = spawner.stream_frames + 1

        local player = spawner.get_master_player()
        local player_go = spawner.get_player_game_object(player)
        local player_tf = player_go and player_go:call("get_Transform")
        local front_pos = player_tf and get_front_spawn_position(player_tf, 2.0) or { x = 0, y = 0, z = 0 }
        local vpos = (Vector3f and Vector3f.new and Vector3f.new(front_pos.x, front_pos.y, front_pos.z))
                  or (Vector4f and Vector4f.new and Vector4f.new(front_pos.x, front_pos.y, front_pos.z, 1.0))
                  or front_pos

        -- Attempt instantiation of Body
        local body_obj = nil
        local ok_b = pcall(function()
            body_obj = spawner.body_pfb:call("instantiate(via.vec3)", vpos)
        end)

        if ok_b and body_obj then
            pcall(function() body_obj:add_ref() end)
            local b_tf = nil
            pcall(function() b_tf = body_obj:call("get_Transform") end)
            if b_tf then
                set_transform_position(b_tf, front_pos.x, front_pos.y, front_pos.z)
            end

            spawner.activate_all_character_parts(body_obj)
            table.insert(spawner.spawned_entities, body_obj)
            log_debug(string.format("Body instantiated at frame %d at (%.2f, %.2f, %.2f)", spawner.stream_frames, front_pos.x, front_pos.y, front_pos.z))

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
                    end)
                    spawner.activate_all_character_parts(head_obj)
                    table.insert(spawner.spawned_entities, head_obj)
                    log_debug("Head instantiated, parented, and activated.")
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
                    end)
                    spawner.activate_all_character_parts(hair_obj)
                    table.insert(spawner.spawned_entities, hair_obj)
                    log_debug("Hair instantiated, parented, and activated.")
                end
            end

            local total_parts = #spawner.spawned_entities
            spawner.last_status = string.format("SUCCESS: CLAIRE FULLY RENDERED (Parts: %d)!", total_parts)
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
end)

-- =========================================================================
-- 8. ImGui Spawner UI
-- =========================================================================
local function draw_spawner_ui(suffix)
    suffix = suffix or ""
    imgui.text_colored("=== RE2 DUO MODE: CLAIRE REDFIELD (RED JACKET) ===", 0.3, 0.9, 1.0, 1.0)
    imgui.text("Status: " .. tostring(spawner.last_status))
    imgui.separator()

    local player = spawner.get_master_player()
    if player then
        imgui.text_colored("Player (Leon): ACTIVE IN SCENE", 0.2, 1.0, 0.4, 1.0)
        imgui.spacing()

        if imgui.button(">>> SPAWN CLAIRE REDFIELD (Red Jacket) <<<##btn_full" .. suffix) then
            log_debug("UI BUTTON CLICKED: Red Jacket Spawn")
            spawner.start_spawn()
        end

        imgui.spacing()
        if imgui.button("Force Re-Activate All Parts##btn_react" .. suffix) then
            for _, ent in ipairs(spawner.spawned_entities) do
                spawner.activate_all_character_parts(ent)
            end
            log_debug("Manual Force Re-Activate Parts clicked.")
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
        if imgui.begin_window("Claire Redfield Spawner (Duo Mode)", true, 0) then
            draw_spawner_ui("##win")
            imgui.end_window()
        end
    end)
end)

-- REFramework Menu entry
re.on_draw_ui(function()
    draw_spawner_ui("##menu")
end)

-- =========================================================================
-- 9. Global Interface
-- =========================================================================
_G.DuoMode = _G.DuoMode or {}
_G.DuoMode.spawner = spawner
_G.DuoMode.get_companion_body = function()
    return spawner.spawned_entities and spawner.spawned_entities[1]
end
_G.DuoMode.get_companion_parts = function()
    return spawner.spawned_entities
end
_G.DuoMode.is_spawned = function()
    return spawner.spawned_entities and #spawner.spawned_entities > 0 and spawner.spawned_entities[1] ~= nil
end
