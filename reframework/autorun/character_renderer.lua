--[[
    Resident Evil 2: Duo Mode — Claire Redfield Spawner
    Script: character_renderer.lua
    Purpose: Dedicated harness to spawn Claire Redfield (PL1000) into the 3D viewport and inspect survivor anatomy.
    Author: AryanTechie-007
]]

local function log_debug(msg)
    pcall(function()
        local f = io.open("reframework/data/spawner_debug.txt", "a")
        if f then
            f:write(os.date("[%H:%M:%S] ") .. tostring(msg) .. "\n")
            f:close()
        end
    end)
    if log and log.info then
        log.info("[Spawner] " .. tostring(msg))
    end
end

log_debug("=== Claire Redfield Spawner Loading ===")

local spawner = {}
spawner.spawned_entities = {}
spawner.last_status = "Ready - Standing by"
spawner.pending_action = nil

-- Streaming State
spawner.loading_prefab = nil
spawner.loading_path = ""
spawner.loading_frames = 0
spawner.load_mode = "body_only" -- "body_only" or "modular"

-- Secondary Prefabs for Modular Mode
spawner.loading_head_prefab = nil
spawner.loading_hair_prefab = nil

-- Inspection state
spawner.leon_inspected = false

-- =========================================================================
-- 1. Helper: Safe Yaw and Forward Vector Extraction
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
-- 2. Player Resolution
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
-- 3. Scene Inspector: Analyze Active Player Anatomy
-- =========================================================================
function spawner.inspect_active_player()
    if spawner.leon_inspected then return end
    local player = spawner.get_master_player()
    if not player then return end
    local pgo = spawner.get_player_game_object(player)
    if not pgo then return end

    spawner.leon_inspected = true
    pcall(function()
        local f = io.open("reframework/data/leon_inspection.txt", "w")
        if not f then return end

        f:write("=======================================================\n")
        f:write("RE2 DUO MODE: ACTIVE SCENE PLAYER INSPECTION\n")
        f:write("Time: " .. os.date() .. "\n")
        f:write("=======================================================\n\n")
        f:write("Player GameObject Name: " .. tostring(pgo:call("get_Name")) .. "\n")

        -- Components on player
        local comp_count = 0
        pcall(function() comp_count = pgo:call("get_ComponentCount") or 0 end)
        f:write("Total Components: " .. tostring(comp_count) .. "\n")
        for i = 0, comp_count - 1 do
            pcall(function()
                local comp = pgo:call("getComponent(System.Int32)", i)
                local td = comp and comp:get_type_definition()
                local cname = td and td:get_full_name() or "unknown"
                f:write(string.format("  [Comp %d] %s\n", i, cname))
            end)
        end

        -- Transform Children
        local tf = nil
        pcall(function() tf = pgo:call("get_Transform") end)
        if tf then
            local child_count = 0
            pcall(function() child_count = tf:call("get_ChildCount") or 0 end)
            f:write("\nTransform Children Count: " .. tostring(child_count) .. "\n")
            for i = 0, child_count - 1 do
                pcall(function()
                    local ch_tf = tf:call("get_Child(System.Int32)", i) or tf:call("get_Child", i)
                    if ch_tf then
                        local ch_go = ch_tf:call("get_GameObject")
                        local ch_name = ch_go and ch_go:call("get_Name") or "unnamed"
                        local pjoint = nil
                        pcall(function() pjoint = ch_tf:call("get_ParentJoint") end)
                        local pj_name = pjoint and pjoint.call and pjoint:call("get_Name") or "none"
                        f:write(string.format("  [Child %d] name='%s', parent_joint='%s'\n", i, tostring(ch_name), tostring(pj_name)))

                        if ch_go then
                            local ch_comp_count = ch_go:call("get_ComponentCount") or 0
                            for j = 0, ch_comp_count - 1 do
                                local ch_comp = ch_go:call("getComponent(System.Int32)", j)
                                local ch_td = ch_comp and ch_comp:get_type_definition()
                                f:write(string.format("     -> Comp: %s\n", ch_td and ch_td:get_full_name() or "unknown"))
                            end
                        end
                    end
                end)
            end
        end

        f:write("\n=======================================================\n")
        f:close()
        log_debug("Active player hierarchy inspection written to reframework/data/leon_inspection.txt")
    end)
end

-- =========================================================================
-- 4. Despawn Logic
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
    spawner.loading_prefab = nil
    spawner.loading_head_prefab = nil
    spawner.loading_hair_prefab = nil
    spawner.last_status = "Despawned"
    log_debug("Despawn executed.")
end

-- =========================================================================
-- 5. Primary Spawner: Guaranteed Body Instantiation (Verified Working)
-- =========================================================================
function spawner.spawn_claire_body(costume_index)
    spawner.execute_despawn()
    costume_index = costume_index or 0

    local body_path = string.format("objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_%d.pfb", costume_index)
    log_debug("Starting Claire Body Stream: " .. body_path)

    local pfb = nil
    pcall(function()
        pfb = sdk.create_instance("via.Prefab"):add_ref()
        pfb:call("set_Path", body_path)
        pfb:call("set_Standby", true)
    end)

    if not pfb then
        spawner.last_status = "Failed: Could not create via.Prefab"
        log_debug("Failed to create via.Prefab instance.")
        return
    end

    spawner.loading_prefab = pfb
    spawner.loading_path = body_path
    spawner.loading_frames = 0
    spawner.load_mode = "body_only"
    spawner.last_status = "Streaming Claire body from archives..."
end

-- =========================================================================
-- 6. Experimental Modular Spawner: Body + Head + Hair
-- =========================================================================
function spawner.spawn_claire_modular(costume_index)
    spawner.execute_despawn()
    costume_index = costume_index or 0

    local body_path = string.format("objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_%d.pfb", costume_index)
    local head_path = "objectroot/prefab/character/survivor/parts/pl1000/pl1000_face_costume_a.pfb"
    local hair_path = "objectroot/prefab/character/survivor/parts/pl1000/pl1000_hair_costume_a.pfb"

    log_debug("Starting Modular Assembly Stream:")
    log_debug("  Body: " .. body_path)
    log_debug("  Head: " .. head_path)
    log_debug("  Hair: " .. hair_path)

    local b_pfb, h_pfb, hr_pfb = nil, nil, nil
    pcall(function()
        b_pfb = sdk.create_instance("via.Prefab"):add_ref()
        b_pfb:call("set_Path", body_path)
        b_pfb:call("set_Standby", true)
    end)
    pcall(function()
        h_pfb = sdk.create_instance("via.Prefab"):add_ref()
        h_pfb:call("set_Path", head_path)
        h_pfb:call("set_Standby", true)
    end)
    pcall(function()
        hr_pfb = sdk.create_instance("via.Prefab"):add_ref()
        hr_pfb:call("set_Path", hair_path)
        hr_pfb:call("set_Standby", true)
    end)

    spawner.loading_prefab = b_pfb
    spawner.loading_head_prefab = h_pfb
    spawner.loading_hair_prefab = hr_pfb
    spawner.loading_frames = 0
    spawner.load_mode = "modular"
    spawner.last_status = "Streaming Body + Head + Hair..."
end

-- =========================================================================
-- 7. Master Frame Loop (re.on_frame)
-- =========================================================================
re.on_frame(function()
    -- Auto-inspect player once loaded
    if not spawner.leon_inspected then
        pcall(spawner.inspect_active_player)
    end

    -- Asynchronous Streaming Tick
    if spawner.loading_prefab then
        spawner.loading_frames = spawner.loading_frames + 1
        local pfb = spawner.loading_prefab
        local is_ready = false
        pcall(function() is_ready = pfb:call("get_Ready") end)

        if is_ready then
            local player = spawner.get_master_player()
            local player_go = spawner.get_player_game_object(player)
            local player_tf = player_go and player_go:call("get_Transform")
            local front_pos = player_tf and get_front_spawn_position(player_tf, 2.0) or { x = 0, y = 0, z = 0 }
            local vpos = (Vector3f and Vector3f.new and Vector3f.new(front_pos.x, front_pos.y, front_pos.z)) or front_pos

            -- 1. Instantiate Body
            local body_go = nil
            local ok_spawn, err = pcall(function()
                body_go = pfb:call("instantiate(via.vec3)", vpos)
            end)

            if ok_spawn and body_go then
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
                log_debug("Body successfully instantiated in viewport.")

                -- 2. If modular mode, attach head and hair
                if spawner.load_mode == "modular" then
                    -- Head
                    if spawner.loading_head_prefab then
                        local h_ready = false
                        pcall(function() h_ready = spawner.loading_head_prefab:call("get_Ready") end)
                        if h_ready then
                            local head_go = nil
                            pcall(function()
                                head_go = spawner.loading_head_prefab:call("instantiate(via.vec3)", vpos)
                            end)
                            if head_go then
                                pcall(function() head_go:add_ref() end)
                                pcall(function()
                                    local h_tf = head_go:call("get_Transform")
                                    if h_tf and b_tf then
                                        h_tf:call("set_Parent", b_tf)
                                    end
                                    head_go:call("set_DrawSelf", true)
                                    head_go:call("set_UpdateSelf", true)
                                end)
                                table.insert(spawner.spawned_entities, head_go)
                                log_debug("Head successfully instantiated and attached.")
                            end
                        end
                    end

                    -- Hair
                    if spawner.loading_hair_prefab then
                        local hr_ready = false
                        pcall(function() hr_ready = spawner.loading_hair_prefab:call("get_Ready") end)
                        if hr_ready then
                            local hair_go = nil
                            pcall(function()
                                hair_go = spawner.loading_hair_prefab:call("instantiate(via.vec3)", vpos)
                            end)
                            if hair_go then
                                pcall(function() hair_go:add_ref() end)
                                pcall(function()
                                    local hr_tf = hair_go:call("get_Transform")
                                    if hr_tf and b_tf then
                                        hr_tf:call("set_Parent", b_tf)
                                    end
                                    hair_go:call("set_DrawSelf", true)
                                    hair_go:call("set_UpdateSelf", true)
                                end)
                                table.insert(spawner.spawned_entities, hair_go)
                                log_debug("Hair successfully instantiated and attached.")
                            end
                        end
                    end
                end

                local total_parts = #spawner.spawned_entities
                if total_parts >= 3 then
                    spawner.last_status = "SUCCESS: CLAIRE FULLY RENDERED (Body + Head + Hair)!"
                else
                    spawner.last_status = "CLAIRE RENDERED IN VIEWPORT!"
                end
                log_debug("Spawn completed. Total parts in scene: " .. tostring(total_parts))
            else
                spawner.last_status = "Instantiation failed"
                log_debug("Body instantiate failed: " .. tostring(err))
            end

            spawner.loading_prefab = nil
            spawner.loading_head_prefab = nil
            spawner.loading_hair_prefab = nil
        elseif spawner.loading_frames > 180 then
            spawner.last_status = "Streaming timed out"
            log_debug("Streaming timed out at frame 180.")
            spawner.loading_prefab = nil
            spawner.loading_head_prefab = nil
            spawner.loading_hair_prefab = nil
        end
    end

    -- Process pending action
    if spawner.pending_action == "spawn_body" then
        spawner.pending_action = nil
        pcall(function() spawner.spawn_claire_body(0) end)
    elseif spawner.pending_action == "spawn_modular" then
        spawner.pending_action = nil
        pcall(function() spawner.spawn_claire_modular(0) end)
    elseif spawner.pending_action == "spawn_tank" then
        spawner.pending_action = nil
        pcall(function() spawner.spawn_claire_body(1) end)
    elseif spawner.pending_action == "despawn" then
        spawner.pending_action = nil
        pcall(spawner.execute_despawn)
    end
end)

-- =========================================================================
-- 8. Clean, Minimalist ImGui Spawner UI
-- =========================================================================
local function draw_spawner_ui()
    imgui.text_colored("=== RE2 DUO MODE: CLAIRE REDFIELD SPAWNER ===", 0.3, 0.9, 1.0, 1.0)
    imgui.text("Status: " .. tostring(spawner.last_status))
    imgui.separator()

    local player = spawner.get_master_player()
    if player then
        imgui.text_colored("Player (Leon): ACTIVE IN SCENE", 0.2, 1.0, 0.4, 1.0)
        imgui.spacing()

        if imgui.button(">>> SPAWN CLAIRE REDFIELD (Instant Spawn) <<<") then
            spawner.pending_action = "spawn_body"
        end

        imgui.spacing()
        if imgui.button("Spawn Claire + Head/Hair (Modular Test)") then
            spawner.pending_action = "spawn_modular"
        end

        imgui.same_line()
        if imgui.button("Spawn Claire (Tank Top)") then
            spawner.pending_action = "spawn_tank"
        end

        imgui.spacing()
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
