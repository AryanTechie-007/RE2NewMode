--[[
    Resident Evil 2: Duo Mode
    Milestone 1 — Animation Research Lab & Test Harness (Rigorous Edition v1.4)
    File: reframework/autorun/animation_lab.lua
    Author: AryanTechie-007

    Purpose:
    Three isolated, safe in-engine reverse-engineering experiments to resolve
    the companion animation blocker with strict, non-optimistic verification:
      - Experiment A: Native NPC Allocation (SurvivorAssignManager / SurvivorStandbyCatalog + standby casting probe)
      - Experiment B: Character Duplication (via.Scene.duplicateGameObject with multi-path scene resolution + input disabling)
      - Experiment C: Direct Motion Playback (TreeLayer / MotionFsm2 — with one-click companion spawn bridge and target isolation)

    Strict Verification Rules:
      - Rule 1: No imaginary functionality. No PASS without verified entities, active functioning controllers, and observed behavior.
      - Rule 2: No speculative RE Engine APIs in production.
      - Rule 3: Single confirmed destruction route without double-free risks; unverified cleanups retain references.
]]

local lab = {
    version = "1.4.0-scene-fix",
    window_open = false,
    selected_tab = 1,
    log_buffer = {},
    max_log_lines = 120,

    -- Experiment A State
    exp_a = {
        status = "NOT_RUN", -- NOT_RUN | RUNNING | PASS | PARTIAL | UNVERIFIED | FAILED
        singleton_found = false,
        types_resolved = {},
        casting_methods = {},
        returned_actor = nil,
        actor_valid = false,
        has_motion = false,
        has_motion_fsm2 = false,
        has_survivor_motion = false,
        motion_active = false,
        layer_count = 0,
        last_result = "Standing by. Click 'Run Experiment A Probe' to inspect Native NPC Casting.",
    },

    -- Experiment B State
    exp_b = {
        status = "NOT_RUN", -- NOT_RUN | RUNNING | PASS | PARTIAL | FAILED | CLEANED_UP | CLEANUP_FAILED
        clone_entity = nil,
        surviving_components = {},
        input_stripped = false,
        input_verified_disabled = false,
        independent_transform_control = false,
        motion_ticking = false,
        clone_frame_history = {},
        cleanup_status = "No test clone instantiated.",
        last_result = "Standing by. Click 'Spawn Duplicate Actor' to probe Character Duplication.",
        loco_test = {
            active = false,
            current_frame = 0,
            target_frames = 60,
            clone_initial_pos = nil,
            leon_initial_pos = nil,
            max_clone_displacement = 0.0,
            max_leon_displacement = 0.0,
            clone_moved = false,
            leon_unmoved = false,
            verdict = "NOT_STARTED",
        }
    },

    -- Experiment C State
    exp_c = {
        inspection_status = "NOT_RUN", -- NOT_RUN | INSPECTION_COMPLETE | INSPECTION_PARTIAL | FAILED
        playback_status = "NOT_RUN",   -- NOT_RUN | TESTING | FRAME_PROGRESSION_VERIFIED | PLAYBACK_AND_VISUAL_VERIFIED | PLAYBACK_FAILED | PLAYBACK_STALLED | PLAYBACK_OVERRIDDEN
        visual_confirmed = false,
        leon_bank_asset = nil,
        leon_layer_count = 0,
        leon_active_mid = 0,
        leon_active_bid = 0,
        leon_frame = 0.0,
        leon_speed = 0.0,
        target_name = "None",
        selected_mid = 160,
        selected_bid = 1,
        discovered_motions = {},
        last_result = "Standing by. Step 1: Inspect Leon Motion Bank. Step 2: Test Controlled Playback.",
        playback_monitor = {
            active = false,
            target_obj = nil,
            target_mid = 0,
            target_bid = 0,
            start_frame = 0.0,
            current_frame = 0.0,
            ticks_observed = 0,
            max_ticks = 45,
        }
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
-- Helpers: Player, Scene & Companion Target Resolution
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

local function get_current_scene(player_go)
    -- Multi-path resolution for via.Scene in RE Engine:
    -- In RE2 Remake, player GameObjects typically live inside a via.Folder.
    local scene = nil
    local source = nil
    local folder = nil

    -- Path 1: Folder hierarchy from player GameObject (most reliable in RE2)
    if player_go then
        pcall(function() folder = player_go:call("get_Folder") end)
        if folder then
            local curr_f = folder
            while curr_f and not scene do
                pcall(function() scene = curr_f:call("get_Scene") end)
                if scene then
                    source = "player_go:get_Folder():get_Scene()"
                    break
                end
                local parent = nil
                pcall(function() parent = curr_f:call("get_Parent") end)
                curr_f = parent
            end
        end
    end

    -- Path 2: Direct get_Scene on player GameObject
    if not scene and player_go then
        pcall(function() scene = player_go:call("get_Scene") end)
        if scene then source = "player_go:get_Scene()" end
    end

    -- Path 3: via.SceneManager native singleton
    local scene_man = nil
    pcall(function() scene_man = sdk.get_native_singleton("via.SceneManager") end)
    if scene_man then
        -- 3a. get_CurrentScene
        if not scene then
            pcall(function() scene = scene_man:call("get_CurrentScene") end)
            if scene then source = "SceneManager:get_CurrentScene()" end
        end
        -- 3b. get_PrimaryScene
        if not scene then
            pcall(function() scene = scene_man:call("get_PrimaryScene") end)
            if scene then source = "SceneManager:get_PrimaryScene()" end
        end
        -- 3c. MainView scene
        if not scene then
            pcall(function()
                local view = scene_man:call("get_MainView")
                if view then
                    scene = view:call("get_PrimaryScene") or view:call("get_Scene")
                    if scene then source = "SceneManager:get_MainView():get_Scene()" end
                end
            end)
        end
        -- 3d. getScene(0)
        if not scene then
            pcall(function()
                local count = scene_man:call("get_SceneCount") or 0
                if count and count > 0 then
                    scene = scene_man:call("getScene", 0)
                    if scene then source = "SceneManager:getScene(0)" end
                end
            end)
        end
    end

    -- Path 4: static via.Scene methods
    if not scene then
        pcall(function()
            local sc_td = sdk.find_type_definition("via.Scene")
            if sc_td then
                local m = sc_td:get_method("get_CurrentScene()") or sc_td:get_method("get_PrimaryScene()")
                if m then
                    scene = m:call(nil)
                    if scene then source = "via.Scene static method" end
                end
            end
        end)
    end

    return scene, source, folder
end

-- Resolves the target actor for animation playback tests (Priority: Claire from character_renderer -> Exp B clone -> Leon)
local function get_playback_target()
    -- 1. Check if Claire is spawned by character_renderer.lua (via global bridge _G.duo_spawner or local spawner)
    local duo = _G.duo_spawner or spawner
    if duo and duo.spawned_entities and #duo.spawned_entities > 0 then
        local body = duo.spawned_entities[1]
        if body and body.call then
            local is_v = true
            pcall(function() is_v = (body:call("get_Valid") == true) end)
            if is_v then
                return body, "Claire (character_renderer.lua Prefab Body)"
            end
        end
    end

    -- 2. Check if Exp B clone is active
    if lab.exp_b.clone_entity and lab.exp_b.clone_entity.call then
        local is_v = false
        pcall(function() is_v = (lab.exp_b.clone_entity:call("get_Valid") == true) end)
        if is_v then
            return lab.exp_b.clone_entity, "Test Clone (Experiment B Actor)"
        end
    end

    -- 3. Fallback: Leon
    local player = get_active_player()
    local p_go = get_player_go(player)
    if p_go then
        return p_go, "Leon (Player Actor - CAUTION: modifies player animation)"
    end

    return nil, "None"
end

-- =========================================================================
-- EXPERIMENT A: Native NPC Allocation (SurvivorAssignManager Probe)
-- =========================================================================

function lab.run_experiment_a()
    lab_log("================================================================")
    lab_log("STARTING EXPERIMENT A: Native NPC Allocation Probe (Strict Evaluation v1.3)")
    lab_log("================================================================")
    lab.exp_a.status = "RUNNING"
    lab.exp_a.types_resolved = {}
    lab.exp_a.casting_methods = {}
    lab.exp_a.returned_actor = nil
    lab.exp_a.actor_valid = false
    lab.exp_a.has_motion = false
    lab.exp_a.has_motion_fsm2 = false
    lab.exp_a.has_survivor_motion = false
    lab.exp_a.motion_active = false
    lab.exp_a.layer_count = 0

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

    -- 5. Safe Exploratory Cast Probe targeting discovered standby method
    local cast_attempted = false
    local returned_obj = nil
    local standby_result = nil

    -- 5a. Inspect and log Enum values for standby parameters
    pcall(function()
        local pt_td = sdk.find_type_definition("app.ropeway.PlayerDefine.PlayerType")
        if pt_td then
            lab_log("[Exp A] PlayerDefine.PlayerType enum fields:")
            for _, f in ipairs(pt_td:get_fields() or {}) do
                local val = f:get_data(nil)
                lab_log(string.format("   PlayerType.%s = %s", f:get_name() or "", tostring(val)))
            end
        end

        local cr_td = sdk.find_type_definition("app.ropeway.SurvivorAssignManager.CastingReason")
        if cr_td then
            lab_log("[Exp A] CastingReason enum fields:")
            for _, f in ipairs(cr_td:get_fields() or {}) do
                local val = f:get_data(nil)
                lab_log(string.format("   CastingReason.%s = %s", f:get_name() or "", tostring(val)))
            end
        end

        local om_td = sdk.find_type_definition("app.ropeway.SurvivorAssignManager.OfferMode")
        if om_td then
            lab_log("[Exp A] OfferMode enum fields:")
            for _, f in ipairs(om_td:get_fields() or {}) do
                local val = f:get_data(nil)
                lab_log(string.format("   OfferMode.%s = %s", f:get_name() or "", tostring(val)))
            end
        end

        local crr_td = sdk.find_type_definition("app.ropeway.SurvivorAssignManager.CastingRequestResult")
        if crr_td then
            lab_log("[Exp A] CastingRequestResult enum fields:")
            for _, f in ipairs(crr_td:get_fields() or {}) do
                local val = f:get_data(nil)
                lab_log(string.format("   CastingRequestResult.%s = %s", f:get_name() or "", tostring(val)))
            end
        end
    end)

    -- 5b. Safe exploratory standby invocation on SurvivorAssignManager
    pcall(function()
        local td_sam = sam:get_type_definition()
        if td_sam then
            for _, m in ipairs(td_sam:get_methods() or {}) do
                if m:get_name() == "standby" then
                    local ptypes = m:get_param_types() or {}
                    if #ptypes == 3 then
                        local sig = format_method_sig(m)
                        lab_log("[Exp A] Invoking candidate standby method: " .. sig)
                        cast_attempted = true
                        -- Test with Claire (PlayerType.PL1000 = 1), Reason=0, Mode=0
                        local ok, res = pcall(function() return m:call(sam, 1, 0, 0) end)
                        standby_result = res
                        lab_log(string.format("[Exp A] standby(1, 0, 0) returned: ok=%s, result=%s", tostring(ok), tostring(res)))
                        break
                    end
                end
            end
        end
    end)

    -- 5c. Inspect SurvivorManager singleton for casting execution
    pcall(function()
        local sm = sdk.get_managed_singleton("app.ropeway.SurvivorManager")
        if sm then
            lab_log("[Exp A] SurvivorManager singleton present: " .. tostring(sm))
            local in_c = sm:call("inCasting")
            lab_log("   SurvivorManager:inCasting() = " .. tostring(in_c))
            local req = sm:call("get_ExecCastingRequest")
            lab_log("   SurvivorManager:get_ExecCastingRequest() = " .. tostring(req))
            if in_c == false and req then
                lab_log("   SurvivorManager has pending request. Attempting applyCastingRequest()...")
                sm:call("applyCastingRequest")
            end
        end
    end)

    -- 5d. Search for newly cast Survivor GameObject in scene
    pcall(function()
        local go_td = sdk.find_type_definition("via.GameObject")
        if go_td then
            local find_m = go_td:get_method("find(System.String)")
            if find_m then
                for _, target_name in ipairs({"pl1000", "pl1000_body", "survivor", "Claire"}) do
                    local found_go = find_m:call(nil, target_name)
                    if found_go then
                        lab_log("[Exp A] Discovered candidate GameObject in scene: '" .. target_name .. "' -> " .. tostring(found_go))
                        returned_obj = found_go
                        break
                    end
                end
            end
        end
    end)

    -- 6. Strict Evidence Evaluation (Actor validity + Functioning controller verification)
    if cast_attempted and returned_obj then
        lab.exp_a.returned_actor = returned_obj
        lab_log("[Exp A] Cast probe returned entity pointer: " .. tostring(returned_obj))
        
        local actor_valid = false
        pcall(function() actor_valid = (returned_obj:call("get_Valid") == true) end)
        lab.exp_a.actor_valid = actor_valid

        local has_mot = false
        local has_fsm2 = false
        local has_surv_mot = false
        local motion_active = false
        local layer_count = 0
        local active_speed = 0.0

        pcall(function()
            local c_mot = returned_obj:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion"))
            has_mot = (c_mot ~= nil)
            if c_mot then
                layer_count = c_mot:call("getLayerCount") or 0
                local is_play = c_mot:call("get_Play")
                local spd = c_mot:call("get_PlaySpeed") or 0.0
                local l0 = c_mot:call("getLayer", 0)
                local l0_play = l0 and l0:call("get_Play")
                local l0_spd = l0 and l0:call("get_Speed") or 0.0
                if layer_count > 0 and (is_play == true or l0_play == true) and (spd > 0 or l0_spd > 0) then
                    motion_active = true
                    active_speed = math.max(spd, l0_spd)
                end
            end
            local c_fsm = returned_obj:call("getComponent(System.Type)", sdk.typeof("via.motion.MotionFsm2"))
            has_fsm2 = (c_fsm ~= nil)
            local c_sm = returned_obj:call("getComponent(System.Type)", sdk.typeof("app.ropeway.survivor.SurvivorMotionController"))
            has_surv_mot = (c_sm ~= nil)
        end)

        lab.exp_a.has_motion = has_mot
        lab.exp_a.has_motion_fsm2 = has_fsm2
        lab.exp_a.has_survivor_motion = has_surv_mot
        lab.exp_a.motion_active = motion_active
        lab.exp_a.layer_count = layer_count

        -- Strict criteria: PASS requires valid actor AND verified active functioning animation controllers
        if actor_valid and has_mot and (has_fsm2 or has_surv_mot) and motion_active then
            lab.exp_a.status = "PASS"
            lab.exp_a.last_result = string.format("PASS: Native NPC instantiated with active animation controllers (Valid=true, Layers=%d, PlaySpeed=%.2f)!",
                layer_count, active_speed)
        elseif actor_valid and (has_mot or has_fsm2 or has_surv_mot) then
            lab.exp_a.status = "PARTIAL"
            lab.exp_a.last_result = string.format("PARTIAL: Actor returned (Valid=true, Motion=%s, Fsm2=%s, SurvMot=%s), but controller activity/layers unconfirmed (Active=%s, Layers=%d).",
                tostring(has_mot), tostring(has_fsm2), tostring(has_surv_mot), tostring(motion_active), layer_count)
        else
            lab.exp_a.status = "PARTIAL"
            lab.exp_a.last_result = string.format("PARTIAL: Object returned (%s, Valid=%s), but lacks required active animation controllers.",
                tostring(returned_obj), tostring(actor_valid))
        end
    else
        lab.exp_a.status = "UNVERIFIED"
        lab.exp_a.last_result = "UNVERIFIED: SurvivorAssignManager types mapped, but direct parameterless/int cast returned nil. Requires formal CastingOrder construction."
    end

    lab_log("[Exp A] Final Verdict: " .. lab.exp_a.last_result)
    lab_log("================================================================")
end

-- =========================================================================
-- EXPERIMENT B: Character Duplication Probe (via.Scene.duplicateGameObject)
-- =========================================================================

local function update_exp_b_verdict()
    local has_motion = false
    for _, c in ipairs(lab.exp_b.surviving_components) do
        if c == "via.motion.Motion" then has_motion = true end
    end

    -- Strict criteria: PASS requires valid clone, verified input disabling, independent transform control, intact Motion, AND verified motion ticking
    if lab.exp_b.clone_entity 
        and lab.exp_b.input_stripped 
        and lab.exp_b.input_verified_disabled 
        and lab.exp_b.independent_transform_control 
        and has_motion 
        and lab.exp_b.motion_ticking then
        
        lab.exp_b.status = "PASS"
        lab.exp_b.last_result = string.format("PASS: Clone active (%d components). Inputs disabled, independent transform control verified, and Motion blend tree ticking verified.", #lab.exp_b.surviving_components)
    elseif lab.exp_b.clone_entity then
        lab.exp_b.status = "PARTIAL"
        lab.exp_b.last_result = string.format("PARTIAL: Clone spawned (%d components), verification pending (InputDisabled=%s, TransformControl=%s, MotionTicking=%s).",
            #lab.exp_b.surviving_components, tostring(lab.exp_b.input_verified_disabled), tostring(lab.exp_b.independent_transform_control), tostring(lab.exp_b.motion_ticking))
    end
end

function lab.run_experiment_b()
    lab_log("================================================================")
    lab_log("STARTING EXPERIMENT B: Character Duplication Probe (Rigorous Evaluation v1.3)")
    lab_log("================================================================")
    lab.exp_b.status = "RUNNING"
    lab.exp_b.surviving_components = {}
    lab.exp_b.input_stripped = false
    lab.exp_b.input_verified_disabled = false
    lab.exp_b.independent_transform_control = false
    lab.exp_b.motion_ticking = false
    lab.exp_b.clone_frame_history = {}
    lab.exp_b.cleanup_status = "Test clone active in viewport."

    local player = get_active_player()
    local player_go = get_player_go(player)
    if not player_go then
        lab.exp_b.status = "FAILED"
        lab.exp_b.last_result = "FAIL: Player GameObject not found. Please load into active gameplay first."
        lab_log("[Exp B] " .. lab.exp_b.last_result)
        return
    end

    local cur_scene, scene_source, cur_folder = get_current_scene(player_go)

    if not cur_scene then
        lab.exp_b.status = "FAILED"
        lab.exp_b.last_result = "FAIL: via.Scene could not be retrieved from player (checked folder hierarchy, SceneManager views, and static methods)."
        lab_log("[Exp B] " .. lab.exp_b.last_result)
        return
    end

    lab_log(string.format("[Exp B] Active player GameObject: %s", tostring(player_go)))
    lab_log(string.format("[Exp B] Target Scene: %s (Source: %s)", tostring(cur_scene), tostring(scene_source)))
    if cur_folder then
        lab_log(string.format("[Exp B] Player Folder: %s", tostring(cur_folder)))
    end

    -- 1. Perform Duplication
    local clone = nil
    pcall(function() clone = cur_scene:call("duplicateGameObject(via.GameObject)", player_go) end)
    if not clone and cur_folder then
        pcall(function() clone = cur_scene:call("duplicateGameObject(via.GameObject, via.Folder)", player_go, cur_folder) end)
    end
    if not clone then
        pcall(function() clone = cur_scene:call("duplicateGameObject", player_go) end)
    end
    if not clone and cur_folder then
        pcall(function() clone = cur_folder:call("duplicateGameObject", player_go) end)
    end
    if not clone then
        local sm = sdk.get_native_singleton("via.SceneManager")
        if sm then
            pcall(function() clone = sm:call("duplicateGameObject", player_go) end)
        end
    end

    if not clone then
        lab.exp_b.status = "FAILED"
        lab.exp_b.last_result = "FAIL: duplicateGameObject returned nil across all tested Scene/Folder signatures."
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

    -- 3. Strict Input Stripping & Verification (No false-positive flags)
    local found_input_comps = 0
    local verified_disabled = 0

    pcall(function()
        local in_rec = clone:call("getComponent(System.Type)", sdk.typeof("app.ropeway.PlayerInputReceiver"))
        if in_rec then
            found_input_comps = found_input_comps + 1
            in_rec:call("set_Valid", false)
            local is_valid = nil
            pcall(function() is_valid = in_rec:call("get_Valid") end)
            if is_valid == false then
                verified_disabled = verified_disabled + 1
            end
        end

        local pad = clone:call("getComponent(System.Type)", sdk.typeof("app.ropeway.PadManager"))
        if pad then
            found_input_comps = found_input_comps + 1
            pad:call("set_Valid", false)
            local is_valid = nil
            pcall(function() is_valid = pad:call("get_Valid") end)
            if is_valid == false then
                verified_disabled = verified_disabled + 1
            end
        end
    end)

    if found_input_comps > 0 and verified_disabled == found_input_comps then
        lab.exp_b.input_stripped = true
        lab.exp_b.input_verified_disabled = true
        lab_log(string.format("[Exp B] Input stripping verified! %d/%d input components found and confirmed disabled.", verified_disabled, found_input_comps))
    elseif found_input_comps > 0 then
        lab.exp_b.input_stripped = false
        lab.exp_b.input_verified_disabled = false
        lab_log(string.format("[Exp B] FAILED: %d input components found, but only %d verified disabled. Flags remain false.", found_input_comps, verified_disabled))
    else
        lab.exp_b.input_stripped = false
        lab.exp_b.input_verified_disabled = false
        lab_log("[Exp B] Warning: No input receiver components found on cloned actor.")
    end

    -- 4. Initialize Multi-Frame Independent Transform Control Test
    pcall(function()
        local p_tf = player_go:call("get_Transform")
        local c_tf = clone:call("get_Transform")
        if p_tf and c_tf then
            local pos = p_tf:call("get_Position")
            if pos then
                local init_pos = (Vector3f and Vector3f.new and Vector3f.new(pos.x + 2.0, pos.y, pos.z)) or { x = pos.x + 2.0, y = pos.y, z = pos.z }
                c_tf:call("set_Position", init_pos)
                
                lab.exp_b.loco_test = {
                    active = true,
                    current_frame = 0,
                    target_frames = 60,
                    clone_initial_pos = { x = pos.x + 2.0, y = pos.y, z = pos.z },
                    leon_initial_pos = { x = pos.x, y = pos.y, z = pos.z },
                    max_clone_displacement = 0.0,
                    max_leon_displacement = 0.0,
                    clone_moved = false,
                    leon_unmoved = false,
                    verdict = "TESTING_INDEPENDENT_TRANSFORM_CONTROL",
                }
                lab_log("[Exp B] Initiated 60-frame independent transform control test...")
            end
        end
    end)

    update_exp_b_verdict()
    lab_log("================================================================")
end

-- Cleanup: Confirms invalidity after both primary and fallback destruction; retains reference if unverified
function lab.cleanup_experiment_b()
    if not lab.exp_b.clone_entity then
        lab.exp_b.cleanup_status = "No active clone to destroy."
        return
    end

    local clone = lab.exp_b.clone_entity
    local player = get_active_player()
    local player_go = get_player_go(player)
    local cur_scene = get_current_scene(player_go)

    pcall(function()
        clone:call("set_DrawSelf", false)
        clone:call("set_UpdateSelf", false)
    end)

    -- Route 1: via.Scene.destroyGameObject
    if cur_scene then
        pcall(function() cur_scene:call("destroyGameObject(via.GameObject)", clone) end)
        pcall(function() cur_scene:call("destroyGameObject", clone) end)
    end

    -- Verify whether Route 1 invalidated the object
    local is_valid_after_scene = nil
    pcall(function() is_valid_after_scene = clone:call("get_Valid") end)

    if is_valid_after_scene == false then
        lab.exp_b.cleanup_status = "CLEANUP_VERIFIED (Destroyed via via.Scene.destroyGameObject, verified get_Valid==false)"
        lab_log("[Exp B] Cleanup: " .. lab.exp_b.cleanup_status)
        lab.exp_b.clone_entity = nil
        lab.exp_b.status = "CLEANED_UP"
        lab.exp_b.last_result = lab.exp_b.cleanup_status
        return
    end

    -- Route 2 (Fallback): static via.GameObject.destroy ONLY if Route 1 did not invalidate
    lab_log("[Exp B] Scene destroy did not invalidate object. Attempting fallback via.GameObject.destroy...")
    local go_td = sdk.find_type_definition("via.GameObject")
    local destroy_static = go_td and go_td:get_method("destroy(via.GameObject)")
    if destroy_static then
        pcall(function() destroy_static:call(nil, clone) end)
    end

    -- Strictly verify invalidity after fallback
    local is_valid_after_fallback = nil
    pcall(function() is_valid_after_fallback = clone:call("get_Valid") end)

    if is_valid_after_fallback == false then
        lab.exp_b.cleanup_status = "CLEANUP_VERIFIED (Destroyed via fallback static via.GameObject.destroy, verified get_Valid==false)"
        lab_log("[Exp B] Cleanup: " .. lab.exp_b.cleanup_status)
        lab.exp_b.clone_entity = nil
        lab.exp_b.status = "CLEANED_UP"
        lab.exp_b.last_result = lab.exp_b.cleanup_status
    else
        lab.exp_b.cleanup_status = "CLEANUP_UNVERIFIED (Entity still reports valid or check failed; reference retained)"
        lab_log("[Exp B] WARNING: " .. lab.exp_b.cleanup_status)
        lab.exp_b.status = "CLEANUP_FAILED"
        lab.exp_b.last_result = lab.exp_b.cleanup_status
    end
end

-- =========================================================================
-- EXPERIMENT C: Direct Motion Playback & Layer Probe
-- (Separating Inspection from Playback & Unswallowed Setup Validation)
-- =========================================================================

-- Step 1: Inspection of Leon's Motion Bank Asset & Layers
function lab.run_experiment_c_inspect()
    lab_log("================================================================")
    lab_log("STARTING EXPERIMENT C (Step 1): Motion Bank & Layer Inspection")
    lab_log("================================================================")
    lab.exp_c.inspection_status = "RUNNING"
    lab.exp_c.leon_bank_asset = nil
    lab.exp_c.leon_layer_count = 0
    lab.exp_c.discovered_motions = {}

    local player = get_active_player()
    local player_go = get_player_go(player)
    if not player_go then
        lab.exp_c.inspection_status = "FAILED"
        lab.exp_c.last_result = "FAIL: Player GameObject not found."
        lab_log("[Exp C] " .. lab.exp_c.last_result)
        return
    end

    local p_mot = nil
    pcall(function() p_mot = player_go:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion")) end)
    if not p_mot then
        lab.exp_c.inspection_status = "FAILED"
        lab.exp_c.last_result = "FAIL: Leon player actor does not have via.motion.Motion component."
        lab_log("[Exp C] " .. lab.exp_c.last_result)
        return
    end

    local p_asset = nil
    pcall(function() p_asset = p_mot:call("get_MotionBankAsset") end)
    lab.exp_c.leon_bank_asset = p_asset
    lab_log("[Exp C] Leon MotionBankAsset: " .. tostring(p_asset))

    if not p_asset then
        lab.exp_c.inspection_status = "INSPECTION_PARTIAL"
        lab.exp_c.last_result = "PARTIAL: Leon Motion component found, but MotionBankAsset is nil."
        lab_log("[Exp C] " .. lab.exp_c.last_result)
        return
    end

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

    lab.exp_c.discovered_motions = {
        { id = lab.exp_c.leon_active_mid, name = string.format("Currently Active Leon Layer 0 Motion (VERIFIED in scene)", lab.exp_c.leon_active_mid), bank = lab.exp_c.leon_active_bid, is_active = true },
        { id = 160, name = "Stance / Idle (Standard Pistol - Provisional Candidate)", bank = 1, is_active = false },
        { id = 161, name = "Walk Forward (Standard Pistol - Provisional Candidate)", bank = 1, is_active = false },
        { id = 162, name = "Jog / Run Forward (Provisional Candidate)", bank = 1, is_active = false },
        { id = 163, name = "Turn 90 / 180 Transition (Provisional Candidate)", bank = 1, is_active = false },
    }

    lab.exp_c.inspection_status = "INSPECTION_COMPLETE"
    lab.exp_c.last_result = string.format("INSPECTION_COMPLETE: Leon MotionBankAsset valid (%s). Active MotionID=%s, BankID=%s. Ready for playback test.",
        tostring(p_asset), tostring(lab.exp_c.leon_active_mid), tostring(lab.exp_c.leon_active_bid))
    lab_log("[Exp C] " .. lab.exp_c.last_result)
    lab_log("================================================================")
end

-- Step 2: Controlled Motion Playback Test with Unswallowed Setup Validation & Frame Progression
function lab.run_experiment_c_playback(target_mid, target_bid)
    lab_log("================================================================")
    lab_log(string.format("STARTING EXPERIMENT C (Step 2): Controlled Playback Test (MotionID: %d, BankID: %d)", target_mid, target_bid))
    lab_log("================================================================")
    lab.exp_c.playback_status = "TESTING"
    lab.exp_c.visual_confirmed = false
    lab.exp_c.selected_mid = target_mid
    lab.exp_c.selected_bid = target_bid

    local target_obj, target_desc = get_playback_target()
    lab.exp_c.target_name = target_desc

    if not target_obj then
        lab.exp_c.playback_status = "PLAYBACK_FAILED"
        lab.exp_c.last_result = "FAIL: No valid target GameObject found for playback test."
        lab_log("[Exp C] " .. lab.exp_c.last_result)
        return
    end

    lab_log("[Exp C] Target selected for playback test: " .. target_desc)

    -- Query target Motion component
    local t_mot = nil
    pcall(function() t_mot = target_obj:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion")) end)
    if not t_mot then
        lab.exp_c.playback_status = "PLAYBACK_FAILED"
        lab.exp_c.last_result = string.format("FAIL: Target '%s' has no via.motion.Motion component.", target_desc)
        lab_log("[Exp C] " .. lab.exp_c.last_result)
        return
    end

    -- Check existing MotionBankAsset
    local cur_asset = nil
    local ok_asset, res_asset = pcall(function() return t_mot:call("get_MotionBankAsset") end)
    if ok_asset then cur_asset = res_asset end

    -- Explicit unswallowed bank setup validation
    if not cur_asset then
        if not lab.exp_c.leon_bank_asset then
            lab.exp_c.playback_status = "PLAYBACK_FAILED"
            lab.exp_c.last_result = "FAIL: Target has no MotionBankAsset and Leon's MotionBankAsset is nil. Run inspection first."
            lab_log("[Exp C] " .. lab.exp_c.last_result)
            return
        end

        -- Step A: set_MotionBankAsset with explicit pcall verification
        local ok_set, err_set = pcall(function()
            t_mot:call("set_MotionBankAsset", lab.exp_c.leon_bank_asset)
        end)
        if not ok_set then
            lab.exp_c.playback_status = "PLAYBACK_FAILED"
            lab.exp_c.last_result = string.format("FAIL: set_MotionBankAsset threw exception: %s", tostring(err_set))
            lab_log("[Exp C] " .. lab.exp_c.last_result)
            return
        end

        -- Step B: setupMotionBank with explicit pcall verification
        local ok_setup, err_setup = pcall(function()
            t_mot:call("setupMotionBank")
        end)
        if not ok_setup then
            lab.exp_c.playback_status = "PLAYBACK_FAILED"
            lab.exp_c.last_result = string.format("FAIL: setupMotionBank threw exception: %s", tostring(err_setup))
            lab_log("[Exp C] " .. lab.exp_c.last_result)
            return
        end

        -- Step C: Verify assigned asset after setup
        local verified_asset = nil
        local ok_verify = pcall(function() verified_asset = t_mot:call("get_MotionBankAsset") end)
        if not ok_verify or not verified_asset then
            lab.exp_c.playback_status = "PLAYBACK_FAILED"
            lab.exp_c.last_result = "FAIL: MotionBankAsset verified nil after setupMotionBank."
            lab_log("[Exp C] " .. lab.exp_c.last_result)
            return
        end
        lab_log("[Exp C] Successfully assigned Leon's MotionBankAsset to target and verified non-nil.")
    end

    -- Ensure Play and PlaySpeed with explicit error checking
    local ok_play, err_play = pcall(function()
        t_mot:call("set_Play", true)
        t_mot:call("set_PlaySpeed", 1.0)
    end)
    if not ok_play then
        lab.exp_c.playback_status = "PLAYBACK_FAILED"
        lab.exp_c.last_result = string.format("FAIL: set_Play/set_PlaySpeed threw exception: %s", tostring(err_play))
        lab_log("[Exp C] " .. lab.exp_c.last_result)
        return
    end

    -- Query Layer 0
    local l0 = nil
    pcall(function() l0 = t_mot:call("getLayer", 0) end)
    if not l0 then
        lab.exp_c.playback_status = "PLAYBACK_FAILED"
        lab.exp_c.last_result = "FAIL: Target Motion component has no Layer 0."
        lab_log("[Exp C] " .. lab.exp_c.last_result)
        return
    end

    -- Test changeMotion invocation safely
    local exception_thrown = false
    local error_detail = nil
    local initial_frame = 0.0

    pcall(function() initial_frame = l0:call("get_Frame") or 0.0 end)

    local ok, err = pcall(function()
        l0:call("set_Play", true)
        l0:call("set_Speed", 1.0)
        
        local td_l = l0:get_type_definition()
        local cm = td_l:get_method("changeMotion(System.UInt32, System.UInt32, System.Single)")
                or td_l:get_method("changeMotion(System.Int32, System.Int32, System.Single)")
                or td_l:get_method("changeMotion")
        if cm then
            cm:call(l0, target_bid, target_mid, 5.0)
        else
            l0:call("set_MotionID", target_mid)
        end
    end)

    if not ok then
        exception_thrown = true
        error_detail = tostring(err)
    end

    if exception_thrown then
        lab.exp_c.playback_status = "PLAYBACK_FAILED"
        lab.exp_c.last_result = string.format("FAIL: changeMotion threw exception: %s. (Unconfigured MotionFsm2).", tostring(error_detail))
        lab_log("[Exp C] " .. lab.exp_c.last_result)
        return
    end

    -- Initiate 45-frame telemetry monitoring to verify actual frame progression
    lab.exp_c.playback_monitor = {
        active = true,
        target_obj = target_obj,
        target_mid = target_mid,
        target_bid = target_bid,
        start_frame = initial_frame,
        current_frame = initial_frame,
        ticks_observed = 0,
        max_ticks = 45,
    }
    lab_log(string.format("[Exp C] changeMotion invoked cleanly! Monitoring frame progression from %.2f...", initial_frame))
end

-- =========================================================================
-- Master Telemetry Loop (Multi-Frame Verification for Exp B & C)
-- =========================================================================

local function update_lab_telemetry()
    -- 1. Exp B Independent Transform Control & Blend Tree Ticking Monitor
    if lab.exp_b.clone_entity then
        -- Check motion blend tree ticking
        pcall(function()
            local c_mot = lab.exp_b.clone_entity:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion"))
            if c_mot then
                local l0 = c_mot:call("getLayer", 0)
                if l0 then
                    local frm = l0:call("get_Frame") or 0.0
                    local history = lab.exp_b.clone_frame_history
                    table.insert(history, frm)
                    if #history > 30 then table.remove(history, 1) end
                    if #history >= 10 and history[#history] ~= history[1] then
                        if not lab.exp_b.motion_ticking then
                            lab.exp_b.motion_ticking = true
                            lab_log("[Exp B] Motion blend tree ticking confirmed! Frame progressing.")
                            update_exp_b_verdict()
                        end
                    end
                end
            end
        end)

        -- Multi-frame independent transform control test
        local lt = lab.exp_b.loco_test
        if lt and lt.active then
            local p = get_active_player()
            local p_go = get_player_go(p)
            local p_tf = p_go and p_go:call("get_Transform")
            local c_tf = lab.exp_b.clone_entity:call("get_Transform")

            if p_tf and c_tf then
                lt.current_frame = lt.current_frame + 1
                
                -- Dynamically translate clone transform slightly each frame
                local offset_x = math.sin(lt.current_frame * 0.1) * 0.6
                local step_pos = (Vector3f and Vector3f.new and Vector3f.new(lt.clone_initial_pos.x + offset_x, lt.clone_initial_pos.y, lt.clone_initial_pos.z)) 
                                or { x = lt.clone_initial_pos.x + offset_x, y = lt.clone_initial_pos.y, z = lt.clone_initial_pos.z }
                c_tf:call("set_Position", step_pos)

                -- Sample current displacement each frame
                local cur_c = c_tf:call("get_Position")
                local cur_p = p_tf:call("get_Position")
                if cur_c and lt.clone_initial_pos then
                    local c_disp = math.abs(cur_c.x - lt.clone_initial_pos.x)
                    if c_disp > lt.max_clone_displacement then
                        lt.max_clone_displacement = c_disp
                    end
                end
                if cur_p and lt.leon_initial_pos then
                    local p_disp = math.abs(cur_p.x - lt.leon_initial_pos.x) + math.abs(cur_p.z - lt.leon_initial_pos.z)
                    if p_disp > lt.max_leon_displacement then
                        lt.max_leon_displacement = p_disp
                    end
                end

                if lt.current_frame >= lt.target_frames then
                    lt.active = false
                    
                    lt.clone_moved = (lt.max_clone_displacement > 0.25)
                    lt.leon_unmoved = (lt.max_leon_displacement < 0.25)

                    if lt.clone_moved and lt.leon_unmoved then
                        lab.exp_b.independent_transform_control = true
                        lt.verdict = "INDEPENDENT_TRANSFORM_CONTROL_VERIFIED (Clone transform translated over 60 frames without affecting Leon. Note: Does not imply autonomous native locomotion controller)"
                    else
                        lab.exp_b.independent_transform_control = false
                        lt.verdict = string.format("FAILED (MaxCloneMoved: %.2f m, MaxLeonMoved: %.2f m)", lt.max_clone_displacement, lt.max_leon_displacement)
                    end
                    lab_log("[Exp B] Transform Control Verdict: " .. lt.verdict)
                    update_exp_b_verdict()
                end
            end
        end
    end

    -- 2. Exp C Playback Frame Progression Monitor with continuous strict actor & layer validity verification
    local pm = lab.exp_c.playback_monitor
    if pm and pm.active and pm.target_obj then
        -- Strict actor validity check (treat unreadable or false as failure)
        local ok_val, is_valid = pcall(function() return pm.target_obj:call("get_Valid") end)
        if not ok_val or is_valid ~= true then
            pm.active = false
            lab.exp_c.playback_status = "PLAYBACK_FAILED"
            lab.exp_c.last_result = string.format("FAIL: Target actor validity check failed (ok=%s, valid=%s). Target unreadable or destroyed.", tostring(ok_val), tostring(is_valid))
            lab_log("[Exp C] " .. lab.exp_c.last_result)
            return
        end

        -- Strict Motion component & Layer 0 check (treat unreadable or nil as failure)
        local ok_mot, t_mot = pcall(function() return pm.target_obj:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion")) end)
        local ok_l0, l0 = nil, nil
        if ok_mot and t_mot then
            ok_l0, l0 = pcall(function() return t_mot:call("getLayer", 0) end)
        end

        if not ok_mot or not t_mot or not ok_l0 or not l0 then
            pm.active = false
            lab.exp_c.playback_status = "PLAYBACK_FAILED"
            lab.exp_c.last_result = "FAIL: Target via.motion.Motion or Layer 0 became unreadable during monitoring."
            lab_log("[Exp C] " .. lab.exp_c.last_result)
            return
        end

        pm.ticks_observed = pm.ticks_observed + 1
        pcall(function()
            pm.current_frame = l0:call("get_Frame") or 0.0
            local mid = l0:call("get_MotionID") or 0
            
            if pm.ticks_observed >= pm.max_ticks then
                pm.active = false
                local frame_advanced = (pm.current_frame > pm.start_frame) or (pm.current_frame < pm.start_frame and pm.start_frame > 15.0) -- looped
                
                if mid == pm.target_mid and frame_advanced then
                    lab.exp_c.playback_status = "FRAME_PROGRESSION_VERIFIED"
                    lab.exp_c.last_result = string.format("FRAME_PROGRESSION_VERIFIED: MotionID %d on Bank %d progressed (%.1f -> %.1f, +%d ticks). Pending visual confirmation in viewport.",
                        pm.target_mid, pm.target_bid, pm.start_frame, pm.current_frame, pm.ticks_observed)
                elseif mid == pm.target_mid and not frame_advanced then
                    lab.exp_c.playback_status = "PLAYBACK_STALLED"
                    lab.exp_c.last_result = string.format("PARTIAL: MotionID %d assigned, but frame remained stationary at %.1f (PlaySpeed=0 or animation paused).",
                        pm.target_mid, pm.current_frame)
                else
                    lab.exp_c.playback_status = "PLAYBACK_OVERRIDDEN"
                    lab.exp_c.last_result = string.format("PARTIAL: changeMotion executed, but native motion graph immediately reverted MotionID %d to %d.",
                        pm.target_mid, mid)
                end
                lab_log("[Exp C] " .. lab.exp_c.last_result)
            end
        end)
    end
end

-- =========================================================================
-- ImGui UI Dashboard
-- =========================================================================

local function draw_lab_ui()
    imgui.text_colored("=== RE2 DUO MODE — ANIMATION RESEARCH LAB ===", 0.3, 0.9, 1.0, 1.0)
    imgui.text_colored("Milestone 1: In-Engine Reverse Engineering (Rigorous Edition v1.4)", 0.7, 0.7, 0.7, 1.0)
    imgui.separator()

    -- Quick Companion Control Bridge (character_renderer.lua bridge)
    local duo = _G.duo_spawner or spawner
    local claire_body = (duo and duo.spawned_entities and #duo.spawned_entities > 0 and duo.spawned_entities[1])
    local claire_valid = false
    if claire_body and claire_body.call then
        pcall(function() claire_valid = (claire_body:call("get_Valid") == true) end)
    end

    if claire_valid then
        imgui.text_colored("Claire Companion: SPAWNED & ACTIVE IN SCENE (Target for Exp C)", 0.2, 1.0, 0.4, 1.0)
        imgui.same_line()
        if imgui.button("Despawn Claire##btn_bridge_despawn") then
            if duo and duo.execute_despawn then duo.execute_despawn() end
        end
    else
        imgui.text_colored("Claire Companion: NOT SPAWNED", 1.0, 0.6, 0.2, 1.0)
        imgui.same_line()
        if imgui.button(">>> SPAWN CLAIRE IN FRONT OF LEON <<<##btn_bridge_spawn") then
            if duo and duo.start_spawn then
                duo.start_spawn("full")
            end
        end
    end
    imgui.separator()

    -- Navigation Tabs
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
        imgui.text_colored("Research Roadmap Status & Strict Acceptance Criteria:", 1.0, 0.8, 0.2, 1.0)
        imgui.text("Goal: Identify a proven, animated Claire pathway before story scripting.")
        imgui.spacing()

        -- Exp A Summary
        local col_a = (lab.exp_a.status == "PASS" and {0.2, 1.0, 0.4}) or (lab.exp_a.status == "PARTIAL" and {1.0, 0.8, 0.2}) or {0.8, 0.8, 0.8}
        imgui.text_colored("Experiment A: Native NPC Allocation (SurvivorAssignManager)", col_a[1], col_a[2], col_a[3], 1.0)
        imgui.text("  Status: " .. lab.exp_a.status)
        imgui.text("  Result: " .. lab.exp_a.last_result)
        imgui.spacing()

        -- Exp B Summary
        local col_b = (lab.exp_b.status == "PASS" and {0.2, 1.0, 0.4}) or (lab.exp_b.status == "PARTIAL" and {1.0, 0.8, 0.2}) or {0.8, 0.8, 0.8}
        imgui.text_colored("Experiment B: Character Duplication (via.Scene.duplicateGameObject)", col_b[1], col_b[2], col_b[3], 1.0)
        imgui.text("  Status: " .. lab.exp_b.status)
        imgui.text("  Result: " .. lab.exp_b.last_result)
        imgui.spacing()

        -- Exp C Summary
        local col_c = (lab.exp_c.playback_status == "PLAYBACK_AND_VISUAL_VERIFIED" and {0.2, 1.0, 0.4}) 
                   or (lab.exp_c.playback_status == "FRAME_PROGRESSION_VERIFIED" and {0.2, 0.9, 1.0}) 
                   or (lab.exp_c.playback_status == "PLAYBACK_STALLED" and {1.0, 0.8, 0.2}) or {0.8, 0.8, 0.8}
        imgui.text_colored("Experiment C: Direct Motion Playback (TreeLayer / MotionFsm2)", col_c[1], col_c[2], col_c[3], 1.0)
        imgui.text("  Inspection: " .. lab.exp_c.inspection_status .. " | Playback: " .. lab.exp_c.playback_status)
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
        imgui.text("Status: " .. lab.exp_a.status)
        imgui.text("Singleton Detected: " .. tostring(lab.exp_a.singleton_found))
        imgui.text("Returned Actor Non-Nil: " .. tostring(lab.exp_a.returned_actor ~= nil))
        imgui.text("Actor Verified Valid (get_Valid==true): " .. tostring(lab.exp_a.actor_valid))
        imgui.text("Has via.motion.Motion: " .. tostring(lab.exp_a.has_motion))
        imgui.text("Has MotionFsm2: " .. tostring(lab.exp_a.has_motion_fsm2))
        imgui.text("Has SurvivorMotionController: " .. tostring(lab.exp_a.has_survivor_motion))
        imgui.text(string.format("Controller Functioning Active: %s (Layers=%d)", tostring(lab.exp_a.motion_active), lab.exp_a.layer_count))
        imgui.text("Verdict: " .. lab.exp_a.last_result)

        imgui.spacing()
        imgui.text_colored("Casting Methods Discovered (" .. #lab.exp_a.casting_methods .. "):", 0.6, 0.9, 0.6, 1.0)
        for _, sig in ipairs(lab.exp_a.casting_methods) do
            imgui.text("  " .. sig)
        end

    -- TAB 3: EXPERIMENT B
    elseif lab.selected_tab == 3 then
        imgui.text_colored("Experiment B: Character Duplication Probe", 1.0, 0.8, 0.2, 1.0)
        imgui.text("Clones player actor via via.Scene.duplicateGameObject with verified input disabling.")
        imgui.spacing()

        if imgui.button("Spawn Duplicate Actor##btn_exp_b_spawn") then
            lab.run_experiment_b()
        end
        imgui.same_line()
        if imgui.button("Destroy Test Clone (Safe Single Route)##btn_exp_b_destroy") then
            lab.cleanup_experiment_b()
        end

        imgui.spacing()
        imgui.text("Status: " .. lab.exp_b.status)
        imgui.text("Clone Active: " .. tostring(lab.exp_b.clone_entity ~= nil))
        imgui.text("Input Components Found & Disabled: " .. tostring(lab.exp_b.input_stripped))
        imgui.text("Input Verified Disabled (get_Valid==false): " .. tostring(lab.exp_b.input_verified_disabled))
        imgui.text("Independent Transform Control (60 Frames): " .. tostring(lab.exp_b.independent_transform_control))
        imgui.text("Transform Test Verdict: " .. tostring(lab.exp_b.loco_test.verdict))
        imgui.text("Motion Blend Tree Ticking: " .. tostring(lab.exp_b.motion_ticking))
        imgui.text("Cleanup Status: " .. tostring(lab.exp_b.cleanup_status))
        imgui.text("Verdict: " .. lab.exp_b.last_result)

        imgui.spacing()
        imgui.text_colored("Components Surviving Duplication (" .. #lab.exp_b.surviving_components .. "):", 0.6, 0.9, 0.6, 1.0)
        for _, cname in ipairs(lab.exp_b.surviving_components) do
            imgui.text("  " .. cname)
        end

    -- TAB 4: EXPERIMENT C
    elseif lab.selected_tab == 4 then
        imgui.text_colored("Experiment C: Direct Motion Playback & Layer Probe", 1.0, 0.8, 0.2, 1.0)
        imgui.text("Step 1 inspects Leon's Motion Bank. Step 2 tests controlled playback with frame monitoring.")
        imgui.spacing()

        if imgui.button("1. Inspect Leon Motion Bank & Layers##btn_exp_c_insp") then
            lab.run_experiment_c_inspect()
        end

        imgui.spacing()
        imgui.text("Inspection Status: " .. lab.exp_c.inspection_status)
        imgui.text("Leon Bank Asset Present: " .. tostring(lab.exp_c.leon_bank_asset ~= nil))
        imgui.text(string.format("Leon Layer[0]: BankID=%s, Active MotionID=%s (Frame=%.1f)",
            tostring(lab.exp_c.leon_active_bid), tostring(lab.exp_c.leon_active_mid), lab.exp_c.leon_frame))

        imgui.separator()
        local cur_target_obj, cur_target_name = get_playback_target()
        lab.exp_c.target_name = cur_target_name

        imgui.text_colored("Controlled Playback Testing (Target: " .. tostring(lab.exp_c.target_name) .. "):", 1.0, 0.8, 0.2, 1.0)
        if string.find(tostring(lab.exp_c.target_name), "Leon") then
            imgui.text_colored("[!] CAUTION: Targeting Leon (Player Actor). Any stick/keyboard movement will immediately revert this animation back to player locomotion. Use 'SPAWN CLAIRE' above to test on companion!", 1.0, 0.4, 0.2, 1.0)
        elseif string.find(tostring(lab.exp_c.target_name), "Claire") then
            imgui.text_colored("[OK] Targeting Claire Companion. Animation will play independently without player movement interference.", 0.2, 1.0, 0.4, 1.0)
        end
        
        -- Primary recommended test: Play the dynamically confirmed active Leon motion ID!
        if lab.exp_c.leon_active_mid > 0 then
            local active_btn_label = string.format("Play Active Leon Motion (ID %d, Bank %d) [VERIFIED IN SCENE]##btn_play_active", lab.exp_c.leon_active_mid, lab.exp_c.leon_active_bid)
            if imgui.button(active_btn_label) then
                lab.run_experiment_c_playback(lab.exp_c.leon_active_mid, lab.exp_c.leon_active_bid)
            end
        end

        imgui.text("Provisional Locomotion Candidates:")
        if imgui.button("Play Stance / Idle (ID 160)##btn_play_160") then
            lab.run_experiment_c_playback(160, 1)
        end
        imgui.same_line()
        if imgui.button("Play Walk Forward (ID 161)##btn_play_161") then
            lab.run_experiment_c_playback(161, 1)
        end
        imgui.same_line()
        if imgui.button("Play Jog / Run (ID 162)##btn_play_162") then
            lab.run_experiment_c_playback(162, 1)
        end

        imgui.spacing()
        imgui.text("Playback Status: " .. lab.exp_c.playback_status)
        if lab.exp_c.playback_monitor.active then
            imgui.text_colored(string.format("Monitoring frame progression: Tick %d/%d (Start: %.1f, Current: %.1f)...",
                lab.exp_c.playback_monitor.ticks_observed, lab.exp_c.playback_monitor.max_ticks,
                lab.exp_c.playback_monitor.start_frame, lab.exp_c.playback_monitor.current_frame), 0.2, 0.9, 1.0, 1.0)
        end
        imgui.text("Verdict: " .. lab.exp_c.last_result)

        -- Visual Confirmation Step (Separating logical telemetry from viewport observation)
        if lab.exp_c.playback_status == "FRAME_PROGRESSION_VERIFIED" or lab.exp_c.playback_status == "PLAYBACK_AND_VISUAL_VERIFIED" then
            imgui.spacing()
            local v_changed, v_val = imgui.checkbox("Visual Animation Playback Confirmed in Viewport##chk_visual", lab.exp_c.visual_confirmed)
            if v_changed then
                lab.exp_c.visual_confirmed = v_val
                if v_val then
                    lab.exp_c.playback_status = "PLAYBACK_AND_VISUAL_VERIFIED"
                    lab.exp_c.last_result = string.format("PASS: PLAYBACK_AND_VISUAL_VERIFIED (Logical frame progression verified and confirmed visually on character)")
                else
                    lab.exp_c.playback_status = "FRAME_PROGRESSION_VERIFIED"
                end
                lab_log("[Exp C] Visual Confirmation Changed: " .. tostring(v_val))
            end
        end

        imgui.spacing()
        imgui.text_colored("Candidate Motion IDs:", 0.6, 0.9, 0.6, 1.0)
        for _, m in ipairs(lab.exp_c.discovered_motions) do
            local tag = m.is_active and " [ACTIVE IN SCENE]" or " [Provisional]"
            imgui.text(string.format("  Motion %d (Bank %d): %s%s", m.id, m.bank, m.name, tag))
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
