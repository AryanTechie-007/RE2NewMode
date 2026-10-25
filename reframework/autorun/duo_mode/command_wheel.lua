--[[
    Resident Evil 2: Duo Mode
    command_wheel.lua - ImGui-based tactical radial command wheel
]]

local config = require("duo_mode/config")
local fsm = require("duo_mode/fsm")

local command_wheel = {}
command_wheel.is_open = false

function command_wheel.draw()
    if not command_wheel.is_open then return end

    local viewport = imgui.get_main_viewport()
    local center = Vector2f.new(viewport.Size.x * 0.5, viewport.Size.y * 0.5)

    imgui.set_next_window_pos(center, 1, Vector2f.new(0.5, 0.5))
    imgui.set_next_window_size(Vector2f.new(320, 260), 1)

    if imgui.begin_window("Duo Command Menu", nil, 1 | 2 | 4 | 32) then -- NoTitleBar, NoResize, NoMove, AlwaysAutoResize
        imgui.text_colored("TACTICAL COMMANDS", 0.2, 0.8, 1.0, 1.0)
        imgui.separator()
        imgui.spacing()

        if imgui.button("  [1] FOLLOW ME  ", Vector2f.new(280, 40)) then
            fsm.set_state(fsm.STATES.FOLLOW)
            command_wheel.close()
        end

        if imgui.button("  [2] HOLD POSITION  ", Vector2f.new(280, 40)) then
            fsm.set_state(fsm.STATES.WAIT)
            command_wheel.close()
        end

        if imgui.button("  [3] COVER FIRE  ", Vector2f.new(280, 40)) then
            fsm.set_state(fsm.STATES.COVER)
            command_wheel.close()
        end

        imgui.spacing()
        imgui.separator()
        imgui.text_colored("Current State: " .. fsm.get_state_name(), 0.8, 0.8, 0.8, 1.0)
        imgui.end_window()
    end
end

function command_wheel.open()
    command_wheel.is_open = true
    local time_man = sdk.get_managed_singleton("app.ropeway.TimeManager")
    if time_man then
        time_man:call("setTimeScale", config.time_scale_slowdown)
    end
end

function command_wheel.close()
    command_wheel.is_open = false
    local time_man = sdk.get_managed_singleton("app.ropeway.TimeManager")
    if time_man then
        time_man:call("setTimeScale", 1.0)
    end
end

return command_wheel
