--[[
    Resident Evil 2: Duo Mode
    command_wheel.lua - Day 4: Tactical Command Wheel with Gamepad & Mouse Triggers
    Author: AryanTechie-007
]]

local config = require("duo_mode/config")
local fsm = require("duo_mode/fsm")

local command_wheel = {}
command_wheel.is_open = false
command_wheel.selected_index = 1

local options = {
    { id = fsm.STATES.FOLLOW, label = "FOLLOW ME", desc = "Companion follows at standard tether" },
    { id = fsm.STATES.WAIT,   label = "HOLD POSITION", desc = "Companion anchors here in low profile" },
    { id = fsm.STATES.COVER,  label = "COVER FIRE", desc = "Companion holds tight (1.5m) and engages threats" }
}

function command_wheel.draw()
    if not command_wheel.is_open then return end

    local display_size = (imgui and imgui.get_display_size and imgui.get_display_size()) or Vector2f.new(1920, 1080)
    local center = Vector2f.new(display_size.x * 0.5, display_size.y * 0.5)

    imgui.set_next_window_pos(center, 1, Vector2f.new(0.5, 0.5))
    imgui.set_next_window_size(Vector2f.new(340, 290), 1)

    if imgui.begin_window("Tactical Orders", nil, 1 | 2 | 4 | 32) then -- NoTitleBar, NoResize, NoMove, AutoResize
        imgui.text_colored("TACTICAL COMMAND WHEEL", 0.3, 0.85, 1.0, 1.0)
        imgui.separator()
        imgui.spacing()

        for idx, opt in ipairs(options) do
            local is_active = (fsm.current_state == opt.id)
            if is_active then
                imgui.text_colored("-> [ACTIVE] " .. opt.label, 0.2, 1.0, 0.3, 1.0)
            else
                imgui.text_colored("   " .. opt.label, 0.8, 0.8, 0.8, 1.0)
            end

            if imgui.button(string.format("Select [%d]: %s", idx, opt.label), Vector2f.new(300, 34)) then
                fsm.set_state(opt.id)
                command_wheel.close()
            end
            imgui.spacing()
        end

        imgui.separator()
        imgui.text_colored("Hold Middle Mouse / RB to keep open", 0.6, 0.6, 0.6, 1.0)
        imgui.end_window()
    end
end

function command_wheel.open()
    if command_wheel.is_open then return end
    command_wheel.is_open = true
    pcall(function()
        local time_man = sdk.get_managed_singleton("app.ropeway.TimeManager")
        if time_man then
            time_man:call("setTimeScale", config.time_scale_slowdown)
        end
    end)
end

function command_wheel.close()
    if not command_wheel.is_open then return end
    command_wheel.is_open = false
    pcall(function()
        local time_man = sdk.get_managed_singleton("app.ropeway.TimeManager")
        if time_man then
            time_man:call("setTimeScale", 1.0)
        end
    end)
end

-- Detect hardware trigger button state every frame
function command_wheel.update_input()
    -- Check if middle mouse button or hotkey is held
    local is_key_down = false
    pcall(function()
        if reframework and reframework.is_key_down then
            is_key_down = reframework.is_key_down(config.command_wheel_key)
        end
    end)

    if is_key_down and not command_wheel.is_open then
        command_wheel.open()
    elseif not is_key_down and command_wheel.is_open then
        command_wheel.close()
    end
end

return command_wheel
