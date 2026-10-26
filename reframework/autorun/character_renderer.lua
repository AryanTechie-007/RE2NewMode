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
    end
end

log_msg("=== Character Renderer Harness Loading ===")

local renderer = {}
renderer.spawned_entity = nil
renderer.diagnostic_log = {}
renderer.last_status = "Ready - Standing by"

local function add_diag(text)
    table.insert(renderer.diagnostic_log, 1, os.date("[%H:%M:%S] ") .. text)
    if #renderer.diagnostic_log > 15 then
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

    local go = renderer.get_player_game_object(player)
    if not go then
        add_diag("ERROR: Player GameObject not found.")
        return
    end

    add_diag(string.format("Player GameObject Name: '%s'", tostring(go.call and go:call("get_Name"))))

    -- List components
    local comps = nil
    pcall(function()
        if go.get_components then comps = go:get_components() end
    end)

    if comps and #comps > 0 then
        add_diag(string.format("Player has %d components attached:", #comps))
        for i, c in ipairs(comps) do
            local td = c:get_type_definition()
            add_diag(string.format("   [%d] %s", i, td and td:get_full_name() or "Unknown"))
        end
    else
        add_diag("Could not enumerate components directly via get_components.")
    end

    -- Inspect Mesh component
    local mesh_td = sdk.find_type_definition("via.render.Mesh")
    if mesh_td then
        local mesh = nil
        pcall(function() mesh = go:call("getComponent(System.Type)", mesh_td:get_runtime_type()) end)
        if mesh then
            local draw_mesh = false
            pcall(function() draw_mesh = mesh:call("get_DrawMesh") end)
            add_diag(string.format("Player Mesh Component: DrawMesh=%s", tostring(draw_mesh)))
        else
            add_diag("Player Mesh Component: NOT FOUND on root GameObject")
        end
    end

    -- Inspect Motion component
    local motion_td = sdk.find_type_definition("via.motion.Motion")
    if motion_td then
        local motion = nil
        pcall(function() motion = go:call("getComponent(System.Type)", motion_td:get_runtime_type()) end)
        if motion then
            add_diag("Player Motion Component: PRESENT and active.")
        end
    end
end

function renderer.understand_subsystems()
    add_diag("Running Understander: Inspecting Survivor Subsystems...")
    local types = {
        "app.ropeway.SurvivorAssignManager",
        "app.ropeway.SurvivorAssignManager.CastingOrder",
        "app.ropeway.SurvivorAssignManager.CastingOrderNpc",
        "app.ropeway.SurvivorAssignManager.CastingOrderActor",
        "app.ropeway.SurvivorStandbyCatalog",
        "app.ropeway.SurvivorManager",
        "app.ropeway.PlayerManager"
    }

    for _, tname in ipairs(types) do
        local td = sdk.find_type_definition(tname)
        if td then
            local methods = td:get_methods() or {}
            local fields = td:get_fields() or {}
            add_diag(string.format("FOUND %s: %d methods, %d fields", tname, #methods, #fields))
            for _, m in ipairs(methods) do
                local mname = m:get_name()
                if string.find(string.lower(mname), "cast") or string.find(string.lower(mname), "order") or string.find(string.lower(mname), "request") or string.find(string.lower(mname), "create") then
                    add_diag(string.format("   -> Method: %s (%d params)", mname, m:get_num_params()))
                end
            end
        else
            add_diag("NOT FOUND: " .. tname)
        end
    end

    local sam = sdk.get_managed_singleton("app.ropeway.SurvivorAssignManager")
    add_diag("SurvivorAssignManager Singleton: " .. (sam and "ONLINE" or "OFFLINE"))

    local sm = sdk.get_managed_singleton("app.ropeway.SurvivorManager")
    add_diag("SurvivorManager Singleton: " .. (sm and "ONLINE" or "OFFLINE"))
end

-- =========================================================================
-- 4. The "RENDERER": Isolated Spawning Experiments
-- =========================================================================

-- Clean up any previous test entity
function renderer.despawn_test_entity()
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

-- Experiment 1: Native SurvivorAssignManager Casting
function renderer.test_native_casting()
    renderer.despawn_test_entity()
    add_diag("Attempting Experiment 1: Native SurvivorAssignManager Casting...")

    local sam = sdk.get_managed_singleton("app.ropeway.SurvivorAssignManager")
    if not sam then
        add_diag("FAIL: SurvivorAssignManager singleton not active in this scene.")
        renderer.last_status = "Failed: SurvivorAssignManager is nil"
        return
    end

    -- Check available casting methods on SAM
    local sam_td = sam:get_type_definition()
    local methods = sam_td:get_methods()
    add_diag("Inspecting SAM methods for casting trigger...")
    local casting_order_method = nil
    for _, m in ipairs(methods) do
        local n = m:get_name()
        if string.find(string.lower(n), "casting") or string.find(string.lower(n), "request") then
            add_diag(string.format("SAM method: %s (%d params)", n, m:get_num_params()))
            if not casting_order_method then casting_order_method = m end
        end
    end

    renderer.last_status = "SAM inspected - Check log for method signatures"
end

-- Experiment 2: Character Duplication Directly In Front of Leon
function renderer.test_character_duplication()
    renderer.despawn_test_entity()
    add_diag("Attempting Experiment 2: Character Duplication in Viewport...")

    local player = renderer.get_master_player()
    local player_go = renderer.get_player_game_object(player)
    if not player_go then
        add_diag("FAIL: Master player GameObject not resolved.")
        renderer.last_status = "Failed: Player GO not found"
        return
    end

    local player_tf = player_go:call("get_Transform")
    if not player_tf then
        add_diag("FAIL: Player Transform not resolved.")
        renderer.last_status = "Failed: Player Transform not found"
        return
    end

    -- Spawn position: 2.0 meters directly IN FRONT of Leon!
    local front_pos = get_front_spawn_position(player_tf, 2.0)
    add_diag(string.format("Calculated Viewport Spawn Target: (%.2f, %.2f, %.2f)", front_pos.x, front_pos.y, front_pos.z))

    local scene_man = sdk.get_native_singleton("via.SceneManager")
    local cur_scene = scene_man and scene_man:call("get_CurrentScene")
    if not cur_scene then
        add_diag("FAIL: via.Scene not available.")
        renderer.last_status = "Failed: Scene not found"
        return
    end

    local clone = nil
    local ok1 = pcall(function()
        clone = cur_scene:call("duplicateGameObject(via.GameObject)", player_go)
    end)
    if not ok1 or not clone then
        pcall(function() clone = cur_scene:call("duplicateGameObject", player_go) end)
    end

    if not clone then
        add_diag("FAIL: duplicateGameObject returned nil.")
        renderer.last_status = "Failed: duplicateGameObject returned nil"
        return
    end

    pcall(function() clone:add_ref() end)

    -- Move clone to front position
    local clone_tf = clone:call("get_Transform")
    if clone_tf then
        clone_tf:call("set_Position", front_pos)
        add_diag("Repositioned clone 2.0m directly in front of Leon.")
    end

    -- Ensure mesh is drawing
    pcall(function()
        clone:call("set_DrawSelf", true)
        clone:call("set_UpdateSelf", true)
        local mesh_td = sdk.find_type_definition("via.render.Mesh")
        if mesh_td then
            local mesh = clone:call("getComponent(System.Type)", mesh_td:get_runtime_type())
            if mesh then
                mesh:call("set_DrawMesh", true)
                mesh:set_field("Enabled", true)
                add_diag("Forced set_DrawMesh(true) on clone Mesh component.")
            end
        end
    end)

    -- Disable gamepad input mirroring on clone
    local input_td = sdk.find_type_definition("app.ropeway.survivor.PlayerInputReceiver")
                  or sdk.find_type_definition("app.ropeway.PlayerInputReceiver")
    if input_td then
        pcall(function()
            local inp = clone:call("getComponent(System.Type)", input_td:get_runtime_type())
            if inp then inp:set_field("Enabled", false) end
        end)
    end

    renderer.spawned_entity = clone
    renderer.last_status = "SUCCESS: Cloned Player In Front of Leon"
    add_diag("SUCCESS: Cloned entity placed in viewport! Look directly ahead.")
end

-- Experiment 3: Swap Clone Costume/Model to Claire (PL1000)
function renderer.test_costume_swap()
    if not renderer.spawned_entity then
        add_diag("ERROR: No active test entity spawned. Run Experiment 2 first.")
        renderer.last_status = "Error: Spawn entity first"
        return
    end

    add_diag("Attempting Experiment 3: Swapping Clone to Claire (PL1000)...")
    local survivor_man = sdk.get_managed_singleton("app.ropeway.SurvivorManager")
    if not survivor_man then
        add_diag("FAIL: SurvivorManager singleton not available.")
        renderer.last_status = "Failed: SurvivorManager is nil"
        return
    end

    local swapped = false
    -- Try requestCostumeChange(clone, 1) -> 1 = Claire
    pcall(function()
        survivor_man:call("requestCostumeChange", renderer.spawned_entity, 1)
        swapped = true
        add_diag("Called SurvivorManager:requestCostumeChange(clone, 1 [Claire]).")
    end)

    if not swapped then
        pcall(function()
            survivor_man:call("changeCostume", renderer.spawned_entity, 1)
            swapped = true
            add_diag("Called SurvivorManager:changeCostume(clone, 1 [Claire]).")
        end)
    end

    if swapped then
        renderer.last_status = "Costume Swap Requested (Check Viewport)"
    else
        renderer.last_status = "Costume Swap Failed"
    end
end

-- =========================================================================
-- 5. ImGui Control Panel & HUD
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
    imgui.text_colored("--- Step 1: The Understander ---", 0.9, 0.9, 0.2, 1.0)
    if imgui.button("Inspect Player 1 (Leon Components)") then
        renderer.understand_player()
    end
    imgui.same_line()
    if imgui.button("Inspect Survivor Subsystems (SAM / SM)") then
        renderer.understand_subsystems()
    end

    imgui.separator()
    imgui.text_colored("--- Step 2: The Renderer Experiments ---", 0.2, 1.0, 0.4, 1.0)
    if imgui.button("Experiment 2: Duplicate Leon In Front (2.0m)") then
        renderer.test_character_duplication()
    end
    imgui.same_line()
    if imgui.button("Experiment 3: Swap Clone to Claire (PL1000)") then
        renderer.test_costume_swap()
    end

    if imgui.button("Experiment 1: Test Native SAM Casting") then
        renderer.test_native_casting()
    end
    imgui.same_line()
    if imgui.button("Despawn Test Character") then
        renderer.despawn_test_entity()
    end

    imgui.separator()
    imgui.text_colored("--- Live Diagnostic Log ---", 0.7, 0.7, 0.7, 1.0)
    for _, line in ipairs(renderer.diagnostic_log) do
        imgui.text(line)
    end
end)

log_msg("Character Renderer Harness initialized.")
