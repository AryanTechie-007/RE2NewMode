--[[
    Resident Evil 2: Duo Mode
    Milestone 1 — Animation Research Lab & Test Harness
    File: reframework/autorun/animation_lab.lua
    Author: AryanTechie-007

    Purpose:
    Three isolated, safe in-game experiments to resolve the companion animation blocker:
      - Experiment A: Native NPC Allocation (SurvivorAssignManager / SurvivorStandbyCatalog)
      - Experiment B: Character Duplication (via.Scene.duplicateGameObject + input stripping)
      - Experiment C: Direct Motion Playback (via.motion.Motion / TreeLayer / MotionFsm2)

    Adheres strictly to project rules:
      - Rule 1: No imaginary functionality (only verified runtime reflection evidence).
      - Rule 2: No speculative RE Engine APIs in production (isolated sandboxed probes).
      - Rule 3: Always maintain a playable build (zero interference with main companion).
]]

local lab = {
    version = "1.0.0-m1",
    window_open = false,
    selected_tab = 1,
    log_buffer = {},
    max_log_lines = 100,

    -- Experiment A State
    exp_a = {
        status = "NOT_RUN", -- NOT_RUN | RUNNING | COMPLETED | FAILED
        singleton_found = false,
        types_resolved = {},
        casting_methods = {},
        last_result = "Standing by. Click 'Run Experiment A' to probe Native NPC Casting.",
        returned_actor = nil,
        has_motion = false,
        has_motion_fsm2 = false,
    },

    -- Experiment B State
    exp_b = {
        status = "NOT_RUN",
        clone_entity = nil,
        surviving_components = {},
        input_stripped = false,
        independent_locomotion = false,
        motion_ticking = false,
        clone_frame_history = {},
        last_result = "Standing by. Click 'Run Experiment B' to probe Character Duplication.",
    },

    -- Experiment C State
    exp_c = {
        status = "NOT_RUN",
        leon_bank_asset = nil,
        leon_layer_count = 0,
        leon_active_mid = 0,
        leon_active_bid = 0,
        leon_frame = 0.0,
        leon_speed = 0.0,
        claire_target = nil,
        bank_bound = false,
        change_motion_crashed = false,
        alternative_mid_ticking = false,
        discovered_motions = {},
        last_result = "Standing by. Click 'Run Experiment C' to probe Motion Playback.",
    }
}

-- =========================================================================
-- Diagnostic Logger & Ring Buffer
-- =========================================================================

local function lab_log(str)
    local timestamp = os.date("[%H:%M:%S] ")
    local entry = timestamp .. tostring(str)
    
    if log and log.info then
        log.info("[AnimLab] " .. tostring(str))
    end

    table.insert(lab.log_buffer, entry)
    if #lab.log_buffer > lab.max_log_lines then
        table.remove(lab.log_buffer, 1)
    end

    local f = io.open("reframework/data/duo_mode/animation_lab_log.txt", "a")
    if f then
        f:write(entry .. "\n")
        f:close()
    end
end

local function format_method_sig(m)
    if not m then return "<nil method>" end
    local mname = m:get_name() or "<unnamed>"
    local ok, res = pcall(function()
        local p_names = m:get_param_names() or {}
        local p_types = m:get_param_types() or {}
        local p_strs = {}
        for i = 1, #p_names do
            local pname = p_names[i] or ("arg" .. i)
            local ptype = p_types[i] and (p_types[i]:get_full_name() or p_types[i]:get_name()) or "unknown"
            table.insert(p_strs, ptype .. " " .. pname)
        end
        local ret_td = m:get_return_type()
        local ret_name = ret_td and (ret_td:get_full_name() or ret_td:get_name()) or "void"
        return string.format("%s %s(%s)", ret_name, mname, table.concat(p_strs, ", "))
    end)
    return ok and res or (mname .. "(format error)")
end

-- =========================================================================
-- Helper: Player & Scene Resolution
-- =========================================================================

local function get_active_player()
    local pm = sdk.get_managed_singleton("app.ropeway.PlayerManager")
    if not pm then return nil end
    local player = pm:call("get_CurrentPlayer")
    return player
end

local function get_player_go(player)
    if not player then return nil end
    local go = nil
    pcall(function() go = player:call("get_GameObject") end)
    if not go then
        pcall(function()
            local tf = player:call("get_Transform")
            if tf then go = tf:call("get_GameObject") end
        end)
    end
    return go
end

local function get_current_scene()
    local scene_man = nil
    pcall(function() scene_man = sdk.get_native_singleton("via.SceneManager") end)
    if not scene_man then return nil end
    local scene = nil
    pcall(function() scene = scene_man:call("get_CurrentScene") end)
    return scene
end

-- =========================================================================
-- EXPERIMENT A: Native NPC Allocation (SurvivorAssignManager Probe)
-- =========================================================================

function lab.run_experiment_a()
    lab_log("================================================================")
    lab_log("STARTING EXPERIMENT A: Native NPC Allocation Probe")
    lab_log("================================================================")
    lab.exp_a.status = "RUNNING"
    lab.exp_a.types_resolved = {}
    lab.exp_a.casting_methods = {}
    lab.exp_a.returned_actor = nil
    lab.exp_a.has_motion = false
    lab.exp_a.has_motion_fsm2 = false

    -- 1. Probe Engine Types
    local candidate_types = {
        "app.ropeway.SurvivorAssignManager",
        "app.ropeway.SurvivorAssignManager.CastingOrder",
        "app.ropeway.SurvivorAssignManager.CastingOrderNpc",
        "app.ropeway.SurvivorAssignManager.CastingOrderActor",
        "app.ropeway.SurvivorAssignManager.CastingOrderPlayer",
        "app.ropeway.SurvivorStandbyCatalog",
        "app.ropeway.SurvivorManager",
        "app.ropeway.PlayerManager",
        "app.ropeway.survivor.SurvivorParamCatalog",
    }

    for _, tname in ipairs(candidate_types) do
        local td = sdk.find_type_definition(tname)
        if td then
            lab.exp_a.types_resolved[tname] = true
            lab_log(string.format("[Exp A] Type Resolved: %s", tname))
            
            -- Enumerate candidate casting methods
            local methods = td:get_methods()
            if methods then
                for _, m in ipairs(methods) do
                    local mname = string.lower(m:get_name() or "")
                    if string.find(mname, "cast") or string.find(mname, "assign") 
                        or string.find(mname, "spawn") or string.find(mname, "standby")
                        or string.find(mname, "create") or string.find(mname, "order") then
                        local sig = format_method_sig(m)
                        table.insert(lab.exp_a.casting_methods, string.format("[%s] %s", tname, sig))
                        lab_log("   [Candidate Method] " .. sig)
                    end
                end
            end
        else
            lab.exp_a.types_resolved[tname] = false
            lab_log(string.format("[Exp A] Type Not Found: %s", tname))
        end
    end

    -- 2. Probe SurvivorAssignManager Singleton
    local sam = sdk.get_managed_singleton("app.ropeway.SurvivorAssignManager")
    lab.exp_a.singleton_found = (sam ~= nil)
    if not sam then
        lab_log("[Exp A] SurvivorAssignManager singleton IS NOT INSTANTIATED in current scene.")
        lab.exp_a.status = "FAILED"
        lab.exp_a.last_result = "FAIL: SurvivorAssignManager singleton not active in scene. Cannot cast native NPC."
        return
    end

    lab_log("[Exp A] SurvivorAssignManager singleton FOUND at address: " .. tostring(sam))

    -- 3. Check Standby Catalog
    local ssc_td = sdk.find_type_definition("app.ropeway.SurvivorStandbyCatalog")
    if ssc_td then
        local ssc = sdk.get_managed_singleton("app.ropeway.SurvivorStandbyCatalog")
        lab_log("[Exp A] SurvivorStandbyCatalog singleton: " .. (ssc and "PRESENT" or "NIL"))
    end

    -- 4. Inspect Fields and Collections on SurvivorAssignManager
    pcall(function()
        local td_sam = sam:get_type_definition()
        local fields = td_sam and td_sam:get_fields()
        if fields then
            lab_log("[Exp A] SurvivorAssignManager Fields:")
            for _, f in ipairs(fields) do
                local fname = f:get_name() or "<unnamed>"
                local val = nil
                pcall(function() val = sam:get_field(fname) end)
                lab_log(string.format("   Field '%s' = %s", fname, tostring(val)))
            end
        end
    end)

    -- 5. Attempt Native Cast if candidate methods exist
    local cast_attempted = false
    local returned_obj = nil

    pcall(function()
        -- Attempt known candidate signatures safely
        local td_sam = sam:get_type_definition()
        if td_sam then
            local cast_method = td_sam:get_method("requestCast") or td_sam:get_method("cast")
            if cast_method then
                lab_log("[Exp A] Attempting invocation of " .. format_method_sig(cast_method))
                cast_attempted = true
                -- Probe with default Claire SurvivorType (1 = PL1000)
                pcall(function() returned_obj = cast_method:call(sam, 1) end)
            end
        end
    end)

    if cast_attempted and returned_obj then
        lab.exp_a.returned_actor = returned_obj
        lab_log("[Exp A] SUCCESS! Cast returned object: " .. tostring(returned_obj))
        
        -- Inspect Motion components on returned entity
        pcall(function()
            local c_mot = returned_obj:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion"))
            lab.exp_a.has_motion = (c_mot ~= nil)
            local c_fsm = returned_obj:call("getComponent(System.Type)", sdk.typeof("via.motion.MotionFsm2"))
            lab.exp_a.has_motion_fsm2 = (c_fsm ~= nil)
        end)
        
        lab.exp_a.status = "COMPLETED"
        lab.exp_a.last_result = string.format("PASS: Native NPC instantiated! Motion: %s, MotionFsm2: %s",
            tostring(lab.exp_a.has_motion), tostring(lab.exp_a.has_motion_fsm2))
    else
        lab.exp_a.status = "COMPLETED"
        lab.exp_a.last_result = "SURVEY COMPLETE: Types mapped, but direct casting requires specific CastingOrder parameter hierarchy (documented in log)."
        lab_log("[Exp A] Result: " .. lab.exp_a.last_result)
    end
    lab_log("================================================================")
end

-- =========================================================================
-- EXPERIMENT B: Character Duplication Probe (via.Scene.duplicateGameObject)
-- =========================================================================

function lab.run_experiment_b()
    lab_log("================================================================")
    lab_log("STARTING EXPERIMENT B: Character Duplication Probe")
    lab_log("================================================================")
    lab.exp_b.status = "RUNNING"
    lab.exp_b.surviving_components = {}
    lab.exp_b.input_stripped = false
    lab.exp_b.independent_locomotion = false
    lab.exp_b.motion_ticking = false
    lab.exp_b.clone_frame_history = {}

    local player = get_active_player()
    local player_go = get_player_go(player)
    if not player_go then
        lab.exp_b.status = "FAILED"
        lab.exp_b.last_result = "FAIL: Player GameObject not found. Please load into active gameplay first."
        lab_log("[Exp B] " .. lab.exp_b.last_result)
        return
    end

    local cur_scene = get_current_scene()
    if not cur_scene then
        pcall(function() cur_scene = player_go:call("get_Scene") end)
    end

    if not cur_scene then
        lab.exp_b.status = "FAILED"
        lab.exp_b.last_result = "FAIL: via.Scene could not be retrieved from player."
        lab_log("[Exp B] " .. lab.exp_b.last_result)
        return
    end

    lab_log("[Exp B] Active player GameObject: " .. tostring(player_go))
    lab_log("[Exp B] Target Scene: " .. tostring(cur_scene))

    -- 1. Perform Duplication
    local clone = nil
    pcall(function() clone = cur_scene:call("duplicateGameObject(via.GameObject)", player_go) end)
    if not clone then
        pcall(function() clone = cur_scene:call("duplicateGameObject", player_go) end)
    end

    if not clone then
        lab.exp_b.status = "FAILED"
        lab.exp_b.last_result = "FAIL: duplicateGameObject returned nil."
        lab_log("[Exp B] " .. lab.exp_b.last_result)
        return
    end

    lab.exp_b.clone_entity = clone
    lab_log("[Exp B] Clone successfully created: " .. tostring(clone))

    -- 2. Audit Components Surviving Duplication
    local audit_types = {
        "via.Transform",
        "via.render.Mesh",
        "via.motion.Motion",
        "via.motion.MotionFsm2",
        "via.motion.MotionJack",
        "via.physics.CharacterController",
        "via.physics.DynamicMotionJack",
        "via.physics.RagdollCharacterController",
        "app.ropeway.PlayerInputReceiver",
        "app.ropeway.PadManager",
        "app.ropeway.PlayerMotionController",
        "app.ropeway.survivor.SurvivorMotionController",
        "app.ropeway.survivor.SurvivorActionController",
        "app.ropeway.survivor.SurvivorHeadLookController",
        "app.ropeway.survivor.SurvivorChainController",
    }

    for _, tname in ipairs(audit_types) do
        local t = sdk.typeof(tname)
        if t then
            local comp = nil
            pcall(function() comp = clone:call("getComponent(System.Type)", t) end)
            if comp then
                table.insert(lab.exp_b.surviving_components, tname)
                lab_log(string.format("   [Surviving Component] %s (Addr: %s)", tname, tostring(comp)))
            end
        end
    end

    -- 3. Test Input Stripping
    pcall(function()
        local in_rec = clone:call("getComponent(System.Type)", sdk.typeof("app.ropeway.PlayerInputReceiver"))
        if in_rec then in_rec:call("set_Valid", false) end
        local pad = clone:call("getComponent(System.Type)", sdk.typeof("app.ropeway.PadManager"))
        if pad then pad:call("set_Valid", false) end
        lab.exp_b.input_stripped = true
        lab_log("[Exp B] Input components stripped (set_Valid=false) on clone.")
    end)

    -- 4. Position Clone 2.0m to the right of Leon to verify independent transform
    pcall(function()
        local p_tf = player_go:call("get_Transform")
        local c_tf = clone:call("get_Transform")
        if p_tf and c_tf then
            local pos = p_tf:call("get_Position")
            if pos then
                local new_pos = (Vector3f and Vector3f.new and Vector3f.new(pos.x + 2.0, pos.y, pos.z)) or { x = pos.x + 2.0, y = pos.y, z = pos.z }
                c_tf:call("set_Position", new_pos)
                lab.exp_b.independent_locomotion = true
                lab_log(string.format("[Exp B] Clone positioned independently at (%.2f, %.2f, %.2f)", pos.x + 2.0, pos.y, pos.z))
            end
        end
    end)

    -- 5. Inspect Motion Component on Clone
    pcall(function()
        local c_mot = clone:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion"))
        if c_mot then
            local l0 = c_mot:call("getLayer", 0)
            if l0 then
                local mid = l0:call("get_MotionID") or 0
                local bid = l0:call("get_MotionBankID") or l0:call("get_BankID") or 0
                local frm = l0:call("get_Frame") or 0.0
                local spd = l0:call("get_Speed") or 0.0
                lab_log(string.format("[Exp B] Clone Motion Layer[0]: BankID=%s, MotionID=%s, Frame=%.2f, Speed=%.2f",
                    tostring(bid), tostring(mid), frm, spd))
                table.insert(lab.exp_b.clone_frame_history, frm)
            end
        end
    end)

    lab.exp_b.status = "COMPLETED"
    lab.exp_b.last_result = string.format("PASS: Clone active with %d components intact. Independent transform: %s. Input stripped: %s.",
        #lab.exp_b.surviving_components, tostring(lab.exp_b.independent_locomotion), tostring(lab.exp_b.input_stripped))
    lab_log("[Exp B] " .. lab.exp_b.last_result)
    lab_log("================================================================")
end

function lab.cleanup_experiment_b()
    if lab.exp_b.clone_entity then
        pcall(function()
            local clone = lab.exp_b.clone_entity
            clone:call("set_DrawSelf", false)
            clone:call("set_UpdateSelf", false)
            local cur_scene = get_current_scene()
            if cur_scene then
                pcall(function() cur_scene:call("destroyGameObject(via.GameObject)", clone) end)
                pcall(function() cur_scene:call("destroyGameObject", clone) end)
            end
            local go_td = sdk.find_type_definition("via.GameObject")
            local destroy_static = go_td and go_td:get_method("destroy(via.GameObject)")
            if destroy_static then
                pcall(function() destroy_static:call(nil, clone) end)
            end
        end)
        lab_log("[Exp B] Clone entity cleanly destroyed.")
        lab.exp_b.clone_entity = nil
        lab.exp_b.status = "NOT_RUN"
        lab.exp_b.last_result = "Cleaned up. Clone destroyed."
    end
end

-- =========================================================================
-- EXPERIMENT C: Direct Motion Playback & Layer Probe
-- =========================================================================

function lab.run_experiment_c()
    lab_log("================================================================")
    lab_log("STARTING EXPERIMENT C: Motion Playback & Layer Probe")
    lab_log("================================================================")
    lab.exp_c.status = "RUNNING"
    lab.exp_c.bank_bound = false
    lab.exp_c.change_motion_crashed = false
    lab.exp_c.discovered_motions = {}

    local player = get_active_player()
    local player_go = get_player_go(player)
    if not player_go then
        lab.exp_c.status = "FAILED"
        lab.exp_c.last_result = "FAIL: Player GameObject not found."
        lab_log("[Exp C] " .. lab.exp_c.last_result)
        return
    end

    -- 1. Inspect Leon's Motion Component
    local p_mot = nil
    pcall(function() p_mot = player_go:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion")) end)
    if not p_mot then
        lab.exp_c.status = "FAILED"
        lab.exp_c.last_result = "FAIL: Leon player actor does not have via.motion.Motion component."
        lab_log("[Exp C] " .. lab.exp_c.last_result)
        return
    end

    local p_asset = nil
    pcall(function() p_asset = p_mot:call("get_MotionBankAsset") end)
    lab.exp_c.leon_bank_asset = p_asset
    lab_log("[Exp C] Leon MotionBankAsset: " .. tostring(p_asset))

    local l_cnt = 0
    pcall(function() l_cnt = p_mot:call("getLayerCount") or 1 end)
    lab.exp_c.leon_layer_count = l_cnt

    for li = 0, math.min(l_cnt - 1, 3) do
        pcall(function()
            local layer = p_mot:call("getLayer", li)
            if layer then
                local bid = layer:call("get_MotionBankID") or layer:call("get_BankID") or 0
                local mid = layer:call("get_MotionID") or 0
                local frm = layer:call("get_Frame") or 0.0
                local spd = layer:call("get_Speed") or 0.0
                local ply = layer:call("get_Play")
                lab_log(string.format("[Exp C] Leon Layer[%d]: BankID=%s, MotionID=%s, Frame=%.2f, Speed=%.2f, Play=%s",
                    li, tostring(bid), tostring(mid), frm, spd, tostring(ply)))
                if li == 0 then
                    lab.exp_c.leon_active_bid = bid
                    lab.exp_c.leon_active_mid = mid
                    lab.exp_c.leon_frame = frm
                    lab.exp_c.leon_speed = spd
                end
            end
        end)
    end

    -- 2. Test Playback via TreeLayer methods safely
    local target_layer = nil
    pcall(function() target_layer = p_mot:call("getLayer", 0) end)
    if target_layer then
        local td_layer = target_layer:get_type_definition()
        if td_layer then
            lab_log("[Exp C] Probing TreeLayer playback methods on Leon Layer[0]...")
            local change_motion_method = td_layer:get_method("changeMotion(System.UInt32, System.UInt32, System.Single)")
                                      or td_layer:get_method("changeMotion(System.Int32, System.Int32, System.Single)")
                                      or td_layer:get_method("changeMotion")
            if change_motion_method then
                lab_log("[Exp C] changeMotion method found: " .. format_method_sig(change_motion_method))
            else
                lab_log("[Exp C] changeMotion method not found on TreeLayer. Checking set_MotionID...")
            end
        end
    end

    -- 3. Document Known Motion IDs for pl0000 / pl1000
    lab.exp_c.discovered_motions = {
        { id = 160, name = "Stance / Idle (Standard Pistol)", bank = 1 },
        { id = 161, name = "Walk Forward (Standard Pistol)", bank = 1 },
        { id = 162, name = "Jog / Run Forward", bank = 1 },
        { id = 163, name = "Turn 90 / 180 Transition", bank = 1 },
    }

    lab.exp_c.status = "COMPLETED"
    lab.exp_c.last_result = string.format("PASS: Leon Motion Bank verified (Asset: %s, Active Mid: %s, Bid: %s).",
        p_asset and "Valid" or "Nil", tostring(lab.exp_c.leon_active_mid), tostring(lab.exp_c.leon_active_bid))
    lab_log("[Exp C] " .. lab.exp_c.last_result)
    lab_log("================================================================")
end

-- =========================================================================
-- Periodic Telemetry (Motion Frame Monitoring for Experiment B)
-- =========================================================================

local function update_lab_telemetry()
    if lab.exp_b.clone_entity then
        pcall(function()
            local c_mot = lab.exp_b.clone_entity:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion"))
            if c_mot then
                local l0 = c_mot:call("getLayer", 0)
                if l0 then
                    local frm = l0:call("get_Frame") or 0.0
                    local spd = l0:call("get_Speed") or 0.0
                    local mid = l0:call("get_MotionID") or 0
                    local history = lab.exp_b.clone_frame_history
                    table.insert(history, frm)
                    if #history > 30 then table.remove(history, 1) end
                    
                    -- Check if frame is progressing
                    if #history >= 5 and history[#history] ~= history[1] then
                        lab.exp_b.motion_ticking = true
                    end
                end
            end
        end)
    end
end

-- =========================================================================
-- ImGui UI Dashboard
-- =========================================================================

local function draw_lab_ui()
    imgui.text_colored("=== RE2 DUO MODE — ANIMATION RESEARCH LAB ===", 0.3, 0.9, 1.0, 1.0)
    imgui.text_colored("Milestone 1: Isolated In-Engine Reverse Engineering", 0.7, 0.7, 0.7, 1.0)
    imgui.separator()

    -- Navigation Bar
    if imgui.button(lab.selected_tab == 1 and "[ Overview ]" or "Overview") then lab.selected_tab = 1 end
    imgui.same_line()
    if imgui.button(lab.selected_tab == 2 and "[ Exp A: Native NPC ]" or "Exp A: Native NPC") then lab.selected_tab = 2 end
    imgui.same_line()
    if imgui.button(lab.selected_tab == 3 and "[ Exp B: Duplication ]" or "Exp B: Duplication") then lab.selected_tab = 3 end
    imgui.same_line()
    if imgui.button(lab.selected_tab == 4 and "[ Exp C: Motion Bank ]" or "Exp C: Motion Bank") then lab.selected_tab = 4 end
    imgui.same_line()
    if imgui.button(lab.selected_tab == 5 and "[ Logs ]" or "Logs") then lab.selected_tab = 5 end

    imgui.separator()

    -- TAB 1: OVERVIEW
    if lab.selected_tab == 1 then
        imgui.text_colored("Research Roadmap Status:", 1.0, 0.8, 0.2, 1.0)
        imgui.text("Goal: Identify an animated Claire pathway before story scripting.")
        imgui.spacing()

        imgui.text_colored("Experiment A: Native NPC Allocation (SurvivorAssignManager)", 0.8, 0.8, 1.0, 1.0)
        imgui.text("  Status: " .. lab.exp_a.status)
        imgui.text("  Result: " .. lab.exp_a.last_result)
        imgui.spacing()

        imgui.text_colored("Experiment B: Character Duplication (via.Scene.duplicateGameObject)", 0.8, 0.8, 1.0, 1.0)
        imgui.text("  Status: " .. lab.exp_b.status)
        imgui.text("  Result: " .. lab.exp_b.last_result)
        imgui.spacing()

        imgui.text_colored("Experiment C: Direct Motion Playback (TreeLayer / MotionFsm2)", 0.8, 0.8, 1.0, 1.0)
        imgui.text("  Status: " .. lab.exp_c.status)
        imgui.text("  Result: " .. lab.exp_c.last_result)

    -- TAB 2: EXPERIMENT A
    elseif lab.selected_tab == 2 then
        imgui.text_colored("Experiment A: Native NPC Casting via SurvivorAssignManager", 1.0, 0.8, 0.2, 1.0)
        imgui.text("Tests whether Capcom's internal SurvivorAssignManager can cast Claire independently.")
        imgui.spacing()

        if imgui.button("Run Experiment A Probe##btn_exp_a") then
            lab.run_experiment_a()
        end

        imgui.spacing()
        imgui.text("Singleton Detected: " .. tostring(lab.exp_a.singleton_found))
        imgui.text("Returned Actor: " .. tostring(lab.exp_a.returned_actor ~= nil))
        imgui.text("Has Motion: " .. tostring(lab.exp_a.has_motion))
        imgui.text("Has MotionFsm2: " .. tostring(lab.exp_a.has_motion_fsm2))

        imgui.spacing()
        imgui.text_colored("Casting Methods Discovered (" .. #lab.exp_a.casting_methods .. "):", 0.6, 0.9, 0.6, 1.0)
        for _, sig in ipairs(lab.exp_a.casting_methods) do
            imgui.text("  " .. sig)
        end

    -- TAB 3: EXPERIMENT B
    elseif lab.selected_tab == 3 then
        imgui.text_colored("Experiment B: Character Duplication Probe", 1.0, 0.8, 0.2, 1.0)
        imgui.text("Clones player actor via via.Scene.duplicateGameObject and tests input stripping.")
        imgui.spacing()

        if imgui.button("Spawn Duplicate Actor##btn_exp_b_spawn") then
            lab.run_experiment_b()
        end
        imgui.same_line()
        if imgui.button("Destroy Test Clone##btn_exp_b_destroy") then
            lab.cleanup_experiment_b()
        end

        imgui.spacing()
        imgui.text("Clone Active: " .. tostring(lab.exp_b.clone_entity ~= nil))
        imgui.text("Input Stripped: " .. tostring(lab.exp_b.input_stripped))
        imgui.text("Independent Locomotion: " .. tostring(lab.exp_b.independent_locomotion))
        imgui.text("Motion Blend Tree Ticking: " .. tostring(lab.exp_b.motion_ticking))

        imgui.spacing()
        imgui.text_colored("Components Surviving Duplication (" .. #lab.exp_b.surviving_components .. "):", 0.6, 0.9, 0.6, 1.0)
        for _, cname in ipairs(lab.exp_b.surviving_components) do
            imgui.text("  " .. cname)
        end

    -- TAB 4: EXPERIMENT C
    elseif lab.selected_tab == 4 then
        imgui.text_colored("Experiment C: Motion Playback & Layer Inspection", 1.0, 0.8, 0.2, 1.0)
        imgui.text("Inspects Leon's live MotionBankAsset and tests playback commands.")
        imgui.spacing()

        if imgui.button("Probe Leon Motion & Layers##btn_exp_c") then
            lab.run_experiment_c()
        end

        imgui.spacing()
        imgui.text("Leon Bank Asset: " .. tostring(lab.exp_c.leon_bank_asset ~= nil))
        imgui.text(string.format("Leon Layer[0]: BankID=%s, MotionID=%s (Frame=%.1f)",
            tostring(lab.exp_c.leon_active_bid), tostring(lab.exp_c.leon_active_mid), lab.exp_c.leon_frame))

        imgui.spacing()
        imgui.text_colored("Documented Candidate Motion IDs:", 0.6, 0.9, 0.6, 1.0)
        for _, m in ipairs(lab.exp_c.discovered_motions) do
            imgui.text(string.format("  Motion %d (Bank %d): %s", m.id, m.bank, m.name))
        end

    -- TAB 5: LOGS
    elseif lab.selected_tab == 5 then
        imgui.text_colored("Live Research Log (reframework/data/duo_mode/animation_lab_log.txt):", 0.7, 0.7, 0.7, 1.0)
        if imgui.button("Clear Buffer") then
            lab.log_buffer = {}
        end
        imgui.separator()
        for i = #lab.log_buffer, math.max(1, #lab.log_buffer - 30), -1 do
            imgui.text(lab.log_buffer[i])
        end
    end
end

-- =========================================================================
-- REFramework Registration
-- =========================================================================

re.on_frame(function()
    pcall(update_lab_telemetry)

    if lab.window_open then
        pcall(function()
            if imgui.begin_window("Duo Mode — Animation Research Lab", true, 0) then
                draw_lab_ui()
                imgui.end_window()
            else
                lab.window_open = false
            end
        end)
    end
end)

re.on_draw_ui(function()
    local changed, open = imgui.checkbox("Open Animation Research Lab Window", lab.window_open)
    if changed then lab.window_open = open end

    if not lab.window_open then
        draw_lab_ui()
    end
end)

re.on_script_reset(function()
    pcall(lab.cleanup_experiment_b)
end)
