--[[
    Resident Evil 2: Duo Mode
    audio_bridge.lua - Day 9: Audio Plugin Bridge & Engine Lifecycle Management
    Author: AryanTechie-007
]]

local config = require("duo_mode/config")

local audio_bridge = {}
audio_bridge.is_paused = false
audio_bridge.current_playing_file = nil
audio_bridge.last_played_time = 0.0

local function log_msg(msg)
    if config.log_verbose then
        if log and log.info then
            log.info("[DuoMode:Audio] " .. tostring(msg))
        end
        local f = io.open("reframework/data/duo_mode/test_log.txt", "a")
        if f then
            f:write(os.date("[%Y-%m-%d %H:%M:%S] [DuoMode:Audio] ") .. tostring(msg) .. "\n")
            f:close()
        end
    end
end

-- Attempt to play audio file via native C++ bridge (miniaudio_reframework.dll) or Windows PlaySound fallback
function audio_bridge.play_wav(filepath, volume, pan)
    if not filepath or filepath == "" then return false end
    volume = volume or 1.0
    pan = pan or 0.0

    audio_bridge.current_playing_file = filepath
    audio_bridge.last_played_time = os.clock()

    log_msg(string.format("Playing voice track: %s (Vol: %.2f, Pan: %.2f)", filepath, volume, pan))

    -- 1. Try C++ miniaudio_reframework plugin if loaded in REFramework
    local ok_native = false
    pcall(function()
        if miniaudio and miniaudio.play_wav then
            ok_native = miniaudio.play_wav(filepath, volume, pan)
        end
    end)

    -- 2. Fallback: Trigger native RE Engine Wwise sound event if named event matches
    if not ok_native then
        pcall(function()
            local wwise = sdk.get_native_singleton("via.wwise.Wwise")
            if wwise and wwise.call then
                wwise:call("postEvent", filepath)
            end
        end)
    end

    return true
end

-- Pause audio playback (e.g. pause menus, alt-tab focus loss)
function audio_bridge.pause_all()
    if audio_bridge.is_paused then return end
    audio_bridge.is_paused = true
    log_msg("Audio playback paused.")
    pcall(function()
        if miniaudio and miniaudio.pause_all_audio then
            miniaudio.pause_all_audio()
        end
    end)
end

-- Resume audio playback (e.g. returning to game, gaining focus)
function audio_bridge.resume_all()
    if not audio_bridge.is_paused then return end
    audio_bridge.is_paused = false
    log_msg("Audio playback resumed.")
    pcall(function()
        if miniaudio and miniaudio.resume_all_audio then
            miniaudio.resume_all_audio()
        end
    end)
end

-- Stop all audio immediately (e.g. death / game over screen)
function audio_bridge.stop_all()
    audio_bridge.current_playing_file = nil
    audio_bridge.is_paused = false
    log_msg("Audio playback stopped completely.")
    pcall(function()
        if miniaudio and miniaudio.stop_all_audio then
            miniaudio.stop_all_audio()
        end
    end)
end

-- Check engine lifecycle states (pause menu, focus lost, game over)
function audio_bridge.update_lifecycle()
    -- Check Game Over state
    local is_game_over = false
    pcall(function()
        local go_flow = sdk.get_managed_singleton("app.ropeway.gamemastering.GameOverFlow")
                     or sdk.get_managed_singleton("app.ropeway.GameOverManager")
        if go_flow and go_flow.call then
            is_game_over = go_flow:call("isGameOver") or false
        end
    end)

    if is_game_over then
        audio_bridge.stop_all()
        return
    end

    -- Check Pause State
    local is_game_paused = false
    pcall(function()
        local pause_man = sdk.get_managed_singleton("app.ropeway.gamemastering.PauseManager")
                       or sdk.get_managed_singleton("app.ropeway.PauseManager")
        if pause_man and pause_man.call then
            is_game_paused = pause_man:call("isPause") or false
        end
    end)

    if is_game_paused and not audio_bridge.is_paused then
        audio_bridge.pause_all()
    elseif not is_game_paused and audio_bridge.is_paused then
        audio_bridge.resume_all()
    end
end

return audio_bridge
