--[[
    Resident Evil 2: Duo Mode
    duo_mode.lua - Master entry point loaded by REFramework
    Days 1–8 Production Architecture
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

log_msg("[DuoMode] Initializing Days 1–8 modules...")

local config = require("duo_mode/config")
local spawner = require("duo_mode/spawner")
local locomotion = require("duo_mode/locomotion")
local portal_defense = require("duo_mode/portal_defense")
local fsm = require("duo_mode/fsm")
local command_wheel = require("duo_mode/command_wheel")
local door_hooks = require("duo_mode/door_hooks")
local inventory_manager = require("duo_mode/inventory_manager")
local combat_ai = require("duo_mode/combat_ai")
local health_manager = require("duo_mode/health_manager")
local test_harness = require("duo_mode/test_harness")

-- Run regression test suite on startup
local test_results = test_harness.run_all()
log_msg("[DuoMode] Boot Regression Suite: " .. (test_results and "ALL PASSED" or "SOME FAILED"))

local current_gametime = 0.0

-- Master frame update loop
re.on_frame(function()
    if not config.enabled then return end
    current_gametime = current_gametime + 0.016

    -- Check hardware trigger for tactical command wheel
    command_wheel.update_input()

    -- Ensure companion is spawned once the scene is ready
    if not spawner.is_spawned then
        if spawner.is_scene_ready() then
            spawner.spawn_companion()
        end
    end

    -- Active companion processing
    if spawner.is_spawned and spawner.companion_game_object then
        local player_man = sdk.get_managed_singleton("app.ropeway.survivor.PlayerManager")
        local master_player = player_man and player_man:call("getMasterPlayerCharacter")

        -- Update FSM and bleed-out timer
        local status = fsm.update(0.016, health_manager.current_hp)
        if status == "GAME_OVER" then
            local game_over_man = sdk.get_managed_singleton("app.ropeway.GameOverManager")
            if game_over_man then
                game_over_man:call("startGameOver")
            end
        end

        -- Day 5: Update door state machine and cutscene protection
        door_hooks.update(spawner.companion_game_object)

        -- Day 8: Update health and proximity revive checks
        if master_player then
            health_manager.update(spawner.companion_game_object, master_player, 0.016)
        end

        -- State-specific execution
        if fsm.current_state == fsm.STATES.FOLLOW and master_player then
            -- Day 2: Locomotion root-motion tracking
            locomotion.update_locomotion(spawner.companion_game_object, master_player, 0.016, false)
            -- Day 3: Portal room culling defense
            portal_defense.update(spawner.companion_game_object, master_player)

        elseif fsm.current_state == fsm.STATES.COVER and master_player then
            -- Day 7: Combat AI target acquisition and muzzle-ray firing
            locomotion.update_locomotion(spawner.companion_game_object, master_player, 0.016, false)
            combat_ai.update(spawner.companion_game_object, master_player, current_gametime)

        elseif fsm.current_state == fsm.STATES.WAIT then
            -- Hold position; zero velocity
        end
    end
end)

-- Master UI rendering loop
re.on_draw_ui(function()
    if not config.enabled then return end

    -- Day 4: Draw Tactical Command Wheel
    command_wheel.draw()

    -- Day 6: Draw Docked Dual-Bag Inventory
    inventory_manager.draw_ui()

    -- Day 8: Draw Downed / Revive HUD
    health_manager.draw_ui()

    -- REFramework Developer Menu under Script Generated UI
    if imgui.tree_node("RE2: Duo Mode") then
        config.enabled = imgui.checkbox("Mod Enabled", config.enabled)
        config.debug_mode = imgui.checkbox("Debug Mode", config.debug_mode)
        
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

        imgui.tree_pop()
    end
end)

log_msg("[DuoMode] Days 1–8 hooks registered successfully.")
