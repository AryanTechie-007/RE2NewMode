--[[
    Resident Evil 2: Duo Mode
    fsm.lua - Companion Finite State Machine
]]

local config = require("duo_mode/config")

local fsm = {}

-- State Enumeration
fsm.STATES = {
    FOLLOW       = 1, -- Active NavMesh tracking behind leader
    WAIT         = 2, -- Hold position, low-profile scan
    COVER        = 3, -- Close tether, weapon drawn, cover fire
    DOWNED       = 4, -- Incapacitated, bleed-out timer running
    INTERACTING  = 5  -- Stepping up to unlock a door or pick up loot
}

fsm.current_state = fsm.STATES.FOLLOW
fsm.bleed_out_remaining = config.bleed_out_time

function fsm.set_state(new_state)
    if fsm.current_state == new_state then return end
    fsm.current_state = new_state
end

function fsm.get_state_name()
    for name, val in pairs(fsm.STATES) do
        if val == fsm.current_state then return name end
    end
    return "UNKNOWN"
end

function fsm.update(delta_time, companion_hp)
    -- Check for downed state
    if companion_hp <= 0 and fsm.current_state ~= fsm.STATES.DOWNED then
        fsm.set_state(fsm.STATES.DOWNED)
        fsm.bleed_out_remaining = config.bleed_out_time
    end

    if fsm.current_state == fsm.STATES.DOWNED then
        fsm.bleed_out_remaining = fsm.bleed_out_remaining - delta_time
        if fsm.bleed_out_remaining <= 0 then
            return "GAME_OVER"
        end
    end

    return fsm.current_state
end

return fsm
