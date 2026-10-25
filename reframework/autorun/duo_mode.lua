--[[
    Resident Evil 2: Duo Mode
    duo_mode.lua - Master entry point loaded by REFramework
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

log_msg("[DuoMode] Loading modules...")

local config = require("duo_mode/config")
local spawner = require("duo_mode/spawner")
local locomotion = require("duo_mode/locomotion")
local portal_defense = require("duo_mode/portal_defense")
local fsm = require("duo_mode/fsm")
local command_wheel = require("duo_mode/command_wheel")
local test_harness = require("duo_mode/test_harness")

log_msg("[DuoMode] Initializing Resident Evil 2 Duo Mode v0.1.0-alpha...")

-- Run Day 1 regression test suite on startup
local test_results = test_harness.run_all()
log_msg("[DuoMode] Boot Regression Suite: " .. (test_results and "ALL PASSED" or "SOME FAILED"))

local companion_hp = config.companion_max_hp

-- Frame update loop
re.on_frame(function()
    if not config.enabled then return end

    -- Check if companion needs to be spawned
    if not spawner.is_spawned then
        if spawner.is_scene_ready() then
            spawner.spawn_companion()
        end
    end

    -- Update companion state machine
    if spawner.is_spawned and spawner.companion_game_object then
        local status = fsm.update(0.016, companion_hp)
        if status == "GAME_OVER" then
            local game_over_man = sdk.get_managed_singleton("app.ropeway.GameOverManager")
            if game_over_man then
                game_over_man:call("startGameOver")
            end
        elseif fsm.current_state == fsm.STATES.FOLLOW then
            local player_man = sdk.get_managed_singleton("app.ropeway.survivor.PlayerManager")
            if player_man then
                local master_player = player_man:call("getMasterPlayerCharacter")
                if master_player then
                    locomotion.update_locomotion(spawner.companion_game_object, master_player, 0.016, false)
                end
            end
        end
    end
end)

-- ImGui rendering loop
re.on_draw_ui(function()
    if not config.enabled then return end

    command_wheel.draw()

    if imgui.tree_node("RE2: Duo Mode") then
        config.enabled = imgui.checkbox("Mod Enabled", config.enabled)
        config.debug_mode = imgui.checkbox("Debug Mode", config.debug_mode)
        
        imgui.separator()
        imgui.text("Companion State: " .. fsm.get_state_name())
        imgui.text("Companion HP: " .. tostring(companion_hp) .. " / " .. tostring(config.companion_max_hp))
        
        if fsm.current_state == fsm.STATES.DOWNED then
            imgui.text_colored(string.format("BLEED OUT: %.1fs", fsm.bleed_out_remaining), 1.0, 0.2, 0.2, 1.0)
            if imgui.button("Debug Revive") then
                companion_hp = config.companion_max_hp
                fsm.set_state(fsm.STATES.FOLLOW)
            end
        end

        imgui.separator()
        if imgui.button("Open Tactical Wheel") then
            command_wheel.open()
        end
        imgui.same_line()
        if imgui.button("Run Automated Test Harness") then
            test_harness.run_all()
        end

        imgui.tree_pop()
    end
end)

log_msg("[DuoMode] Duo Mode hooks registered successfully.")
