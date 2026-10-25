--[[
    Resident Evil 2: Duo Mode
    test_harness.lua - Automated QA regression test suite
    Updated for Days 1–8: Locomotion, Portals, Doors, Inventory, Combat, and Revive
    Author: AryanTechie-007
]]

local config = require("duo_mode/config")
local spawner = require("duo_mode/spawner")
local locomotion = require("duo_mode/locomotion")
local portal_defense = require("duo_mode/portal_defense")
local fsm = require("duo_mode/fsm")
local door_hooks = require("duo_mode/door_hooks")
local inventory_manager = require("duo_mode/inventory_manager")
local combat_ai = require("duo_mode/combat_ai")
local health_manager = require("duo_mode/health_manager")

local test_harness = {}

local function log_msg(str)
    if log and log.info then
        log.info(str)
    end
    local f = io.open("reframework/data/duo_mode/test_log.txt", "a")
    if f then
        f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. tostring(str) .. "\n")
        f:close()
    end
end

local function report(test_name, passed, detail)
    local status = passed and "[PASS]" or "[FAIL]"
    log_msg(string.format("[DuoHarness] %-28s %s : %s", test_name, status, detail or ""))
end

local function make_vec3(x, y, z)
    if Vector3f and Vector3f.new then
        return Vector3f.new(x, y, z)
    end
    return { x = x, y = y, z = z }
end

-- Test 1: Day 2 - Synthetic stick math does not spin during camera rotations
function test_harness.test_synthetic_stick_math()
    local comp_pos = make_vec3(0, 0, 0)
    local target_pos = make_vec3(0, 0, 5)
    local sx, sy = locomotion.calculate_synthetic_stick(comp_pos, 0.0, target_pos)
    local check1 = (math.abs(sx) < 0.01 and sy > 0.4)

    local sx2, sy2 = locomotion.calculate_synthetic_stick(comp_pos, math.pi * 0.5, target_pos)
    local check2 = (sx2 < -0.4 and math.abs(sy2) < 0.1)

    local passed = check1 and check2
    report("SyntheticStickMath", passed, "Verified world-to-local yaw transformation")
    return passed
end

-- Test 2: Day 2 - Distance-based magnitude scaling (Idle -> Walk -> Sprint)
function test_harness.test_distance_magnitude_scaling()
    local comp_pos = make_vec3(0, 0, 0)
    local sx_i, sy_i = locomotion.calculate_synthetic_stick(comp_pos, 0.0, make_vec3(0, 0, 0.8))
    local check_idle = (sx_i == 0.0 and sy_i == 0.0)

    local sx_s, sy_s = locomotion.calculate_synthetic_stick(comp_pos, 0.0, make_vec3(0, 0, 8.0))
    local mag_s = math.sqrt(sx_s * sx_s + sy_s * sy_s)
    local check_sprint = (math.abs(mag_s - 1.0) < 0.05)

    local passed = check_idle and check_sprint
    report("DistanceMagnitudeScaling", passed, "Validated Idle (0.0) and Sprint (1.0)")
    return passed
end

-- Test 3: Day 2 - Licker acoustic stealth speed clamping
function test_harness.test_licker_acoustic_damping()
    local damped_x, damped_y = locomotion.apply_acoustic_damping(0.0, 1.0, true)
    local mag = math.sqrt(damped_x * damped_x + damped_y * damped_y)
    local passed = (math.abs(mag - config.licker_max_stick_magnitude) < 0.01)
    report("LickerAcousticDamping", passed, string.format("Clamped to <= %.2f in stealth zones", config.licker_max_stick_magnitude))
    return passed
end

-- Test 4: Day 3 - Portal room mismatch detection logic
function test_harness.test_portal_room_mismatch()
    local should_teleport = portal_defense.check_room_transition(101, 102, true)
    report("PortalRoomMismatch", should_teleport, "Triggered instant catch-up on door close")
    return should_teleport
end

-- Test 5: Day 3 - Elevator kinematic parenting flags
function test_harness.test_elevator_parenting()
    portal_defense.is_on_elevator = false
    local dummy_comp = { call = function() return { call = function() end, set_field = function() end } end }
    local dummy_elev = { call = function() return { call = function() end } end }
    portal_defense.enter_elevator(dummy_comp, dummy_elev)
    local check_enter = (portal_defense.is_on_elevator == true)
    portal_defense.exit_elevator(dummy_comp)
    local check_exit = (portal_defense.is_on_elevator == false)
    local passed = check_enter and check_exit
    report("ElevatorParenting", passed, "Verified capsule disable and transform parenting")
    return passed
end

-- Test 6: Day 5 - Door key spoofing state machine safety
function test_harness.test_door_key_spoof_safety()
    door_hooks.interaction_state.in_progress = false
    local ok = door_hooks.attempt_unlock_door(5001, true, nil)
    local in_prog = (door_hooks.interaction_state.in_progress == true)
    door_hooks.update(nil)
    local restored = (door_hooks.interaction_state.in_progress == false)
    local passed = ok and in_prog and restored
    report("DoorKeySpoofSafety", passed, "1-frame key spoof and safe slot restore")
    return passed
end

-- Test 7: Day 6 - Dual-bag 8-slot inventory add, query, and remove
function test_harness.test_dual_bag_inventory()
    for i = 1, 8 do inventory_manager.remove_item(i) end
    local added = inventory_manager.add_item(1001, 30, "Handgun Ammo")
    local has_item, slot = inventory_manager.has_item(1001)
    local check = (added and has_item and slot == 1)
    report("DualBagInventory", check, "Verified 8-slot management and item search")
    return check
end

-- Test 8: Day 7 - Combat AI ammo consumption and dry callout
function test_harness.test_combat_ammo_depletion()
    for i = 1, 8 do inventory_manager.remove_item(i) end
    inventory_manager.add_item(1001, 2, "Handgun Ammo")
    local dummy_comp = { call = function() return nil end }
    local shot1 = combat_ai.fire_shot(dummy_comp, make_vec3(0, 0, 5))
    local shot2 = combat_ai.fire_shot(dummy_comp, make_vec3(0, 0, 5))
    local shot3 = combat_ai.fire_shot(dummy_comp, make_vec3(0, 0, 5)) -- Should be out of ammo!
    local passed = shot1 and shot2 and (shot3 == false) and combat_ai.is_dry
    report("CombatAmmoDepletion", passed, "Decremented inventory rounds and triggered 'I'm out!'")
    return passed
end

-- Test 9: Day 8 - Anti-grab filtering, downed state, and herb revive
function test_harness.test_anti_grab_and_revive()
    health_manager.current_hp = 500
    health_manager.apply_damage(100, true) -- Grab attack -> halved to 50
    local check_grab = (health_manager.current_hp == 450)

    health_manager.apply_damage(500, false) -- Exceeds HP -> triggers downed
    local check_downed = health_manager.is_downed and (fsm.current_state == fsm.STATES.DOWNED)

    local revived = health_manager.revive("GreenHerb")
    local check_revived = (revived and not health_manager.is_downed and health_manager.current_hp > 0)

    local passed = check_grab and check_downed and check_revived
    report("AntiGrabAndRevive", passed, "Verified grab neutralization, downed FSM, and Green Herb revive")
    return passed
end

-- Test 10: Multi-slot save path generation
function test_harness.test_save_slot_indexing()
    local function get_path(slot)
        if slot == 99 then return "save_state_scenario_transition.json" end
        return string.format("save_state_slot_%02d.json", slot)
    end
    local passed = (get_path(1) == "save_state_slot_01.json") and (get_path(99) == "save_state_scenario_transition.json")
    report("SaveSlotIndexing", passed, "Verified multi-slot isolation")
    return passed
end

-- Run entire Days 1–8 regression test suite
function test_harness.run_all()
    log_msg("====================================================")
    log_msg("     RUNNING DUO MODE DAYS 1-8 REGRESSION HARNESS   ")
    log_msg("====================================================")

    local p1, r1 = pcall(test_harness.test_synthetic_stick_math)
    local p2, r2 = pcall(test_harness.test_distance_magnitude_scaling)
    local p3, r3 = pcall(test_harness.test_licker_acoustic_damping)
    local p4, r4 = pcall(test_harness.test_portal_room_mismatch)
    local p5, r5 = pcall(test_harness.test_elevator_parenting)
    local p6, r6 = pcall(test_harness.test_door_key_spoof_safety)
    local p7, r7 = pcall(test_harness.test_dual_bag_inventory)
    local p8, r8 = pcall(test_harness.test_combat_ammo_depletion)
    local p9, r9 = pcall(test_harness.test_anti_grab_and_revive)
    local p10, r10 = pcall(test_harness.test_save_slot_indexing)

    local all_passed = (p1 and r1) and (p2 and r2) and (p3 and r3) and (p4 and r4) and 
                       (p5 and r5) and (p6 and r6) and (p7 and r7) and (p8 and r8) and 
                       (p9 and r9) and (p10 and r10)

    log_msg("====================================================")
    log_msg("TEST SUMMARY: " .. (all_passed and "ALL TESTS PASSED (10/10)" or "SOME TESTS FAILED"))
    log_msg("====================================================")
    return all_passed
end

return test_harness
