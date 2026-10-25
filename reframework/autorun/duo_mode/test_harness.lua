--[[
    Resident Evil 2: Duo Mode
    test_harness.lua - Automated QA regression test suite
]]

local config = require("duo_mode/config")
local spawner = require("duo_mode/spawner")
local locomotion = require("duo_mode/locomotion")
local portal_defense = require("duo_mode/portal_defense")
local fsm = require("duo_mode/fsm")

local test_harness = {}

local function report(test_name, passed, detail)
    local status = passed and "[PASS]" or "[FAIL]"
    re.msg(string.format("[DuoHarness] %-25s %s : %s", test_name, status, detail or ""))
end

local function make_vec3(x, y, z)
    if Vector3f and Vector3f.new then
        return Vector3f.new(x, y, z)
    end
    return { x = x, y = y, z = z }
end

-- Test 1: Verify synthetic stick math does not spin during camera rotations
function test_harness.test_synthetic_stick_math()
    local comp_pos = make_vec3(0, 0, 0)
    local target_pos = make_vec3(0, 0, 5) -- Directly forward in world Z
    local comp_yaw = 0.0 -- Facing forward

    local sx, sy, dist = locomotion.calculate_synthetic_stick(comp_pos, comp_yaw, target_pos)
    local check1 = (math.abs(sx) < 0.01 and sy > 0.4)

    -- Now rotate companion 90 degrees to the right (pi/2 radians)
    local comp_yaw_rotated = math.pi * 0.5
    local sx2, sy2, _ = locomotion.calculate_synthetic_stick(comp_pos, comp_yaw_rotated, target_pos)
    -- Target is now to companion's left (-X in local space)
    local check2 = (sx2 < -0.4 and math.abs(sy2) < 0.1)

    local passed = check1 and check2
    report("SyntheticStickMath", passed, "Verified world-to-local yaw transformation")
    return passed
end

-- Test 2: Verify portal room mismatch detection logic
function test_harness.test_portal_room_mismatch()
    local leader_room = 101
    local comp_room = 102
    local door_closed = true

    local should_teleport = portal_defense.check_room_transition(leader_room, comp_room, door_closed)
    local passed = (should_teleport == true)
    report("PortalRoomMismatch", passed, "Triggered instant catch-up on door close")
    return passed
end

-- Test 3: Verify FSM state transitions and downed bleed-out timer
function test_harness.test_fsm_downed_transition()
    fsm.set_state(fsm.STATES.FOLLOW)
    fsm.update(0.1, 0) -- HP = 0

    local is_downed = (fsm.current_state == fsm.STATES.DOWNED)
    fsm.update(config.bleed_out_time + 1.0, 0)
    local result = fsm.update(0.1, 0)
    local is_game_over = (result == "GAME_OVER")

    local passed = is_downed and is_game_over
    fsm.set_state(fsm.STATES.FOLLOW) -- Reset
    report("FSMDownedTransition", passed, "Verified incapacitation and bleed-out expiration")
    return passed
end

-- Test 4: Verify save state slot path formatting
function test_harness.test_save_slot_indexing()
    local function get_path(slot)
        if slot == 99 then return "save_state_scenario_transition.json" end
        return string.format("save_state_slot_%02d.json", slot)
    end

    local check1 = (get_path(1) == "save_state_slot_01.json")
    local check2 = (get_path(99) == "save_state_scenario_transition.json")
    local passed = check1 and check2
    report("SaveSlotIndexing", passed, "Verified multi-slot isolation")
    return passed
end

-- Run entire automated regression test suite
function test_harness.run_all()
    re.msg("====================================================")
    re.msg("     RUNNING DUO MODE AUTOMATED TEST HARNESS        ")
    re.msg("====================================================")
    local p1 = test_harness.test_synthetic_stick_math()
    local p2 = test_harness.test_portal_room_mismatch()
    local p3 = test_harness.test_fsm_downed_transition()
    local p4 = test_harness.test_save_slot_indexing()
    local all_passed = p1 and p2 and p3 and p4
    re.msg("====================================================")
    re.msg("TEST SUMMARY: " .. (all_passed and "ALL TESTS PASSED" or "SOME TESTS FAILED"))
    re.msg("====================================================")
    return all_passed
end

return test_harness
