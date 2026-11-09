--[[
    Resident Evil 2: Duo Mode
    duo_mode.lua - Master entry point loaded by REFramework
    Production Architecture: Days 1–14
    Author: AryanTechie-007
]]

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

log_msg("[DuoMode] Initializing Duo Mode production modules...")

local config = require("duo_mode/config")
local utils = require("duo_mode/utils")
local spawner = require("duo_mode/spawner")
local locomotion = require("duo_mode/locomotion")
local portal_defense = require("duo_mode/portal_defense")
local fsm = require("duo_mode/fsm")
local command_wheel = require("duo_mode/command_wheel")
local door_hooks = require("duo_mode/door_hooks")
local inventory_manager = require("duo_mode/inventory_manager")
local combat_ai = require("duo_mode/combat_ai")
local health_manager = require("duo_mode/health_manager")
local audio_bridge = require("duo_mode/audio_bridge")
local banter_manager = require("duo_mode/banter_manager")
local save_manager = require("duo_mode/save_manager")
local test_harness = require("duo_mode/test_harness")

-- Run regression test suite on startup
local test_results = test_harness.run_all()
log_msg("[DuoMode] Boot Regression Suite: " .. (test_results and "ALL PASSED" or "SOME FAILED"))

local current_gametime = 0.0

-- Reset state when loading saves or resetting scripts
re.on_script_reset(function()
    spawner.is_spawned = false
    spawner.companion_game_object = nil
    spawner.spawn_in_progress = false
    health_manager.current_hp = config.companion_max_hp
    health_manager.is_downed = false
    fsm.set_state(fsm.STATES.FOLLOW)
    audio_bridge.stop_all()
end)

-- Master frame update loop
re.on_frame(function()
    if not config.enabled then return end
    current_gametime = current_gametime + 0.016

    -- Day 9: Audio lifecycle monitoring (pause / focus / game over)
    pcall(audio_bridge.update_lifecycle)

    -- Day 4: Check hardware trigger for tactical command wheel
    pcall(command_wheel.update_input)

    -- Ensure companion is spawned once the scene is ready
    if not spawner.is_spawned then
        if spawner.is_scene_ready() then
            pcall(spawner.spawn_companion)
        end
    end

    -- Active companion processing
    local master_player = spawner.get_master_player()
    if spawner.is_spawned and spawner.companion_game_object then
        -- Update FSM and bleed-out timer
        local status = nil
        pcall(function()
            status = fsm.update(0.016, health_manager.current_hp)
        end)

        if status == "GAME_OVER" then
            local game_over_flow = sdk.get_managed_singleton("app.ropeway.gamemastering.GameOverFlow")
                                or sdk.get_managed_singleton("app.ropeway.GameOverManager")
            if game_over_flow and game_over_flow.call then
                pcall(function() game_over_flow:call("startGameOver") end)
            end
        end

        -- Day 5: Update door state machine and cutscene protection
        pcall(door_hooks.update, spawner.companion_game_object)

        -- Day 8: Update health and proximity revive checks
        if master_player then
            pcall(health_manager.update, spawner.companion_game_object, master_player, 0.016)
        end

        -- Day 10: Dynamic Banter Engine update
        local is_safe_room = (portal_defense.last_leader_room == 100 or portal_defense.last_leader_room == 102)
        pcall(banter_manager.update, current_gametime, 0.016, health_manager.current_hp, health_manager.max_hp, is_safe_room)

        -- State-specific execution (Crash-Protected)
        if fsm.current_state == fsm.STATES.FOLLOW and master_player then
            -- Day 2: Locomotion root-motion tracking
            pcall(locomotion.update_locomotion, spawner.companion_game_object, master_player, 0.016, false)
            -- Day 3: Portal room culling defense
            pcall(portal_defense.update, spawner.companion_game_object, master_player)

        elseif fsm.current_state == fsm.STATES.COVER and master_player then
            -- Day 7: Combat AI target acquisition and muzzle-ray firing
            pcall(locomotion.update_locomotion, spawner.companion_game_object, master_player, 0.016, false)
            pcall(combat_ai.update, spawner.companion_game_object, master_player, current_gametime)

        elseif fsm.current_state == fsm.STATES.WAIT then
            -- Hold position; zero velocity
        end
    end

    -- Render in-game floating HUD overlays (Command Wheel, Inventory, Downed HUD, Subtitles)
    pcall(command_wheel.draw)
    pcall(inventory_manager.draw_ui)
    pcall(health_manager.draw_ui)
    pcall(banter_manager.draw_subtitles)
end)

-- REFramework Menu rendering loop (inside Script Generated UI)
re.on_draw_ui(function()
    imgui.text_colored("=== RESIDENT EVIL 2: DUO MODE ===", 0.2, 0.9, 1.0, 1.0)

    local changed, new_val = imgui.checkbox("Mod Enabled", config.enabled)
    if changed then
        config.enabled = new_val
    end

    imgui.same_line()
    local dbg_changed, new_dbg = imgui.checkbox("Debug Mode", config.debug_mode)
    if dbg_changed then
        config.debug_mode = new_dbg
    end

    imgui.separator()
    imgui.text("Companion State: " .. fsm.get_state_name())
    imgui.text(string.format("Companion HP: %d / %d", health_manager.current_hp, health_manager.max_hp))

    if imgui.button("Damage Companion (-250 HP)") then
        health_manager.apply_damage(250, false)
    end
    imgui.same_line()
    if imgui.button("Test Anti-Grab Hit") then
        health_manager.apply_damage(100, true)
    end

    imgui.separator()
    if imgui.button("Open Tactical Wheel") then
        command_wheel.open()
    end
    imgui.same_line()
    if imgui.button("Run Automated Test Suite") then
        test_harness.run_all()
    end

    imgui.separator()
    imgui.text_colored("--- Native Survivor Engine Spawner ---", 0.9, 0.9, 0.2, 1.0)
    local master_p = spawner.get_master_player()
    imgui.text("Master Player (Leon): " .. (master_p and "CONNECTED" or "WAITING FOR IN-GAME SCENE"))

    local pos = master_p and spawner.get_player_position(master_p)
    if pos then
        imgui.text(string.format("Player Coordinates: (%.2f, %.2f, %.2f)", pos.x, pos.y, pos.z))
    end

    imgui.text("Companion 3D Entity: " .. (spawner.companion_game_object and "ACTIVE (IN 3D WORLD)" or "NOT SPAWNED"))
    imgui.text("Spawn Status: " .. tostring(spawner.last_spawn_status))

    if imgui.button("Spawn Companion (Native / Rigged)") then
        spawner.force_spawn()
    end
    imgui.same_line()
    if imgui.button("Dump Survivor Engine Types to Log") then
        spawner.inspect_survivor_system()
    end
    imgui.same_line()
    if imgui.button("Despawn Companion") then
        spawner.despawn_companion()
    end

    imgui.separator()
    imgui.text_colored("--- Save / Load & Banter Controls ---", 0.2, 0.8, 0.9, 1.0)
    if imgui.button("Save State (Slot 1)") then
        save_manager.save_slot(1)
    end
    imgui.same_line()
    if imgui.button("Load State (Slot 1)") then
        save_manager.load_slot(1)
    end
    imgui.same_line()
    if imgui.button("Trigger Safe Room Voice") then
        banter_manager.safe_room_voiced = false
        banter_manager.on_safe_room_tick(6.0, true)
    end
    imgui.same_line()
    if imgui.button("Trigger Low HP Voice") then
        banter_manager.danger_voiced = false
        banter_manager.on_health_check(200, 1000)
    end
    imgui.separator()
end)

log_msg("[DuoMode] Master duo_mode.lua initialized successfully.")
