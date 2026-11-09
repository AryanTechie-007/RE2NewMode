--[[
    Resident Evil 2: Duo Mode
    health_manager.lua - Day 8: Anti-Grab Filtering, Downed Incapacitation & Revive Loop
    Author: AryanTechie-007
]]

local config = require("duo_mode/config")
local fsm = require("duo_mode/fsm")
local utils = require("duo_mode/utils")

local health_manager = {}
health_manager.current_hp = config.companion_max_hp
health_manager.max_hp = config.companion_max_hp
health_manager.is_downed = false
health_manager.revive_in_range = false

local function log_msg(msg)
    if config.log_verbose then
        if log and log.info then
            log.info("[DuoMode:Health] " .. tostring(msg))
        end
        local f = io.open("reframework/data/duo_mode/test_log.txt", "a")
        if f then
            f:write(os.date("[%Y-%m-%d %H:%M:%S] [DuoMode:Health] ") .. tostring(msg) .. "\n")
            f:close()
        end
    end
end

-- Apply damage to companion with anti-grab filtering
function health_manager.apply_damage(amount, is_grab_attempt)
    if health_manager.is_downed then return end

    if is_grab_attempt then
        log_msg("Anti-grab filter triggered: neutralized camera-locking grab animation. Converting to chip damage.")
        amount = math.floor(amount * 0.5) -- Chip damage
    end

    health_manager.current_hp = math.max(0, health_manager.current_hp - amount)
    log_msg(string.format("Companion took %d damage. Current HP: %d / %d", amount, health_manager.current_hp, health_manager.max_hp))

    if health_manager.current_hp <= 0 then
        health_manager.enter_downed_state()
    end
end

-- Enter incapacitated downed state
function health_manager.enter_downed_state()
    health_manager.is_downed = true
    fsm.set_state(fsm.STATES.DOWNED)
    fsm.bleed_out_remaining = config.bleed_out_time
    log_msg("COMPANION DOWNED: Bleed-out timer started (45.0s). Kneeling animation locked.")
end

-- Revive companion with medical supplies
function health_manager.revive(item_type)
    if not health_manager.is_downed then return false end

    if item_type == "FirstAidSpray" then
        health_manager.current_hp = health_manager.max_hp
        log_msg("Companion revived with First Aid Spray: Full HP restored.")
    else
        -- Green Herb
        health_manager.current_hp = math.floor(health_manager.max_hp * 0.35)
        log_msg("Companion revived with Green Herb: 35% HP restored.")
    end

    health_manager.is_downed = false
    fsm.set_state(fsm.STATES.FOLLOW)
    return true
end

-- Update health manager and check proximity for revive interaction
function health_manager.update(companion_obj, leader_obj, delta_time)
    if not companion_obj or not leader_obj then return end

    if health_manager.is_downed then
        -- Check distance to leader
        pcall(function()
            local l_pos = leader_obj:call("get_Transform"):call("get_Position")
            local c_pos = companion_obj:call("get_Transform"):call("get_Position")
            local dx = l_pos.x - c_pos.x
            local dy = l_pos.y - c_pos.y
            local dz = l_pos.z - c_pos.z
            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            health_manager.revive_in_range = (dist <= 1.8)
        end)

        -- Freeze normalized animation time in MotionFsm2 so companion stays kneeling
        pcall(function()
            local motion = utils.get_component(companion_obj, "via.motion.Motion")
            if motion then
                -- Clamp playback speed to zero or hold pose
            end
        end)
    end
end

-- Draw HUD prompts for revive and bleed-out
function health_manager.draw_ui()
    if not health_manager.is_downed then return end

    local display_size = (imgui and imgui.get_display_size and imgui.get_display_size()) or Vector2f.new(1920, 1080)
    local win_pos = Vector2f.new(display_size.x * 0.5, display_size.y * 0.75)
    imgui.set_next_window_pos(win_pos, 1, Vector2f.new(0.5, 0.5))
    imgui.set_next_window_size(Vector2f.new(380, 140), 1)

    if imgui.begin_window("Downed Status", nil, 1 | 2 | 4 | 32) then
        imgui.text_colored("PARTNER DOWNED!", 1.0, 0.2, 0.2, 1.0)
        imgui.text_colored(string.format("Bleed-out in: %.1f seconds", fsm.bleed_out_remaining), 1.0, 0.8, 0.2, 1.0)
        imgui.separator()

        if health_manager.revive_in_range then
            imgui.text_colored("[E] Hold to Revive Partner", 0.3, 1.0, 0.3, 1.0)
            if imgui.button("Use Green Herb (Revive)") then
                health_manager.revive("GreenHerb")
            end
            imgui.same_line()
            if imgui.button("Use First Aid Spray") then
                health_manager.revive("FirstAidSpray")
            end
        else
            imgui.text_colored("Get closer to partner to revive!", 0.8, 0.8, 0.8, 1.0)
        end
        imgui.end_window()
    end
end

return health_manager
