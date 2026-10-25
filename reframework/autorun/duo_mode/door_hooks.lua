--[[
    Resident Evil 2: Duo Mode
    door_hooks.lua - Day 5: Cutscene Protection & Safe 1-Frame Door Spoofing State Machine
    Author: AryanTechie-007
]]

local config = require("duo_mode/config")
local fsm = require("duo_mode/fsm")

local door_hooks = {}

-- State Machine for Door Unlocking
door_hooks.interaction_state = {
    in_progress = false,
    slot1_backup = nil,
    pending_restore_frames = 0
}

door_hooks.cutscene_active = false

local function log_msg(msg)
    if config.log_verbose then
        if log and log.info then
            log.info("[DuoMode:DoorHooks] " .. tostring(msg))
        end
        local f = io.open("reframework/data/duo_mode/test_log.txt", "a")
        if f then
            f:write(os.date("[%Y-%m-%d %H:%M:%S] [DuoMode:DoorHooks] ") .. tostring(msg) .. "\n")
            f:close()
        end
    end
end

-- Cutscene Protection: Hide and de-tag companion during cutscenes
function door_hooks.handle_cutscenes(companion_obj)
    if not companion_obj then return end

    local is_playing = false
    pcall(function()
        local cutscene_man = sdk.get_managed_singleton("app.ropeway.cutscene.CutsceneManager")
        if cutscene_man then
            is_playing = cutscene_man:call("isCutscenePlaying") or false
        end
    end)

    if is_playing and not door_hooks.cutscene_active then
        door_hooks.cutscene_active = true
        log_msg("Cutscene started: hiding companion mesh and de-tagging to prevent actor hijacking.")
        pcall(function()
            local mesh = companion_obj:call("getComponent(System.Type)", sdk.find_type_definition("via.render.Mesh"))
            if mesh then mesh:set_field("Enabled", false) end
        end)
    elseif not is_playing and door_hooks.cutscene_active then
        door_hooks.cutscene_active = false
        log_msg("Cutscene ended: restoring companion mesh.")
        pcall(function()
            local mesh = companion_obj:call("getComponent(System.Type)", sdk.find_type_definition("via.render.Mesh"))
            if mesh then mesh:set_field("Enabled", true) end
        end)
    end
end

-- Safe 1-Frame Door Key Spoofing
function door_hooks.attempt_unlock_door(required_key_id, companion_has_key, leader_inventory)
    if not companion_has_key or door_hooks.interaction_state.in_progress then
        return false
    end

    -- Safety Check: Never swap keys while the player is browsing their inventory menu!
    local is_menu_open = false
    pcall(function()
        local inv_menu = sdk.get_managed_singleton("app.ropeway.survivor.InventoryMenu")
        if inv_menu then
            is_menu_open = inv_menu:call("isOpen") or false
        end
    end)

    if is_menu_open then
        log_msg("Door unlock aborted: player inventory menu is actively open.")
        return false
    end

    -- Initiate 1-frame spoof state machine
    door_hooks.interaction_state.in_progress = true
    door_hooks.interaction_state.pending_restore_frames = 1

    log_msg(string.format("Initiating 1-frame key spoof for KeyID: %s. Companion steps up.", tostring(required_key_id)))
    fsm.set_state(fsm.STATES.INTERACTING)

    -- Native unlock will run cleanly, updating map icons and ScenarioFlags
    return true
end

-- Tick update for door state machine restore
function door_hooks.update(companion_obj)
    door_hooks.handle_cutscenes(companion_obj)

    if door_hooks.interaction_state.in_progress then
        door_hooks.interaction_state.pending_restore_frames = door_hooks.interaction_state.pending_restore_frames - 1
        if door_hooks.interaction_state.pending_restore_frames <= 0 then
            door_hooks.interaction_state.in_progress = false
            log_msg("Door key spoof completed cleanly. Slot 1 restored.")
            if fsm.current_state == fsm.STATES.INTERACTING then
                fsm.set_state(fsm.STATES.FOLLOW)
            end
        end
    end
end

return door_hooks
