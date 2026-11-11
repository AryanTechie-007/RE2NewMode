--[[
    Resident Evil 2: Duo Mode
    Milestone 1 — Animation Research Lab & Test Harness (Rigorous Safety Edition v1.5.2)
    File: reframework/autorun/animation_lab.lua
    Author: AryanTechie-007

    Purpose:
    Isolated in-engine reverse-engineering laboratory to establish a verified,
    animated Claire companion pathway while maintaining the playable M0 baseline:
      - Experiment A: Native Survivor Casting (Overload selection by exact parameter types; genuine scene
                      enumeration; automatic downgrade to UNVERIFIED if scene diffing is partial/unsupported;
                      strict exclusion of existing Claire companion)
      - Experiment B: GameObject Duplication (Positive identification of inert static mesh props with via.render.Mesh;
                      strict get_Valid() == false confirmation for cleanup; single-route sequential destruction)
      - Experiment C: Claire Animation Playback (Full snapshot and verified restoration of original MotionBankAsset
                      including nil; restoration on normal 45-frame completion, failure and exceptions; capability
                      audit including bank assignment methods; distinct 3-tier verification)
      - Telemetry: Schema-versioned CSV logging (animation_lab_session_v152.csv) with header validation before append.

    Strict Verification Rules (v1.5.2):
      - Rule 1: No imaginary functionality. Distinguish confirmed observations from hypotheses.
      - Rule 2: Overloads matched by exact parameter types (PlayerType vs NpcType), not parameter count alone.
      - Rule 3: Single confirmed destruction route at a time; pcall + get_Valid() == false confirmation.
      - Rule 4: No silent bank substitutions. Full restoration verified on normal monitor completion.
      - Rule 5: Schema-versioned CSV logging with header validation.
      - Rule 6: Complete isolation from character_renderer.lua and M0 playable baseline.
]]

local lab = {
    version = "1.5.2-m1-safety",
    window_open = false,
    selected_tab = 1,
    log_buffer = {},
    max_log_lines = 140,

    -- Experiment A State: Native Survivor Casting
    exp_a = {
        status = "NOT_RUN", -- NOT_RUN | REFLECTION_COMPLETE | CASTING_TESTED | PASS | PARTIAL | REFUSED | UNVERIFIED | FAILED | CLEANED_UP
        singleton_found = false,
        types_resolved = {},
        casting_methods = {},
        standby_overloads = {},
        selected_overload_sig = "None",
        order_types_resolved = {},
        order_constructors = {},
        exec_casting_request = nil,
        exec_request_fields = {},
        selected_player_type = 1000, -- PL1000 = Claire (1000)
        selected_reason = 1,         -- InitialSet = 1
        selected_mode = 0,           -- Normal = 0
        last_standby_call = "None",
        last_standby_ret = "NOT_TESTED",
        apply_casting_result = "NOT_TESTED",
        scene_enumeration_mode = "NONE", -- FULL_ENUMERATION | PARTIAL_NAME_SCAN | UNSUPPORTED
        pre_cast_actor_count = 0,
        created_actor = nil,
        actor_valid = false,
        has_motion = false,
        has_motion_fsm2 = false,
        has_survivor_motion = false,
        motion_active = false,
        layer_count = 0,
        last_result = "Standing by. Step 1: Passive Reflection. Step 2: Controlled Standby Invocation.",
    },

    -- Experiment B State: Character & Control Duplication
    exp_b = {
        status = "NOT_RUN", -- NOT_RUN | RUNNING | PASS | PARTIAL | FAILED | CLEANED_UP | CLEANUP_FAILED
        control_target_name = "None",
        control_target_ptr = "None",
        control_target_has_mesh = false,
        control_test_status = "NOT_RUN", -- NOT_RUN | RUNNING | SUCCESS | FAILED | SKIPPED
        control_test_verdict = "Not tested yet.",
        control_cleanup_status = "NOT_RUN",
        clone_entity = nil,
        surviving_components = {},
        scene_duplicate_methods = {},
        folder_duplicate_methods = {},
        input_stripped = false,
        input_verified_disabled = false,
        independent_transform_control = false,
        motion_ticking = false,
        clone_frame_history = {},
        cleanup_status = "No test clone instantiated.",
        last_result = "Standing by. Step 1: Control Test on Inert Prop. Step 2: Player Duplication.",
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
        playback_status = "NOT_RUN",   -- NOT_RUN | TESTING | FRAME_PROGRESSION_VERIFIED | PLAYBACK_AND_VISUAL_VERIFIED | PLAYBACK_FAILED | PLAYBACK_STALLED | PLAYBACK_OVERRIDDEN | BLOCKED_NO_BANK
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
        allow_cross_bank_assignment = false, -- EXPLICIT: User must check box to allow substituting Leon's bank
        original_settings = nil,             -- Full snapshot before any mutation
        restoration_status = "NOT_PERFORMED",
        setter_capabilities = {},            -- Verified reflection flags for setters & bank methods
        discovered_motions = {},
        motion_reflection_methods = {},
        layer_reflection_methods = {},
        last_result = "Standing by. Step 1: Inspect Target. Step 2: Optional Frame-Step Probe. Step 3: Controlled Playback.",
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

-- Forward declarations
local update_exp_b_verdict
local verify_object_destroyed

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
        local rtype = m:get_return_type()
        local rname = rtype and rtype:get_name() or "System.Void"
        local pnames = {}
        for _, p in ipairs(m:get_param_types() or {}) do
            table.insert(pnames, p:get_name() or "UnknownType")
        end
        return string.format("%s %s(%s)", rname, mname, table.concat(pnames, ", "))
    end)
    return ok and res or mname
end

-- =========================================================================
-- Engine Actor & Scene Resolution Helpers
-- =========================================================================

local function get_active_player()
    local player = nil
    pcall(function()
        local pm = sdk.get_managed_singleton("app.ropeway.PlayerManager")
        if pm then
            player = pm:call("get_CurrentPlayer")
        end
    end)
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
    end

    return scene, source, folder
end

-- Checks if a GameObject belongs to the character_renderer.lua companion spawner
local function is_companion_object(obj)
    if not obj then return false end
    local duo = _G.duo_spawner or spawner
    if duo and duo.spawned_entities then
        for _, e in ipairs(duo.spawned_entities) do
            if e and (e == obj or tostring(e) == tostring(obj)) then
                return true
            end
        end
    end
    return false
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

-- Strict get_Valid() confirmation helper (fixes false-positive cleanup claim)
verify_object_destroyed = function(obj)
    if not obj then return true, "Object reference is nil" end
    local ok, valid = pcall(function() return obj:call("get_Valid") end)
    if ok and valid == false then
        return true, "get_Valid returned exactly false"
    elseif ok and valid == true then
        return false, "get_Valid returned true (object still alive)"
    elseif not ok then
        return false, "get_Valid threw exception: " .. tostring(valid)
    else
        return false, "get_Valid returned non-boolean: " .. tostring(valid)
    end
end

-- =========================================================================
-- STRUCTURED & VERSIONED SESSION LOGGER (v1.5.2 Schema - 48 Fixed Columns)
-- =========================================================================

local session_logger = {
    path = "reframework/data/duo_mode/animation_lab_session_v152.csv",
    frame = 0,
    interval = 30, -- One snapshot every 30 REFramework frames (~2 Hz at 60 FPS)
    ready = false,
}

local schema_columns = {
    "record_type",                  -- 1
    "timestamp",                    -- 2
    "session_frame",                -- 3
    "scene_pointer",                -- 4
    "player_pointer",               -- 5
    "A_status",                     -- 6
    "A_singleton",                  -- 7
    "A_selected_player_type",       -- 8
    "A_selected_reason",            -- 9
    "A_selected_mode",              -- 10
    "A_standby_result",             -- 11
    "A_actor_pointer",              -- 12
    "A_actor_valid",                -- 13
    "A_motion",                     -- 14
    "A_fsm2",                       -- 15
    "A_survivor_motion",            -- 16
    "A_motion_active",              -- 17
    "A_layer_count",                -- 18
    "B_status",                     -- 19
    "B_control_target_name",        -- 20
    "B_control_target_ptr",         -- 21
    "B_control_test_status",        -- 22
    "B_control_cleanup_status",     -- 23
    "B_clone_pointer",              -- 24
    "B_clone_valid",                -- 25
    "B_input_stripped",             -- 26
    "B_input_verified_disabled",    -- 27
    "B_transform_verified",         -- 28
    "B_motion_ticking",             -- 29
    "B_cleanup_status",             -- 30
    "B_loco_frames",                -- 31
    "B_clone_displacement",         -- 32
    "B_leon_displacement",          -- 33
    "B_loco_verdict",               -- 34
    "C_inspection_status",          -- 35
    "C_playback_status",            -- 36
    "C_target_name",                -- 37
    "C_target_pointer",             -- 38
    "C_target_valid",               -- 39
    "C_native_bank_present",        -- 40
    "C_frame_step_result",          -- 41
    "C_selected_mid",               -- 42
    "C_selected_bid",               -- 43
    "C_start_frame",                -- 44
    "C_current_frame",              -- 45
    "C_visual_confirmed",           -- 46
    "event_name",                   -- 47
    "event_details"                 -- 48
}

local function csv_value(value)
    local s = tostring(value == nil and "" or value)
    s = string.gsub(s, '"', '""')
    return '"' .. s .. '"'
end

-- Formats a row map into a verified 48-column CSV string
local function format_csv_row(row_map)
    local cells = {}
    for i, col_name in ipairs(schema_columns) do
        local val = row_map[col_name]
        cells[i] = csv_value(val)
    end
    return table.concat(cells, ",") .. "\n"
end

local function logger_write_line(line_str)
    local ok, err = pcall(function()
        local f = io.open(session_logger.path, "a")
        if not f then
            error("Could not open session CSV: " .. session_logger.path)
        end
        f:write(line_str)
        f:flush()
        f:close()
    end)

    if not ok and log and log.error then
        log.error("[AnimLab Logger] " .. tostring(err))
    end
    return ok
end

local function logger_validity(obj)
    if not obj then return "NO_OBJECT" end
    local ok, value = pcall(function() return obj:call("get_Valid") end)
    if not ok then return "UNREADABLE" end
    if value == true then return "TRUE" end
    if value == false then return "FALSE" end
    return "UNKNOWN"
end

-- Validates existing CSV header before appending; rotates if schema mismatch
local function validate_or_init_csv()
    local existing = io.open(session_logger.path, "r")
    local needs_fresh_header = true

    if existing then
        local first_line = existing:read("*l")
        existing:close()

        if first_line then
            -- Count commas outside quotes
            local count = 1
            for _ in string.gmatch(first_line, ",") do
                count = count + 1
            end
            local has_record_type = string.find(first_line, "record_type", 1, true) ~= nil
            local has_event_details = string.find(first_line, "event_details", 1, true) ~= nil

            if count == #schema_columns and has_record_type and has_event_details then
                needs_fresh_header = false
                lab_log("[Logger] Existing CSV header verified valid (48 columns). Appending session records.")
            else
                lab_log(string.format("[Logger] CSV header mismatch (cols=%d, expected=%d). Rotating corrupt file.", count, #schema_columns))
                local rot_name = session_logger.path .. ".mismatch_" .. os.date("%Y%m%d_%H%M%S") .. ".bak"
                os.rename(session_logger.path, rot_name)
                needs_fresh_header = true
            end
        end
    end

    if needs_fresh_header then
        local header_cells = {}
        for i, col in ipairs(schema_columns) do
            header_cells[i] = csv_value(col)
        end
        logger_write_line(table.concat(header_cells, ",") .. "\n")
        lab_log("[Logger] Fresh 48-column canonical header written to " .. session_logger.path)
    end
end

local function logger_init()
    if session_logger.ready then return end

    validate_or_init_csv()
    session_logger.ready = true

    local init_row = {
        record_type = "SESSION_START",
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        session_frame = 0,
        A_status = lab.exp_a.status,
        B_status = lab.exp_b.status,
        C_inspection_status = lab.exp_c.inspection_status,
        C_playback_status = lab.exp_c.playback_status,
        event_name = "SESSION_INIT",
        event_details = lab.version
    }
    logger_write_line(format_csv_row(init_row))
end

-- Event-level telemetry logger with strict 48-column mapping
function lab.log_event(event_type, event_name, event_details)
    if not session_logger.ready then logger_init() end

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
        record_type = event_type or "EVENT",
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        session_frame = session_logger.frame,
        scene_pointer = tostring(scene),
        player_pointer = tostring(player_go),

        A_status = a.status,
        A_singleton = tostring(a.singleton_found),
        A_selected_player_type = a.selected_player_type,
        A_selected_reason = a.selected_reason,
        A_selected_mode = a.selected_mode,
        A_standby_result = tostring(a.last_standby_ret),
        A_actor_pointer = tostring(a.created_actor),
        A_actor_valid = tostring(a.actor_valid),
        A_motion = tostring(a.has_motion),
        A_fsm2 = tostring(a.has_motion_fsm2),
        A_survivor_motion = tostring(a.has_survivor_motion),
        A_motion_active = tostring(a.motion_active),
        A_layer_count = a.layer_count,

        B_status = b.status,
        B_control_target_name = b.control_target_name,
        B_control_target_ptr = tostring(b.control_target_ptr),
        B_control_test_status = b.control_test_status,
        B_control_cleanup_status = b.control_cleanup_status,
        B_clone_pointer = tostring(b.clone_entity),
        B_clone_valid = clone_valid,
        B_input_stripped = tostring(b.input_stripped),
        B_input_verified_disabled = tostring(b.input_verified_disabled),
        B_transform_verified = tostring(b.independent_transform_control),
        B_motion_ticking = tostring(b.motion_ticking),
        B_cleanup_status = b.cleanup_status,
        B_loco_frames = loco.current_frame or 0,
        B_clone_displacement = loco.max_clone_displacement or 0,
        B_leon_displacement = loco.max_leon_displacement or 0,
        B_loco_verdict = loco.verdict or "NOT_STARTED",

        C_inspection_status = c.inspection_status,
        C_playback_status = c.playback_status,
        C_target_name = c.target_name,
        C_target_pointer = tostring(target),
        C_target_valid = target_valid,
        C_native_bank_present = tostring(c.claire_native_bank ~= nil),
        C_frame_step_result = tostring(c.claire_frame_step_result),
        C_selected_mid = c.selected_mid,
        C_selected_bid = c.selected_bid,
        C_start_frame = monitor.start_frame or 0,
        C_current_frame = monitor.current_frame or 0,
        C_visual_confirmed = tostring(c.visual_confirmed),

        event_name = event_name or "",
        event_details = event_details or ""
    }

    logger_write_line(format_csv_row(row))
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
        record_type = "SNAPSHOT",
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        session_frame = session_logger.frame,
        scene_pointer = tostring(scene),
        player_pointer = tostring(player_go),

        A_status = a.status,
        A_singleton = tostring(a.singleton_found),
        A_selected_player_type = a.selected_player_type,
        A_selected_reason = a.selected_reason,
        A_selected_mode = a.selected_mode,
        A_standby_result = tostring(a.last_standby_ret),
        A_actor_pointer = tostring(a.created_actor),
        A_actor_valid = tostring(a.actor_valid),
        A_motion = tostring(a.has_motion),
        A_fsm2 = tostring(a.has_motion_fsm2),
        A_survivor_motion = tostring(a.has_survivor_motion),
        A_motion_active = tostring(a.motion_active),
        A_layer_count = a.layer_count,

        B_status = b.status,
        B_control_target_name = b.control_target_name,
        B_control_target_ptr = tostring(b.control_target_ptr),
        B_control_test_status = b.control_test_status,
        B_control_cleanup_status = b.control_cleanup_status,
        B_clone_pointer = tostring(b.clone_entity),
        B_clone_valid = clone_valid,
        B_input_stripped = tostring(b.input_stripped),
        B_input_verified_disabled = tostring(b.input_verified_disabled),
        B_transform_verified = tostring(b.independent_transform_control),
        B_motion_ticking = tostring(b.motion_ticking),
        B_cleanup_status = b.cleanup_status,
        B_loco_frames = loco.current_frame or 0,
        B_clone_displacement = loco.max_clone_displacement or 0,
        B_leon_displacement = loco.max_leon_displacement or 0,
        B_loco_verdict = loco.verdict or "NOT_STARTED",

        C_inspection_status = c.inspection_status,
        C_playback_status = c.playback_status,
        C_target_name = c.target_name,
        C_target_pointer = tostring(target),
        C_target_valid = target_valid,
        C_native_bank_present = tostring(c.claire_native_bank ~= nil),
        C_frame_step_result = tostring(c.claire_frame_step_result),
        C_selected_mid = c.selected_mid,
        C_selected_bid = c.selected_bid,
        C_start_frame = monitor.start_frame or 0,
        C_current_frame = monitor.current_frame or 0,
        C_visual_confirmed = tostring(c.visual_confirmed),

        event_name = "FRAME_SNAPSHOT",
        event_details = ""
    }

    return logger_write_line(format_csv_row(row))
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
-- EXPERIMENT A: Native Survivor Casting (Exact Overload & Strict Scene Diffing)
-- =========================================================================

-- Helper to match standby overloads by EXACT parameter types
local function find_standby_overload_by_param(sam_td, expected_first_param_substring)
    if not sam_td then return nil, "<no type definition>" end
    local methods = sam_td:get_methods() or {}
    for _, m in ipairs(methods) do
        if m:get_name() == "standby" then
            local ptypes = m:get_param_types() or {}
            if #ptypes == 3 then
                local p1_name = ptypes[1] and ptypes[1]:get_name() or ""
                local p2_name = ptypes[2] and ptypes[2]:get_name() or ""
                local p3_name = ptypes[3] and ptypes[3]:get_name() or ""
                if string.find(p1_name, expected_first_param_substring, 1, true)
                   and string.find(p2_name, "CastingReason", 1, true)
                   and string.find(p3_name, "OfferMode", 1, true) then
                    return m, format_method_sig(m)
                end
            end
        end
    end
    return nil, "<no matching overload>"
end

-- Helper to attempt genuine scene GameObject enumeration
local function enumerate_scene_game_objects(scene)
    if not scene then return nil, "No scene available" end
    local list = {}
    local ok = false

    -- Method 1: get_GameObjects() managed array
    pcall(function()
        local arr = scene:call("get_GameObjects")
        if arr then
            local count = nil
            pcall(function() count = arr:call("get_Length") or arr:call("get_Count") or arr:get_size() or #arr end)
            if count and count > 0 then
                for i = 0, count - 1 do
                    local go = nil
                    pcall(function() go = arr[i] or arr:call("get_Item", i) or arr:get_element(i) end)
                    if go then table.insert(list, go) end
                end
                if #list > 0 then ok = true end
            end
        end
    end)

    -- Method 2: getGameObjectCount() + getGameObject(i)
    if not ok then
        pcall(function()
            local cnt = scene:call("getGameObjectCount") or scene:call("get_GameObjectCount") or 0
            if cnt and cnt > 0 then
                for i = 0, cnt - 1 do
                    local go = nil
                    pcall(function() go = scene:call("getGameObject", i) end)
                    if go then table.insert(list, go) end
                end
                if #list > 0 then ok = true end
            end
        end)
    end

    if ok then
        return list, "FULL_ENUMERATION"
    else
        return nil, "UNSUPPORTED"
    end
end

-- Step 1: Passive Reflection Probe (SAFE - NO STANDBY INVOCATIONS)
function lab.run_experiment_a_reflect()
    lab.log_event("EXP_START", "EXP_A_REFLECT", "Starting Native Survivor Casting Passive Reflection Probe v1.5.2")
    lab.exp_a.status = "RUNNING"
    lab.exp_a.types_resolved = {}
    lab.exp_a.casting_methods = {}
    lab.exp_a.standby_overloads = {}
    lab.exp_a.order_types_resolved = {}
    lab.exp_a.order_constructors = {}
    lab.exp_a.exec_request_fields = {}

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

    -- Match exact PlayerType overload
    local ptype_method, ptype_sig = find_standby_overload_by_param(td_sam, "PlayerType")
    lab.exp_a.selected_overload_sig = ptype_sig
    lab.log_event("OVERLOAD_VERIFY", "EXACT_PLAYER_TYPE_OVERLOAD", ptype_sig)

    -- 3. Investigate CastingOrder Types
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
        end
    end

    -- 4. Probe SurvivorAssignManager Singleton & Fields
    local sam = sdk.get_managed_singleton("app.ropeway.SurvivorAssignManager")
    lab.exp_a.singleton_found = (sam ~= nil)
    if not sam then
        lab.exp_a.status = "FAILED"
        lab.exp_a.last_result = "FAIL: SurvivorAssignManager singleton not active in scene."
        lab.log_event("EXP_RESULT", "EXP_A_REFLECT_FAIL", lab.exp_a.last_result)
        return
    end

    lab.log_event("SINGLETON_FOUND", "SurvivorAssignManager", tostring(sam))

    -- 5. Deep Inspection of SurvivorManager & get_ExecCastingRequest()
    local sm = sdk.get_managed_singleton("app.ropeway.SurvivorManager")
    local exec_req = nil
    local in_c_before = false
    if sm then
        lab.log_event("SINGLETON_FOUND", "SurvivorManager", tostring(sm))
        pcall(function() in_c_before = sm:call("inCasting") end)
        pcall(function() exec_req = sm:call("get_ExecCastingRequest") end)
        lab.exp_a.exec_casting_request = exec_req

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

    lab.exp_a.status = "REFLECTION_COMPLETE"
    lab.exp_a.last_result = string.format("REFLECTION_COMPLETE: Singleton active. Verified PlayerType overload: %s. Ready for controlled test.", lab.exp_a.selected_overload_sig)
    lab.log_event("EXP_END", "EXP_A_REFLECT", lab.exp_a.last_result)
end

-- Step 2: Controlled Standby Invocation (Exact Overload & Rigorous Diffing)
function lab.run_experiment_a_cast()
    local sam = sdk.get_managed_singleton("app.ropeway.SurvivorAssignManager")
    if not sam then
        lab.exp_a.status = "FAILED"
        lab.exp_a.last_result = "FAIL: SurvivorAssignManager singleton not active. Run reflection first."
        lab.log_event("EXP_RESULT", "EXP_A_CAST_FAIL", lab.exp_a.last_result)
        return
    end

    local td_sam = sam:get_type_definition()
    local target_standby, sig_matched = find_standby_overload_by_param(td_sam, "PlayerType")

    if not target_standby then
        lab.exp_a.status = "FAILED"
        lab.exp_a.last_result = "FAIL: Exact standby(PlayerType, CastingReason, OfferMode) overload not found."
        lab.log_event("EXP_RESULT", "EXP_A_CAST_FAIL", lab.exp_a.last_result)
        return
    end

    lab.exp_a.selected_overload_sig = sig_matched
    lab.log_event("OVERLOAD_SELECTED", "STANDBY_TARGET", sig_matched)

    local player = get_active_player()
    local player_go = get_player_go(player)
    local cur_scene = get_current_scene(player_go)

    -- 1. Attempt genuine scene enumeration
    local pre_scene_objs, enum_mode = enumerate_scene_game_objects(cur_scene)
    lab.exp_a.scene_enumeration_mode = enum_mode
    lab.log_event("SCENE_ENUM_STATUS", "PRE_CAST", string.format("Mode: %s, Objects: %s", enum_mode, pre_scene_objs and #pre_scene_objs or "nil"))

    local pre_existing_pointers = {}

    -- Record enumerated pointers if full enumeration is available
    if pre_scene_objs then
        for _, go in ipairs(pre_scene_objs) do
            pre_existing_pointers[tostring(go)] = true
        end
    end

    -- Always record companion spawner entities to strictly forbid false positives
    local duo = _G.duo_spawner or spawner
    if duo and duo.spawned_entities then
        for _, e in ipairs(duo.spawned_entities) do
            if e then pre_existing_pointers[tostring(e)] = true end
        end
    end

    -- Also record fallback name search targets
    local go_td = sdk.find_type_definition("via.GameObject")
    local find_m = go_td and go_td:get_method("find(System.String)")
    if find_m then
        for _, name in ipairs({"pl1000", "pl1000_body", "survivor", "Claire", "Claire_Body", "pl0000"}) do
            local found = find_m:call(nil, name)
            if found then pre_existing_pointers[tostring(found)] = true end
        end
    end

    -- 2. Execute EXACTLY ONE call with verified parameters
    local ptype = lab.exp_a.selected_player_type
    local reason = lab.exp_a.selected_reason
    local mode = lab.exp_a.selected_mode

    lab.exp_a.last_standby_call = string.format("standby(%d, %d, %d) via [%s]", ptype, reason, mode, sig_matched)
    lab.log_event("API_CALL", "STANDBY_INVOKE", lab.exp_a.last_standby_call)

    local ok, ret = pcall(function() return target_standby:call(sam, ptype, reason, mode) end)
    lab.exp_a.last_standby_ret = tostring(ret)
    lab.log_event("API_RESULT", "STANDBY_RETURN", string.format("ok=%s, ret=%s (0=Accepted, 1=Refused)", tostring(ok), tostring(ret)))

    -- 3. Scene Diffing Evaluation
    local newly_created_actor = nil
    local actor_discovery_mode = "NONE"

    -- Path A: Genuine scene diffing if full enumeration was available
    if enum_mode == "FULL_ENUMERATION" and cur_scene then
        local post_scene_objs = enumerate_scene_game_objects(cur_scene)
        if post_scene_objs then
            for _, go in ipairs(post_scene_objs) do
                local ptr_str = tostring(go)
                if not pre_existing_pointers[ptr_str] and not is_companion_object(go) then
                    newly_created_actor = go
                    actor_discovery_mode = "FULL_SCENE_DIFF"
                    break
                end
            end
        end
    end

    -- Path B: Fallback name scan (if full enumeration unsupported)
    if not newly_created_actor and find_m then
        for _, name in ipairs({"pl1000", "pl1000_body", "survivor", "Claire"}) do
            local found = find_m:call(nil, name)
            if found then
                local ptr_str = tostring(found)
                if not pre_existing_pointers[ptr_str] and not is_companion_object(found) then
                    newly_created_actor = found
                    actor_discovery_mode = "NAME_SCAN_FALLBACK"
                    break
                end
            end
        end
    end

    -- 4. Evaluate Verdict based on discovery mode and controller verification
    if newly_created_actor then
        lab.exp_a.created_actor = newly_created_actor
        local actor_v = false
        pcall(function() actor_v = (newly_created_actor:call("get_Valid") == true) end)
        lab.exp_a.actor_valid = actor_v

        local has_m = false
        local has_f2 = false
        local has_sm = false
        local m_active = false
        local l_count = 0

        pcall(function()
            local c_mot = newly_created_actor:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion"))
            has_m = (c_mot ~= nil)
            if c_mot then
                l_count = c_mot:call("getLayerCount") or 0
                local is_p = c_mot:call("get_Play")
                local spd = c_mot:call("get_PlaySpeed") or 0.0
                if l_count > 0 and is_p == true and spd > 0 then m_active = true end
            end
            has_f2 = (newly_created_actor:call("getComponent(System.Type)", sdk.typeof("via.motion.MotionFsm2")) ~= nil)
            has_sm = (newly_created_actor:call("getComponent(System.Type)", sdk.typeof("app.ropeway.survivor.SurvivorMotionController")) ~= nil)
        end)

        lab.exp_a.has_motion = has_m
        lab.exp_a.has_motion_fsm2 = has_f2
        lab.exp_a.has_survivor_motion = has_sm
        lab.exp_a.motion_active = m_active
        lab.exp_a.layer_count = l_count

        if actor_discovery_mode == "FULL_SCENE_DIFF" and actor_v and has_m and (has_f2 or has_sm) and m_active then
            lab.exp_a.status = "PASS"
            lab.exp_a.last_result = string.format("PASS: Full scene diff confirmed newly cast actor (%s) with active motion (Layers=%d)!", tostring(newly_created_actor), l_count)
        elseif actor_discovery_mode == "NAME_SCAN_FALLBACK" then
            -- STRICT: Downgrade to UNVERIFIED when full scene enumeration is unavailable
            lab.exp_a.status = "UNVERIFIED"
            lab.exp_a.last_result = string.format("UNVERIFIED: Candidate actor found via name search (%s), but full scene enumeration is unavailable. Cannot mathematically prove actor was newly instantiated.", tostring(newly_created_actor))
        else
            lab.exp_a.status = "PARTIAL"
            lab.exp_a.last_result = string.format("PARTIAL: Actor observed (%s), but active ticking unconfirmed.", tostring(newly_created_actor))
        end
    else
        if ret == 0 then
            lab.exp_a.status = "PARTIAL"
            lab.exp_a.last_result = string.format("PARTIAL: standby returned Accepted (0), but no new actor instantiated in current frame (EnumMode=%s).", enum_mode)
        elseif ret == 1 then
            lab.exp_a.status = "REFUSED"
            lab.exp_a.last_result = string.format("REFUSED: standby returned Refused (1) for PlayerType=%d, Reason=%d, Mode=%d.", ptype, reason, mode)
        else
            lab.exp_a.status = "FAILED"
            lab.exp_a.last_result = string.format("FAILED: standby call returned unexpected code: %s.", tostring(ret))
        end
    end

    lab.log_event("EXP_END", "EXP_A_CAST", lab.exp_a.last_result)
end

-- Step 3: Explicit Trigger for SurvivorManager:applyCastingRequest()
function lab.run_experiment_a_apply()
    local sm = sdk.get_managed_singleton("app.ropeway.SurvivorManager")
    if not sm then
        lab.exp_a.apply_casting_result = "FAIL: SurvivorManager not active."
        lab.log_event("EXP_RESULT", "EXP_A_APPLY_FAIL", lab.exp_a.apply_casting_result)
        return
    end

    local in_c_before = false
    pcall(function() in_c_before = sm:call("inCasting") end)
    lab.log_event("API_CALL", "APPLY_CASTING_INVOKE", string.format("SurvivorManager:applyCastingRequest() [inCastingBefore=%s]", tostring(in_c_before)))

    local ok, err = pcall(function() sm:call("applyCastingRequest") end)
    local in_c_after = false
    pcall(function() in_c_after = sm:call("inCasting") end)

    if ok then
        lab.exp_a.apply_casting_result = string.format("SUCCESS: applyCastingRequest executed (inCasting: %s -> %s).", tostring(in_c_before), tostring(in_c_after))
    else
        lab.exp_a.apply_casting_result = "FAIL: applyCastingRequest threw exception: " .. tostring(err)
    end
    lab.log_event("API_RESULT", "APPLY_CASTING_RESULT", lab.exp_a.apply_casting_result)
end

-- Step 4: Strict Sequential Cleanup for Cast Actor
function lab.cleanup_experiment_a()
    lab.log_event("CLEANUP_START", "EXP_A_CLEANUP", "Initiating verified cleanup for cast actor")
    local actor = lab.exp_a.created_actor
    if not actor then
        lab.log_event("CLEANUP_INFO", "EXP_A_CLEANUP", "No active cast actor to clean up.")
        return
    end

    local player = get_active_player()
    local player_go = get_player_go(player)
    local cur_scene = get_current_scene(player_go)

    -- Route 1: Scene-level destruction
    if cur_scene then
        pcall(function() cur_scene:call("destroyGameObject(via.GameObject)", actor) end)
    end

    local destroyed_r1, reason_r1 = verify_object_destroyed(actor)
    if destroyed_r1 then
        lab.exp_a.created_actor = nil
        lab.exp_a.actor_valid = false
        lab.exp_a.status = "CLEANED_UP"
        lab.log_event("CLEANUP_SUCCESS", "EXP_A_CLEANUP", "Cast actor destroyed via Route 1 (confirmed get_Valid==false).")
        return
    end

    -- Route 2: Fallback static GameObject.destroy ONLY if Route 1 did not invalidate
    local go_td = sdk.find_type_definition("via.GameObject")
    local destroy_static = go_td and go_td:get_method("destroy(via.GameObject)")
    if destroy_static then
        pcall(function() destroy_static:call(nil, actor) end)
    end

    local destroyed_r2, reason_r2 = verify_object_destroyed(actor)
    if destroyed_r2 then
        lab.exp_a.created_actor = nil
        lab.exp_a.actor_valid = false
        lab.exp_a.status = "CLEANED_UP"
        lab.log_event("CLEANUP_SUCCESS", "EXP_A_CLEANUP", "Cast actor destroyed via Route 2 fallback (confirmed get_Valid==false).")
    else
        lab.log_event("CLEANUP_FAILED", "EXP_A_CLEANUP", string.format("Cast actor cleanup failed: Route1=%s, Route2=%s", reason_r1, reason_r2))
    end
end

-- =========================================================================
-- EXPERIMENT B: Character & Control Duplication (Inert Prop Mesh & Strict Cleanup)
-- =========================================================================

-- Helper to verify positive identification of an inert static mesh prop
local function is_inert_mesh_prop(obj, player_go)
    if not obj or obj == player_go or is_companion_object(obj) then return false end

    local is_v = false
    pcall(function() is_v = (obj:call("get_Valid") == true) end)
    if not is_v then return false end

    -- Requirement 1: MUST have via.render.Mesh (positive identification of static geometry)
    local has_mesh = false
    pcall(function() has_mesh = (obj:call("getComponent(System.Type)", sdk.typeof("via.render.Mesh")) ~= nil) end)
    if not has_mesh then return false end

    -- Requirement 2: MUST have via.Transform
    local has_tf = false
    pcall(function() has_tf = (obj:call("getComponent(System.Type)", sdk.typeof("via.Transform")) ~= nil) end)
    if not has_tf then return false end

    -- Requirement 3: MUST NOT have sensitive components
    local forbidden_types = {
        "via.camera.Camera", "via.render.Light", "app.ropeway.PlayerManager",
        "app.ropeway.PlayerInputReceiver", "app.ropeway.PadManager",
        "app.ropeway.survivor.SurvivorMotionController", "via.motion.MotionFsm2",
        "via.motion.Motion", "via.gui.GUI"
    }
    for _, ft in ipairs(forbidden_types) do
        local ok, c = pcall(function() return obj:call("getComponent(System.Type)", sdk.typeof(ft)) end)
        if ok and c then return false end
    end

    return true
end

-- Finds a genuinely expendable non-player static mesh prop in active scene
local function find_inert_mesh_prop_target(player_go)
    local candidate_names = {
        "sm00_000", "sm00_001", "sm00_002", "sm00_005", "sm00_010",
        "sm01_000", "sm02_000", "sm03_000", "StaticMesh", "Environment",
        "prop_desk", "prop_chair", "prop_door", "sm_table", "sm_box"
    }

    local go_td = sdk.find_type_definition("via.GameObject")
    local find_m = go_td and go_td:get_method("find(System.String)")

    if find_m then
        for _, name in ipairs(candidate_names) do
            local obj = nil
            pcall(function() obj = find_m:call(nil, name) end)
            if obj and is_inert_mesh_prop(obj, player_go) then
                return obj, name
            end
        end
    end

    return nil, "None"
end

-- Control Test on verified inert mesh prop with strict sequential cleanup
function lab.run_experiment_b_control()
    lab.log_event("EXP_START", "EXP_B_CONTROL", "Starting Control Duplication Test on Inert Mesh Prop")
    lab.exp_b.control_test_status = "RUNNING"
    lab.exp_b.control_cleanup_status = "NOT_RUN"

    local player = get_active_player()
    local player_go = get_player_go(player)
    local cur_scene, scene_source, cur_folder = get_current_scene(player_go)

    if not cur_scene then
        lab.exp_b.control_test_status = "FAILED"
        lab.exp_b.control_test_verdict = "FAIL: via.Scene could not be retrieved for control test."
        lab.log_event("CONTROL_RESULT", "EXP_B_CONTROL_FAIL", lab.exp_b.control_test_verdict)
        return
    end

    -- 1. Locate positively identified inert static mesh prop (NOT Claire, NOT Camera, NOT Player)
    local control_target, target_name = find_inert_mesh_prop_target(player_go)
    if not control_target then
        lab.exp_b.control_test_status = "SKIPPED"
        lab.exp_b.control_test_verdict = "SKIPPED: No verified inert static mesh prop found in active scene chunk."
        lab.log_event("CONTROL_RESULT", "EXP_B_CONTROL_SKIPPED", lab.exp_b.control_test_verdict)
        return
    end

    lab.exp_b.control_target_name = target_name
    lab.exp_b.control_target_ptr = tostring(control_target)
    lab.exp_b.control_target_has_mesh = true
    lab.log_event("CONTROL_TARGET_IDENTIFIED", target_name, string.format("Pointer: %s (Verified via.render.Mesh + via.Transform, 0 forbidden components)", tostring(control_target)))

    -- 2. Attempt duplication of inert mesh prop
    local control_clone = nil
    pcall(function() control_clone = cur_scene:call("duplicateGameObject(via.GameObject)", control_target) end)
    if not control_clone and cur_folder then
        pcall(function() control_clone = cur_scene:call("duplicateGameObject(via.GameObject, via.Folder)", control_target, cur_folder) end)
    end
    if not control_clone then
        pcall(function() control_clone = cur_scene:call("duplicateGameObject", control_target) end)
    end

    if not control_clone then
        lab.exp_b.control_test_status = "FAILED"
        lab.exp_b.control_test_verdict = string.format("CONTROL_TEST_FAILED: duplicateGameObject returned nil for inert mesh prop '%s'.", target_name)
        lab.log_event("CONTROL_RESULT", "EXP_B_CONTROL_FAIL", lab.exp_b.control_test_verdict)
        return
    end

    local is_v = false
    pcall(function() is_v = (control_clone:call("get_Valid") == true) end)
    lab.log_event("CONTROL_DUPLICATE_OK", target_name, string.format("Inert mesh clone created: %s (Valid=%s)", tostring(control_clone), tostring(is_v)))

    -- 3. Strict Sequential Cleanup (One route at a time; pcall + get_Valid() == false confirmation)
    if cur_scene then
        pcall(function() cur_scene:call("destroyGameObject(via.GameObject)", control_clone) end)
    end

    local destroyed_r1, reason_r1 = verify_object_destroyed(control_clone)
    if destroyed_r1 then
        lab.exp_b.control_cleanup_status = "CLEANUP_VERIFIED (Route 1 confirmed get_Valid==false)"
        lab.exp_b.control_test_status = "SUCCESS"
        lab.exp_b.control_test_verdict = string.format("CONTROL_TEST_SUCCESS: Inert mesh prop '%s' duplicated and destroyed cleanly via Route 1.", target_name)
        lab.log_event("CONTROL_CLEANUP", "EXP_B_CONTROL_DESTROY", lab.exp_b.control_cleanup_status)
        return
    end

    -- Route 2 Fallback ONLY IF Route 1 did not confirm destruction
    local go_td = sdk.find_type_definition("via.GameObject")
    local destroy_static = go_td and go_td:get_method("destroy(via.GameObject)")
    if destroy_static then
        pcall(function() destroy_static:call(nil, control_clone) end)
    end

    local destroyed_r2, reason_r2 = verify_object_destroyed(control_clone)
    if destroyed_r2 then
        lab.exp_b.control_cleanup_status = "CLEANUP_VERIFIED (Route 2 static GameObject.destroy confirmed get_Valid==false)"
        lab.exp_b.control_test_status = "SUCCESS"
        lab.exp_b.control_test_verdict = string.format("CONTROL_TEST_SUCCESS: Inert mesh prop '%s' duplicated and destroyed via Route 2 fallback.", target_name)
    else
        lab.exp_b.control_cleanup_status = string.format("CLEANUP_FAILED (Route 1: %s; Route 2: %s)", reason_r1, reason_r2)
        lab.exp_b.control_test_status = "FAILED"
        lab.exp_b.control_test_verdict = string.format("CONTROL_TEST_FAILED: Inert mesh prop '%s' duplicated, but cleanup failed.", target_name)
    end
    lab.log_event("CONTROL_CLEANUP", "EXP_B_CONTROL_DESTROY", lab.exp_b.control_cleanup_status)
end

function lab.run_experiment_b()
    lab.log_event("EXP_START", "EXPERIMENT_B", "Starting Player Duplication Probe v1.5.2")
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

    -- 1. Full Reflection of duplicate signatures
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

    -- 3. Controlled Duplication on Player GameObject
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

    if not clone then
        lab.exp_b.status = "FAILED"
        lab.exp_b.last_result = string.format("FAIL: duplicateGameObject returned nil for Player GameObject. Engine singleton guards active. (Control test: %s)", lab.exp_b.control_test_status)
        lab.log_event("EXP_RESULT", "EXP_B_PLAYER_FAIL", lab.exp_b.last_result)
        return
    end

    lab.exp_b.clone_entity = clone
    lab.log_event("EXP_RESULT", "EXP_B_PLAYER_CLONED", "Player GameObject duplicated successfully! Pointer: " .. tostring(clone))

    -- 4. Audit Components Surviving Duplication
    local audit_types = {
        "via.Transform", "via.render.Mesh", "via.motion.Motion", "via.motion.MotionFsm2",
        "via.physics.CharacterController", "app.ropeway.PlayerInputReceiver", "app.ropeway.PadManager",
    }
    for _, tname in ipairs(audit_types) do
        local ok, c = pcall(function() return clone:call("getComponent(System.Type)", sdk.typeof(tname)) end)
        if ok and c then table.insert(lab.exp_b.surviving_components, tname) end
    end

    -- 5. Strip and Verify Input Disabling
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

    lab.exp_b.input_stripped = (in_rec_disabled and pad_disabled)
    lab.exp_b.input_verified_disabled = (in_rec_disabled and pad_disabled)

    -- 6. Position Clone and initiate independent transform test
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
        end
    end

    update_exp_b_verdict()
end

-- Strictly sequential cleanup of duplicate clone with exact get_Valid() == false confirmation
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

    -- Route 1: Scene destruction
    if cur_scene then
        pcall(function() cur_scene:call("destroyGameObject(via.GameObject)", clone) end)
    end

    local destroyed_r1, reason_r1 = verify_object_destroyed(clone)
    if destroyed_r1 then
        lab.exp_b.cleanup_status = "CLEANUP_VERIFIED (Route 1 confirmed get_Valid==false)"
        lab.log_event("CLEANUP_SUCCESS", "EXP_B_CLEANUP", lab.exp_b.cleanup_status)
        lab.exp_b.clone_entity = nil
        lab.exp_b.status = "CLEANED_UP"
        lab.exp_b.last_result = lab.exp_b.cleanup_status
        return
    end

    -- Route 2: Fallback ONLY IF Route 1 did not confirm destruction
    local go_td = sdk.find_type_definition("via.GameObject")
    local destroy_static = go_td and go_td:get_method("destroy(via.GameObject)")
    if destroy_static then
        pcall(function() destroy_static:call(nil, clone) end)
    end

    local destroyed_r2, reason_r2 = verify_object_destroyed(clone)
    if destroyed_r2 then
        lab.exp_b.cleanup_status = "CLEANUP_VERIFIED (Route 2 fallback confirmed get_Valid==false)"
        lab.log_event("CLEANUP_SUCCESS", "EXP_B_CLEANUP", lab.exp_b.cleanup_status)
        lab.exp_b.clone_entity = nil
        lab.exp_b.status = "CLEANED_UP"
        lab.exp_b.last_result = lab.exp_b.cleanup_status
    else
        lab.exp_b.cleanup_status = string.format("CLEANUP_FAILED (Route 1: %s; Route 2: %s)", reason_r1, reason_r2)
        lab.log_event("CLEANUP_FAILED", "EXP_B_CLEANUP", lab.exp_b.cleanup_status)
        lab.exp_b.status = "CLEANUP_FAILED"
        lab.exp_b.last_result = lab.exp_b.cleanup_status
    end
end

update_exp_b_verdict = function()
    local b = lab.exp_b
    if not b.clone_entity then return end

    local is_v = false
    pcall(function() is_v = (b.clone_entity:call("get_Valid") == true) end)

    if is_v and b.input_verified_disabled and b.independent_transform_control and b.motion_ticking then
        b.status = "PASS"
        b.last_result = "PASS: Cloned actor verified with stripped input, independent transform control, and ticking motion."
    elseif is_v and b.input_verified_disabled and b.independent_transform_control then
        b.status = "PARTIAL"
        b.last_result = "PARTIAL: Input stripped and transform control verified, but motion ticking unconfirmed."
    elseif is_v and b.input_verified_disabled then
        b.status = "PARTIAL"
        b.last_result = "PARTIAL: Input stripped, pending transform control verification."
    elseif is_v then
        b.status = "PARTIAL"
        b.last_result = "PARTIAL: Cloned actor exists, but input stripping verification failed."
    end
end

-- =========================================================================
-- EXPERIMENT C: Claire Animation Playback & Stalled Frame Investigation
-- =========================================================================

-- Helper to audit setter capabilities on Motion, Layer 0, and Bank assignment via reflection
local function audit_motion_setter_capabilities(t_mot, l0)
    local caps = {
        mot_set_play = false,
        mot_set_pause = false,
        mot_set_playspeed = false,
        mot_set_bank = false,
        mot_setup_bank = false,
        l0_set_play = false,
        l0_set_pause = false,
        l0_set_speed = false,
        l0_set_weight = false,
        l0_set_frame = false,
    }

    if t_mot then
        local td = t_mot:get_type_definition()
        if td then
            caps.mot_set_play = (td:get_method("set_Play(System.Boolean)") ~= nil or td:get_method("set_Play") ~= nil)
            caps.mot_set_pause = (td:get_method("set_Pause(System.Boolean)") ~= nil or td:get_method("set_Pause") ~= nil)
            caps.mot_set_playspeed = (td:get_method("set_PlaySpeed(System.Single)") ~= nil or td:get_method("set_PlaySpeed") ~= nil)
            caps.mot_set_bank = (td:get_method("set_MotionBankAsset(via.motion.MotionBankAsset)") ~= nil or td:get_method("set_MotionBankAsset") ~= nil)
            caps.mot_setup_bank = (td:get_method("setupMotionBank()") ~= nil or td:get_method("setupMotionBank") ~= nil)
        end
    end

    if l0 then
        local td = l0:get_type_definition()
        if td then
            caps.l0_set_play = (td:get_method("set_Play(System.Boolean)") ~= nil or td:get_method("set_Play") ~= nil)
            caps.l0_set_pause = (td:get_method("set_Pause(System.Boolean)") ~= nil or td:get_method("set_Pause") ~= nil)
            caps.l0_set_speed = (td:get_method("set_Speed(System.Single)") ~= nil or td:get_method("set_Speed") ~= nil)
            caps.l0_set_weight = (td:get_method("set_Weight(System.Single)") ~= nil or td:get_method("set_Weight") ~= nil)
            caps.l0_set_frame = (td:get_method("set_Frame(System.Single)") ~= nil or td:get_method("set_Frame") ~= nil)
        end
    end

    return caps
end

-- Snapshots all original Motion and Layer 0 settings before any test mutation
local function snapshot_original_settings(t_mot, l0)
    local orig = {
        t_mot = t_mot,
        l0 = l0,
        mot_play = nil,
        mot_pause = nil,
        mot_playspeed = nil,
        mot_bank = nil,
        l0_play = nil,
        l0_pause = nil,
        l0_speed = nil,
        l0_weight = nil,
        l0_frame = nil,
        l0_mid = nil,
        l0_bid = nil,
    }

    if t_mot then
        pcall(function() orig.mot_play = t_mot:call("get_Play") end)
        pcall(function() orig.mot_pause = t_mot:call("get_Pause") end)
        pcall(function() orig.mot_playspeed = t_mot:call("get_PlaySpeed") end)
        pcall(function() orig.mot_bank = t_mot:call("get_MotionBankAsset") end)
    end

    if l0 then
        pcall(function() orig.l0_play = l0:call("get_Play") end)
        pcall(function() orig.l0_pause = l0:call("get_Pause") end)
        pcall(function() orig.l0_speed = l0:call("get_Speed") end)
        pcall(function() orig.l0_weight = l0:call("get_Weight") end)
        pcall(function() orig.l0_frame = l0:call("get_Frame") end)
        pcall(function() orig.l0_mid = l0:call("get_MotionID") end)
        pcall(function() orig.l0_bid = l0:call("get_BankID") end)
    end

    return orig
end

-- Safely restores original Motion, Layer 0 settings, AND MotionBankAsset (including nil) with property verification
function lab.restore_experiment_c_state()
    local orig = lab.exp_c.original_settings
    if not orig or not orig.t_mot then
        lab.exp_c.restoration_status = "SKIPPED_NO_ORIGINAL_SNAPSHOT"
        return
    end
    local caps = lab.exp_c.setter_capabilities or {}

    lab.log_event("STATE_RESTORE", "EXP_C_RESTORE", "Initiating verified restoration of original Motion/Layer settings and MotionBankAsset")

    -- 1. Restore MotionBankAsset (including originally nil bank)
    if caps.mot_set_bank then
        pcall(function() orig.t_mot:call("set_MotionBankAsset", orig.mot_bank) end)
        if caps.mot_setup_bank then
            pcall(function() orig.t_mot:call("setupMotionBank") end)
        end
    end

    -- 2. Restore Motion component settings
    pcall(function()
        if caps.mot_set_play and orig.mot_play ~= nil then orig.t_mot:call("set_Play", orig.mot_play) end
        if caps.mot_set_pause and orig.mot_pause ~= nil then orig.t_mot:call("set_Pause", orig.mot_pause) end
        if caps.mot_set_playspeed and orig.mot_playspeed ~= nil then orig.t_mot:call("set_PlaySpeed", orig.mot_playspeed) end
    end)

    -- 3. Restore Layer 0 settings
    if orig.l0 then
        pcall(function()
            if caps.l0_set_play and orig.l0_play ~= nil then orig.l0:call("set_Play", orig.l0_play) end
            if caps.l0_set_pause and orig.l0_pause ~= nil then orig.l0:call("set_Pause", orig.l0_pause) end
            if caps.l0_set_speed and orig.l0_speed ~= nil then orig.l0:call("set_Speed", orig.l0_speed) end
            if caps.l0_set_weight and orig.l0_weight ~= nil then orig.l0:call("set_Weight", orig.l0_weight) end
            if caps.l0_set_frame and orig.l0_frame ~= nil then orig.l0:call("set_Frame", orig.l0_frame) end
            if orig.l0_mid and orig.l0_bid and orig.l0_mid > 0 then
                pcall(function() orig.l0:call("changeMotion", orig.l0_bid, orig.l0_mid, 0.0) end)
            end
        end)
    end

    -- 4. Verify each restored property instead of assuming success
    local verified_count = 0
    local total_checked = 0
    local discrepancies = {}

    pcall(function()
        -- Verify MotionBankAsset
        local cur_bank = orig.t_mot:call("get_MotionBankAsset")
        total_checked = total_checked + 1
        if cur_bank == orig.mot_bank then
            verified_count = verified_count + 1
        else
            table.insert(discrepancies, string.format("BankAsset (cur=%s, expected=%s)", tostring(cur_bank), tostring(orig.mot_bank)))
        end

        -- Verify Motion pause
        local cur_m_pause = orig.t_mot:call("get_Pause")
        total_checked = total_checked + 1
        if cur_m_pause == orig.mot_pause then
            verified_count = verified_count + 1
        else
            table.insert(discrepancies, string.format("MotionPause (cur=%s, expected=%s)", tostring(cur_m_pause), tostring(orig.mot_pause)))
        end

        -- Verify Motion speed
        local cur_m_speed = orig.t_mot:call("get_PlaySpeed")
        total_checked = total_checked + 1
        if cur_m_speed == orig.mot_playspeed then
            verified_count = verified_count + 1
        else
            table.insert(discrepancies, string.format("MotionSpeed (cur=%s, expected=%s)", tostring(cur_m_speed), tostring(orig.mot_playspeed)))
        end

        -- Verify Layer 0 pause
        if orig.l0 then
            local cur_l_pause = orig.l0:call("get_Pause")
            total_checked = total_checked + 1
            if cur_l_pause == orig.l0_pause then
                verified_count = verified_count + 1
            else
                table.insert(discrepancies, string.format("LayerPause (cur=%s, expected=%s)", tostring(cur_l_pause), tostring(orig.l0_pause)))
            end
        end
    end)

    if #discrepancies == 0 then
        lab.exp_c.restoration_status = string.format("RESTORE_VERIFIED (%d/%d properties checked)", verified_count, total_checked)
    else
        lab.exp_c.restoration_status = string.format("RESTORE_PARTIAL (%d/%d verified; discrepancies: %s)", verified_count, total_checked, table.concat(discrepancies, "; "))
    end

    lab.log_event("STATE_RESTORE_VERIFIED", "EXP_C_RESTORE", lab.exp_c.restoration_status)
end

-- Step 1: Component Audit & Passive Pause/Speed Inspection
function lab.run_experiment_c_inspect()
    lab.log_event("EXP_START", "EXPERIMENT_C_INSPECT", "Starting Target & Animation Component Audit v1.5.2")
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
        "via.Transform", "via.render.Mesh", "via.motion.Motion", "via.motion.MotionFsm2",
        "via.physics.CharacterController", "app.ropeway.survivor.SurvivorMotionController"
    }

    for _, tname in ipairs(audit_types) do
        local ok, c = pcall(function() return target_obj:call("getComponent(System.Type)", sdk.typeof(tname)) end)
        if ok and c then table.insert(lab.exp_c.target_components, tname) end
    end

    -- 2. Inspect Target's Native Motion Component & MotionBankAsset
    local t_mot = nil
    pcall(function() t_mot = target_obj:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion")) end)
    if not t_mot then
        lab.exp_c.inspection_status = "FAILED"
        lab.exp_c.last_result = string.format("FAIL: Target '%s' has no via.motion.Motion component.", target_desc)
        lab.log_event("EXP_RESULT", "EXP_C_INSPECT_FAIL", lab.exp_c.last_result)
        return
    end

    local l0 = nil
    pcall(function() l0 = t_mot:call("getLayer", 0) end)

    -- Audit setter & bank capabilities
    lab.exp_c.setter_capabilities = audit_motion_setter_capabilities(t_mot, l0)

    -- Take initial snapshot of original settings
    lab.exp_c.original_settings = snapshot_original_settings(t_mot, l0)

    local native_bank = lab.exp_c.original_settings.mot_bank
    lab.exp_c.claire_native_bank = native_bank
    lab.log_event("BANK_DISCOVERY", "NATIVE_BANK_INSPECT", tostring(native_bank))

    -- 3. Deep Inspection of Pause State & Speed Parameters
    lab.exp_c.claire_motion_pause = tostring(lab.exp_c.original_settings.mot_pause)
    lab.exp_c.claire_layer_pause = tostring(lab.exp_c.original_settings.l0_pause)
    lab.exp_c.claire_play_speed = lab.exp_c.original_settings.mot_playspeed or 0.0
    lab.exp_c.claire_layer_speed = lab.exp_c.original_settings.l0_speed or 0.0
    lab.exp_c.claire_layer_weight = lab.exp_c.original_settings.l0_weight or 0.0

    lab.log_event("PAUSE_SPEED_AUDIT", target_desc,
        string.format("Motion(Play=%s, Pause=%s, Speed=%s) | Layer0(Play=%s, Pause=%s, Speed=%s, Weight=%s, Frame=%s)",
            tostring(lab.exp_c.original_settings.mot_play), tostring(lab.exp_c.original_settings.mot_pause), tostring(lab.exp_c.original_settings.mot_playspeed),
            tostring(lab.exp_c.original_settings.l0_play), tostring(lab.exp_c.original_settings.l0_pause), tostring(lab.exp_c.original_settings.l0_speed),
            tostring(lab.exp_c.original_settings.l0_weight), tostring(lab.exp_c.original_settings.l0_frame)))

    -- 4. Inspect Leon's Motion Bank Asset for Comparison (DO NOT AUTO-ASSIGN)
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
        { id = lab.exp_c.leon_active_mid, name = string.format("Leon Active Motion (ID %d) [SCENE ACTIVE]", lab.exp_c.leon_active_mid), bank = lab.exp_c.leon_active_bid },
        { id = 160, name = "Stance / Idle (Standard Pistol - Candidate)", bank = 1 },
        { id = 161, name = "Walk Forward (Standard Pistol - Candidate)", bank = 1 },
        { id = 162, name = "Jog / Run Forward (Candidate)", bank = 1 },
    }

    lab.exp_c.inspection_status = "INSPECTION_COMPLETE"
    lab.exp_c.last_result = string.format("INSPECTION_COMPLETE: Target '%s' inspected. NativeBank=%s, Pause(Motion=%s, Layer=%s).",
        target_desc, tostring(native_bank), tostring(lab.exp_c.claire_motion_pause), tostring(lab.exp_c.claire_layer_pause))
    lab.log_event("EXP_END", "EXPERIMENT_C_INSPECT", lab.exp_c.last_result)
end

-- Step 2: Tier 1 Frame-Step Acceptance Probe (Tests set_Frame 12.5 and immediately restores)
function lab.run_experiment_c_framestep()
    local target_obj, target_desc = get_playback_target()
    if not target_obj then return end

    local t_mot = target_obj:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion"))
    local l0 = t_mot and t_mot:call("getLayer", 0)
    if not l0 then
        lab.exp_c.claire_frame_step_result = "FAIL: No Layer 0"
        return
    end

    local caps = audit_motion_setter_capabilities(t_mot, l0)
    if not caps.l0_set_frame then
        lab.exp_c.claire_frame_step_tested = false
        lab.exp_c.claire_frame_step_result = "FRAME_STEP_REJECTED: Layer 0 has no set_Frame method."
        lab.log_event("PROBE_RESULT", "FRAME_STEP_PROBE", lab.exp_c.claire_frame_step_result)
        return
    end

    local orig_f = l0:call("get_Frame") or 0.0
    local test_f = 12.50
    local f_after = nil

    pcall(function() l0:call("set_Frame", test_f) end)
    pcall(function() f_after = l0:call("get_Frame") end)

    if f_after and math.abs(f_after - test_f) < 0.1 then
        lab.exp_c.claire_frame_step_tested = true
        lab.exp_c.claire_frame_step_result = string.format("FRAME_STEP_ACCEPTED: set_Frame(12.5) updated Layer 0 frame (%.2f -> %.2f). Setter functions.", orig_f, f_after)
    else
        lab.exp_c.claire_frame_step_tested = false
        lab.exp_c.claire_frame_step_result = string.format("FRAME_STEP_REJECTED: set_Frame(12.5) failed to update frame (remained %.2f).", tostring(f_after))
    end

    -- Cleanly restore original frame
    pcall(function() l0:call("set_Frame", orig_f) end)
    lab.log_event("PROBE_RESULT", "FRAME_STEP_PROBE", lab.exp_c.claire_frame_step_result)
end

-- Step 3: Tier 2 Controlled Playback Test (Requires explicit bank permission if native bank is nil; auto-restores on completion)
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

    local t_mot = target_obj:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion"))
    local l0 = t_mot and t_mot:call("getLayer", 0)
    if not t_mot or not l0 then
        lab.exp_c.playback_status = "PLAYBACK_FAILED"
        lab.exp_c.last_result = "FAIL: Target lacks via.motion.Motion or Layer 0."
        lab.log_event("EXP_RESULT", "EXP_C_PLAYBACK_FAIL", lab.exp_c.last_result)
        return
    end

    -- Snapshot original settings if not yet snapshotted
    if not lab.exp_c.original_settings then
        lab.exp_c.original_settings = snapshot_original_settings(t_mot, l0)
        lab.exp_c.setter_capabilities = audit_motion_setter_capabilities(t_mot, l0)
    end

    local caps = lab.exp_c.setter_capabilities or audit_motion_setter_capabilities(t_mot, l0)

    -- 1. Check MotionBankAsset: STRICT NO SILENT SUBSTITUTION & REFLECTED CAPABILITY CHECK
    local cur_asset = t_mot:call("get_MotionBankAsset")
    if not cur_asset then
        -- Claire has no native bank asset
        if not lab.exp_c.allow_cross_bank_assignment then
            lab.exp_c.playback_status = "BLOCKED_NO_BANK"
            lab.exp_c.last_result = "BLOCKED: Target has no native MotionBankAsset. Check 'Allow Cross-Bank Assignment' to explicitly link Leon's bank."
            lab.log_event("EXP_RESULT", "EXP_C_NO_BANK", lab.exp_c.last_result)
            return
        end

        local bank_to_assign = lab.exp_c.leon_bank_asset
        if not bank_to_assign then
            lab.exp_c.playback_status = "PLAYBACK_FAILED"
            lab.exp_c.last_result = "FAIL: Leon's MotionBankAsset is nil. Run inspection first."
            lab.log_event("EXP_RESULT", "EXP_C_PLAYBACK_FAIL", lab.exp_c.last_result)
            return
        end

        if not caps.mot_set_bank then
            lab.exp_c.playback_status = "PLAYBACK_FAILED"
            lab.exp_c.last_result = "FAIL: Motion component lacks set_MotionBankAsset method definition."
            lab.log_event("EXP_RESULT", "EXP_C_PLAYBACK_FAIL", lab.exp_c.last_result)
            return
        end

        lab.log_event("API_CALL", "EXPLICIT_CROSS_BANK_SET", "set_MotionBankAsset(LeonBank): " .. tostring(bank_to_assign))
        local ok_set = pcall(function() t_mot:call("set_MotionBankAsset", bank_to_assign) end)
        local ok_setup = true
        if caps.mot_setup_bank then
            ok_setup = pcall(function() t_mot:call("setupMotionBank") end)
        end

        if not ok_set or not ok_setup then
            lab.exp_c.playback_status = "PLAYBACK_FAILED"
            lab.exp_c.last_result = "FAIL: Cross-bank assignment threw exception."
            lab.restore_experiment_c_state()
            return
        end
    end

    -- 2. Explicit Unpausing & Speed Activation using ONLY verified setter capabilities
    pcall(function()
        if caps.mot_set_play then t_mot:call("set_Play", true) end
        if caps.mot_set_playspeed then t_mot:call("set_PlaySpeed", 1.0) end
        if caps.mot_set_pause then t_mot:call("set_Pause", false) end
        if caps.l0_set_play then l0:call("set_Play", true) end
        if caps.l0_set_speed then l0:call("set_Speed", 1.0) end
        if caps.l0_set_weight then l0:call("set_Weight", 1.0) end
        if caps.l0_set_pause then l0:call("set_Pause", false) end
    end)

    -- 3. Execute changeMotion
    local initial_frame = l0:call("get_Frame") or 0.0
    lab.log_event("API_CALL", "CHANGE_MOTION_INVOKE", string.format("changeMotion(Bank=%d, Motion=%d, Blend=5.0) on %s", target_bid, target_mid, target_desc))

    local ok_cm, err_cm = pcall(function()
        local td_l = l0:get_type_definition()
        local cm = td_l and (td_l:get_method("changeMotion(System.UInt32, System.UInt32, System.Single)") 
                          or td_l:get_method("changeMotion(System.Int32, System.Int32, System.Single)"))
        if cm then cm:call(l0, target_bid, target_mid, 5.0) else l0:call("changeMotion", target_bid, target_mid, 5.0) end
    end)

    if not ok_cm then
        lab.exp_c.playback_status = "PLAYBACK_FAILED"
        lab.exp_c.last_result = "FAIL: changeMotion threw exception: " .. tostring(err_cm)
        lab.log_event("EXP_RESULT", "EXP_C_PLAYBACK_FAIL", lab.exp_c.last_result)
        lab.restore_experiment_c_state()
        return
    end

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
                        lt.verdict = "INDEPENDENT_TRANSFORM_CONTROL_VERIFIED"
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

    -- 2. Exp C Playback Frame Progression Monitor with Guaranteed Automatic Restoration
    local pm = lab.exp_c.playback_monitor
    if pm and pm.active and pm.target_obj then
        local ok_val, is_valid = pcall(function() return pm.target_obj:call("get_Valid") end)
        if not ok_val or is_valid ~= true then
            pm.active = false
            lab.exp_c.playback_status = "PLAYBACK_FAILED"
            lab.exp_c.last_result = "FAIL: Target unreadable during monitoring."
            lab.log_event("EXP_RESULT", "EXP_C_MONITOR_FAIL", lab.exp_c.last_result)
            lab.restore_experiment_c_state()
            return
        end

        local t_mot = pm.target_obj:call("getComponent(System.Type)", sdk.typeof("via.motion.Motion"))
        local l0 = t_mot and t_mot:call("getLayer", 0)

        if not t_mot or not l0 then
            pm.active = false
            lab.exp_c.playback_status = "PLAYBACK_FAILED"
            lab.exp_c.last_result = "FAIL: Target Motion or Layer 0 unreadable during monitoring."
            lab.log_event("EXP_RESULT", "EXP_C_MONITOR_FAIL", lab.exp_c.last_result)
            lab.restore_experiment_c_state()
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
                    lab.exp_c.last_result = string.format("FRAME_PROGRESSION_VERIFIED: Motion %d progressed (%.1f -> %.1f, +%d ticks). Pending visual confirmation.",
                        pm.target_mid, pm.start_frame, pm.current_frame, pm.ticks_observed)
                elseif mid == pm.target_mid and not frame_advanced then
                    lab.exp_c.playback_status = "PLAYBACK_STALLED"
                    lab.exp_c.last_result = string.format("PLAYBACK_STALLED: Motion %d assigned, but frame remained stationary at %.1f (Pause=%s, Speed=%.2f).",
                        pm.target_mid, pm.current_frame, tostring(lab.exp_c.claire_layer_pause), lab.exp_c.claire_layer_speed)
                else
                    lab.exp_c.playback_status = "PLAYBACK_OVERRIDDEN"
                    lab.exp_c.last_result = string.format("PLAYBACK_OVERRIDDEN: Native controller immediately reverted Motion %d to %d.", pm.target_mid, mid)
                end
                lab.log_event("EXP_RESULT", "EXP_C_MONITOR_FINISH", lab.exp_c.last_result)

                -- GUARANTEED: Automatically restore original settings upon normal 45-frame monitor completion!
                lab.restore_experiment_c_state()
            end
        end)
    end
end

-- =========================================================================
-- ImGui UI Dashboard
-- =========================================================================

local function draw_lab_ui()
    imgui.text_colored("=== RE2 DUO MODE — ANIMATION RESEARCH LAB ===", 0.3, 0.9, 1.0, 1.0)
    imgui.text_colored("Milestone 1: Rigorous Safety Edition (v1.5.2-m1-safety)", 0.7, 0.7, 0.7, 1.0)
    imgui.separator()

    -- Quick Companion Control Bridge
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
            if duo and duo.start_spawn then duo.start_spawn("full") end
        end
    end
    imgui.separator()

    -- Navigation Tabs
    if imgui.button(lab.selected_tab == 1 and "[ Overview ]" or "Overview") then lab.selected_tab = 1 end
    imgui.same_line()
    if imgui.button(lab.selected_tab == 2 and "[ Exp A: Native Cast ]" or "Exp A: Native Cast") then lab.selected_tab = 2 end
    imgui.same_line()
    if imgui.button(lab.selected_tab == 3 and "[ Exp B: Duplication ]" or "Exp B: Duplication") then lab.selected_tab = 3 end
    imgui.same_line()
    if imgui.button(lab.selected_tab == 4 and "[ Exp C: Motion Bank ]" or "Exp C: Motion Bank") then lab.selected_tab = 4 end
    imgui.same_line()
    if imgui.button(lab.selected_tab == 5 and "[ Logs ]" or "Logs") then lab.selected_tab = 5 end

    imgui.separator()

    -- TAB 1: OVERVIEW
    if lab.selected_tab == 1 then
        imgui.text_colored("Roadmap Status & Strict Verification Criteria (v1.5.2):", 1.0, 0.8, 0.2, 1.0)
        imgui.text("Objective: Establish empirical proof for animated companion pathways without guessing.")
        imgui.spacing()

        -- Exp A Summary
        local col_a = (lab.exp_a.status == "PASS" and {0.2, 1.0, 0.4}) or (lab.exp_a.status == "PARTIAL" and {1.0, 0.8, 0.2}) or {0.8, 0.8, 0.8}
        imgui.text_colored("Experiment A: Native Survivor Casting (SurvivorAssignManager)", col_a[1], col_a[2], col_a[3], 1.0)
        imgui.text("  Status: " .. lab.exp_a.status .. " | Scene Enum: " .. lab.exp_a.scene_enumeration_mode)
        imgui.text("  Result: " .. lab.exp_a.last_result)
        imgui.spacing()

        -- Exp B Summary
        local col_b = (lab.exp_b.status == "PASS" and {0.2, 1.0, 0.4}) or (lab.exp_b.status == "PARTIAL" and {1.0, 0.8, 0.2}) or {0.8, 0.8, 0.8}
        imgui.text_colored("Experiment B: Character & Inert Mesh Prop Duplication", col_b[1], col_b[2], col_b[3], 1.0)
        imgui.text("  Status: " .. lab.exp_b.status .. " | Control Test: " .. lab.exp_b.control_test_status)
        imgui.text("  Result: " .. lab.exp_b.last_result)
        imgui.spacing()

        -- Exp C Summary
        local col_c = (lab.exp_c.playback_status == "PLAYBACK_AND_VISUAL_VERIFIED" and {0.2, 1.0, 0.4}) 
                   or (lab.exp_c.playback_status == "FRAME_PROGRESSION_VERIFIED" and {0.2, 0.9, 1.0}) 
                   or (lab.exp_c.playback_status == "PLAYBACK_STALLED" and {1.0, 0.8, 0.2}) or {0.8, 0.8, 0.8}
        imgui.text_colored("Experiment C: Direct Motion Playback & Unpausing", col_c[1], col_c[2], col_c[3], 1.0)
        imgui.text("  Inspection: " .. lab.exp_c.inspection_status .. " | Playback: " .. lab.exp_c.playback_status .. " | Restore: " .. lab.exp_c.restoration_status)
        imgui.text("  Result: " .. lab.exp_c.last_result)

    -- TAB 2: EXPERIMENT A
    elseif lab.selected_tab == 2 then
        imgui.text_colored("Experiment A: Native Survivor Casting (Safe Modular Execution)", 1.0, 0.8, 0.2, 1.0)
        imgui.text("Overload selection by exact parameter signature. Scene diffing with UNVERIFIED downgrade.")
        imgui.spacing()

        if imgui.button("Step 1: Run Passive Reflection Probe (SAFE)##btn_exp_a_ref") then
            lab.run_experiment_a_reflect()
        end
        imgui.spacing()
        imgui.separator()

        imgui.text_colored("Step 2: Configure Controlled Casting Invocation:", 1.0, 0.8, 0.2, 1.0)
        imgui.text("Matched Overload Signature: " .. tostring(lab.exp_a.selected_overload_sig))

        -- PlayerType selector
        imgui.text("Select PlayerType: ")
        imgui.same_line()
        if imgui.button(lab.exp_a.selected_player_type == 1000 and "[ PL1000: Claire ]" or "PL1000: Claire") then lab.exp_a.selected_player_type = 1000 end
        imgui.same_line()
        if imgui.button(lab.exp_a.selected_player_type == 0 and "[ PL0000: Leon ]" or "PL0000: Leon") then lab.exp_a.selected_player_type = 0 end
        imgui.same_line()
        if imgui.button(lab.exp_a.selected_player_type == 2000 and "[ PL2000: Ada ]" or "PL2000: Ada") then lab.exp_a.selected_player_type = 2000 end

        -- CastingReason selector
        imgui.text("Select CastingReason: ")
        imgui.same_line()
        if imgui.button(lab.exp_a.selected_reason == 1 and "[ InitialSet (1) ]" or "InitialSet (1)") then lab.exp_a.selected_reason = 1 end
        imgui.same_line()
        if imgui.button(lab.exp_a.selected_reason == 8 and "[ Debug (8) ]" or "Debug (8)") then lab.exp_a.selected_reason = 8 end
        imgui.same_line()
        if imgui.button(lab.exp_a.selected_reason == 0 and "[ None (0) ]" or "None (0)") then lab.exp_a.selected_reason = 0 end

        -- Execution button
        if imgui.button("Execute Single Controlled Standby Call##btn_exp_a_cast") then
            lab.run_experiment_a_cast()
        end
        imgui.same_line()
        if imgui.button("Trigger applyCastingRequest() [Optional]##btn_exp_a_apply") then
            lab.run_experiment_a_apply()
        end
        imgui.same_line()
        if imgui.button("Clean Up Cast Actor##btn_exp_a_clean") then
            lab.cleanup_experiment_a()
        end

        imgui.spacing()
        imgui.separator()
        imgui.text("Status: " .. lab.exp_a.status)
        imgui.text("Singleton Detected: " .. tostring(lab.exp_a.singleton_found))
        imgui.text("Scene Enum Mode: " .. tostring(lab.exp_a.scene_enumeration_mode))
        imgui.text("Last Standby Call: " .. tostring(lab.exp_a.last_standby_call))
        imgui.text("Last Standby Result: " .. tostring(lab.exp_a.last_standby_ret) .. " (0=Accepted, 1=Refused)")
        imgui.text("Apply Casting Result: " .. tostring(lab.exp_a.apply_casting_result))
        imgui.text("Newly Created Actor: " .. tostring(lab.exp_a.created_actor) .. " (Valid=" .. tostring(lab.exp_a.actor_valid) .. ")")
        imgui.text("Verdict: " .. lab.exp_a.last_result)

    -- TAB 3: EXPERIMENT B
    elseif lab.selected_tab == 3 then
        imgui.text_colored("Experiment B: Character & Inert Mesh Prop Duplication", 1.0, 0.8, 0.2, 1.0)
        imgui.text("Positive identification of via.render.Mesh. Strict get_Valid()==false confirmation on cleanup.")
        imgui.spacing()

        if imgui.button("1. Run Control Test (Inert Mesh Prop)##btn_exp_b_control") then
            lab.run_experiment_b_control()
        end
        imgui.same_line()
        if imgui.button("2. Spawn Duplicate Player Actor##btn_exp_b_spawn") then
            lab.run_experiment_b()
        end
        imgui.same_line()
        if imgui.button("Destroy Test Clone (Sequential Cleanup)##btn_exp_b_destroy") then
            lab.cleanup_experiment_b()
        end

        imgui.spacing()
        imgui.separator()
        imgui.text("Control Target: " .. tostring(lab.exp_b.control_target_name) .. " (" .. tostring(lab.exp_b.control_target_ptr) .. ")")
        imgui.text("Control Target Has Mesh: " .. tostring(lab.exp_b.control_target_has_mesh))
        imgui.text("Control Test Status: " .. tostring(lab.exp_b.control_test_status))
        imgui.text("Control Cleanup Status: " .. tostring(lab.exp_b.control_cleanup_status))
        imgui.text("Control Test Verdict: " .. tostring(lab.exp_b.control_test_verdict))
        imgui.separator()
        imgui.text("Player Clone Active: " .. tostring(lab.exp_b.clone_entity ~= nil))
        imgui.text("Input Verified Disabled: " .. tostring(lab.exp_b.input_verified_disabled))
        imgui.text("Independent Transform Control: " .. tostring(lab.exp_b.independent_transform_control))
        imgui.text("Motion Blend Tree Ticking: " .. tostring(lab.exp_b.motion_ticking))
        imgui.text("Player Clone Cleanup Status: " .. tostring(lab.exp_b.cleanup_status))
        imgui.text("Verdict: " .. lab.exp_b.last_result)

    -- TAB 4: EXPERIMENT C
    elseif lab.selected_tab == 4 then
        imgui.text_colored("Experiment C: Claire Animation Playback & Stalled Frame Investigation", 1.0, 0.8, 0.2, 1.0)
        imgui.text("Automatic restoration on 45-frame completion. Verifies bank restoration (including nil).")
        imgui.spacing()

        if imgui.button("1. Inspect Target & Original Animation Settings##btn_exp_c_insp") then
            lab.run_experiment_c_inspect()
        end
        imgui.same_line()
        if imgui.button("Restore Original Animation Settings (Verified)##btn_exp_c_restore") then
            lab.restore_experiment_c_state()
        end

        imgui.spacing()
        imgui.text("Inspection Status: " .. lab.exp_c.inspection_status)
        imgui.text("Target Selected: " .. tostring(lab.exp_c.target_name))
        imgui.text("Native Bank Present: " .. tostring(lab.exp_c.claire_native_bank ~= nil))
        imgui.text(string.format("Motion Pause: %s | Layer 0 Pause: %s", tostring(lab.exp_c.claire_motion_pause), tostring(lab.exp_c.claire_layer_pause)))
        imgui.text(string.format("Play Speed: %.2f | Layer Speed: %.2f | Weight: %.2f", lab.exp_c.claire_play_speed, lab.exp_c.claire_layer_speed, lab.exp_c.claire_layer_weight))
        imgui.text("Restoration Status: " .. tostring(lab.exp_c.restoration_status))

        imgui.separator()
        imgui.text_colored("Tier 1: Frame-Step Acceptance Probe:", 1.0, 0.8, 0.2, 1.0)
        if imgui.button("Run Frame-Step Probe (Test set_Frame 12.5 & Auto-Restore)##btn_framestep") then
            lab.run_experiment_c_framestep()
        end
        imgui.same_line()
        imgui.text("Probe Result: " .. tostring(lab.exp_c.claire_frame_step_result))

        imgui.separator()
        imgui.text_colored("Tier 2: Controlled Playback Testing:", 1.0, 0.8, 0.2, 1.0)

        -- Explicit Cross-Bank Assignment Checkbox (Prevents silent substitution)
        local cb_changed, cb_val = imgui.checkbox("Allow Cross-Bank Assignment (Link Leon's MotionBankAsset to Claire if native bank is nil)##chk_cross_bank", lab.exp_c.allow_cross_bank_assignment)
        if cb_changed then lab.exp_c.allow_cross_bank_assignment = cb_val end

        if lab.exp_c.leon_active_mid > 0 then
            local active_btn_label = string.format("Play Active Leon Motion (ID %d, Bank %d)##btn_play_active", lab.exp_c.leon_active_mid, lab.exp_c.leon_active_bid)
            if imgui.button(active_btn_label) then lab.run_experiment_c_playback(lab.exp_c.leon_active_mid, lab.exp_c.leon_active_bid) end
        end

        if imgui.button("Play Stance / Idle (ID 160)##btn_play_160") then lab.run_experiment_c_playback(160, 1) end
        imgui.same_line()
        if imgui.button("Play Walk Forward (ID 161)##btn_play_161") then lab.run_experiment_c_playback(161, 1) end
        imgui.same_line()
        if imgui.button("Play Jog / Run (ID 162)##btn_play_162") then lab.run_experiment_c_playback(162, 1) end

        imgui.spacing()
        imgui.text("Playback Status: " .. lab.exp_c.playback_status)
        if lab.exp_c.playback_monitor.active then
            imgui.text_colored(string.format("Monitoring frame progression: Tick %d/%d (Start: %.1f, Current: %.1f)...",
                lab.exp_c.playback_monitor.ticks_observed, lab.exp_c.playback_monitor.max_ticks,
                lab.exp_c.playback_monitor.start_frame, lab.exp_c.playback_monitor.current_frame), 0.2, 0.9, 1.0, 1.0)
        end
        imgui.text("Verdict: " .. lab.exp_c.last_result)

        -- Tier 3: Visual Viewport Confirmation
        imgui.separator()
        imgui.text_colored("Tier 3: Viewport Visual Confirmation:", 1.0, 0.8, 0.2, 1.0)
        local v_changed, v_val = imgui.checkbox("Visual Animation Confirmed in Viewport (Mesh/Bones Deforming)##chk_visual", lab.exp_c.visual_confirmed)
        if v_changed then
            lab.exp_c.visual_confirmed = v_val
            if v_val and lab.exp_c.playback_status == "FRAME_PROGRESSION_VERIFIED" then
                lab.exp_c.playback_status = "PLAYBACK_AND_VISUAL_VERIFIED"
                lab.exp_c.last_result = "PASS: PLAYBACK_AND_VISUAL_VERIFIED (Logical frame progression verified and confirmed visually on character)"
            elseif not v_val and lab.exp_c.playback_status == "PLAYBACK_AND_VISUAL_VERIFIED" then
                lab.exp_c.playback_status = "FRAME_PROGRESSION_VERIFIED"
            end
            lab.log_event("VISUAL_CONFIRM", "VIEWPORT_CONFIRMATION", tostring(v_val))
        end

    -- TAB 5: LOGS
    elseif lab.selected_tab == 5 then
        imgui.text_colored("Live Research Log (reframework/data/duo_mode/animation_lab_log.txt):", 0.7, 0.7, 0.7, 1.0)
        if imgui.button("Clear Buffer") then lab.log_buffer = {} end
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
    pcall(lab.restore_experiment_c_state)
end)
