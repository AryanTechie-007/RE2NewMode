--[[
    Resident Evil 2: Duo Mode — Claire Redfield Spawner
    Script: character_renderer.lua
    Purpose: Dedicated harness to spawn Claire Redfield (Classic Red Jacket) into the 3D viewport.
    Author: AryanTechie-007
]]

local spawner = {}
spawner.spawned_entities = {}
spawner.last_status = "Ready - Standing by (Click button to spawn)"
spawner.click_count = 0

-- Locked Exclusively to Classic Red Jacket Version
spawner.CLAIRE_BODY = "objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_1.pfb"
spawner.CLAIRE_FACE = "objectroot/prefab/character/survivor/parts/pl1000/pl1000_face_costume_1.pfb"
spawner.CLAIRE_HAIR = "objectroot/prefab/character/survivor/parts/pl1000/pl1000_hair_costume_1.pfb"

-- Streaming State
spawner.body_pfb = nil
spawner.head_pfb = nil
spawner.hair_pfb = nil
spawner.streaming = false
spawner.stream_frames = 0
spawner.mode = "full"

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
-- 1. Transform Math & Safe Position Setters
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
-- 2. Force Enable All Meshes, Materials, Submeshes, and Parts Controller
-- =========================================================================
function spawner.force_reveal_hierarchy(root_go)
    if not root_go then return end

    local function process_go(go)
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

                -- 1. Mesh Component: Enable draw and ALL submeshes and materials
                if tname:find("via.render.Mesh") then
                    pcall(function() c:call("set_Draw", true) end)
                    pcall(function() c:call("set_Enabled", true) end)
                    pcall(function() c:call("set_DrawMesh", true) end)

                    -- Enable all submeshes
                    pcall(function()
                        local mesh_count = c:call("get_MeshNum") or 0
                        for i = 0, mesh_count - 1 do
                            pcall(function() c:call("setMeshEnable(System.Int32, System.Boolean)", i, true) end)
                            pcall(function() c:call("setMeshEnable", i, true) end)
                        end
                    end)

                    -- Enable all materials
                    pcall(function()
                        local mat_count = c:call("get_MaterialNum") or 0
                        for j = 0, mat_count - 1 do
                            pcall(function() c:call("setMaterialsEnable(System.Int32, System.Boolean)", j, true) end)
                            pcall(function() c:call("setMaterialsEnable", j, true) end)
                        end
                    end)
                end

                -- 2. ComputeSkinning: Enable GPU skinning
                if tname:find("ComputeSkinning") then
                    pcall(function() c:call("set_Enabled", true) end)
                end

                -- 3. SurvivorMeshPartsController: Force parts on & update
                if tname:find("SurvivorMeshPartsController") then
                    pcall(function() c:call("set_Enabled", true) end)
                    pcall(function() c:call("set_PartsForm", 0) end)
                    pcall(function() c:call("set_PartsForm", 1) end)
                    pcall(function() c:call("updateMeshPartsSettings") end)
                    pcall(function() c:call("updateScenarioSettings") end)
                    pcall(function() c:call("updateVariableSettings") end)

                    -- Enable all individual part elements
                    pcall(function()
                        local parts_arr = c:call("get_Parts")
                        if parts_arr and parts_arr.get_elements then
                            for _, p in ipairs(parts_arr:get_elements()) do
                                if p and p.call then
                                    pcall(function() p:call("set_Enable", true) end)
                                    pcall(function() p:call("set_IsEnable", true) end)
                                end
                            end
                        end
                    end)
                end

                -- 4. ParentMotionSynchronizer: Enable on Face
                if tname:find("ParentMotionSynchronizer") then
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
                if ch_go then process_go(ch_go) end
                local nxt = nil
                pcall(function() nxt = child:call("get_Next") end)
                child = nxt
            end
        end
    end

    process_go(root_go)
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
    spawner.last_status = "Despawned - Standing by"
    log_debug("Despawn executed cleanly.")
end

-- =========================================================================
-- 5. Initiate Spawner Pipeline (Classic Red Jacket Exclusively)
-- =========================================================================
function spawner.start_spawn()
    spawner.execute_despawn()
    spawner.mode = "full"

    log_debug("Starting Claire Spawn Pipeline [Classic Red Jacket]:")
    log_debug("  Body: " .. tostring(spawner.CLAIRE_BODY))
    log_debug("  Face: " .. tostring(spawner.CLAIRE_FACE))
    log_debug("  Hair: " .. tostring(spawner.CLAIRE_HAIR))

    -- Create Body Prefab
    pcall(function()
        local b = sdk.create_instance("via.Prefab"):add_ref()
        b:call("set_Path", spawner.CLAIRE_BODY)
        b:call("set_Standby", true)
        spawner.body_pfb = b
    end)

    -- Create Head Prefab
    pcall(function()
        local h = sdk.create_instance("via.Prefab"):add_ref()
        h:call("set_Path", spawner.CLAIRE_FACE)
        h:call("set_Standby", true)
        spawner.head_pfb = h
    end)

    -- Create Hair Prefab
    pcall(function()
        local hr = sdk.create_instance("via.Prefab"):add_ref()
        hr:call("set_Path", spawner.CLAIRE_HAIR)
        hr:call("set_Standby", true)
        spawner.hair_pfb = hr
    end)

    spawner.streaming = true
    spawner.stream_frames = 0
    spawner.last_status = "Streaming Claire Red Jacket assets... (Frame 0)"
end

-- =========================================================================
-- 6. Master Frame Loop (re.on_frame)
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

            spawner.force_reveal_hierarchy(body_obj)
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
                    spawner.force_reveal_hierarchy(head_obj)
                    table.insert(spawner.spawned_entities, head_obj)
                    log_debug("Head instantiated and attached to Body.")
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
                    spawner.force_reveal_hierarchy(hair_obj)
                    table.insert(spawner.spawned_entities, hair_obj)
                    log_debug("Hair instantiated and attached to Body.")
                end
            end

            local total_parts = #spawner.spawned_entities
            spawner.last_status = string.format("SUCCESS: CLAIRE (Red Jacket) FULLY RENDERED (Parts: %d)!", total_parts)
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
-- 7. ImGui Spawner UI (Clean, Single Focus: Red Jacket)
-- =========================================================================
local function draw_spawner_ui(suffix)
    suffix = suffix or ""
    imgui.text_colored("=== RE2 DUO MODE: CLAIRE REDFIELD (RED JACKET) ===", 0.3, 0.9, 1.0, 1.0)
    imgui.text("Status: " .. tostring(spawner.last_status))
    imgui.text_colored("Outfit: Classic Red Leather Jacket (pl1000_body_costume_1)", 1.0, 0.85, 0.2, 1.0)
    imgui.separator()

    local player = spawner.get_master_player()
    if player then
        imgui.text_colored("Player (Leon): ACTIVE IN SCENE", 0.2, 1.0, 0.4, 1.0)
        imgui.spacing()

        if imgui.button(">>> SPAWN CLAIRE REDFIELD (Red Jacket) <<<##btn_full" .. suffix) then
            spawner.click_count = spawner.click_count + 1
            log_debug("UI BUTTON CLICKED: Red Jacket Spawn")
            spawner.start_spawn()
        end

        imgui.spacing()
        if imgui.button("Force Reveal Visuals (All Parts)##btn_reveal" .. suffix) then
            for _, ent in ipairs(spawner.spawned_entities) do
                spawner.force_reveal_hierarchy(ent)
            end
            log_debug("Manual Force Reveal Visuals clicked.")
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
-- 8. Global Interface
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
