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

log_msg("=== Claire Redfield Spawner Loading ===")

local spawner = {}
spawner.spawned_entity = nil
spawner.locating_claire = false
spawner.locating_frames = 0
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
    spawner.locating_claire = false
    spawner.last_status = "Despawned"
end

-- =========================================================================
-- 4. Native Claire Spawner (Actor & Player Casting)
-- =========================================================================
function spawner.spawn_claire_native(role_type)
    role_type = role_type or "actor" -- "actor" or "player"
    spawner.execute_despawn()
    log_msg("Executing Native Claire Cast (Role: " .. role_type .. ")...")

    local sam = sdk.get_managed_singleton("app.ropeway.SurvivorAssignManager")
    local sm = sdk.get_managed_singleton("app.ropeway.SurvivorManager")
    if not sam or not sm then
        spawner.last_status = "Failed: Survivor Managers not found"
        return
    end

    local player = spawner.get_master_player()
    local player_go = spawner.get_player_game_object(player)
    local player_tf = player_go and player_go:call("get_Transform")
    local front_pos = player_tf and get_front_spawn_position(player_tf, 2.0) or { x = 0, y = 0, z = 0 }

    -- Step 1: Open Transaction
    pcall(function()
        sam:call("beginRequestTransaction(app.ropeway.SurvivorAssignManager.TransactionOption)", 0)
    end)

    -- Step 2: Call sceneIn with proper enum value (1 = PL1000 Claire)
    local result = nil
    if role_type == "actor" then
        -- ActorDefine.ActorType.PL1000 = 1
        pcall(function()
            result = sam:call("sceneIn(app.ropeway.ActorDefine.ActorType, app.ropeway.SurvivorAssignManager.CastingReason, app.ropeway.SurvivorAssignManager.OfferMode, app.ropeway.gamemastering.Map.ID, app.ropeway.gamemastering.Location.ID)", 1, 1, 0, 0, 0)
        end)
    else
        -- PlayerDefine.PlayerType.PL1000 = 1
        pcall(function()
            result = sam:call("sceneIn(app.ropeway.PlayerDefine.PlayerType, app.ropeway.SurvivorAssignManager.CastingReason, app.ropeway.SurvivorAssignManager.OfferMode)", 1, 1, 0)
        end)
    end

    -- Step 3: End Transaction & Process
    pcall(function() sam:call("endRequestTransaction") end)
    pcall(function() sam:call("onUpdateWaitingRequest") end)
    log_msg("Native sceneIn dispatched. Result: " .. tostring(result))

    -- Step 4: Locate Claire's GameObject and Teleport to Viewport!
    local claire_go = nil

    -- Check static getSurvivorGameObject
    local sm_td = sm:get_type_definition()
    if sm_td then
        local m = sm_td:get_method("getSurvivorGameObject")
        if m then
            pcall(function() claire_go = m:call(nil, "pl1000", 0) end)
            if not claire_go then
                pcall(function() claire_go = m:call(nil, "PL1000", 0) end)
            end
        end
    end

    -- Check Actors dictionary
    if not claire_go then
        pcall(function()
            local actors = sm:call("get_Actors")
            if actors then
                local actor_cond = actors:call("get_Item", 1)
                if actor_cond then
                    claire_go = actor_cond:call("get_GameObject")
                end
            end
        end)
    end

    -- Check Scene Search
    if not claire_go then
        local scene_man = sdk.get_native_singleton("via.SceneManager")
        local cur_scene = scene_man and scene_man:call("get_CurrentScene")
        if cur_scene then
            pcall(function() claire_go = cur_scene:call("findGameObject(System.String)", "pl1000") end)
            if not claire_go then
                pcall(function() claire_go = cur_scene:call("findGameObject(System.String)", "PL1000") end)
            end
        end
    end

    if claire_go then
        pcall(function() claire_go:add_ref() end)
        local c_tf = claire_go.call and claire_go:call("get_Transform")
        if c_tf then
            pcall(function() c_tf:call("set_Position", front_pos) end)
        end
        pcall(function()
            claire_go:call("set_DrawSelf", true)
            claire_go:call("set_UpdateSelf", true)
        end)
        spawner.spawned_entity = claire_go
        spawner.last_status = "SUCCESS: CLAIRE RENDERED IN FRONT OF LEON!"
        log_msg("SUCCESS: Claire found and positioned in viewport!")
    else
        spawner.last_status = "Order sent. Teleporting Claire into viewport..."
        spawner.locating_claire = true
        spawner.locating_frames = 0
    end
end

-- =========================================================================
-- 5. Master Frame Loop (re.on_frame)
-- =========================================================================
re.on_frame(function()
    -- Asynchronous Locator Tick
    if spawner.locating_claire then
        spawner.locating_frames = spawner.locating_frames + 1
        local sm = sdk.get_managed_singleton("app.ropeway.SurvivorManager")
        local claire_go = nil

        -- Check getSurvivorGameObject
        pcall(function()
            local sm_td = sm and sm:get_type_definition()
            local m = sm_td and sm_td:get_method("getSurvivorGameObject")
            if m then claire_go = m:call(nil, "pl1000", 0) or m:call(nil, "PL1000", 0) end
        end)

        -- Check Actors dictionary
        if not claire_go and sm then
            pcall(function()
                local actors = sm:call("get_Actors")
                local actor_cond = actors and actors:call("get_Item", 1)
                if actor_cond then claire_go = actor_cond:call("get_GameObject") end
            end)
        end

        -- Check scene search
        if not claire_go then
            local scene_man = sdk.get_native_singleton("via.SceneManager")
            local cur_scene = scene_man and scene_man:call("get_CurrentScene")
            if cur_scene then
                pcall(function() claire_go = cur_scene:call("findGameObject(System.String)", "pl1000") or cur_scene:call("findGameObject(System.String)", "PL1000") end)
            end
        end

        if claire_go then
            pcall(function() claire_go:add_ref() end)
            local player = spawner.get_master_player()
            local player_go = spawner.get_player_game_object(player)
            local player_tf = player_go and player_go:call("get_Transform")
            local front_pos = player_tf and get_front_spawn_position(player_tf, 2.0) or { x = 0, y = 0, z = 0 }
            local c_tf = claire_go.call and claire_go:call("get_Transform")
            if c_tf then
                pcall(function() c_tf:call("set_Position", front_pos) end)
            end
            pcall(function()
                claire_go:call("set_DrawSelf", true)
                claire_go:call("set_UpdateSelf", true)
            end)
            spawner.spawned_entity = claire_go
            spawner.last_status = "SUCCESS: CLAIRE RENDERED IN FRONT OF LEON!"
            log_msg("SUCCESS: Claire located and positioned in viewport!")
            spawner.locating_claire = false
        elseif spawner.locating_frames > 60 then
            spawner.last_status = "Entity registered in engine (Checking location)"
            spawner.locating_claire = false
        end
    end

    -- Action Queue
    if spawner.pending_action == "spawn_actor" then
        spawner.pending_action = nil
        pcall(function() spawner.spawn_claire_native("actor") end)
    elseif spawner.pending_action == "spawn_player" then
        spawner.pending_action = nil
        pcall(function() spawner.spawn_claire_native("player") end)
    elseif spawner.pending_action == "despawn" then
        spawner.pending_action = nil
        pcall(spawner.execute_despawn)
    end
end)

-- =========================================================================
-- 6. Clean, Minimalist ImGui Spawner UI
-- =========================================================================
local function draw_spawner_ui()
    imgui.text_colored("=== RE2 DUO MODE: CLAIRE REDFIELD SPAWNER ===", 0.3, 0.9, 1.0, 1.0)
    imgui.text("Status: " .. tostring(spawner.last_status))
    imgui.separator()

    local player = spawner.get_master_player()
    if player then
        imgui.text_colored("Player (Leon): ACTIVE IN SCENE", 0.2, 1.0, 0.4, 1.0)
        imgui.spacing()

        if imgui.button(">>> SPAWN CLAIRE REDFIELD (Actor Cast) <<<") then
            spawner.pending_action = "spawn_actor"
        end

        imgui.same_line()
        if imgui.button("Spawn Claire (Player Cast)") then
            spawner.pending_action = "spawn_player"
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
