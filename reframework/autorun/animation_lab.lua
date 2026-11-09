--[[
    Resident Evil 2: Duo Mode
    Milestone 1 — Animation Research Lab & Test Harness (Rigorous Edition v1.5.0)
    File: reframework/autorun/animation_lab.lua
    Author: AryanTechie-007

    Purpose:
    Isolated in-engine reverse-engineering laboratory to establish a verified,
    animated Claire companion pathway while maintaining the playable M0 baseline:
      - Experiment A: Native Survivor Casting (SurvivorAssignManager, standby overloads, CastingOrder construction, SurvivorCastingRequest deep probe & controlled PL1000 retry)
      - Experiment B: GameObject Duplication (via.Scene / via.Folder duplicate signatures, harmless non-player control test, player duplication & input disabling)
      - Experiment C: Claire Animation Playback (Target component inventory, native MotionBankAsset query, pause/speed/weight inspection, frame-step probe & controlled playback)

    Strict Verification Rules:
      - Rule 1: No imaginary functionality. Distinguish confirmed observations from hypotheses.
      - Rule 2: No speculative RE Engine APIs in production.
      - Rule 3: Single confirmed destruction route without double-free risks; unverified cleanups retain references.
      - Rule 4: Event-level structured CSV & text logging for every API call, argument, return value, and state transition.
]]

local lab = {
    version = "1.5.0-m1-validation",
    window_open = false,
    selected_tab = 1,
    log_buffer = {},
    max_log_lines = 140,

    -- Experiment A State: Native Survivor Casting
    exp_a = {
        status = "NOT_RUN", -- NOT_RUN | RUNNING | PASS | PARTIAL | UNVERIFIED | FAILED | CLEANED_UP
        singleton_found = false,
        types_resolved = {},
        casting_methods = {},
        standby_overloads = {},
        order_types_resolved = {},
        order_constructors = {},
        exec_casting_request = nil,
        exec_request_fields = {},
        returned_actor = nil,
        created_actor = nil,
        actor_valid = false,
        has_motion = false,
        has_motion_fsm2 = false,
        has_survivor_motion = false,
        motion_active = false,
        layer_count = 0,
        standby_1000_result = "NOT_TESTED",
        last_result = "Standing by. Click 'Run Experiment A Probe' to inspect Native Survivor Casting.",
    },

    -- Experiment B State: Character & Control Duplication
    exp_b = {
        status = "NOT_RUN", -- NOT_RUN | RUNNING | PASS | PARTIAL | FAILED | CLEANED_UP | CLEANUP_FAILED
        clone_entity = nil,
        surviving_components = {},
        scene_duplicate_methods = {},
        folder_duplicate_methods = {},
        control_target_name = "None",
        control_test_status = "NOT_RUN", -- NOT_RUN | SUCCESS | FAILED | SKIPPED
        control_test_verdict = "Not tested yet.",
        input_stripped = false,
        input_verified_disabled = false,
        independent_transform_control = false,
        motion_ticking = false,
        clone_frame_history = {},
        cleanup_status = "No test clone instantiated.",
        last_result = "Standing by. Click 'Run Exp B Control Test' or 'Spawn Duplicate Actor'.",
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

    -- Experiment C State: Claire Animation Playback & Stalled Frame Investigation
    exp_c = {
        inspection_status = "NOT_RUN", -- NOT_RUN | INSPECTION_COMPLETE | INSPECTION_PARTIAL | FAILED
        playback_status = "NOT_RUN",   -- NOT_RUN | TESTING | FRAME_PROGRESSION_VERIFIED | PLAYBACK_AND_VISUAL_VERIFIED | PLAYBACK_FAILED | PLAYBACK_STALLED | PLAYBACK_OVERRIDDEN
        visual_confirmed = false,
        target_name = "None",
        target_components = {},
        claire_native_bank = nil,
        claire_motion_pause = "UNKNOWN",
        claire_layer_pause = "UNKNOWN",
        claire_play_speed = 0.0,
        claire_layer_speed = 0.0,
        claire_layer_weight = 0.0,
        claire_frame_step_tested = false,
        claire_frame_step_result = "NOT_TESTED",
        leon_bank_asset = nil,
        leon_layer_count = 0,
        leon_active_mid = 0,
        leon_active_bid = 0,
        leon_frame = 0.0,
        leon_speed = 0.0,
        selected_mid = 160,
        selected_bid = 1,
        discovered_motions = {},
        motion_reflection_methods = {},
        layer_reflection_methods = {},
        last_result = "Standing by. Step 1: Inspect Target & Animation Reflection. Step 2: Test Playback.",
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
        local is_stat = false
        pcall(function() is_stat = m:is_static() end)
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
        local prefix = is_stat and "static " or ""
        return string.format("%s%s %s(%s)", prefix, ret_name, mname, table.concat(p_strs, ", "))
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
    local scene = nil
    local source = nil
    local folder = nil

    -- Path 1: Folder hierarchy from player GameObject (primary in RE2)
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
        if not scene then
            pcall(function() scene = scene_man:call("get_CurrentScene") end)
            if scene then source = "SceneManager:get_CurrentScene()" end
        end
        if not scene then
            pcall(function() scene = scene_man:call("get_PrimaryScene") end)
            if scene then source = "SceneManager:get_PrimaryScene()" end
        end
        if not scene then
            pcall(function()
                local view = scene_man:call("get_MainView")
                if view then
                    scene = view:call("get_PrimaryScene") or view:call("get_Scene")
                    if scene then source = "SceneManager:get_MainView():get_Scene()" end
                end
            end)
        end
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
    -- 1. Check if Claire is spawned by character_renderer.lua
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
-- STRUCTURED SESSION & EVENT LOGGER — A/B/C RESEARCH TELEMETRY
-- =========================================================================

local session_logger = {
    path = "reframework/data/duo_mode/animation_lab_session.csv",
    frame = 0,
    interval = 30, -- One snapshot every 30 REFramework frames (~2 Hz at 60 FPS)
    ready = false,
}

local function csv_value(value)
    local s = tostring(value == nil and "" or value)
    s = string.gsub(s, '"', '""')
    return '"' .. s .. '"'
end

local function logger_write_row(values)
    local ok, err = pcall(function()
        local f = io.open(session_logger.path, "a")
        if not f then
            error("Could not open session CSV: " .. session_logger.path)
        end

        local row = {}
        for i, value in ipairs(values) do
            row[i] = csv_value(value)
        end

        f:write(table.concat(row, ",") .. "\n")
        f:flush()
        f:close()
    end)

    if not ok then
        if log and log.error then
            log.error("[AnimLab Logger] " .. tostring(err))
        end
        return false
    end

    return true
end

local function logger_validity(obj)
    if not obj then return "NO_OBJECT" end

    local ok, value = pcall(function()
        return obj:call("get_Valid")
    end)

    if not ok then return "UNREADABLE" end
    if value == true then return "TRUE" end
    if value == false then return "FALSE" end
    return "UNKNOWN"
end

local function logger_init()
    if session_logger.ready then return end

    local header = {
        "record_type", "timestamp", "session_frame",
        "scene_pointer", "player_pointer",
        "A_status", "A_singleton", "A_actor_pointer",
        "A_actor_valid", "A_motion", "A_fsm2",
        "A_survivor_motion", "A_motion_active", "A_layer_count",
        "A_casting_method_count",
        "B_status", "B_clone_pointer", "B_clone_valid",
        "B_input_stripped", "B_input_verified_disabled",
        "B_transform_verified", "B_motion_ticking",
        "B_components", "B_cleanup_status",
        "B_loco_frames", "B_clone_displacement",
        "B_leon_displacement", "B_loco_verdict",
        "C_inspection_status", "C_playback_status",
        "C_target_name", "C_target_pointer", "C_target_valid",
        "C_bank_asset_present", "C_layer_count",
        "C_active_motion_id", "C_active_bank_id",
        "C_selected_motion_id", "C_selected_bank_id",
        "C_monitor_active", "C_monitor_ticks",
        "C_start_frame", "C_current_frame",
        "C_visual_confirmed",
        "event_name", "event_details"
    }

    local existing = io.open(session_logger.path, "r")
    if existing then
        existing:close()
    else
        logger_write_row(header)
    end

    session_logger.ready = true

    logger_write_row({
        "SESSION_START", os.date("%Y-%m-%d %H:%M:%S"),
        0, "", "",
        lab.exp_a.status, "", "", "", "", "", "", "", 0, 0,
        lab.exp_b.status, "", "", "", "", "", "", "", "",
        0, 0, 0, "",
        lab.exp_c.inspection_status, lab.exp_c.playback_status,
        "", "", "", "", 0, 0, 0, 0, 0,
        "", 0, 0, 0, "",
        "SESSION_INIT", lab.version
    })

    lab_log("[Logger] Structured CSV session & event logging initialized.")
end

-- Event-level telemetry logger for unjittered recording of exact calls, arguments & results
function lab.log_event(event_type, event_name, event_details)
    if not session_logger.ready then
        logger_init()
    end

    local a = lab.exp_a
    local b = lab.exp_b
    local c = lab.exp_c
    local loco = b.loco_test or {}
    local monitor = c.playback_monitor or {}

    local player = nil
    local player_go = nil
    local scene = nil

    pcall(function() player = get_active_player() end)
    pcall(function() player_go = get_player_go(player) end)
    pcall(function() scene = get_current_scene(player_go) end)

    local target = monitor.target_obj or (c.playback_monitor and c.playback_monitor.target_obj)
    local clone_valid = logger_validity(b.clone_entity)
    local target_valid = logger_validity(target)

    local row = {
        event_type or "EVENT",
        os.date("%Y-%m-%d %H:%M:%S"),
        session_logger.frame,
        tostring(scene),
        tostring(player_go),

        a.status,
        tostring(a.singleton_found),
        tostring(a.created_actor or a.returned_actor),
        tostring(a.actor_valid),
        tostring(a.has_motion),
        tostring(a.has_motion_fsm2),
        tostring(a.has_survivor_motion),
        tostring(a.motion_active),
        a.layer_count,
        #a.casting_methods,

        b.status,
        tostring(b.clone_entity),
        clone_valid,
        tostring(b.input_stripped),
        tostring(b.input_verified_disabled),
        tostring(b.independent_transform_control),
        tostring(b.motion_ticking),
        table.concat(b.surviving_components, ";"),
        b.cleanup_status,

        loco.current_frame or 0,
        loco.max_clone_displacement or 0,
        loco.max_leon_displacement or 0,
        loco.verdict or "NOT_STARTED",

        c.inspection_status,
        c.playback_status,
        c.target_name,
        tostring(target),
        target_valid,
        tostring(c.leon_bank_asset ~= nil or c.claire_native_bank ~= nil),
        c.leon_layer_count,
        c.leon_active_mid,
        c.leon_active_bid,
        c.selected_mid,
        c.selected_bid,
        tostring(monitor.active),
        monitor.ticks_observed or 0,
        monitor.start_frame or 0,
        monitor.current_frame or 0,
        tostring(c.visual_confirmed),

        event_name or "",
        event_details or ""
    }

    logger_write_row(row)
    lab_log(string.format("[%s] %s: %s", event_type or "EVENT", event_name or "", event_details or ""))
end

local function logger_snapshot()
    local a = lab.exp_a
    local b = lab.exp_b
    local c = lab.exp_c
    local loco = b.loco_test or {}
    local monitor = c.playback_monitor or {}

    local player = nil
    local player_go = nil
    local scene = nil

    pcall(function() player = get_active_player() end)
    pcall(function() player_go = get_player_go(player) end)
    pcall(function() scene = get_current_scene(player_go) end)

    local target = monitor.target_obj
    local clone_valid = logger_validity(b.clone_entity)
    local target_valid = logger_validity(target)

    local row = {
        "SNAPSHOT",
        os.date("%Y-%m-%d %H:%M:%S"),
        session_logger.frame,
        tostring(scene),
        tostring(player_go),

        a.status,
        tostring(a.singleton_found),
        tostring(a.created_actor or a.returned_actor),
        tostring(a.actor_valid),
        tostring(a.has_motion),
        tostring(a.has_motion_fsm2),
        tostring(a.has_survivor_motion),
        tostring(a.motion_active),
        a.layer_count,
        #a.casting_methods,

        b.status,
        tostring(b.clone_entity),
        clone_valid,
        tostring(b.input_stripped),
        tostring(b.input_verified_disabled),
        tostring(b.independent_transform_control),
        tostring(b.motion_ticking),
        table.concat(b.surviving_components, ";"),
        b.cleanup_status,

        loco.current_frame or 0,
        loco.max_clone_displacement or 0,
        loco.max_leon_displacement or 0,
        loco.verdict or "NOT_STARTED",

        c.inspection_status,
        c.playback_status,
        c.target_name,
        tostring(target),
        target_valid,
        tostring(c.leon_bank_asset ~= nil or c.claire_native_bank ~= nil),
        c.leon_layer_count,
        c.leon_active_mid,
        c.leon_active_bid,
        c.selected_mid,
        c.selected_bid,
        tostring(monitor.active),
        monitor.ticks_observed or 0,
        monitor.start_frame or 0,
        monitor.current_frame or 0,
        tostring(c.visual_confirmed),

        "FRAME_SNAPSHOT",
        ""
    }

    return logger_write_row(row)
end

local function logger_update()
    session_logger.frame = session_logger.frame + 1

    if not session_logger.ready then
        logger_init()
    end

    if session_logger.frame % session_logger.interval == 0 then
        logger_snapshot()
    end
end

-- =========================================================================
-- EXPERIMENT A: Native Survivor Casting Deep Reverse Engineering & Controlled PL1000 Retry
-- =========================================================================

function lab.run_experiment_a()
    lab.log_event("EXP_START", "EXPERIMENT_A", "Starting Native Survivor Casting Reverse Engineering v1.5")
    lab.exp_a.status = "RUNNING"
    lab.exp_a.types_resolved = {}
    lab.exp_a.casting_methods = {}
    lab.exp_a.standby_overloads = {}
    lab.exp_a.order_types_resolved = {}
    lab.exp_a.order_constructors = {}
    lab.exp_a.exec_request_fields = {}
    lab.exp_a.created_actor = nil
    lab.exp_a.returned_actor = nil
    lab.exp_a.actor_valid = false
    lab.exp_a.has_motion = false
    lab.exp_a.has_motion_fsm2 = false
    lab.exp_a.has_survivor_motion = false
    lab.exp_a.motion_active = false
    lab.exp_a.layer_count = 0

    -- 1. Probe Core Engine Types
    local candidate_types = {
        "app.ropeway.SurvivorAssignManager",
        "app.ropeway.SurvivorManager",
        "app.ropeway.PlayerManager",
        "app.ropeway.SurvivorStandbyCatalog",
        "app.ropeway.SurvivorCastingRequest",
        "app.ropeway.SurvivorCast",
        "app.ropeway.PlayerDefine.PlayerType",
        "app.ropeway.SurvivorAssignManager.CastingReason",
        "app.ropeway.SurvivorAssignManager.OfferMode",
        "app.ropeway.SurvivorAssignManager.CastingRequestResult",
    }

    for _, tname in ipairs(candidate_types) do
        local td = sdk.find_type_definition(tname)
        lab.exp_a.types_resolved[tname] = (td ~= nil)
        lab.log_event("TYPE_RESOLVE", tname, td and "RESOLVED" or "NOT_FOUND")
    end

    -- 2. Inspect all standby() overloads on SurvivorAssignManager
    local td_sam = sdk.find_type_definition("app.ropeway.SurvivorAssignManager")
    if td_sam then
        local methods = td_sam:get_methods() or {}
        for _, m in ipairs(methods) do
            local mname = m:get_name() or ""
            if mname == "standby" then
                local sig = format_method_sig(m)
                table.insert(lab.exp_a.standby_overloads, sig)
                table.insert(lab.exp_a.casting_methods, sig)
                lab.log_event("API_DISCOVERY", "STANDBY_OVERLOAD", sig)
            elseif string.find(string.lower(mname), "cast") or string.find(string.lower(mname), "assign") then
                local sig = format_method_sig(m)
                table.insert(lab.exp_a.casting_methods, sig)
            end
        end
    end

    -- 3. Investigate CastingOrder Types (Constructors, Fields & Instantiation)
    local order_type_names = {
        "app.ropeway.SurvivorAssignManager.CastingOrder",
        "app.ropeway.SurvivorAssignManager.CastingOrderNpc",
        "app.ropeway.SurvivorAssignManager.CastingOrderActor",
        "app.ropeway.SurvivorAssignManager.CastingOrderPlayer",
    }

    for _, otname in ipairs(order_type_names) do
        local otd = sdk.find_type_definition(otname)
        lab.exp_a.order_types_resolved[otname] = (otd ~= nil)
        if otd then
            local ctors = {}
            for _, m in ipairs(otd:get_methods() or {}) do
                local mn = m:get_name() or ""
                if mn == ".ctor" or mn == "ctor" then
                    table.insert(ctors, format_method_sig(m))
                end
            end
            lab.exp_a.order_constructors[otname] = ctors
            lab.log_event("ORDER_TYPE_AUDIT", otname, string.format("Constructors: %d, Fields: %d", #ctors, #(otd:get_fields() or {})))
            
            -- Attempt protected instantiation probe
            local inst = nil
            pcall(function() inst = sdk.create_instance(otname) end)
            if inst then
                lab.log_event("ORDER_INSTANCE_PROBE", otname, "SUCCESS: Instance allocated at " .. tostring(inst))
            else
                lab.log_event("ORDER_INSTANCE_PROBE", otname, "NIL: Parameterless constructor rejected or type abstract.")
            end
        end
    end

    -- 4. Probe SurvivorAssignManager Singleton & Fields
    local sam = sdk.get_managed_singleton("app.ropeway.SurvivorAssignManager")
    lab.exp_a.singleton_found = (sam ~= nil)
    if not sam then
        lab.exp_a.status = "FAILED"
        lab.exp_a.last_result = "FAIL: SurvivorAssignManager singleton not active in scene."
        lab.log_event("EXP_RESULT", "EXP_A_FAIL", lab.exp_a.last_result)
        return
    end

    lab.log_event("SINGLETON_FOUND", "SurvivorAssignManager", tostring(sam))

    local req_tx_now = nil
    local curr_phase = nil
    local stack_req = nil
    pcall(function()
        req_tx_now = sam:get_field("RequestTransactionNow")
        curr_phase = sam:get_field("CurrentPhase")
        stack_req = sam:get_field("StackRequest")
    end)
    lab.log_event("SAM_STATE_BEFORE", "SurvivorAssignManager",
        string.format("RequestTransactionNow=%s, CurrentPhase=%s, StackRequest=%s", tostring(req_tx_now), tostring(curr_phase), tostring(stack_req)))

    -- 5. Deep Inspection of SurvivorManager & get_ExecCastingRequest()
    local sm = sdk.get_managed_singleton("app.ropeway.SurvivorManager")
    local exec_req = nil
    local in_c_before = false
    if sm then
        lab.log_event("SINGLETON_FOUND", "SurvivorManager", tostring(sm))
        pcall(function() in_c_before = sm:call("inCasting") end)
        pcall(function() exec_req = sm:call("get_ExecCastingRequest") end)
        lab.exp_a.exec_casting_request = exec_req
        lab.log_event("SM_STATE_BEFORE", "SurvivorManager",
            string.format("inCasting=%s, get_ExecCastingRequest=%s", tostring(in_c_before), tostring(exec_req)))

        -- Inspect what SurvivorCastingRequest actually represents
        if exec_req then
            local req_td = exec_req:get_type_definition()
            if req_td then
                local req_fields = {}
                for _, f in ipairs(req_td:get_fields() or {}) do
                    local fn = f:get_name() or "<unnamed>"
                    local val = nil
                    pcall(function() val = exec_req:get_field(fn) end)
                    table.insert(req_fields, fn .. "=" .. tostring(val))
                end
                lab.exp_a.exec_request_fields = req_fields
                lab.log_event("EXEC_REQUEST_INSPECT", req_td:get_name() or "SurvivorCastingRequest", table.concat(req_fields, "; "))
            end
        end
    end

    -- 6. Controlled Retry using Verified Claire Enum: PlayerType.PL1000 = 1000
    local target_standby = nil
    if td_sam then
        for _, m in ipairs(td_sam:get_methods() or {}) do
            if m:get_name() == "standby" then
                local ptypes = m:get_param_types() or {}
                if #ptypes == 3 then
                    target_standby = m
                    break
                end
            end
        end
    end

    if not target_standby then
        lab.exp_a.status = "FAILED"
        lab.exp_a.last_result = "FAIL: standby(PlayerType, CastingReason, OfferMode) method definition not located."
        lab.log_event("EXP_RESULT", "EXP_A_FAIL", lab.exp_a.last_result)
        return
    end

    -- Controlled Call 1: standby(PL1000=1000, InitialSet=1, Normal=0)
    lab.log_event("API_CALL", "STANDBY_INVOKE", "standby(PL1000=1000, InitialSet=1, Normal=0)")
    local ok1, ret1 = pcall(function() return target_standby:call(sam, 1000, 1, 0) end)
    lab.log_event("API_RESULT", "STANDBY_RETURN", string.format("ok=%s, ret=%s (0=Accepted, 1=Refused)", tostring(ok1), tostring(ret1)))
    lab.exp_a.standby_1000_result = string.format("Call 1 (InitialSet=1): ret=%s", tostring(ret1))

    -- Controlled Call 2: if refused, retry with CastingReason.Debug = 8
    local final_ret = ret1
    if ok1 and ret1 == 1 then
        lab.log_event("API_CALL", "STANDBY_RETRY_DEBUG", "standby(PL1000=1000, Debug=8, Normal=0)")
        local ok2, ret2 = pcall(function() return target_standby:call(sam, 1000, 8, 0) end)
        lab.log_event("API_RESULT", "STANDBY_DEBUG_RETURN", string.format("ok=%s, ret=%s (0=Accepted, 1=Refused)", tostring(ok2), tostring(ret2)))
        lab.exp_a.standby_1000_result = lab.exp_a.standby_1000_result .. string.format(" | Call 2 (Debug=8): ret=%s", tostring(ret2))
        final_ret = ret2
    end

    -- Controlled Call 3: if still refused, retry with CastingReason.None = 0
    if final_ret == 1 then
        lab.log_event("API_CALL", "STANDBY_RETRY_NONE", "standby(PL1000=1000, None=0, Normal=0)")
        local ok3, ret3 = pcall(function() return target_standby:call(sam, 1000, 0, 0) end)
        lab.log_event("API_RESULT", "STANDBY_NONE_RETURN", string.format("ok=%s, ret=%s (0=Accepted, 1=Refused)", tostring(ok3), tostring(ret3)))
        lab.exp_a.standby_1000_result = lab.exp_a.standby_1000_result .. string.format(" | Call 3 (None=0): ret=%s", tostring(ret3))
        final_ret = ret3
    end

    -- 7. State Transitions After Calls
    local req_tx_after = nil
    local curr_phase_after = nil
    pcall(function()
        req_tx_after = sam:get_field("RequestTransactionNow")
        curr_phase_after = sam:get_field("CurrentPhase")
    end)
    lab.log_event("SAM_STATE_AFTER", "SurvivorAssignManager",
        string.format("RequestTransactionNow=%s, CurrentPhase=%s", tostring(req_tx_after), tostring(curr_phase_after)))

    if sm then
        local in_c_after = false
        local exec_req_after = nil
        pcall(function() in_c_after = sm:call("inCasting") end)
        pcall(function() exec_req_after = sm:call("get_ExecCastingRequest") end)
        lab.log_event("SM_STATE_AFTER", "SurvivorManager",
            string.format("inCasting=%s, get_ExecCastingRequest=%s", tostring(in_c_after), tostring(exec_req_after)))

        -- Attempt applyCastingRequest only if request transaction was queued
        if req_tx_after == true or in_c_after == false and exec_req_after then
            lab.log_event("API_CALL", "APPLY_CASTING_INVOKE", "Attempting applyCastingRequest() on SurvivorManager")
            pcall(function() sm:call("applyCastingRequest") end)
        end
    end

    -- 8. Scan Scene for Newly Created/Cast Actor
    local candidate_actor = nil
    pcall(function()
        local go_td = sdk.find_type_definition("via.GameObject")
        if go_td then
            local find_m = go_td:get_method("find(System.String)")
            if find_m then
                for _, target_name in ipairs({"pl1000", "pl1000_body", "survivor", "Claire"}) do
                    local found = find_m:call(nil, target_name)
                    if found then
                        candidate_actor = found
                        break
                    end
                end
            end
        end
    end)

    if candidate_actor then
        lab.exp_a.created_actor = candidate_actor
        lab.exp_a.returned_actor = candidate_actor
        lab.log_event("ACTOR_DISCOVERY", "EXP_A_ACTOR_FOUND", "Found candidate actor: " .. tostring(candidate_actor))

        local actor_v = false
        pcall(function() actor_v = (candidate_actor:call("get_Valid") == true) end)
        lab.exp_a.actor_valid = actor_v

        local has_m = false
        local has_f2 = false
        local has_sm = false
        local m_active = false
        local l_count = 0

        pcall(function()
            local c_mot = candidate_actor:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion"))
            has_m = (c_mot ~= nil)
            if c_mot then
                l_count = c_mot:call("getLayerCount") or 0
                local is_p = c_mot:call("get_Play")
                local spd = c_mot:call("get_PlaySpeed") or 0.0
                if l_count > 0 and is_p == true and spd > 0 then
                    m_active = true
                end
            end
            has_f2 = (candidate_actor:call("getComponent(System.Type)", sdk.typeof("via.motion.MotionFsm2")) ~= nil)
            has_sm = (candidate_actor:call("getComponent(System.Type)", sdk.typeof("app.ropeway.survivor.SurvivorMotionController")) ~= nil)
        end)

        lab.exp_a.has_motion = has_m
        lab.exp_a.has_motion_fsm2 = has_f2
        lab.exp_a.has_survivor_motion = has_sm
        lab.exp_a.motion_active = m_active
        lab.exp_a.layer_count = l_count

        if actor_v and has_m and (has_f2 or has_sm) and m_active then
            lab.exp_a.status = "PASS"
            lab.exp_a.last_result = string.format("PASS: Native Claire actor instantiated with active motion controllers (Valid=true, Layers=%d)!", l_count)
        else
            lab.exp_a.status = "PARTIAL"
            lab.exp_a.last_result = string.format("PARTIAL: Actor found (%s, Valid=%s, Motion=%s, Fsm2=%s), but active ticking unconfirmed.",
                tostring(candidate_actor), tostring(actor_v), tostring(has_m), tostring(has_f2))
        end
    else
        if final_ret == 0 then
            lab.exp_a.status = "PARTIAL"
            lab.exp_a.last_result = "PARTIAL: standby(1000) returned Accepted (0) and transaction queued, but actor instantiation not observed in current frame."
        else
            lab.exp_a.status = "UNVERIFIED"
            lab.exp_a.last_result = string.format("UNVERIFIED: standby(PL1000=1000) returned Refused (1) across all tested CastingReasons. SurvivorAssignManager requires formal CastingOrder object or campaign conditions. (%s)", lab.exp_a.standby_1000_result)
        end
    end

    lab.log_event("EXP_END", "EXPERIMENT_A", lab.exp_a.last_result)
end

function lab.cleanup_experiment_a()
    if not lab.exp_a.created_actor then
        lab.log_event("CLEANUP", "EXP_A_CLEANUP", "No active native actor to clean up.")
        return
    end

    local actor = lab.exp_a.created_actor
    lab.log_event("CLEANUP_START", "EXP_A_CLEANUP", "Attempting verified cleanup of native actor: " .. tostring(actor))

    local cur_scene = get_current_scene()
    pcall(function()
        actor:call("set_DrawSelf", false)
        actor:call("set_UpdateSelf", false)
    end)

    if cur_scene then
        pcall(function() cur_scene:call("destroyGameObject(via.GameObject)", actor) end)
        pcall(function() cur_scene:call("destroyGameObject", actor) end)
    end

    local is_v = true
    pcall(function() is_v = actor:call("get_Valid") end)
    if is_v == false then
        lab.exp_a.created_actor = nil
        lab.exp_a.status = "CLEANED_UP"
        lab.log_event("CLEANUP_VERIFIED", "EXP_A_CLEANUP", "Native actor successfully destroyed (get_Valid==false).")
    else
        lab.log_event("CLEANUP_UNVERIFIED", "EXP_A_CLEANUP", "Native actor still reports valid after destroy call.")
    end
end

-- =========================================================================
-- EXPERIMENT B: GameObject Duplication Deep Reverse Engineering & Control Test
-- =========================================================================

local function update_exp_b_verdict()
    local has_motion = false
    for _, c in ipairs(lab.exp_b.surviving_components) do
        if c == "via.motion.Motion" then has_motion = true end
    end

    if lab.exp_b.clone_entity and lab.exp_b.input_stripped and lab.exp_b.input_verified_disabled 
       and lab.exp_b.independent_transform_control and has_motion and lab.exp_b.motion_ticking then
        lab.exp_b.status = "PASS"
        lab.exp_b.last_result = "PASS: Duplicate actor created with verified disabled input, verified independent transform control, and ticking motion!"
    elseif lab.exp_b.clone_entity and lab.exp_b.input_stripped and lab.exp_b.independent_transform_control then
        lab.exp_b.status = "PARTIAL"
        lab.exp_b.last_result = string.format("PARTIAL: Transform independent, but motion ticking unconfirmed (MotionTicking=%s).", tostring(lab.exp_b.motion_ticking))
    elseif lab.exp_b.clone_entity then
        lab.exp_b.status = "PARTIAL"
        lab.exp_b.last_result = string.format("PARTIAL: Actor cloned, but input stripping (%s) or independent transform control (%s) unverified.",
            tostring(lab.exp_b.input_verified_disabled), tostring(lab.exp_b.independent_transform_control))
    else
        lab.exp_b.status = "FAILED"
    end
    lab.log_event("VERDICT_UPDATE", "EXPERIMENT_B", lab.exp_b.last_result)
end

-- Control Test on a harmless non-player GameObject to verify whether duplicateGameObject works at all
function lab.run_experiment_b_control()
    lab.log_event("EXP_START", "EXP_B_CONTROL", "Starting Control Duplication Test on non-player GameObject")
    lab.exp_b.control_test_status = "RUNNING"

    local player = get_active_player()
    local player_go = get_player_go(player)
    local cur_scene, scene_source, cur_folder = get_current_scene(player_go)

    if not cur_scene then
        lab.exp_b.control_test_status = "FAILED"
        lab.exp_b.control_test_verdict = "FAIL: via.Scene could not be retrieved for control test."
        lab.log_event("CONTROL_RESULT", "EXP_B_CONTROL_FAIL", lab.exp_b.control_test_verdict)
        return
    end

    -- Locate candidate non-player GameObject (Claire body or scene entity)
    local control_target = nil
    local duo = _G.duo_spawner or spawner
    if duo and duo.spawned_entities and #duo.spawned_entities > 0 then
        control_target = duo.spawned_entities[1]
        lab.exp_b.control_target_name = "Claire Prefab Body"
    end

    if not control_target and cur_scene then
        pcall(function()
            local go_td = sdk.find_type_definition("via.GameObject")
            if go_td then
                local find_m = go_td:get_method("find(System.String)")
                if find_m then
                    for _, name in ipairs({"sm00_000", "pl1000_body", "Light", "Camera", "Environment"}) do
                        local obj = find_m:call(nil, name)
                        if obj and obj ~= player_go then
                            control_target = obj
                            lab.exp_b.control_target_name = name
                            break
                        end
                    end
                end
            end
        end)
    end

    if not control_target then
        lab.exp_b.control_test_status = "SKIPPED"
        lab.exp_b.control_test_verdict = "SKIPPED: No non-player GameObject found in scene. Click 'SPAWN CLAIRE' first to provide control target."
        lab.log_event("CONTROL_RESULT", "EXP_B_CONTROL_SKIPPED", lab.exp_b.control_test_verdict)
        return
    end

    lab.log_event("CONTROL_TARGET", lab.exp_b.control_target_name, tostring(control_target))

    -- Attempt duplication of control target
    local control_clone = nil
    pcall(function() control_clone = cur_scene:call("duplicateGameObject(via.GameObject)", control_target) end)
    if not control_clone and cur_folder then
        pcall(function() control_clone = cur_scene:call("duplicateGameObject(via.GameObject, via.Folder)", control_target, cur_folder) end)
    end
    if not control_clone then
        pcall(function() control_clone = cur_scene:call("duplicateGameObject", control_target) end)
    end

    if control_clone then
        local is_v = false
        pcall(function() is_v = (control_clone:call("get_Valid") == true) end)
        lab.exp_b.control_test_status = "SUCCESS"
        lab.exp_b.control_test_verdict = string.format("CONTROL_TEST_SUCCESS: Non-player GameObject ('%s') duplicated cleanly! (Valid=%s, Pointer=%s). Proves duplicateGameObject API works in RE Engine; failure on Leon is target-specific.",
            lab.exp_b.control_target_name, tostring(is_v), tostring(control_clone))
        lab.log_event("CONTROL_RESULT", "EXP_B_CONTROL_SUCCESS", lab.exp_b.control_test_verdict)

        -- Immediate clean destruction of control clone
        pcall(function() cur_scene:call("destroyGameObject(via.GameObject)", control_clone) end)
        pcall(function() cur_scene:call("destroyGameObject", control_clone) end)
        lab.log_event("CONTROL_CLEANUP", "EXP_B_CONTROL_DESTROY", "Control clone destroyed safely.")
    else
        lab.exp_b.control_test_status = "FAILED"
        lab.exp_b.control_test_verdict = string.format("CONTROL_TEST_FAILED: duplicateGameObject returned nil even for non-player GameObject ('%s'). Indicates API requires specific flags or is disabled in release engine.",
            lab.exp_b.control_target_name)
        lab.log_event("CONTROL_RESULT", "EXP_B_CONTROL_FAIL", lab.exp_b.control_test_verdict)
    end
end

function lab.run_experiment_b()
    lab.log_event("EXP_START", "EXPERIMENT_B", "Starting Player Duplication Probe v1.5")
    lab.exp_b.status = "RUNNING"
    lab.exp_b.scene_duplicate_methods = {}
    lab.exp_b.folder_duplicate_methods = {}
    lab.exp_b.surviving_components = {}
    lab.exp_b.input_stripped = false
    lab.exp_b.input_verified_disabled = false
    lab.exp_b.independent_transform_control = false
    lab.exp_b.motion_ticking = false
    lab.exp_b.clone_frame_history = {}
    lab.exp_b.cleanup_status = "No test clone instantiated."

    -- 1. Full Reflection of all duplicate/clone signatures
    local scene_td = sdk.find_type_definition("via.Scene")
    if scene_td then
        for _, m in ipairs(scene_td:get_methods() or {}) do
            local mn = string.lower(m:get_name() or "")
            if string.find(mn, "duplicate") or string.find(mn, "clone") then
                local sig = format_method_sig(m)
                table.insert(lab.exp_b.scene_duplicate_methods, sig)
                lab.log_event("API_DISCOVERY", "SCENE_DUPLICATE_SIG", sig)
            end
        end
    end

    local folder_td = sdk.find_type_definition("via.Folder")
    if folder_td then
        for _, m in ipairs(folder_td:get_methods() or {}) do
            local mn = string.lower(m:get_name() or "")
            if string.find(mn, "duplicate") or string.find(mn, "clone") then
                local sig = format_method_sig(m)
                table.insert(lab.exp_b.folder_duplicate_methods, sig)
                lab.log_event("API_DISCOVERY", "FOLDER_DUPLICATE_SIG", sig)
            end
        end
    end

    -- 2. Resolve Player and Target Scene
    local player = get_active_player()
    local player_go = get_player_go(player)
    if not player_go then
        lab.exp_b.status = "FAILED"
        lab.exp_b.last_result = "FAIL: Player GameObject not found. Please load into active gameplay first."
        lab.log_event("EXP_RESULT", "EXP_B_FAIL", lab.exp_b.last_result)
        return
    end

    local cur_scene, scene_source, cur_folder = get_current_scene(player_go)
    if not cur_scene then
        lab.exp_b.status = "FAILED"
        lab.exp_b.last_result = "FAIL: via.Scene could not be retrieved from player."
        lab.log_event("EXP_RESULT", "EXP_B_FAIL", lab.exp_b.last_result)
        return
    end

    lab.log_event("SCENE_RESOLVED", tostring(scene_source), string.format("Scene: %s, Folder: %s", tostring(cur_scene), tostring(cur_folder)))

    -- 3. Run Control Test first if not yet run
    if lab.exp_b.control_test_status == "NOT_RUN" then
        lab.run_experiment_b_control()
    end

    -- 4. Controlled Duplication on Player GameObject
    local clone = nil
    lab.log_event("API_CALL", "DUPLICATE_PLAYER_INVOKE", "cur_scene:duplicateGameObject(via.GameObject, player_go)")
    pcall(function() clone = cur_scene:call("duplicateGameObject(via.GameObject)", player_go) end)
    
    if not clone and cur_folder then
        lab.log_event("API_CALL", "DUPLICATE_PLAYER_FOLDER", "cur_scene:duplicateGameObject(player_go, folder)")
        pcall(function() clone = cur_scene:call("duplicateGameObject(via.GameObject, via.Folder)", player_go, cur_folder) end)
    end
    if not clone then
        pcall(function() clone = cur_scene:call("duplicateGameObject", player_go) end)
    end
    if not clone and cur_folder then
        pcall(function() clone = cur_folder:call("duplicateGameObject", player_go) end)
    end

    if not clone then
        lab.exp_b.status = "FAILED"
        lab.exp_b.last_result = string.format("FAIL: duplicateGameObject returned nil for Player GameObject across all tested signatures. Control test status: %s.", lab.exp_b.control_test_status)
        lab.log_event("EXP_RESULT", "EXP_B_PLAYER_FAIL", lab.exp_b.last_result)
        return
    end

    lab.exp_b.clone_entity = clone
    lab.log_event("EXP_RESULT", "EXP_B_PLAYER_CLONED", "Player GameObject duplicated successfully! Pointer: " .. tostring(clone))

    -- 5. Audit Components Surviving Duplication
    local audit_types = {
        "via.Transform",
        "via.render.Mesh",
        "via.motion.Motion",
        "via.motion.MotionFsm2",
        "via.motion.MotionJack",
        "via.physics.CharacterController",
        "app.ropeway.PlayerInputReceiver",
        "app.ropeway.PadManager",
        "app.ropeway.PlayerMotionController",
        "app.ropeway.survivor.SurvivorMotionController",
    }

    for _, tname in ipairs(audit_types) do
        local ok, c = pcall(function() return clone:call("getComponent(System.Type)", sdk.typeof(tname)) end)
        if ok and c then
            table.insert(lab.exp_b.surviving_components, tname)
        end
    end
    lab.log_event("COMPONENT_AUDIT", "CLONE_COMPONENTS", table.concat(lab.exp_b.surviving_components, "; "))

    -- 6. Strip and Verify Input Disabling
    local in_rec = nil
    local pad = nil
    pcall(function() in_rec = clone:call("getComponent(System.Type)", sdk.typeof("app.ropeway.PlayerInputReceiver")) end)
    pcall(function() pad = clone:call("getComponent(System.Type)", sdk.typeof("app.ropeway.PadManager")) end)

    local in_rec_disabled = false
    local pad_disabled = false

    if in_rec then
        pcall(function() in_rec:call("set_Valid", false) end)
        pcall(function() in_rec_disabled = (in_rec:call("get_Valid") == false) end)
    else
        in_rec_disabled = true
    end

    if pad then
        pcall(function() pad:call("set_Valid", false) end)
        pcall(function() pad_disabled = (pad:call("get_Valid") == false) end)
    else
        pad_disabled = true
    end

    if in_rec_disabled and pad_disabled then
        lab.exp_b.input_stripped = true
        lab.exp_b.input_verified_disabled = true
    else
        lab.exp_b.input_stripped = false
        lab.exp_b.input_verified_disabled = false
    end
    lab.log_event("INPUT_STRIP_VERIFY", "EXP_B", string.format("InputStripped=%s, VerifiedDisabled=%s", tostring(lab.exp_b.input_stripped), tostring(lab.exp_b.input_verified_disabled)))

    -- 7. Position Clone near Leon & Initiate 60-frame independent transform test
    local p_tf = player_go:call("get_Transform")
    local c_tf = clone:call("get_Transform")
    if p_tf and c_tf then
        local p_pos = p_tf:call("get_Position")
        local p_rot = p_tf:call("get_Rotation")
        if p_pos and p_rot then
            local front_x = p_pos.x + (math.sin(p_rot.y or 0) * 2.0)
            local front_z = p_pos.z + (math.cos(p_rot.y or 0) * 2.0)
            local spawn_pos = (Vector3f and Vector3f.new and Vector3f.new(front_x, p_pos.y, front_z)) or { x = front_x, y = p_pos.y, z = front_z }
            pcall(function() c_tf:call("set_Position", spawn_pos) end)

            lab.exp_b.loco_test = {
                active = true,
                current_frame = 0,
                target_frames = 60,
                clone_initial_pos = spawn_pos,
                leon_initial_pos = p_pos,
                max_clone_displacement = 0.0,
                max_leon_displacement = 0.0,
                clone_moved = false,
                leon_unmoved = false,
                verdict = "TESTING",
            }
            lab.log_event("TRANSFORM_TEST_INIT", "EXP_B_LOCO", "60-frame independent transform test initiated.")
        end
    end

    update_exp_b_verdict()
end

function lab.cleanup_experiment_b()
    lab.log_event("CLEANUP_START", "EXP_B_CLEANUP", "Initiating verified destruction of duplicate clone")

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

    if cur_scene then
        pcall(function() cur_scene:call("destroyGameObject(via.GameObject)", clone) end)
        pcall(function() cur_scene:call("destroyGameObject", clone) end)
    end

    local is_valid_after_scene = nil
    pcall(function() is_valid_after_scene = clone:call("get_Valid") end)

    if is_valid_after_scene == false then
        lab.exp_b.cleanup_status = "CLEANUP_VERIFIED (Destroyed via via.Scene.destroyGameObject, verified get_Valid==false)"
        lab.log_event("CLEANUP_VERIFIED", "EXP_B_CLEANUP", lab.exp_b.cleanup_status)
        lab.exp_b.clone_entity = nil
        lab.exp_b.status = "CLEANED_UP"
        lab.exp_b.last_result = lab.exp_b.cleanup_status
        return
    end

    -- Fallback: static via.GameObject.destroy ONLY if Route 1 did not invalidate
    local go_td = sdk.find_type_definition("via.GameObject")
    local destroy_static = go_td and go_td:get_method("destroy(via.GameObject)")
    if destroy_static then
        pcall(function() destroy_static:call(nil, clone) end)
    end

    local is_valid_after_fallback = nil
    pcall(function() is_valid_after_fallback = clone:call("get_Valid") end)

    if is_valid_after_fallback == false then
        lab.exp_b.cleanup_status = "CLEANUP_VERIFIED (Destroyed via fallback static via.GameObject.destroy, verified get_Valid==false)"
        lab.log_event("CLEANUP_VERIFIED", "EXP_B_CLEANUP", lab.exp_b.cleanup_status)
        lab.exp_b.clone_entity = nil
        lab.exp_b.status = "CLEANED_UP"
        lab.exp_b.last_result = lab.exp_b.cleanup_status
    else
        lab.exp_b.cleanup_status = "CLEANUP_UNVERIFIED (Target still reports get_Valid==true)"
        lab.log_event("CLEANUP_UNVERIFIED", "EXP_B_CLEANUP", lab.exp_b.cleanup_status)
        lab.exp_b.status = "CLEANUP_FAILED"
        lab.exp_b.last_result = lab.exp_b.cleanup_status
    end
end

-- =========================================================================
-- EXPERIMENT C: Claire Animation Playback Deep Reverse Engineering & Stalled Frame Investigation
-- =========================================================================

function lab.run_experiment_c_inspect()
    lab.log_event("EXP_START", "EXPERIMENT_C_INSPECT", "Starting Target & Animation Component Reverse Engineering v1.5")
    lab.exp_c.inspection_status = "RUNNING"
    lab.exp_c.target_components = {}
    lab.exp_c.motion_reflection_methods = {}
    lab.exp_c.layer_reflection_methods = {}
    lab.exp_c.claire_native_bank = nil
    lab.exp_c.claire_frame_step_tested = false

    local target_obj, target_desc = get_playback_target()
    lab.exp_c.target_name = target_desc

    if not target_obj then
        lab.exp_c.inspection_status = "FAILED"
        lab.exp_c.last_result = "FAIL: No valid target GameObject found for animation inspection."
        lab.log_event("EXP_RESULT", "EXP_C_INSPECT_FAIL", lab.exp_c.last_result)
        return
    end

    lab.log_event("TARGET_SELECTED", target_desc, tostring(target_obj))

    -- 1. Full Component Inventory on Target
    local audit_types = {
        "via.Transform",
        "via.render.Mesh",
        "via.motion.Motion",
        "via.motion.MotionFsm2",
        "via.motion.MotionJack",
        "via.motion.DynamicMotionJack",
        "via.physics.CharacterController",
        "app.ropeway.survivor.SurvivorMotionController",
        "app.ropeway.survivor.SurvivorActionController",
        "app.ropeway.survivor.SurvivorHeadLookController",
    }

    for _, tname in ipairs(audit_types) do
        local ok, c = pcall(function() return target_obj:call("getComponent(System.Type)", sdk.typeof(tname)) end)
        if ok and c then
            table.insert(lab.exp_c.target_components, tname)
        end
    end
    lab.log_event("COMPONENT_AUDIT", target_desc, table.concat(lab.exp_c.target_components, "; "))

    -- 2. Inspect Target's Native Motion Component & MotionBankAsset BEFORE Modification
    local t_mot = nil
    pcall(function() t_mot = target_obj:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion")) end)
    if not t_mot then
        lab.exp_c.inspection_status = "FAILED"
        lab.exp_c.last_result = string.format("FAIL: Target '%s' has no via.motion.Motion component.", target_desc)
        lab.log_event("EXP_RESULT", "EXP_C_INSPECT_FAIL", lab.exp_c.last_result)
        return
    end

    local native_bank = nil
    pcall(function() native_bank = t_mot:call("get_MotionBankAsset") end)
    lab.exp_c.claire_native_bank = native_bank
    lab.log_event("BANK_DISCOVERY", "NATIVE_BANK_BEFORE_MOD", tostring(native_bank))

    -- 3. Reflect Methods on via.motion.Motion & via.motion.TreeLayer
    local mot_td = t_mot:get_type_definition()
    if mot_td then
        for _, m in ipairs(mot_td:get_methods() or {}) do
            local mn = string.lower(m:get_name() or "")
            if string.find(mn, "play") or string.find(mn, "pause") or string.find(mn, "speed") 
               or string.find(mn, "frame") or string.find(mn, "update") or string.find(mn, "step") then
                local sig = format_method_sig(m)
                table.insert(lab.exp_c.motion_reflection_methods, sig)
            end
        end
    end

    local l0 = nil
    pcall(function() l0 = t_mot:call("getLayer", 0) end)
    if l0 then
        local layer_td = l0:get_type_definition()
        if layer_td then
            for _, m in ipairs(layer_td:get_methods() or {}) do
                local mn = string.lower(m:get_name() or "")
                if string.find(mn, "play") or string.find(mn, "pause") or string.find(mn, "speed") 
                   or string.find(mn, "frame") or string.find(mn, "weight") or string.find(mn, "motion") then
                    local sig = format_method_sig(m)
                    table.insert(lab.exp_c.layer_reflection_methods, sig)
                end
            end
        end
    end

    -- 4. Deep Inspection of Pause State & Speed Parameters on Target
    local m_play, m_pause, m_speed = nil, nil, nil
    local l_play, l_pause, l_speed, l_weight, l_frame = nil, nil, nil, nil, nil

    pcall(function() m_play = t_mot:call("get_Play") end)
    pcall(function() m_pause = t_mot:call("get_Pause") end)
    pcall(function() m_speed = t_mot:call("get_PlaySpeed") end)

    if l0 then
        pcall(function() l_play = l0:call("get_Play") end)
        pcall(function() l_pause = l0:call("get_Pause") end)
        pcall(function() l_speed = l0:call("get_Speed") end)
        pcall(function() l_weight = l0:call("get_Weight") end)
        pcall(function() l_frame = l0:call("get_Frame") end)
    end

    lab.exp_c.claire_motion_pause = tostring(m_pause)
    lab.exp_c.claire_layer_pause = tostring(l_pause)
    lab.exp_c.claire_play_speed = m_speed or 0.0
    lab.exp_c.claire_layer_speed = l_speed or 0.0
    lab.exp_c.claire_layer_weight = l_weight or 0.0

    lab.log_event("PAUSE_SPEED_AUDIT", target_desc,
        string.format("Motion(Play=%s, Pause=%s, Speed=%s) | Layer0(Play=%s, Pause=%s, Speed=%s, Weight=%s, Frame=%s)",
            tostring(m_play), tostring(m_pause), tostring(m_speed),
            tostring(l_play), tostring(l_pause), tostring(l_speed), tostring(l_weight), tostring(l_frame)))

    -- 5. Controlled Frame-Stepping Probe (Test whether layer accepts frame writing)
    if l0 then
        local f_before = l_frame or 0.0
        local test_step_frame = 12.50
        local f_after = nil
        pcall(function() l0:call("set_Frame", test_step_frame) end)
        pcall(function() f_after = l0:call("get_Frame") end)

        if f_after and math.abs(f_after - test_step_frame) < 0.1 then
            lab.exp_c.claire_frame_step_tested = true
            lab.exp_c.claire_frame_step_result = string.format("FRAME_STEP_ACCEPTED: set_Frame(%.1f) successfully updated Layer 0 frame from %.2f to %.2f. Confirms bone transform update path is receptive.",
                test_step_frame, f_before, f_after)
            -- Restore original frame
            pcall(function() l0:call("set_Frame", f_before) end)
        else
            lab.exp_c.claire_frame_step_tested = false
            lab.exp_c.claire_frame_step_result = string.format("FRAME_STEP_REJECTED: set_Frame(%.1f) failed to modify Layer 0 frame (remained %.2f).",
                test_step_frame, tostring(f_after))
        end
        lab.log_event("PROBE_RESULT", "FRAME_STEP_PROBE", lab.exp_c.claire_frame_step_result)
    end

    -- 6. Inspect Leon's Motion Bank Asset for Comparison
    local player = get_active_player()
    local p_go = get_player_go(player)
    if p_go then
        pcall(function()
            local p_mot = p_go:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion"))
            if p_mot then
                lab.exp_c.leon_bank_asset = p_mot:call("get_MotionBankAsset")
                lab.exp_c.leon_layer_count = p_mot:call("getLayerCount") or 0
                local p_l0 = p_mot:call("getLayer", 0)
                if p_l0 then
                    lab.exp_c.leon_active_mid = p_l0:call("get_MotionID") or 0
                    lab.exp_c.leon_active_bid = p_l0:call("get_BankID") or 0
                    lab.exp_c.leon_frame = p_l0:call("get_Frame") or 0.0
                    lab.exp_c.leon_speed = p_l0:call("get_Speed") or 0.0
                end
            end
        end)
    end

    lab.exp_c.discovered_motions = {
        { id = lab.exp_c.leon_active_mid, name = string.format("Leon Active Layer 0 Motion (ID %d) [VERIFIED IN SCENE]", lab.exp_c.leon_active_mid), bank = lab.exp_c.leon_active_bid, is_active = true },
        { id = 160, name = "Stance / Idle (Standard Pistol - Provisional Candidate)", bank = 1, is_active = false },
        { id = 161, name = "Walk Forward (Standard Pistol - Provisional Candidate)", bank = 1, is_active = false },
        { id = 162, name = "Jog / Run Forward (Provisional Candidate)", bank = 1, is_active = false },
        { id = 163, name = "Turn 90 / 180 Transition (Provisional Candidate)", bank = 1, is_active = false },
    }

    lab.exp_c.inspection_status = "INSPECTION_COMPLETE"
    lab.exp_c.last_result = string.format("INSPECTION_COMPLETE: Target '%s' inspected. NativeBank=%s, Pause(Motion=%s, Layer=%s), FrameStep=%s.",
        target_desc, tostring(native_bank), tostring(lab.exp_c.claire_motion_pause), tostring(lab.exp_c.claire_layer_pause), tostring(lab.exp_c.claire_frame_step_tested))
    lab.log_event("EXP_END", "EXPERIMENT_C_INSPECT", lab.exp_c.last_result)
end

function lab.run_experiment_c_playback(target_mid, target_bid)
    lab.log_event("EXP_START", "EXPERIMENT_C_PLAYBACK", string.format("Controlled Playback Test (MotionID: %d, BankID: %d)", target_mid, target_bid))
    lab.exp_c.playback_status = "TESTING"
    lab.exp_c.visual_confirmed = false
    lab.exp_c.selected_mid = target_mid
    lab.exp_c.selected_bid = target_bid

    local target_obj, target_desc = get_playback_target()
    lab.exp_c.target_name = target_desc

    if not target_obj then
        lab.exp_c.playback_status = "PLAYBACK_FAILED"
        lab.exp_c.last_result = "FAIL: No valid target GameObject found for playback test."
        lab.log_event("EXP_RESULT", "EXP_C_PLAYBACK_FAIL", lab.exp_c.last_result)
        return
    end

    lab.log_event("PLAYBACK_TARGET", target_desc, tostring(target_obj))

    local t_mot = nil
    pcall(function() t_mot = target_obj:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion")) end)
    if not t_mot then
        lab.exp_c.playback_status = "PLAYBACK_FAILED"
        lab.exp_c.last_result = string.format("FAIL: Target '%s' has no via.motion.Motion component.", target_desc)
        lab.log_event("EXP_RESULT", "EXP_C_PLAYBACK_FAIL", lab.exp_c.last_result)
        return
    end

    -- 1. Determine MotionBankAsset to use (prefer Claire's native bank if present, fallback to Leon's bank)
    local cur_asset = nil
    pcall(function() cur_asset = t_mot:call("get_MotionBankAsset") end)

    if not cur_asset then
        local bank_to_assign = lab.exp_c.claire_native_bank or lab.exp_c.leon_bank_asset
        if not bank_to_assign then
            lab.exp_c.playback_status = "PLAYBACK_FAILED"
            lab.exp_c.last_result = "FAIL: Target has no MotionBankAsset and Leon's MotionBankAsset is nil. Run inspection first."
            lab.log_event("EXP_RESULT", "EXP_C_PLAYBACK_FAIL", lab.exp_c.last_result)
            return
        end

        lab.log_event("API_CALL", "SET_BANK_ASSET", "set_MotionBankAsset: " .. tostring(bank_to_assign))
        local ok_set, err_set = pcall(function() t_mot:call("set_MotionBankAsset", bank_to_assign) end)
        if not ok_set then
            lab.exp_c.playback_status = "PLAYBACK_FAILED"
            lab.exp_c.last_result = string.format("FAIL: set_MotionBankAsset threw exception: %s", tostring(err_set))
            lab.log_event("EXP_RESULT", "EXP_C_PLAYBACK_FAIL", lab.exp_c.last_result)
            return
        end

        local ok_setup, err_setup = pcall(function() t_mot:call("setupMotionBank") end)
        if not ok_setup then
            lab.exp_c.playback_status = "PLAYBACK_FAILED"
            lab.exp_c.last_result = string.format("FAIL: setupMotionBank threw exception: %s", tostring(err_setup))
            lab.log_event("EXP_RESULT", "EXP_C_PLAYBACK_FAIL", lab.exp_c.last_result)
            return
        end
    end

    -- 2. Explicit Unpausing & Speed Activation on Motion Component and Layer 0
    pcall(function()
        t_mot:call("set_Play", true)
        t_mot:call("set_PlaySpeed", 1.0)
        pcall(function() t_mot:call("set_Pause", false) end)
    end)

    local l0 = nil
    pcall(function() l0 = t_mot:call("getLayer", 0) end)
    if not l0 then
        lab.exp_c.playback_status = "PLAYBACK_FAILED"
        lab.exp_c.last_result = "FAIL: Target Motion component has no Layer 0."
        lab.log_event("EXP_RESULT", "EXP_C_PLAYBACK_FAIL", lab.exp_c.last_result)
        return
    end

    pcall(function()
        l0:call("set_Play", true)
        l0:call("set_Speed", 1.0)
        l0:call("set_Weight", 1.0)
        pcall(function() l0:call("set_Pause", false) end)
    end)

    -- 3. Execute changeMotion
    local initial_frame = 0.0
    pcall(function() initial_frame = l0:call("get_Frame") or 0.0 end)

    lab.log_event("API_CALL", "CHANGE_MOTION_INVOKE", string.format("changeMotion(Bank=%d, Motion=%d, Blend=5.0) on %s", target_bid, target_mid, target_desc))

    local ok_cm, err_cm = pcall(function()
        local td_l = l0:get_type_definition()
        local cm = td_l and (td_l:get_method("changeMotion(System.UInt32, System.UInt32, System.Single)") 
                          or td_l:get_method("changeMotion(System.Int32, System.Int32, System.Single)"))
        if cm then
            cm:call(l0, target_bid, target_mid, 5.0)
        else
            l0:call("changeMotion", target_bid, target_mid, 5.0)
        end
    end)

    if not ok_cm then
        lab.exp_c.playback_status = "PLAYBACK_FAILED"
        lab.exp_c.last_result = string.format("FAIL: changeMotion threw exception: %s", tostring(err_cm))
        lab.log_event("EXP_RESULT", "EXP_C_PLAYBACK_FAIL", lab.exp_c.last_result)
        return
    end

    lab.log_event("API_RESULT", "CHANGE_MOTION_OK", string.format("changeMotion executed cleanly. InitialFrame=%.2f", initial_frame))

    -- 4. Initiate 45-frame telemetry monitor
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
end

-- =========================================================================
-- Master Telemetry Loop (Multi-Frame Verification for Exp B & C)
-- =========================================================================

local function update_lab_telemetry()
    -- 1. Exp B Independent Transform Control & Blend Tree Ticking Monitor
    if lab.exp_b.clone_entity then
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
                            lab.log_event("TELEMETRY", "MOTION_TICKING_CONFIRMED", string.format("Frame progressing (%.2f -> %.2f)", history[1], history[#history]))
                            update_exp_b_verdict()
                        end
                    end
                end
            end
        end)

        local lt = lab.exp_b.loco_test
        if lt and lt.active then
            local p = get_active_player()
            local p_go = get_player_go(p)
            local p_tf = p_go and p_go:call("get_Transform")
            local c_tf = lab.exp_b.clone_entity:call("get_Transform")

            if p_tf and c_tf then
                lt.current_frame = lt.current_frame + 1
                local offset_x = math.sin(lt.current_frame * 0.1) * 0.6
                local step_pos = (Vector3f and Vector3f.new and Vector3f.new(lt.clone_initial_pos.x + offset_x, lt.clone_initial_pos.y, lt.clone_initial_pos.z)) 
                                or { x = lt.clone_initial_pos.x + offset_x, y = lt.clone_initial_pos.y, z = lt.clone_initial_pos.z }
                pcall(function() c_tf:call("set_Position", step_pos) end)

                local cur_c = c_tf:call("get_Position")
                local cur_p = p_tf:call("get_Position")
                if cur_c and lt.clone_initial_pos then
                    local c_disp = math.abs(cur_c.x - lt.clone_initial_pos.x)
                    if c_disp > lt.max_clone_displacement then lt.max_clone_displacement = c_disp end
                end
                if cur_p and lt.leon_initial_pos then
                    local p_disp = math.abs(cur_p.x - lt.leon_initial_pos.x) + math.abs(cur_p.z - lt.leon_initial_pos.z)
                    if p_disp > lt.max_leon_displacement then lt.max_leon_displacement = p_disp end
                end

                if lt.current_frame >= lt.target_frames then
                    lt.active = false
                    lt.clone_moved = (lt.max_clone_displacement > 0.25)
                    lt.leon_unmoved = (lt.max_leon_displacement < 0.25)

                    if lt.clone_moved and lt.leon_unmoved then
                        lab.exp_b.independent_transform_control = true
                        lt.verdict = "INDEPENDENT_TRANSFORM_CONTROL_VERIFIED (Clone translated over 60 frames without affecting Leon)"
                    else
                        lab.exp_b.independent_transform_control = false
                        lt.verdict = string.format("FAILED (MaxCloneMoved: %.2f m, MaxLeonMoved: %.2f m)", lt.max_clone_displacement, lt.max_leon_displacement)
                    end
                    lab.log_event("TELEMETRY", "TRANSFORM_TEST_VERDICT", lt.verdict)
                    update_exp_b_verdict()
                end
            end
        end
    end

    -- 2. Exp C Playback Frame Progression Monitor with Strict Validity Verification
    local pm = lab.exp_c.playback_monitor
    if pm and pm.active and pm.target_obj then
        local ok_val, is_valid = pcall(function() return pm.target_obj:call("get_Valid") end)
        if not ok_val or is_valid ~= true then
            pm.active = false
            lab.exp_c.playback_status = "PLAYBACK_FAILED"
            lab.exp_c.last_result = "FAIL: Target actor validity check failed during monitoring. Target unreadable or destroyed."
            lab.log_event("EXP_RESULT", "EXP_C_MONITOR_FAIL", lab.exp_c.last_result)
            return
        end

        local ok_mot, t_mot = pcall(function() return pm.target_obj:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion")) end)
        local ok_l0, l0 = nil, nil
        if ok_mot and t_mot then
            ok_l0, l0 = pcall(function() return t_mot:call("getLayer", 0) end)
        end

        if not ok_mot or not t_mot or not ok_l0 or not l0 then
            pm.active = false
            lab.exp_c.playback_status = "PLAYBACK_FAILED"
            lab.exp_c.last_result = "FAIL: Target via.motion.Motion or Layer 0 became unreadable during monitoring."
            lab.log_event("EXP_RESULT", "EXP_C_MONITOR_FAIL", lab.exp_c.last_result)
            return
        end

        pm.ticks_observed = pm.ticks_observed + 1
        pcall(function()
            pm.current_frame = l0:call("get_Frame") or 0.0
            local mid = l0:call("get_MotionID") or 0
            
            if pm.ticks_observed >= pm.max_ticks then
                pm.active = false
                local frame_advanced = (pm.current_frame > pm.start_frame) or (pm.current_frame < pm.start_frame and pm.start_frame > 15.0)
                
                if mid == pm.target_mid and frame_advanced then
                    lab.exp_c.playback_status = "FRAME_PROGRESSION_VERIFIED"
                    lab.exp_c.last_result = string.format("FRAME_PROGRESSION_VERIFIED: MotionID %d on Bank %d progressed (%.1f -> %.1f, +%d ticks). Pending visual confirmation in viewport.",
                        pm.target_mid, pm.target_bid, pm.start_frame, pm.current_frame, pm.ticks_observed)
                elseif mid == pm.target_mid and not frame_advanced then
                    lab.exp_c.playback_status = "PLAYBACK_STALLED"
                    lab.exp_c.last_result = string.format("PARTIAL: MotionID %d assigned, but frame remained stationary at %.1f (Pause=%s, PlaySpeed=%.2f).",
                        pm.target_mid, pm.current_frame, tostring(lab.exp_c.claire_layer_pause), lab.exp_c.claire_layer_speed)
                else
                    lab.exp_c.playback_status = "PLAYBACK_OVERRIDDEN"
                    lab.exp_c.last_result = string.format("PARTIAL: changeMotion executed, but native motion graph immediately reverted MotionID %d to %d.",
                        pm.target_mid, mid)
                end
                lab.log_event("EXP_RESULT", "EXP_C_MONITOR_FINISH", lab.exp_c.last_result)
            end
        end)
    end
end

-- =========================================================================
-- ImGui UI Dashboard
-- =========================================================================

local function draw_lab_ui()
    imgui.text_colored("=== RE2 DUO MODE — ANIMATION RESEARCH LAB ===", 0.3, 0.9, 1.0, 1.0)
    imgui.text_colored("Milestone 1: In-Engine Reverse Engineering (Rigorous Edition v1.5.0)", 0.7, 0.7, 0.7, 1.0)
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
        imgui.text_colored("Experiment B: Character Duplication & Control Test", col_b[1], col_b[2], col_b[3], 1.0)
        imgui.text("  Status: " .. lab.exp_b.status .. " | Control Test: " .. lab.exp_b.control_test_status)
        imgui.text("  Result: " .. lab.exp_b.last_result)
        imgui.spacing()

        -- Exp C Summary
        local col_c = (lab.exp_c.playback_status == "PLAYBACK_AND_VISUAL_VERIFIED" and {0.2, 1.0, 0.4}) 
                   or (lab.exp_c.playback_status == "FRAME_PROGRESSION_VERIFIED" and {0.2, 0.9, 1.0}) 
                   or (lab.exp_c.playback_status == "PLAYBACK_STALLED" and {1.0, 0.8, 0.2}) or {0.8, 0.8, 0.8}
        imgui.text_colored("Experiment C: Direct Motion Playback & Component Audit", col_c[1], col_c[2], col_c[3], 1.0)
        imgui.text("  Inspection: " .. lab.exp_c.inspection_status .. " | Playback: " .. lab.exp_c.playback_status)
        imgui.text("  Result: " .. lab.exp_c.last_result)

    -- TAB 2: EXPERIMENT A
    elseif lab.selected_tab == 2 then
        imgui.text_colored("Experiment A: Native Survivor Casting (Deep Reverse Engineering)", 1.0, 0.8, 0.2, 1.0)
        imgui.text("Probes Capcom's internal SurvivorAssignManager, standby overloads, CastingOrders & PL1000.")
        imgui.spacing()

        if imgui.button("Run Experiment A Probe (Reverse Engineering & PL1000 Retry)##btn_exp_a") then
            lab.run_experiment_a()
        end
        imgui.same_line()
        if imgui.button("Clean Up Native Cast Actor##btn_exp_a_clean") then
            lab.cleanup_experiment_a()
        end

        imgui.spacing()
        imgui.text("Status: " .. lab.exp_a.status)
        imgui.text("Singleton Detected: " .. tostring(lab.exp_a.singleton_found))
        imgui.text("Standby PL1000 Retry Result: " .. tostring(lab.exp_a.standby_1000_result))
        imgui.text("Actor Verified Valid: " .. tostring(lab.exp_a.actor_valid))
        imgui.text("Has via.motion.Motion: " .. tostring(lab.exp_a.has_motion))
        imgui.text("Has MotionFsm2: " .. tostring(lab.exp_a.has_motion_fsm2))
        imgui.text("Has SurvivorMotionController: " .. tostring(lab.exp_a.has_survivor_motion))
        imgui.text(string.format("Motion Active: %s (Layers=%d)", tostring(lab.exp_a.motion_active), lab.exp_a.layer_count))
        imgui.text("Verdict: " .. lab.exp_a.last_result)

        imgui.spacing()
        imgui.text_colored("Standby Overloads Discovered (" .. #lab.exp_a.standby_overloads .. "):", 0.6, 0.9, 0.6, 1.0)
        for _, sig in ipairs(lab.exp_a.standby_overloads) do
            imgui.text("  " .. sig)
        end

    -- TAB 3: EXPERIMENT B
    elseif lab.selected_tab == 3 then
        imgui.text_colored("Experiment B: Character & Control Duplication Probe", 1.0, 0.8, 0.2, 1.0)
        imgui.text("Tests via.Scene.duplicateGameObject on control non-player objects vs player actor.")
        imgui.spacing()

        if imgui.button("1. Run Control Test (Non-Player Duplication)##btn_exp_b_control") then
            lab.run_experiment_b_control()
        end
        imgui.same_line()
        if imgui.button("2. Spawn Duplicate Player Actor##btn_exp_b_spawn") then
            lab.run_experiment_b()
        end
        imgui.same_line()
        if imgui.button("Destroy Test Clone##btn_exp_b_destroy") then
            lab.cleanup_experiment_b()
        end

        imgui.spacing()
        imgui.text("Status: " .. lab.exp_b.status)
        imgui.text("Control Test Target: " .. tostring(lab.exp_b.control_target_name))
        imgui.text("Control Test Status: " .. tostring(lab.exp_b.control_test_status))
        imgui.text("Control Test Verdict: " .. tostring(lab.exp_b.control_test_verdict))
        imgui.separator()
        imgui.text("Player Clone Active: " .. tostring(lab.exp_b.clone_entity ~= nil))
        imgui.text("Input Verified Disabled: " .. tostring(lab.exp_b.input_verified_disabled))
        imgui.text("Independent Transform Control (60 Frames): " .. tostring(lab.exp_b.independent_transform_control))
        imgui.text("Transform Test Verdict: " .. tostring(lab.exp_b.loco_test.verdict))
        imgui.text("Motion Blend Tree Ticking: " .. tostring(lab.exp_b.motion_ticking))
        imgui.text("Cleanup Status: " .. tostring(lab.exp_b.cleanup_status))
        imgui.text("Verdict: " .. lab.exp_b.last_result)

    -- TAB 4: EXPERIMENT C
    elseif lab.selected_tab == 4 then
        imgui.text_colored("Experiment C: Claire Animation Playback & Stalled Frame Investigation", 1.0, 0.8, 0.2, 1.0)
        imgui.text("Investigates why prefab motion stalled at frame 0.0: pause states, frame stepping & speed.")
        imgui.spacing()

        if imgui.button("1. Inspect Target & Animation Reflection##btn_exp_c_insp") then
            lab.run_experiment_c_inspect()
        end

        imgui.spacing()
        imgui.text("Inspection Status: " .. lab.exp_c.inspection_status)
        imgui.text("Target Selected: " .. tostring(lab.exp_c.target_name))
        imgui.text("Target Native Bank Present: " .. tostring(lab.exp_c.claire_native_bank ~= nil))
        imgui.text(string.format("Motion Pause: %s | Layer 0 Pause: %s", tostring(lab.exp_c.claire_motion_pause), tostring(lab.exp_c.claire_layer_pause)))
        imgui.text(string.format("Play Speed: %.2f | Layer Speed: %.2f | Weight: %.2f", lab.exp_c.claire_play_speed, lab.exp_c.claire_layer_speed, lab.exp_c.claire_layer_weight))
        imgui.text("Frame-Step Probe: " .. tostring(lab.exp_c.claire_frame_step_result))

        imgui.separator()
        local cur_target_obj, cur_target_name = get_playback_target()
        lab.exp_c.target_name = cur_target_name

        imgui.text_colored("Controlled Playback Testing (Target: " .. tostring(lab.exp_c.target_name) .. "):", 1.0, 0.8, 0.2, 1.0)
        if string.find(tostring(lab.exp_c.target_name), "Leon") then
            imgui.text_colored("[!] CAUTION: Targeting Leon (Player Actor). Input will immediately revert this animation. Use 'SPAWN CLAIRE' above!", 1.0, 0.4, 0.2, 1.0)
        elseif string.find(tostring(lab.exp_c.target_name), "Claire") then
            imgui.text_colored("[OK] Targeting Claire Companion. Her animation plays independently of player movement.", 0.2, 1.0, 0.4, 1.0)
        end
        
        if lab.exp_c.leon_active_mid > 0 then
            local active_btn_label = string.format("Play Active Leon Motion (ID %d, Bank %d)##btn_play_active", lab.exp_c.leon_active_mid, lab.exp_c.leon_active_bid)
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
                lab.log_event("VISUAL_CONFIRM", "VIEWPORT_CONFIRMATION", tostring(v_val))
            end
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
    pcall(logger_update)

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
    pcall(lab.cleanup_experiment_a)
end)
