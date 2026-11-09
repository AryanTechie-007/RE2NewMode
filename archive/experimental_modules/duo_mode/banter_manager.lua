--[[
    Resident Evil 2: Duo Mode
    banter_manager.lua - Day 10: Dynamic Banter Engine & Situational Voice Triggers
    Author: AryanTechie-007
]]

local config = require("duo_mode/config")
local audio_bridge = require("duo_mode/audio_bridge")

local banter_manager = {}

banter_manager.PRIORITY = {
    CRITICAL = 1, -- Bleed-out, Revive, Game Over
    COMBAT   = 2, -- Ammo out, Zombie grab, Licker stealth
    EVENT    = 3, -- Door key spoof, Item transfer
    IDLE     = 4  -- Safe room banter, corridor dialogue
}

banter_manager.voice_queue = {}
banter_manager.current_line = nil
banter_manager.last_line_time = 0.0
banter_manager.line_cooldown = 4.0
banter_manager.safe_room_timer = 0.0
banter_manager.danger_voiced = false
banter_manager.safe_room_voiced = false

local function log_msg(msg)
    if config.log_verbose then
        if log and log.info then
            log.info("[DuoMode:Banter] " .. tostring(msg))
        end
        local f = io.open("reframework/data/duo_mode/test_log.txt", "a")
        if f then
            f:write(os.date("[%Y-%m-%d %H:%M:%S] [DuoMode:Banter] ") .. tostring(msg) .. "\n")
            f:close()
        end
    end
end

-- Queue a voice line with a specific priority and subtitles
function banter_manager.queue_line(line_id, priority, audio_path, subtitle_text)
    priority = priority or banter_manager.PRIORITY.IDLE
    table.insert(banter_manager.voice_queue, {
        id = line_id,
        priority = priority,
        audio_path = audio_path,
        text = subtitle_text,
        timestamp = os.clock()
    })

    -- Sort queue by priority ascending (1 is highest priority)
    table.sort(banter_manager.voice_queue, function(a, b)
        return a.priority < b.priority
    end)

    log_msg(string.format("Queued voice line: [%s] '%s' (Priority: %d)", line_id, subtitle_text or "", priority))
end

-- Play next eligible voice line from queue if cooldown expired
function banter_manager.update_queue(current_time)
    if #banter_manager.voice_queue == 0 then return end

    local next_item = banter_manager.voice_queue[1]
    local is_critical = (next_item.priority == banter_manager.PRIORITY.CRITICAL)

    if is_critical or (current_time - banter_manager.last_line_time >= banter_manager.line_cooldown) then
        table.remove(banter_manager.voice_queue, 1)
        banter_manager.current_line = next_item
        banter_manager.last_line_time = current_time

        log_msg(string.format("Playing dialogue: '%s' (%s)", next_item.text or "", next_item.audio_path or "NoAudio"))
        if next_item.audio_path then
            audio_bridge.play_wav(next_item.audio_path, 1.0, 0.0)
        end
    end
end

-- Trigger: Safe Room Banter (Whisper dialogue after 5 seconds in safe room)
function banter_manager.on_safe_room_tick(delta_time, is_in_safe_room)
    if not is_in_safe_room then
        banter_manager.safe_room_timer = 0.0
        banter_manager.safe_room_voiced = false
        return
    end

    banter_manager.safe_room_timer = banter_manager.safe_room_timer + delta_time
    if banter_manager.safe_room_timer >= 5.0 and not banter_manager.safe_room_voiced then
        banter_manager.safe_room_voiced = true
        banter_manager.queue_line(
            "safe_room_rest_01",
            banter_manager.PRIORITY.IDLE,
            "reframework/data/duo_mode/audio/claire_saferoom_01.wav",
            "Claire: 'Looks like we have a minute to breathe... How are you holding up, Leon?'"
        )
    end
end

-- Trigger: Low HP Warning (< 30% health)
function banter_manager.on_health_check(comp_hp, max_hp)
    local hp_ratio = comp_hp / (max_hp > 0 and max_hp or 1000)
    if hp_ratio <= 0.35 and not banter_manager.danger_voiced then
        banter_manager.danger_voiced = true
        banter_manager.queue_line(
            "danger_hp_warning",
            banter_manager.PRIORITY.COMBAT,
            "reframework/data/duo_mode/audio/claire_danger_01.wav",
            "Claire: 'I'm hit bad! Need to find a herb soon...'"
        )
    elseif hp_ratio > 0.5 then
        banter_manager.danger_voiced = false
    end
end

-- Trigger: Companion Out of Ammo Callout
function banter_manager.on_ammo_depleted()
    banter_manager.queue_line(
        "ammo_depleted_callout",
        banter_manager.PRIORITY.COMBAT,
        "reframework/data/duo_mode/audio/claire_ammo_out_01.wav",
        "Claire: 'I'm out! Leon, I'm out! Falling back!'"
    )
end

-- Trigger: Successful Revive Banter
function banter_manager.on_revived(item_used)
    banter_manager.queue_line(
        "companion_revived",
        banter_manager.PRIORITY.CRITICAL,
        "reframework/data/duo_mode/audio/claire_revived_01.wav",
        "Claire: 'Thanks... That was too close. Let's keep moving.'"
    )
end

-- Trigger: Door Unlock Banter
function banter_manager.on_door_unlock(key_name)
    banter_manager.queue_line(
        "door_unlock_stepup",
        banter_manager.PRIORITY.EVENT,
        "reframework/data/duo_mode/audio/claire_door_unlock_01.wav",
        string.format("Claire: 'I have the key for this one. Hold on.'")
    )
end

-- Master update loop for banter engine
function banter_manager.update(current_time, delta_time, comp_hp, max_hp, is_safe_room)
    banter_manager.update_queue(current_time)
    banter_manager.on_safe_room_tick(delta_time, is_safe_room)
    banter_manager.on_health_check(comp_hp, max_hp)
end

-- Draw active subtitle on screen
function banter_manager.draw_subtitles()
    if not banter_manager.current_line then return end

    local current_time = os.clock()
    if current_time - banter_manager.last_line_time > 4.5 then
        banter_manager.current_line = nil
        return
    end

    local display_size = (imgui and imgui.get_display_size and imgui.get_display_size()) or Vector2f.new(1920, 1080)
    local win_pos = Vector2f.new(display_size.x * 0.5, display_size.y * 0.88)

    imgui.set_next_window_pos(win_pos, 1, Vector2f.new(0.5, 0.5))
    imgui.set_next_window_size(Vector2f.new(display_size.x * 0.7, 50), 1)

    if imgui.begin_window("Subtitles", nil, 1 | 2 | 4 | 32) then
        imgui.text_colored(banter_manager.current_line.text or "", 1.0, 1.0, 0.4, 1.0)
        imgui.end_window()
    end
end

return banter_manager
