--[[
    Resident Evil 2: Duo Mode — Claire Redfield Spawner
    Script: character_renderer.lua
    Purpose: Dedicated harness to spawn Claire Redfield (PL1000) into the 3D viewport.
    Author: AryanTechie-007
]]

local spawner = {}
spawner.spawned_entities = {}
spawner.last_status = "Ready - Standing by (Click button to spawn)"
spawner.click_count = 0

-- Streaming State
spawner.active_pfbs = {}
spawner.loading_frames = 0
spawner.current_candidate_idx = 1
spawner.is_streaming = false

local CANDIDATE_PATHS = {
    "objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_0.pfb",
    "objectroot/prefab/character/survivor/pl1000.pfb",
    "natives/x64/objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_0.pfb",
    "natives/x64/objectroot/prefab/character/survivor/pl1000.pfb",
    "objectroot/prefab/character/player/pl1000.pfb"
}

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

log_debug("=== Claire Redfield Spawner Initialized ===")

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

-- =========================================================================
-- 2. Player Resolution
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
-- 3. Despawn Logic
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
    spawner.active_pfbs = {}
    spawner.is_streaming = false
    spawner.loading_frames = 0
    spawner.last_status = "Despawned - Standing by"
    log_debug("Despawn executed cleanly.")
end

-- =========================================================================
-- 4. Multi-Candidate Adaptive Prefab Spawner
-- =========================================================================
function spawner.start_adaptive_prefab_stream()
    spawner.execute_despawn()
    spawner.active_pfbs = {}
    spawner.loading_frames = 0
    spawner.is_streaming = true

    log_debug("Starting Adaptive Prefab Stream across " .. tostring(#CANDIDATE_PATHS) .. " candidates:")

    for idx, path in ipairs(CANDIDATE_PATHS) do
        pcall(function()
            local pfb = sdk.create_instance("via.Prefab"):add_ref()
            pfb:call("set_Path", path)
            pfb:call("set_Standby", true)
            table.insert(spawner.active_pfbs, {
                path = path,
                pfb = pfb,
                idx = idx
            })
            log_debug(string.format("  [%d] Queued: %s", idx, path))
        end)
    end

    spawner.last_status = "Streaming candidate prefabs from game archives..."
end

-- =========================================================================
-- 5. Native Casting Pathway (SurvivorAssignManager)
-- =========================================================================
function spawner.spawn_claire_native()
    spawner.execute_despawn()
    log_debug("Executing Native Casting Spawner...")

    local sam = nil
    pcall(function() sam = sdk.get_managed_singleton("app.ropeway.SurvivorAssignManager") end)
    local sm = nil
    pcall(function() sm = sdk.get_managed_singleton("app.ropeway.SurvivorManager") end)

    if not sam then
        spawner.last_status = "Error: SurvivorAssignManager not found"
        log_debug("SurvivorAssignManager not found.")
        return
    end

    local player = spawner.get_master_player()
    local player_go = spawner.get_player_game_object(player)
    local player_tf = player_go and player_go:call("get_Transform")
    local front_pos = player_tf and get_front_spawn_position(player_tf, 2.0) or { x = 0, y = 0, z = 0 }

    pcall(function()
        sam:call("beginRequestTransaction(app.ropeway.SurvivorAssignManager.TransactionOption)", 0)
    end)

    -- Try Actor Casting (1000 = PL1000, 1 = SurvivorType PL1000)
    local r1 = nil
    pcall(function()
        r1 = sam:call("sceneIn(app.ropeway.ActorDefine.ActorType, app.ropeway.SurvivorAssignManager.CastingReason, app.ropeway.SurvivorAssignManager.OfferMode, app.ropeway.gamemastering.Map.ID, app.ropeway.gamemastering.Location.ID)", 1000, 1, 0, 0, 0)
    end)
    if not r1 then
        pcall(function()
            r1 = sam:call("sceneIn(app.ropeway.ActorDefine.ActorType, app.ropeway.SurvivorAssignManager.CastingReason, app.ropeway.SurvivorAssignManager.OfferMode, app.ropeway.gamemastering.Map.ID, app.ropeway.gamemastering.Location.ID)", 1, 1, 0, 0, 0)
        end)
    end

    pcall(function() sam:call("endRequestTransaction") end)
    pcall(function() sam:call("onUpdateWaitingRequest") end)
    log_debug("Native casting transaction completed. Result: " .. tostring(r1))

    -- Locate Claire in Scene
    local claire_go = nil
    if sm then
        local sm_td = sm:get_type_definition()
        if sm_td then
            local m = sm_td:get_method("getSurvivorGameObject")
            if m then
                pcall(function() claire_go = m:call(nil, "pl1000", 0) end)
                if not claire_go then pcall(function() claire_go = m:call(nil, "PL1000", 0) end) end
            end
        end
    end

    if not claire_go then
        local scene_man = sdk.get_native_singleton("via.SceneManager")
        local cur_scene = scene_man and scene_man:call("get_CurrentScene")
        if cur_scene then
            pcall(function() claire_go = cur_scene:call("findGameObject(System.String)", "pl1000") end)
            if not claire_go then pcall(function() claire_go = cur_scene:call("findGameObject(System.String)", "PL1000") end) end
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
        table.insert(spawner.spawned_entities, claire_go)
        spawner.last_status = "SUCCESS: CLAIRE CAST VIA ENGINE & POSITIONED!"
        log_debug("Claire found and positioned in viewport!")
    else
        spawner.last_status = "Native cast dispatched. Searching scene..."
        log_debug("Native cast dispatched, searching scene on subsequent frames...")
    end
end

-- =========================================================================
-- 6. Master Frame Loop (re.on_frame)
-- =========================================================================
re.on_frame(function()
    if spawner.is_streaming and #spawner.active_pfbs > 0 then
        spawner.loading_frames = spawner.loading_frames + 1

        local player = spawner.get_master_player()
        local player_go = spawner.get_player_game_object(player)
        local player_tf = player_go and player_go:call("get_Transform")
        local front_pos = player_tf and get_front_spawn_position(player_tf, 2.0) or { x = 0, y = 0, z = 0 }
        local vpos = (Vector3f and Vector3f.new and Vector3f.new(front_pos.x, front_pos.y, front_pos.z)) or front_pos

        local spawned_obj = nil
        local winning_path = nil

        -- Check all candidate prefabs for readiness or instantiate opportunity
        for _, entry in ipairs(spawner.active_pfbs) do
            local pfb = entry.pfb
            local is_ready = false
            pcall(function() is_ready = pfb:call("get_Ready") end)

            -- Try instantiate if ready OR periodically every 15 frames
            if is_ready or (spawner.loading_frames % 15 == 0) then
                local obj = nil
                local ok = pcall(function()
                    obj = pfb:call("instantiate(via.vec3)", vpos)
                end)

                if ok and obj then
                    spawned_obj = obj
                    winning_path = entry.path
                    break
                end
            end
        end

        if spawned_obj then
            pcall(function() spawned_obj:add_ref() end)
            local sp_tf = nil
            pcall(function() sp_tf = spawned_obj:call("get_Transform") end)
            if sp_tf then
                pcall(function() sp_tf:call("set_Position", front_pos) end)
            end
            pcall(function()
                spawned_obj:call("set_DrawSelf", true)
                spawned_obj:call("set_UpdateSelf", true)
            end)
            table.insert(spawner.spawned_entities, spawned_obj)

            spawner.is_streaming = false
            spawner.active_pfbs = {}
            spawner.last_status = "SUCCESS: CLAIRE RENDERED IN VIEWPORT!"
            log_debug(string.format("Spawn succeeded at frame %d using: %s", spawner.loading_frames, tostring(winning_path)))
        else
            spawner.last_status = string.format("Streaming candidates (Frame %d/300)...", spawner.loading_frames)

            if spawner.loading_frames > 300 then
                spawner.is_streaming = false
                spawner.active_pfbs = {}
                spawner.last_status = "Streaming timed out. Try Native Cast button!"
                log_debug("Adaptive streaming timed out at frame 300.")
            end
        end
    end
end)

-- =========================================================================
-- 7. Clean, Minimalist ImGui Spawner UI
-- =========================================================================
local function draw_spawner_ui(suffix)
    suffix = suffix or ""
    imgui.text_colored("=== RE2 DUO MODE: CLAIRE REDFIELD SPAWNER ===", 0.3, 0.9, 1.0, 1.0)
    imgui.text("Status: " .. tostring(spawner.last_status))
    imgui.text("Spawn Requests: " .. tostring(spawner.click_count))
    imgui.separator()

    local player = spawner.get_master_player()
    if player then
        imgui.text_colored("Player (Leon): ACTIVE IN SCENE", 0.2, 1.0, 0.4, 1.0)
        imgui.spacing()

        if imgui.button(">>> SPAWN CLAIRE REDFIELD (Adaptive Prefab) <<<##btn_main" .. suffix) then
            spawner.click_count = spawner.click_count + 1
            log_debug("UI BUTTON CLICKED: Adaptive Prefab Spawn")
            spawner.start_adaptive_prefab_stream()
        end

        imgui.spacing()
        if imgui.button("Spawn Claire (Native Engine Cast)##btn_nat" .. suffix) then
            spawner.click_count = spawner.click_count + 1
            log_debug("UI BUTTON CLICKED: Native Cast")
            spawner.spawn_claire_native()
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
