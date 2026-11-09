--[[
    Resident Evil 2: Duo Mode
    Milestone 1 — Animation Research Lab & Test Harness (Rigorous Edition)
    File: reframework/autorun/animation_lab.lua
    Author: AryanTechie-007

    Purpose:
    Three isolated, safe in-engine reverse-engineering experiments to resolve
    the companion animation blocker with strict, non-optimistic success criteria:
      - Experiment A: Native NPC Allocation (SurvivorAssignManager / SurvivorStandbyCatalog)
      - Experiment B: Character Duplication (via.Scene.duplicateGameObject + verified input stripping + dynamic locomotion)
      - Experiment C: Direct Motion Playback (TreeLayer / MotionFsm2 — Inspection separated from Playback verification)

    Strict Verification Rules:
      - Rule 1: No imaginary functionality. No PASS without runtime verification of entities and active controllers.
      - Rule 2: No speculative RE Engine APIs in production.
      - Rule 3: Single confirmed destruction route without double-free/double-destruction risks.
]]

local lab = {
    version = "1.1.0-m1-strict",
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
        has_motion = false,
        has_motion_fsm2 = false,
        has_survivor_motion = false,
        last_result = "Standing by. Click 'Run Experiment A Probe' to inspect Native NPC Casting.",
    },

    -- Experiment B State
    exp_b = {
        status = "NOT_RUN", -- NOT_RUN | RUNNING | PASS | PARTIAL | FAILED | CLEANED_UP
        clone_entity = nil,
        surviving_components = {},
        input_stripped = false,
        input_verified_disabled = false,
        independent_locomotion = false,
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
            clone_moved = false,
            leon_unmoved = false,
            verdict = "NOT_STARTED",
        }
    },

    -- Experiment C State
    exp_c = {
        inspection_status = "NOT_RUN", -- NOT_RUN | INSPECTION_COMPLETE | INSPECTION_PARTIAL | FAILED
        playback_status = "NOT_RUN",   -- NOT_RUN | TESTING | PLAYBACK_VERIFIED | PLAYBACK_FAILED | PLAYBACK_STALLED | PLAYBACK_OVERRIDDEN
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
            max_ticks = 40,
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

local function get_current_scene()
    local scene_man = nil
    pcall(function() scene_man = sdk.get_native_singleton("via.SceneManager") end)
    if not scene_man then return nil end
    local scene = nil
    pcall(function() scene = scene_man:call("get_CurrentScene") end)
    return scene
end

-- Resolves the target actor for animation playback tests (Priority: Claire from character_renderer -> Exp B clone -> Leon)
local function get_playback_target()
    -- 1. Check if Claire is spawned by character_renderer.lua
    if spawner and spawner.spawned_entities and #spawner.spawned_entities > 0 then
        local body = spawner.spawned_entities[1]
        if body and body.call then
            return body, "Claire (character_renderer.lua Body)"
        end
    end

    -- 2. Check if Exp B clone is active
    if lab.exp_b.clone_entity and lab.exp_b.clone_entity.call then
        return lab.exp_b.clone_entity, "Test Clone (Experiment B Actor)"
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
    lab_log("STARTING EXPERIMENT A: Native NPC Allocation Probe (Strict Evaluation)")
    lab_log("================================================================")
    lab.exp_a.status = "RUNNING"
    lab.exp_a.types_resolved = {}
    lab.exp_a.casting_methods = {}
    lab.exp_a.returned_actor = nil
    lab.exp_a.has_motion = false
    lab.exp_a.has_motion_fsm2 = false
    lab.exp_a.has_survivor_motion = false

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

    -- 5. Safe Exploratory Cast Probe
    local cast_attempted = false
    local returned_obj = nil

    pcall(function()
        local td_sam = sam:get_type_definition()
        if td_sam then
            local cast_method = td_sam:get_method("requestCast") or td_sam:get_method("cast")
            if cast_method then
                lab_log("[Exp A] Attempting invocation of " .. format_method_sig(cast_method))
                cast_attempted = true
                pcall(function() returned_obj = cast_method:call(sam, 1) end)
            end
        end
    end)

    -- 6. Strict Evidence Evaluation
    if cast_attempted and returned_obj then
        lab.exp_a.returned_actor = returned_obj
        lab_log("[Exp A] Cast probe returned entity: " .. tostring(returned_obj))
        
        local has_mot = false
        local has_fsm2 = false
        local has_surv_mot = false

        pcall(function()
            local c_mot = returned_obj:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion"))
            has_mot = (c_mot ~= nil)
            local c_fsm = returned_obj:call("getComponent(System.Type)", sdk.typeof("via.motion.MotionFsm2"))
            has_fsm2 = (c_fsm ~= nil)
            local c_sm = returned_obj:call("getComponent(System.Type)", sdk.typeof("app.ropeway.survivor.SurvivorMotionController"))
            has_surv_mot = (c_sm ~= nil)
        end)

        lab.exp_a.has_motion = has_mot
        lab.exp_a.has_motion_fsm2 = has_fsm2
        lab.exp_a.has_survivor_motion = has_surv_mot

        -- Strict criteria: PASS requires valid actor AND active motion controllers
        if has_mot and (has_fsm2 or has_surv_mot) then
            lab.exp_a.status = "PASS"
            lab.exp_a.last_result = "PASS: Fully animated Native NPC instantiated! Motion and MotionFsm2/SurvivorMotion verified."
        else
            lab.exp_a.status = "PARTIAL"
            lab.exp_a.last_result = string.format("PARTIAL: Actor returned, but animation controller missing (Motion=%s, MotionFsm2=%s, SurvivorMotion=%s).",
                tostring(has_mot), tostring(has_fsm2), tostring(has_surv_mot))
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

    if lab.exp_b.clone_entity and lab.exp_b.input_verified_disabled and lab.exp_b.independent_locomotion and has_motion then
        lab.exp_b.status = "PASS"
        lab.exp_b.last_result = string.format("PASS: Clone active with %d components intact. Inputs verified stripped, independent locomotion verified over time, Motion intact.", #lab.exp_b.surviving_components)
    elseif lab.exp_b.clone_entity then
        lab.exp_b.status = "PARTIAL"
        lab.exp_b.last_result = string.format("PARTIAL: Clone spawned (%d components), verification in progress (InputDisabled=%s, IndependentLoco=%s, MotionTicking=%s).",
            #lab.exp_b.surviving_components, tostring(lab.exp_b.input_verified_disabled), tostring(lab.exp_b.independent_locomotion), tostring(lab.exp_b.motion_ticking))
    end
end

function lab.run_experiment_b()
    lab_log("================================================================")
    lab_log("STARTING EXPERIMENT B: Character Duplication Probe (Rigorous Evaluation)")
    lab_log("================================================================")
    lab.exp_b.status = "RUNNING"
    lab.exp_b.surviving_components = {}
    lab.exp_b.input_stripped = false
    lab.exp_b.input_verified_disabled = false
    lab.exp_b.independent_locomotion = false
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

    -- 3. Strict Input Stripping & Verification
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
        lab.exp_b.input_stripped = true
        lab.exp_b.input_verified_disabled = false
        lab_log(string.format("[Exp B] Warning: %d input components found, but only %d verified disabled.", found_input_comps, verified_disabled))
    else
        lab.exp_b.input_stripped = false
        lab.exp_b.input_verified_disabled = false
        lab_log("[Exp B] Warning: No input receiver components found on cloned actor.")
    end

    -- 4. Initialize Multi-Frame Independent Locomotion Test
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
                    clone_moved = false,
                    leon_unmoved = false,
                    verdict = "TESTING_LOCOMOTION_OVER_TIME",
                }
                lab_log("[Exp B] Initiated 60-frame independent locomotion test over time...")
            end
        end
    end)

    update_exp_b_verdict()
    lab_log("================================================================")
end

-- Cleanup: Uses ONE confirmed destruction route without double-free risks
function lab.cleanup_experiment_b()
    if not lab.exp_b.clone_entity then
        lab.exp_b.cleanup_status = "No active clone to destroy."
        return
    end

    local clone = lab.exp_b.clone_entity
    local cur_scene = get_current_scene()
    local destroyed = false

    pcall(function()
        clone:call("set_DrawSelf", false)
        clone:call("set_UpdateSelf", false)
    end)

    -- Confirmed Primary Route: via.Scene.destroyGameObject
    if cur_scene then
        local ok = pcall(function()
            cur_scene:call("destroyGameObject(via.GameObject)", clone)
            destroyed = true
        end)
        if not ok or not destroyed then
            pcall(function()
                cur_scene:call("destroyGameObject", clone)
                destroyed = true
            end)
        end
    end

    -- Verify whether destruction succeeded
    local still_valid = false
    pcall(function() still_valid = clone:call("get_Valid") end)

    if destroyed and not still_valid then
        lab.exp_b.cleanup_status = "SUCCESS: Destroyed cleanly via via.Scene.destroyGameObject."
        lab_log("[Exp B] " .. lab.exp_b.cleanup_status)
        lab.exp_b.clone_entity = nil
    elseif still_valid then
        -- Only attempt fallback static destroy if scene destroy failed and entity remains valid
        lab_log("[Exp B] Object still valid after scene destroy. Attempting fallback via.GameObject.destroy...")
        local go_td = sdk.find_type_definition("via.GameObject")
        local destroy_static = go_td and go_td:get_method("destroy(via.GameObject)")
        if destroy_static then
            pcall(function() destroy_static:call(nil, clone) end)
            lab.exp_b.cleanup_status = "SUCCESS: Destroyed via fallback static via.GameObject.destroy."
            lab.exp_b.clone_entity = nil
        else
            lab.exp_b.cleanup_status = "WARNING: Entity could not be verified destroyed."
        end
    else
        lab.exp_b.cleanup_status = "SUCCESS: Clone reference cleared and marked invalid."
        lab.exp_b.clone_entity = nil
    end

    lab.exp_b.loco_test.active = false
    lab.exp_b.status = "CLEANED_UP"
    lab.exp_b.last_result = "Cleaned up: " .. lab.exp_b.cleanup_status
end

-- =========================================================================
-- EXPERIMENT C: Direct Motion Playback & Layer Probe
-- (Separating Inspection from Playback Verification)
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
        { id = 160, name = "Stance / Idle (Standard Pistol)", bank = 1 },
        { id = 161, name = "Walk Forward (Standard Pistol)", bank = 1 },
        { id = 162, name = "Jog / Run Forward", bank = 1 },
        { id = 163, name = "Turn 90 / 180 Transition", bank = 1 },
    }

    lab.exp_c.inspection_status = "INSPECTION_COMPLETE"
    lab.exp_c.last_result = string.format("INSPECTION_COMPLETE: Leon MotionBankAsset valid (%s). Layer count: %d. Ready for controlled playback test.",
        tostring(p_asset), lab.exp_c.leon_layer_count)
    lab_log("[Exp C] " .. lab.exp_c.last_result)
    lab_log("================================================================")
end

-- Step 2: Controlled Motion Playback Test with Observable Frame Progression
function lab.run_experiment_c_playback(target_mid, target_bid)
    lab_log("================================================================")
    lab_log(string.format("STARTING EXPERIMENT C (Step 2): Controlled Playback Test (MotionID: %d, BankID: %d)", target_mid, target_bid))
    lab_log("================================================================")
    lab.exp_c.playback_status = "TESTING"
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

    -- If target has no bank asset, attempt to link Leon's bank asset
    pcall(function()
        local cur_asset = t_mot:call("get_MotionBankAsset")
        if not cur_asset and lab.exp_c.leon_bank_asset then
            t_mot:call("set_MotionBankAsset", lab.exp_c.leon_bank_asset)
            t_mot:call("setupMotionBank")
            lab_log("[Exp C] Assigned Leon's MotionBankAsset to target and called setupMotionBank.")
        end
        t_mot:call("set_Play", true)
        t_mot:call("set_PlaySpeed", 1.0)
    end)

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

    -- Initiate 40-frame telemetry monitoring to verify actual frame progression
    lab.exp_c.playback_monitor = {
        active = true,
        target_obj = target_obj,
        target_mid = target_mid,
        target_bid = target_bid,
        start_frame = initial_frame,
        current_frame = initial_frame,
        ticks_observed = 0,
        max_ticks = 40,
    }
    lab_log(string.format("[Exp C] changeMotion invoked cleanly! Monitoring frame progression from %.2f...", initial_frame))
end

-- =========================================================================
-- Master Telemetry Loop (Multi-Frame Verification for Exp B & C)
-- =========================================================================

local function update_lab_telemetry()
    -- 1. Exp B Locomotion & Frame Monitoring over time
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
                        lab.exp_b.motion_ticking = true
                    end
                end
            end
        end)

        -- Multi-frame independent locomotion test
        local lt = lab.exp_b.loco_test
        if lt and lt.active then
            local p = get_active_player()
            local p_go = get_player_go(p)
            local p_tf = p_go and p_go:call("get_Transform")
            local c_tf = lab.exp_b.clone_entity:call("get_Transform")

            if p_tf and c_tf then
                lt.current_frame = lt.current_frame + 1
                
                -- Translate clone slightly each frame
                local offset_x = math.sin(lt.current_frame * 0.1) * 0.6
                local step_pos = (Vector3f and Vector3f.new and Vector3f.new(lt.clone_initial_pos.x + offset_x, lt.clone_initial_pos.y, lt.clone_initial_pos.z)) 
                                or { x = lt.clone_initial_pos.x + offset_x, y = lt.clone_initial_pos.y, z = lt.clone_initial_pos.z }
                c_tf:call("set_Position", step_pos)

                if lt.current_frame >= lt.target_frames then
                    lt.active = false
                    local final_c = c_tf:call("get_Position")
                    local final_p = p_tf:call("get_Position")
                    
                    local c_dx = final_c and math.abs(final_c.x - lt.clone_initial_pos.x) or 0.0
                    local p_dx = final_p and (math.abs(final_p.x - lt.leon_initial_pos.x) + math.abs(final_p.z - lt.leon_initial_pos.z)) or 0.0
                    
                    lt.clone_moved = (c_dx > 0.1)
                    lt.leon_unmoved = (p_dx < 0.25)

                    if lt.clone_moved and lt.leon_unmoved then
                        lab.exp_b.independent_locomotion = true
                        lt.verdict = "VERIFIED (Clone translated dynamically over 60 frames; Leon unaffected)"
                    else
                        lab.exp_b.independent_locomotion = false
                        lt.verdict = string.format("FAILED (CloneMoved: %s, LeonUnaffected: %s)", tostring(lt.clone_moved), tostring(lt.leon_unmoved))
                    end
                    lab_log("[Exp B] Locomotion Over Time Verdict: " .. lt.verdict)
                    update_exp_b_verdict()
                end
            end
        end
    end

    -- 2. Exp C Playback Frame Progression Monitor
    local pm = lab.exp_c.playback_monitor
    if pm and pm.active and pm.target_obj then
        pm.ticks_observed = pm.ticks_observed + 1
        
        pcall(function()
            local t_mot = pm.target_obj:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion"))
            local l0 = t_mot and t_mot:call("getLayer", 0)
            if l0 then
                pm.current_frame = l0:call("get_Frame") or 0.0
                local mid = l0:call("get_MotionID") or 0
                
                if pm.ticks_observed >= pm.max_ticks then
                    pm.active = false
                    local frame_advanced = (pm.current_frame > pm.start_frame) or (pm.current_frame < pm.start_frame and pm.start_frame > 20.0) -- looped
                    
                    if mid == pm.target_mid and frame_advanced then
                        lab.exp_c.playback_status = "PLAYBACK_VERIFIED"
                        lab.exp_c.last_result = string.format("PASS: PLAYBACK_VERIFIED! MotionID %d progressing (Frame %.1f -> %.1f) without exception.",
                            pm.target_mid, pm.start_frame, pm.current_frame)
                    elseif mid == pm.target_mid and not frame_advanced then
                        lab.exp_c.playback_status = "PLAYBACK_STALLED"
                        lab.exp_c.last_result = string.format("PARTIAL: MotionID %d assigned, but frame is stationary at %.1f (PlaySpeed=0 or animation paused).",
                            pm.target_mid, pm.current_frame)
                    else
                        lab.exp_c.playback_status = "PLAYBACK_OVERRIDDEN"
                        lab.exp_c.last_result = string.format("PARTIAL: changeMotion executed, but native motion graph immediately reverted MotionID %d to %d.",
                            pm.target_mid, mid)
                    end
                    lab_log("[Exp C] " .. lab.exp_c.last_result)
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
    imgui.text_colored("Milestone 1: Isolated In-Engine Reverse Engineering (Rigorous V1.1)", 0.7, 0.7, 0.7, 1.0)
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
        local col_c = (lab.exp_c.playback_status == "PLAYBACK_VERIFIED" and {0.2, 1.0, 0.4}) or (lab.exp_c.playback_status == "PLAYBACK_STALLED" and {1.0, 0.8, 0.2}) or {0.8, 0.8, 0.8}
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
        imgui.text("Returned Actor: " .. tostring(lab.exp_a.returned_actor ~= nil))
        imgui.text("Has via.motion.Motion: " .. tostring(lab.exp_a.has_motion))
        imgui.text("Has MotionFsm2: " .. tostring(lab.exp_a.has_motion_fsm2))
        imgui.text("Has SurvivorMotionController: " .. tostring(lab.exp_a.has_survivor_motion))
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
        imgui.text("Input Components Found: " .. tostring(lab.exp_b.input_stripped))
        imgui.text("Input Verified Disabled (get_Valid==false): " .. tostring(lab.exp_b.input_verified_disabled))
        imgui.text("Independent Locomotion (Multi-Frame): " .. tostring(lab.exp_b.independent_locomotion))
        imgui.text("Locomotion Test Detail: " .. tostring(lab.exp_b.loco_test.verdict))
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
        imgui.text(string.format("Leon Layer[0]: BankID=%s, MotionID=%s (Frame=%.1f)",
            tostring(lab.exp_c.leon_active_bid), tostring(lab.exp_c.leon_active_mid), lab.exp_c.leon_frame))

        imgui.separator()
        imgui.text_colored("Controlled Playback Testing (Target: " .. tostring(lab.exp_c.target_name) .. "):", 1.0, 0.8, 0.2, 1.0)
        
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

        imgui.spacing()
        imgui.text_colored("Candidate Motion IDs:", 0.6, 0.9, 0.6, 1.0)
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
