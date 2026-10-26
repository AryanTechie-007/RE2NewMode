--[[
    Resident Evil 2: Duo Mode — Character Renderer & Understander Harness
    Script: character_renderer.lua
    Purpose: Dedicated, isolated harness to inspect RE Engine internals and render Claire (PL1000) into the 3D viewport.
    Author: AryanTechie-007
]]

local function log_msg(str)
    if log and log.info then
        log.info("[Renderer] " .. tostring(str))
    end
    local f = io.open("reframework/data/renderer_log.txt", "a")
    if f then
        f:write(os.date("[%Y-%m-%d %H:%M:%S] [Renderer] ") .. tostring(str) .. "\n")
        f:close()
    else
        local f2 = io.open("renderer_log.txt", "a")
        if f2 then
            f2:write(os.date("[%Y-%m-%d %H:%M:%S] [Renderer] ") .. tostring(str) .. "\n")
            f2:close()
        end
    end
end

log_msg("=== Character Renderer Harness Loading ===")

local renderer = {}
renderer.spawned_entity = nil
renderer.diagnostic_log = {}
renderer.last_status = "Ready - Standing by"
renderer.pending_action = nil -- Thread-safe action queue for re.on_frame

local function add_diag(text)
    table.insert(renderer.diagnostic_log, 1, os.date("[%H:%M:%S] ") .. text)
    if #renderer.diagnostic_log > 30 then
        table.remove(renderer.diagnostic_log)
    end
    log_msg(text)
end

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
function renderer.get_master_player()
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

function renderer.get_player_game_object(player)
    player = player or renderer.get_master_player()
    if not player then return nil end
    local go = nil
    pcall(function() if player.get_game_object then go = player:get_game_object() end end)
    if not go then pcall(function() go = player:call("get_GameObject") end) end
    return go or player
end

-- =========================================================================
-- 3. The "UNDERSTANDER": Deep Engine & Character Inspection
-- =========================================================================
function renderer.understand_player()
    add_diag("Running Understander: Inspecting Player 1...")
    local player = renderer.get_master_player()
    if not player then
        add_diag("ERROR: Master player not found in scene.")
        return
    end

    local player_td = player:get_type_definition()
    add_diag(string.format("Player Managed Class: '%s'", player_td and player_td:get_full_name() or "Unknown"))

    -- Dump relevant fields on Player object (Body, Costume, Parts, Mesh)
    if player_td then
        local fields = player_td:get_fields() or {}
        add_diag(string.format("Player class has %d fields. Scanning for model/mesh/costume references...", #fields))
        for _, f in ipairs(fields) do
            local fname = f:get_name()
            local ftype = f:get_type()
            local ftname = ftype and ftype:get_full_name() or ""
            local lower_name = string.lower(fname)
            if string.find(lower_name, "body") or string.find(lower_name, "costume") or string.find(lower_name, "part") or string.find(lower_name, "mesh") or string.find(lower_name, "visual") or string.find(lower_name, "model") or string.find(lower_name, "figure") then
                local val = nil
                pcall(function() val = f:get_data(player) end)
                add_diag(string.format("   -> Field: %s (%s) = %s", fname, ftname, tostring(val)))
            end
        end
    end

    local go = renderer.get_player_game_object(player)
    if not go then
        add_diag("ERROR: Player GameObject not found.")
        return
    end

    add_diag(string.format("Player Root GameObject: '%s'", tostring(go.call and go:call("get_Name"))))

    -- Check Mesh component on Root
    local mesh_td = sdk.find_type_definition("via.render.Mesh")
    if mesh_td then
        local mesh = nil
        pcall(function() mesh = go:call("getComponent(System.Type)", mesh_td:get_runtime_type()) end)
        if mesh then
            local draw_mesh = false
            pcall(function() draw_mesh = mesh:call("get_DrawMesh") end)
            add_diag(string.format("Root Mesh Component: DrawMesh=%s", tostring(draw_mesh)))
        else
            add_diag("Root Mesh Component: None on root (Meshes are managed by Character Parts)")
        end
    end

    -- Check Motion on Root
    local motion_td = sdk.find_type_definition("via.motion.Motion")
    if motion_td then
        local motion = nil
        pcall(function() motion = go:call("getComponent(System.Type)", motion_td:get_runtime_type()) end)
        if motion then
            add_diag("Root Motion Component: ACTIVE (Drives animation skeleton)")
        end
    end
end

function renderer.deep_dump_sam()
    log_msg("--- STARTING DEEP DUMP OF SAM & SURVIVOR SUBSYSTEMS ---")
    local dump_lines = {}
    local function dlog(str)
        table.insert(dump_lines, str)
        log_msg(str)
    end

    local types_to_dump = {
        "app.ropeway.SurvivorAssignManager",
        "app.ropeway.SurvivorAssignManager.CastingOrder",
        "app.ropeway.SurvivorAssignManager.CastingOrderNpc",
        "app.ropeway.SurvivorAssignManager.CastingOrderActor",
        "app.ropeway.SurvivorAssignManager.CastingOrderPlayer",
        "app.ropeway.SurvivorAssignManager.CastingReason",
        "app.ropeway.SurvivorAssignManager.TransactionOption",
        "app.ropeway.SurvivorAssignManager.OfferMode",
        "app.ropeway.SurvivorAssignManager.CastingStatus",
        "app.ropeway.SurvivorAssignManager.Phase",
        "app.ropeway.SurvivorAssignManager.CastingOrderResult",
        "app.ropeway.SurvivorAssignManager.CastingRequestResult",
        "app.ropeway.SurvivorDefine",
        "app.ropeway.SurvivorDefine.SurvivorType",
        "app.ropeway.SurvivorDefine.Costume",
        "app.ropeway.PlayerDefine.PlayerType",
        "app.ropeway.NpcDefine.NPCType",
        "app.ropeway.ActorDefine.ActorType",
        "app.ropeway.SurvivorManager",
        "app.ropeway.SurvivorPrefabInfo",
        "app.ropeway.SurvivorFolderSetting",
        "app.ropeway.SurvivorFolderSetting.PlayerFolder",
        "app.ropeway.SurvivorFolderSetting.NpcFolder",
        "app.ropeway.SurvivorFolderSetting.ActorFolder",
        "app.ropeway.level.SurvivorStandbyManger",
        "app.ropeway.SurvivorStandbyCatalog",
        "app.ropeway.SurvivorCast",
        "via.Prefab",
        "via.PrefabResource",
        "via.PrefabResourceHolder"
    }

    for _, tname in ipairs(types_to_dump) do
        local td = sdk.find_type_definition(tname)
        if not td then
            dlog("[DUMP] Type NOT FOUND: " .. tname)
        else
            dlog(string.format("[DUMP] === TYPE: %s ===", tname))
            local fields = td:get_fields() or {}
            dlog(string.format("[DUMP]   Fields (%d):", #fields))
            for _, f in ipairs(fields) do
                local ftype = f:get_type()
                local ftname = ftype and ftype:get_full_name() or "unknown"
                dlog(string.format("[DUMP]     %s %s (static=%s)", ftname, f:get_name(), tostring(f:is_static())))
            end

            local methods = td:get_methods() or {}
            dlog(string.format("[DUMP]   Methods (%d):", #methods))
            for _, m in ipairs(methods) do
                local mname = m:get_name()
                local rtype = m:get_return_type()
                local rtname = rtype and rtype:get_full_name() or "void"
                local params = {}
                for _, pt in ipairs(m:get_param_types() or {}) do
                    table.insert(params, pt:get_full_name())
                end
                dlog(string.format("[DUMP]     %s %s(%s) (static=%s)", rtname, mname, table.concat(params, ", "), tostring(m:is_static())))
            end
        end
    end

    local sam = sdk.get_managed_singleton("app.ropeway.SurvivorAssignManager")
    if sam then
        dlog("[DUMP] === LIVE SAM SINGLETON INSTANCE DATA ===")
        local sam_td = sam:get_type_definition()
        if sam_td then
            for _, f in ipairs(sam_td:get_fields() or {}) do
                if not f:is_static() then
                    local ok, val = pcall(function() return f:get_data(sam) end)
                    if ok then
                        dlog(string.format("[DUMP]   SAM.%s = %s", f:get_name(), tostring(val)))
                    end
                end
            end
        end
    end

    local sm = sdk.get_managed_singleton("app.ropeway.SurvivorManager")
    if sm then
        dlog("[DUMP] === LIVE SURVIVOR MANAGER INSTANCE DATA ===")
        local sm_td = sm:get_type_definition()
        if sm_td then
            for _, f in ipairs(sm_td:get_fields() or {}) do
                if not f:is_static() then
                    local ok, val = pcall(function() return f:get_data(sm) end)
                    if ok then
                        dlog(string.format("[DUMP]   SM.%s = %s", f:get_name(), tostring(val)))
                    end
                end
            end
        end

        -- Check PrefabInfoList
        local ok_p, pinfo_list = pcall(function() return sm:call("get_PrefabInfoList") end)
        if ok_p and pinfo_list then
            local cnt = 0
            pcall(function() cnt = pinfo_list:call("get_Count") end)
            dlog(string.format("[DUMP]   SM.PrefabInfoList Count = %d", cnt or 0))
            for i = 0, (cnt or 0) - 1 do
                pcall(function()
                    local item = pinfo_list:call("get_Item", i)
                    if item then
                        local stype = item:get_field("SurvivorType")
                        local loaded = item:get_field("IsLoaded") or item:get_field("Loaded")
                        local pfb = item:get_field("Prefab") or item:get_field("Resource")
                        dlog(string.format("[DUMP]     [%d] SurvivorType=%s, Loaded=%s, Prefab=%s", i, tostring(stype), tostring(loaded), tostring(pfb)))
                    end
                end)
            end
        end
    end
    dlog("--- COMPLETED DEEP DUMP OF SAM & SURVIVOR SUBSYSTEMS ---")
end

function renderer.understand_subsystems()
    add_diag("Running Understander: Inspecting Survivor Subsystems...")
    renderer.deep_dump_sam()
    add_diag("SAM Deep Dump complete. Check re2_framework_log.txt.")
end

-- =========================================================================
-- 4. The "RENDERER": Safe Execution on Game Logic Thread (re.on_frame)
-- =========================================================================

-- Clean up any previous test entity safely
function renderer.execute_despawn()
    if renderer.spawned_entity then
        add_diag("Despawning active test entity...")
        pcall(function()
            if renderer.spawned_entity.call then
                pcall(function() renderer.spawned_entity:call("set_DrawSelf", false) end)
                pcall(function() renderer.spawned_entity:call("set_UpdateSelf", false) end)
            end
            local scene_man = sdk.get_native_singleton("via.SceneManager")
            local cur_scene = scene_man and scene_man:call("get_CurrentScene")
            if cur_scene then
                pcall(function() cur_scene:call("destroyGameObject(via.GameObject)", renderer.spawned_entity) end)
                pcall(function() cur_scene:call("destroyGameObject", renderer.spawned_entity) end)
            end
        end)
        renderer.spawned_entity = nil
        renderer.last_status = "Despawned"
    end
end

-- Check Active Survivors across SurvivorManager
function renderer.check_active_survivors()
    local survivor_man = sdk.get_managed_singleton("app.ropeway.SurvivorManager")
    if not survivor_man then
        add_diag("SurvivorManager singleton not available.")
        return
    end

    add_diag("Querying SurvivorManager for active characters...")
    
    -- Check Player
    local p_cond = nil
    pcall(function() p_cond = survivor_man:call("get_Player") end)
    if p_cond then
        local p_go = nil
        pcall(function() p_go = p_cond:call("get_GameObject") end)
        local p_name = (p_go and p_go.call and p_go:call("get_Name")) or "Player"
        add_diag(string.format("  Player: ACTIVE -> '%s'", tostring(p_name)))
    else
        add_diag("  Player: None")
    end

    -- Check NPC
    local npc_cond = nil
    pcall(function() npc_cond = survivor_man:call("get_Npc") end)
    if npc_cond then
        local npc_go = nil
        pcall(function() npc_go = npc_cond:call("get_GameObject") end)
        local npc_name = (npc_go and npc_go.call and npc_go:call("get_Name")) or "NPC"
        add_diag(string.format("  NPC: ACTIVE -> '%s'", tostring(npc_name)))
        renderer.spawned_entity = npc_go
        renderer.last_status = "NPC ACTIVE IN SCENE: " .. tostring(npc_name)
    else
        add_diag("  NPC: not active (null)")
    end

    -- Check Actors
    local actors_dict = nil
    pcall(function() actors_dict = survivor_man:call("get_Actors") end)
    if actors_dict then
        local count = 0
        pcall(function() count = actors_dict:call("get_Count") end)
        add_diag(string.format("  Actors Dictionary Count: %d", count or 0))
    end
end

-- Safe Native SAM Transaction executed on logic tick
function renderer.execute_sam_transaction()
    add_diag("Executing Native SurvivorAssignManager Transaction Check...")

    local sam = sdk.get_managed_singleton("app.ropeway.SurvivorAssignManager")
    if not sam then
        add_diag("FAIL: SurvivorAssignManager singleton not active.")
        renderer.last_status = "Failed: SAM is nil"
        return
    end

    local ok_tx = false
    pcall(function()
        sam:call("beginRequestTransaction(app.ropeway.SurvivorAssignManager.TransactionOption)", 0)
        add_diag("Transaction: beginRequestTransaction(0 [None]) success.")
        ok_tx = true
    end)

    if not ok_tx then
        pcall(function()
            sam:call("beginRequestTransaction", 0)
            add_diag("Transaction: beginRequestTransaction(0) fallback success.")
            ok_tx = true
        end)
    end

    if ok_tx then
        pcall(function()
            sam:call("endRequestTransaction")
            add_diag("Transaction: endRequestTransaction() success.")
        end)
        renderer.last_status = "SAM Transaction Ready & Verified"
    else
        renderer.last_status = "Failed to begin SAM Transaction"
    end
end

-- Native SAM sceneIn Casting for Claire (SurvivorType 1 / PL1000)
function renderer.execute_sam_scene_in(mode)
    mode = mode or "npc" -- "npc", "player", "actor"
    add_diag("==================================================")
    add_diag(string.format("Native SAM: Executing sceneIn for Claire PL1000 (Mode: %s)...", mode))

    local sam = sdk.get_managed_singleton("app.ropeway.SurvivorAssignManager")
    if not sam then
        add_diag("FAIL: SurvivorAssignManager singleton not active.")
        renderer.last_status = "Failed: SAM is nil"
        return
    end

    local survivor_def = sdk.find_type_definition("app.ropeway.SurvivorDefine")
    if not survivor_def then
        add_diag("FAIL: app.ropeway.SurvivorDefine type not found.")
        renderer.last_status = "Failed: SurvivorDefine missing"
        return
    end

    local target_id = nil
    if mode == "npc" then
        local m = survivor_def:get_method("parseNPC")
        if m then pcall(function() target_id = m:call(nil, 1) end) end
        add_diag("SurvivorDefine.parseNPC(1 [Claire]) -> NpcType: " .. tostring(target_id))
    elseif mode == "player" then
        local m = survivor_def:get_method("parsePlayer")
        if m then pcall(function() target_id = m:call(nil, 1) end) end
        add_diag("SurvivorDefine.parsePlayer(1 [Claire]) -> PlayerType: " .. tostring(target_id))
    elseif mode == "actor" then
        local m = survivor_def:get_method("parseActor")
        if m then pcall(function() target_id = m:call(nil, 1) end) end
        add_diag("SurvivorDefine.parseActor(1 [Claire]) -> ActorType: " .. tostring(target_id))
    end

    if target_id == nil then
        add_diag("FAIL: Could not resolve target ID for mode: " .. mode)
        renderer.last_status = "Failed to resolve target ID"
        return
    end

    -- Step A: Begin Transaction
    local ok_tx = false
    pcall(function()
        sam:call("beginRequestTransaction(app.ropeway.SurvivorAssignManager.TransactionOption)", 0)
        ok_tx = true
    end)
    if not ok_tx then
        pcall(function()
            sam:call("beginRequestTransaction", 0)
            ok_tx = true
        end)
    end
    add_diag("SAM Transaction Opened: " .. tostring(ok_tx))

    -- Step B: Call sceneIn
    local result = nil
    local ok_call = false
    if mode == "npc" then
        ok_call = pcall(function()
            result = sam:call("sceneIn(app.ropeway.NpcDefine.NPCType, app.ropeway.SurvivorAssignManager.CastingReason, app.ropeway.SurvivorAssignManager.OfferMode)", target_id, 1, 0)
        end)
    elseif mode == "player" then
        ok_call = pcall(function()
            result = sam:call("sceneIn(app.ropeway.PlayerDefine.PlayerType, app.ropeway.SurvivorAssignManager.CastingReason, app.ropeway.SurvivorAssignManager.OfferMode)", target_id, 1, 0)
        end)
    elseif mode == "actor" then
        ok_call = pcall(function()
            result = sam:call("sceneIn(app.ropeway.ActorDefine.ActorType, app.ropeway.SurvivorAssignManager.CastingReason, app.ropeway.SurvivorAssignManager.OfferMode, app.ropeway.gamemastering.Map.ID, app.ropeway.gamemastering.Location.ID)", target_id, 1, 0, 0, 0)
        end)
    end

    add_diag(string.format("SAM sceneIn invoked (ok=%s, result=%s)", tostring(ok_call), tostring(result)))

    -- Step C: End Transaction
    pcall(function() sam:call("endRequestTransaction") end)
    add_diag("SAM Transaction closed.")

    -- Step D: Process Waiting Requests
    pcall(function() sam:call("onUpdateWaitingRequest") end)
    add_diag("SAM onUpdateWaitingRequest triggered.")

    renderer.last_status = string.format("SAM sceneIn Sent (%s: %s)", mode, tostring(result))
    renderer.check_active_survivors()
    add_diag("==================================================")
end

-- Direct via.Prefab Spawning (Bypasses story locks and asynchronously streams mesh)
renderer.loading_prefab = nil
renderer.loading_prefab_path = ""
renderer.loading_frames = 0

function renderer.execute_direct_prefab_spawn(prefab_path)
    renderer.execute_despawn()
    prefab_path = prefab_path or "objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_0.pfb"
    add_diag("==================================================")
    add_diag("Requesting via.Prefab Streaming: " .. prefab_path)

    local pfb = nil
    local ok_c = pcall(function()
        pfb = sdk.create_instance("via.Prefab"):add_ref()
    end)
    if not ok_c or not pfb then
        add_diag("FAIL: sdk.create_instance('via.Prefab') failed.")
        renderer.last_status = "Failed: via.Prefab creation"
        return
    end

    pcall(function() pfb:call("set_Path", prefab_path) end)
    pcall(function() pfb:call("set_Standby", true) end)

    local is_exist = nil
    local ok_e = pcall(function() is_exist = pfb:call("get_Exist") end)
    local is_ready = nil
    local ok_r = pcall(function() is_ready = pfb:call("get_Ready") end)

    add_diag(string.format("Prefab handle queued: Exist=%s, Ready=%s", tostring(is_exist), tostring(is_ready)))

    if ok_e and is_exist == false then
        add_diag("WARNING: get_Exist is FALSE. The path was not found in archive index.")
        renderer.last_status = "Path not found: " .. prefab_path
        return
    end

    renderer.loading_prefab = pfb
    renderer.loading_prefab_path = prefab_path
    renderer.loading_frames = 0
    renderer.last_status = "Streaming " .. prefab_path .. " from disk..."
end

-- =========================================================================
-- 5. Master Logic Loop (re.on_frame) — Thread-safe execution
-- =========================================================================
re.on_frame(function()
    -- Asynchronous Prefab Loader Tick
    if renderer.loading_prefab then
        renderer.loading_frames = renderer.loading_frames + 1
        local pfb = renderer.loading_prefab
        local is_ready = false
        pcall(function() is_ready = pfb:call("get_Ready") end)

        if is_ready then
            add_diag(string.format("Prefab READY after %d frames! Instantiating into viewport...", renderer.loading_frames))
            local player = renderer.get_master_player()
            local player_go = renderer.get_player_game_object(player)
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
                renderer.spawned_entity = spawned
                renderer.last_status = "SUCCESS: CLAIRE RENDERED IN VIEWPORT!"
                add_diag("SUCCESS: Claire physically instantiated into scene!")
            else
                add_diag("FAIL: instantiate returned nil or threw error: " .. tostring(spawned))
                renderer.last_status = "Instantiation failed"
            end
            renderer.loading_prefab = nil
        elseif renderer.loading_frames > 180 then
            add_diag("TIMEOUT: Prefab failed to become ready after 180 frames.")
            renderer.last_status = "Streaming timed out"
            renderer.loading_prefab = nil
        end
    end

    -- Action Queue
    if renderer.pending_action == "sam" then
        renderer.pending_action = nil
        pcall(renderer.execute_sam_transaction)
    elseif renderer.pending_action == "sam_scenein_npc" then
        renderer.pending_action = nil
        pcall(function() renderer.execute_sam_scene_in("npc") end)
    elseif renderer.pending_action == "sam_scenein_actor" then
        renderer.pending_action = nil
        pcall(function() renderer.execute_sam_scene_in("actor") end)
    elseif renderer.pending_action == "sam_scenein_player" then
        renderer.pending_action = nil
        pcall(function() renderer.execute_sam_scene_in("player") end)
    elseif renderer.pending_action == "prefab_body_0_clean" then
        renderer.pending_action = nil
        pcall(function() renderer.execute_direct_prefab_spawn("objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_0.pfb") end)
    elseif renderer.pending_action == "prefab_body_0_nat" then
        renderer.pending_action = nil
        pcall(function() renderer.execute_direct_prefab_spawn("natives/x64/objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_0.pfb") end)
    elseif renderer.pending_action == "prefab_pl1000_clean" then
        renderer.pending_action = nil
        pcall(function() renderer.execute_direct_prefab_spawn("objectroot/prefab/character/survivor/pl1000.pfb") end)
    elseif renderer.pending_action == "prefab_leon_test" then
        renderer.pending_action = nil
        pcall(function() renderer.execute_direct_prefab_spawn("objectroot/prefab/character/survivor/parts/pl0000/pl0000_body_costume_0.pfb") end)
    elseif renderer.pending_action == "check_survivors" then
        renderer.pending_action = nil
        pcall(renderer.check_active_survivors)
    elseif renderer.pending_action == "despawn" then
        renderer.pending_action = nil
        pcall(renderer.execute_despawn)
    end
end)

-- =========================================================================
-- 6. ImGui Control Panel & HUD
-- =========================================================================
re.on_draw_ui(function()
    imgui.text_colored("=== RE2 CHARACTER RENDERER & UNDERSTANDER ===", 0.3, 0.9, 1.0, 1.0)
    imgui.text("Status: " .. tostring(renderer.last_status))
    imgui.separator()

    local player = renderer.get_master_player()
    imgui.text("Master Player (Leon): " .. (player and "DETECTED IN WORLD" or "WAITING FOR IN-GAME SCENE"))

    local player_go = renderer.get_player_game_object(player)
    local player_tf = player_go and player_go:call("get_Transform")
    if player_tf then
        local p = player_tf:call("get_Position")
        local y = get_yaw_from_transform(player_tf)
        imgui.text(string.format("Leon Position: (%.2f, %.2f, %.2f) | Yaw: %.2f rad", p.x, p.y, p.z, y))
    end

    imgui.separator()
    imgui.text_colored("--- Pathway 1: Direct via.Prefab Streaming (Bypasses Scenario) ---", 0.2, 1.0, 0.4, 1.0)
    if imgui.button("Spawn Claire Body (objectroot/.../pl1000_body_0.pfb)") then
        renderer.pending_action = "prefab_body_0_clean"
    end
    imgui.same_line()
    if imgui.button("Spawn Claire (natives/x64/.../pl1000_body_0.pfb)") then
        renderer.pending_action = "prefab_body_0_nat"
    end

    if imgui.button("Spawn Claire Root (objectroot/.../pl1000.pfb)") then
        renderer.pending_action = "prefab_pl1000_clean"
    end
    imgui.same_line()
    if imgui.button("Test Path Verification (Leon pl0000 Body)") then
        renderer.pending_action = "prefab_leon_test"
    end

    imgui.separator()
    imgui.text_colored("--- Pathway 2: Native SAM Engine Casting (sceneIn) ---", 0.3, 0.8, 1.0, 1.0)
    if imgui.button("SAM sceneIn: Claire NPC") then
        renderer.pending_action = "sam_scenein_npc"
    end
    imgui.same_line()
    if imgui.button("SAM sceneIn: Claire Actor") then
        renderer.pending_action = "sam_scenein_actor"
    end
    imgui.same_line()
    if imgui.button("SAM sceneIn: Claire Player") then
        renderer.pending_action = "sam_scenein_player"
    end

    imgui.separator()
    imgui.text_colored("--- Controls & Diagnostics ---", 0.9, 0.9, 0.2, 1.0)
    if imgui.button("Despawn Test Entity") then
        renderer.pending_action = "despawn"
    end
    imgui.same_line()
    if imgui.button("Query Active Characters in Scene") then
        renderer.pending_action = "check_survivors"
    end
    imgui.same_line()
    if imgui.button("Dump Full Reflection") then
        renderer.deep_dump_sam()
    end

    imgui.separator()
    imgui.text_colored("--- Live Diagnostic Log ---", 0.7, 0.7, 0.7, 1.0)
    for _, line in ipairs(renderer.diagnostic_log) do
        imgui.text(line)
    end
end)

log_msg("Character Renderer Harness initialized.")
pcall(renderer.deep_dump_sam)
