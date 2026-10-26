--[[
    Resident Evil 2: Duo Mode — Claire Redfield Spawner
    Script: character_renderer.lua
    Purpose: Dedicated harness to spawn and render Claire Redfield (PL1000) into the 3D viewport.
    Author: AryanTechie-007
]]

local function log_msg(str)
    if log and log.info then
        log.info("[Spawner] " .. tostring(str))
    end
end

log_msg("=== Claire Redfield Spawner Loaded ===")

local spawner = {}
spawner.spawned_entity = nil
spawner.loading_prefab = nil
spawner.loading_prefab_path = ""
spawner.loading_frames = 0
spawner.last_status = "Ready - Standing by"
spawner.pending_action = nil

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
-- 2. Helper: Player Resolution
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
-- 3. Despawn Logic
-- =========================================================================
function spawner.execute_despawn()
    if spawner.spawned_entity then
        pcall(function()
            if spawner.spawned_entity.call then
                pcall(function() spawner.spawned_entity:call("set_DrawSelf", false) end)
                pcall(function() spawner.spawned_entity:call("set_UpdateSelf", false) end)
            end
            local scene_man = sdk.get_native_singleton("via.SceneManager")
            local cur_scene = scene_man and scene_man:call("get_CurrentScene")
            if cur_scene then
                pcall(function() cur_scene:call("destroyGameObject(via.GameObject)", spawner.spawned_entity) end)
                pcall(function() cur_scene:call("destroyGameObject", spawner.spawned_entity) end)
            end
        end)
        spawner.spawned_entity = nil
    end
    spawner.loading_prefab = nil
    spawner.last_status = "Despawned"
end

-- =========================================================================
-- 4. Spawning Pathways
-- =========================================================================

-- Pathway A: Asynchronous Direct via.Prefab Streaming
function spawner.spawn_claire_prefab(costume_index)
    spawner.execute_despawn()
    costume_index = costume_index or 0

    local candidate_paths = {
        string.format("objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_%d.pfb", costume_index),
        string.format("natives/x64/objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_%d.pfb", costume_index),
        "objectroot/prefab/character/survivor/pl1000.pfb",
        "natives/x64/objectroot/prefab/character/survivor/pl1000.pfb"
    }

    local pfb = nil
    local chosen_path = nil

    for _, path in ipairs(candidate_paths) do
        local test_pfb = nil
        pcall(function()
            test_pfb = sdk.create_instance("via.Prefab"):add_ref()
            test_pfb:call("set_Path", path)
            test_pfb:call("set_Standby", true)
        end)

        if test_pfb then
            local is_exist = nil
            pcall(function() is_exist = test_pfb:call("get_Exist") end)
            if is_exist ~= false then
                pfb = test_pfb
                chosen_path = path
                break
            end
        end
    end

    if not pfb or not chosen_path then
        pfb = sdk.create_instance("via.Prefab"):add_ref()
        chosen_path = candidate_paths[1]
        pcall(function()
            pfb:call("set_Path", chosen_path)
            pfb:call("set_Standby", true)
        end)
    end

    spawner.loading_prefab = pfb
    spawner.loading_prefab_path = chosen_path
    spawner.loading_frames = 0
    spawner.last_status = "Streaming Claire from game archives..."
    log_msg("Streaming Claire prefab: " .. tostring(chosen_path))
end

-- Pathway B: Native Engine SurvivorAssignManager (SAM)
function spawner.spawn_claire_native()
    spawner.execute_despawn()
    local sam = sdk.get_managed_singleton("app.ropeway.SurvivorAssignManager")
    if not sam then
        spawner.last_status = "Failed: SurvivorAssignManager not active"
        return
    end

    local survivor_def = sdk.find_type_definition("app.ropeway.SurvivorDefine")
    if not survivor_def then
        spawner.last_status = "Failed: SurvivorDefine missing"
        return
    end

    local target_id = nil
    local m = survivor_def:get_method("parseNPC")
    if m then pcall(function() target_id = m:call(nil, 1) end) end

    if target_id == nil then
        spawner.last_status = "Failed to resolve Claire NPC ID"
        return
    end

    pcall(function()
        sam:call("beginRequestTransaction(app.ropeway.SurvivorAssignManager.TransactionOption)", 0)
    end)

    pcall(function()
        sam:call("sceneIn(app.ropeway.NpcDefine.NPCType, app.ropeway.SurvivorAssignManager.CastingReason, app.ropeway.SurvivorAssignManager.OfferMode)", target_id, 1, 0)
    end)

    pcall(function() sam:call("endRequestTransaction") end)
    pcall(function() sam:call("onUpdateWaitingRequest") end)

    spawner.last_status = "Native Claire spawn requested (Check scene)"
    log_msg("Native Claire sceneIn dispatched.")
end

-- =========================================================================
-- 5. Master Frame Loop (re.on_frame)
-- =========================================================================
re.on_frame(function()
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

            local spawned = nil
            local ok_spawn = pcall(function()
                spawned = pfb:call("instantiate(via.vec3)", vpos)
            end)

            if ok_spawn and spawned then
                pcall(function() spawned:add_ref() end)
                local sp_tf = spawned.call and spawned:call("get_Transform")
                if sp_tf then
                    pcall(function() sp_tf:call("set_Position", front_pos) end)
                end
                pcall(function()
                    spawned:call("set_DrawSelf", true)
                    spawned:call("set_UpdateSelf", true)
                end)
                spawner.spawned_entity = spawned
                spawner.last_status = "CLAIRE RENDERED IN VIEWPORT!"
                log_msg("Claire successfully instantiated in viewport.")
            else
                spawner.last_status = "Instantiation failed"
                log_msg("instantiate failed or returned nil.")
            end
            spawner.loading_prefab = nil
        elseif spawner.loading_frames > 180 then
            spawner.last_status = "Streaming timed out"
            spawner.loading_prefab = nil
        end
    end

    -- Process pending action
    if spawner.pending_action == "spawn_default" then
        spawner.pending_action = nil
        pcall(function() spawner.spawn_claire_prefab(0) end)
    elseif spawner.pending_action == "spawn_tank" then
        spawner.pending_action = nil
        pcall(function() spawner.spawn_claire_prefab(1) end)
    elseif spawner.pending_action == "spawn_native" then
        spawner.pending_action = nil
        pcall(spawner.spawn_claire_native)
    elseif spawner.pending_action == "despawn" then
        spawner.pending_action = nil
        pcall(spawner.execute_despawn)
    end
end)

-- =========================================================================
-- 6. Clean, Minimalist ImGui Spawner UI
-- =========================================================================
re.on_draw_ui(function()
    imgui.text_colored("=== RE2 DUO MODE: CLAIRE REDFIELD SPAWNER ===", 0.3, 0.9, 1.0, 1.0)
    imgui.text("Status: " .. tostring(spawner.last_status))
    imgui.separator()

    local player = spawner.get_master_player()
    imgui.text("Player (Leon): " .. (player and "Active in World" or "Waiting for game scene"))
    imgui.separator()

    if imgui.button("SPAWN CLAIRE REDFIELD (Default Jacket)") then
        spawner.pending_action = "spawn_default"
    end

    imgui.same_line()
    if imgui.button("Spawn Claire (Tank Top)") then
        spawner.pending_action = "spawn_tank"
    end

    if imgui.button("Spawn Claire (Native Engine Cast)") then
        spawner.pending_action = "spawn_native"
    end

    imgui.same_line()
    if imgui.button("Despawn Claire") then
        spawner.pending_action = "despawn"
    end
end)
