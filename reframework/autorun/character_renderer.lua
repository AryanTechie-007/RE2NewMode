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
        "app.ropeway.SurvivorManager",
        "app.ropeway.level.SurvivorStandbyManger",
        "app.ropeway.SurvivorStandbyCatalog",
        "app.ropeway.SurvivorFolderSetting",
        "app.ropeway.SurvivorCast"
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

-- Safe Duplication executed on logic tick (prevents D3D12 Present 87a0001 error)
function renderer.execute_duplication()
    add_diag("NOTICE: Duplicate GameObject is deprecated due to D3D12 device resets.")
    add_diag("RE Engine player singletons cannot be cloned via duplicateGameObject.")
    add_diag("Use Native SAM Casting (Experiment 1) instead.")
    renderer.last_status = "Duplication Deprecated - Use Native SAM"
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

-- Check Active Survivors across SurvivorManager
function renderer.check_active_survivors()
    local survivor_man = sdk.get_managed_singleton("app.ropeway.SurvivorManager")
    if not survivor_man then
        add_diag("SurvivorManager singleton not available.")
        return
    end

    add_diag("Querying SurvivorManager for active survivors (0=Leon, 1=Claire, 2=Ada, 3=Sherry)...")
    for i = 0, 3 do
        local s = nil
        pcall(function() s = survivor_man:call("getSurvivor(app.ropeway.SurvivorDefine.SurvivorType)", i) end)
        if not s then
            pcall(function() s = survivor_man:call("getSurvivor", i) end)
        end
        if not s then
            pcall(function() s = survivor_man:call("getSurvivorCharacter(app.ropeway.SurvivorDefine.SurvivorType)", i) end)
        end
        if not s then
            pcall(function() s = survivor_man:call("getSurvivorCharacter", i) end)
        end

        if s then
            local go = nil
            pcall(function() go = s:call("get_GameObject") end)
            local goname = (go and go.call and go:call("get_Name")) or tostring(s)
            add_diag(string.format("  -> SurvivorType %d: ACTIVE (%s)", i, tostring(goname)))
            if i == 1 then
                renderer.spawned_entity = go or s
                renderer.last_status = "CLAIRE REDFIELD ACTIVE IN WORLD!"
            end
        else
            add_diag(string.format("  -> SurvivorType %d: not active", i))
        end
    end
end

-- Native SAM Casting Order for Claire (PL1000)
function renderer.execute_sam_cast(order_type_name)
    order_type_name = order_type_name or "app.ropeway.SurvivorAssignManager.CastingOrderNpc"
    add_diag("==================================================")
    add_diag("Initiating Native SAM Casting: Claire PL1000 via " .. order_type_name)

    local sam = sdk.get_managed_singleton("app.ropeway.SurvivorAssignManager")
    if not sam then
        add_diag("FAIL: SurvivorAssignManager singleton not active.")
        renderer.last_status = "Failed: SAM is nil"
        return
    end

    local order_td = sdk.find_type_definition(order_type_name)
    if not order_td then
        add_diag("FAIL: Order Type Definition not found: " .. order_type_name)
        renderer.last_status = "Failed: Type definition missing"
        return
    end

    local order = nil
    local ok_c = pcall(function()
        order = sdk.create_instance(order_type_name):add_ref()
    end)
    if not ok_c or not order then
        add_diag("FAIL: Failed to create instance of " .. order_type_name)
        renderer.last_status = "Failed to create order instance"
        return
    end
    add_diag("Successfully created order instance: " .. order_type_name)

    -- Configure order fields
    local curr_td = order_td
    while curr_td do
        for _, f in ipairs(curr_td:get_fields() or {}) do
            local fname = f:get_name()
            local lower = string.lower(fname)
            local ftype = f:get_type()
            local ftname = ftype and ftype:get_full_name() or ""

            -- Match SurvivorType
            if string.find(lower, "survivortype") or (string.find(lower, "type") and string.find(ftname, "SurvivorType")) then
                pcall(function() f:set_data(order, 1) end)
                add_diag(string.format("  Configured field: %s = 1 (Claire Redfield)", fname))
            elseif string.find(lower, "reason") or string.find(ftname, "CastingReason") then
                pcall(function() f:set_data(order, 1) end) -- 1 = InitialSet / Normal
                add_diag(string.format("  Configured field: %s = 1 (Reason)", fname))
            elseif string.find(lower, "costume") or string.find(ftname, "Costume") then
                pcall(function() f:set_data(order, 0) end) -- 0 = Default
                add_diag(string.format("  Configured field: %s = 0 (Default Costume)", fname))
            end
        end
        curr_td = curr_td:get_parent_type()
    end

    -- Step A: Begin Request Transaction
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

    -- Step B: Build Current Request
    local ok_bld = false
    pcall(function()
        sam:call("buildCurrentRequest(app.ropeway.SurvivorAssignManager.CastingOrder)", order)
        ok_bld = true
        add_diag("SAM: buildCurrentRequest(CastingOrder) succeeded.")
    end)
    if not ok_bld then
        pcall(function()
            sam:call("buildCurrentRequest", order)
            ok_bld = true
            add_diag("SAM: buildCurrentRequest fallback succeeded.")
        end)
    end

    -- Step C: End Request Transaction
    local ok_end = false
    pcall(function()
        sam:call("endRequestTransaction")
        ok_end = true
        add_diag("SAM: endRequestTransaction() succeeded.")
    end)

    -- Step D: Process Waiting Requests
    pcall(function()
        sam:call("onUpdateWaitingRequest")
        add_diag("SAM: onUpdateWaitingRequest() triggered.")
    end)

    if ok_bld and ok_end then
        renderer.last_status = "SAM Casting Order Queued (" .. order_type_name .. ")"
        add_diag("SUCCESS: Claire PL1000 casting order committed.")
        renderer.check_active_survivors()
    else
        renderer.last_status = "SAM Casting Order Failed"
        add_diag(string.format("FAIL: build=%s, end=%s", tostring(ok_bld), tostring(ok_end)))
    end
    add_diag("==================================================")
end

-- =========================================================================
-- 5. Master Logic Loop (re.on_frame) — Thread-safe execution
-- =========================================================================
re.on_frame(function()
    if renderer.pending_action == "duplicate" then
        renderer.pending_action = nil
        pcall(renderer.execute_duplication)
    elseif renderer.pending_action == "costume" then
        renderer.pending_action = nil
        pcall(renderer.execute_costume_swap)
    elseif renderer.pending_action == "sam" then
        renderer.pending_action = nil
        pcall(renderer.execute_sam_transaction)
    elseif renderer.pending_action == "sam_cast_npc" then
        renderer.pending_action = nil
        pcall(function() renderer.execute_sam_cast("app.ropeway.SurvivorAssignManager.CastingOrderNpc") end)
    elseif renderer.pending_action == "sam_cast_actor" then
        renderer.pending_action = nil
        pcall(function() renderer.execute_sam_cast("app.ropeway.SurvivorAssignManager.CastingOrderActor") end)
    elseif renderer.pending_action == "sam_cast_player" then
        renderer.pending_action = nil
        pcall(function() renderer.execute_sam_cast("app.ropeway.SurvivorAssignManager.CastingOrderPlayer") end)
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
    imgui.text_colored("--- Step 1: The Understander & Diagnostics ---", 0.9, 0.9, 0.2, 1.0)
    if imgui.button("Dump Full Reflection (SAM / SM / Standby)") then
        renderer.deep_dump_sam()
    end
    imgui.same_line()
    if imgui.button("Inspect Player 1 (Leon pl0000)") then
        renderer.understand_player()
    end
    imgui.same_line()
    if imgui.button("Query Active Survivors In World") then
        renderer.pending_action = "check_survivors"
    end

    imgui.separator()
    imgui.text_colored("--- Step 2: Native SAM Casting (Claire PL1000) ---", 0.2, 1.0, 0.4, 1.0)
    if imgui.button("Exp 1A: Test SAM Transaction (Verify)") then
        renderer.pending_action = "sam"
    end
    imgui.same_line()
    if imgui.button("Exp 1B: Cast Claire via CastingOrderNpc") then
        renderer.pending_action = "sam_cast_npc"
    end

    if imgui.button("Exp 1C: Cast Claire via CastingOrderActor") then
        renderer.pending_action = "sam_cast_actor"
    end
    imgui.same_line()
    if imgui.button("Exp 1D: Cast Claire via CastingOrderPlayer") then
        renderer.pending_action = "sam_cast_player"
    end

    imgui.separator()
    imgui.text_colored("--- Cleanup & Deprecated ---", 0.6, 0.6, 0.6, 1.0)
    if imgui.button("Despawn Test Character") then
        renderer.pending_action = "despawn"
    end
    imgui.same_line()
    if imgui.button("Exp 2: Duplicate Leon (Deprecated)") then
        renderer.pending_action = "duplicate"
    end

    imgui.separator()
    imgui.text_colored("--- Live Diagnostic Log ---", 0.7, 0.7, 0.7, 1.0)
    for _, line in ipairs(renderer.diagnostic_log) do
        imgui.text(line)
    end
end)

log_msg("Character Renderer Harness initialized.")
pcall(renderer.deep_dump_sam)
