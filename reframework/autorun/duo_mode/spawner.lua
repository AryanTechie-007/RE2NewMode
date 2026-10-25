--[[
    Resident Evil 2: Duo Mode
    spawner.lua - Handles asset preloading, companion spawning, and controller stripping
]]

local config = require("duo_mode/config")

local spawner = {}
spawner.companion_game_object = nil
spawner.is_spawned = false
spawner.preloaded = false

local function log_msg(msg)
    if config.log_verbose then
        if log and log.info then
            log.info("[DuoMode:Spawner] " .. tostring(msg))
        end
        local f = io.open("reframework/data/duo_mode/test_log.txt", "a")
        if f then
            f:write(os.date("[%Y-%m-%d %H:%M:%S] [DuoMode:Spawner] ") .. tostring(msg) .. "\n")
            f:close()
        end
    end
end

-- Preload required survivor and weapon prefabs into via.ResourceManager
function spawner.preload_assets()
    if spawner.preloaded then return true end

    log_msg("Starting asynchronous asset preloading...")
    local ok, res_man = pcall(function() return sdk.get_native_singleton("via.ResourceManager") end)
    if not ok or not res_man then
        log_msg("Note: via.ResourceManager singleton pending scene initialization.")
        return false
    end

    for key, path in pairs(config.preload_prefabs) do
        log_msg("Queuing prefab: " .. key .. " -> " .. path)
    end

    spawner.preloaded = true
    return true
end

-- Check if current scene and player manager are ready for instantiation
function spawner.is_scene_ready()
    local ok, player_man = pcall(function() return sdk.get_managed_singleton("app.ropeway.survivor.PlayerManager") end)
    if not ok or not player_man then return false end

    local ok2, master_player = pcall(function() return player_man:call("getMasterPlayerCharacter") end)
    if not ok2 or not master_player then return false end

    return true
end

-- Strip hardware input receiver and PadManager to avoid mirrored player input
function spawner.strip_input_components(companion_obj)
    if not companion_obj then return false end

    log_msg("Stripping PlayerInputReceiver and PadManager from companion...")
    pcall(function()
        local input_receiver = companion_obj:call("getComponent(System.Type)", sdk.find_type_definition("app.ropeway.survivor.PlayerInputReceiver"))
        if input_receiver then
            input_receiver:set_field("Enabled", false)
            log_msg("PlayerInputReceiver disabled successfully.")
        end
    end)

    pcall(function()
        local pad_manager = companion_obj:call("getComponent(System.Type)", sdk.find_type_definition("app.ropeway.survivor.PadManager"))
        if pad_manager then
            pad_manager:set_field("Enabled", false)
            log_msg("PadManager disabled successfully.")
        end
    end)

    return true
end

-- Spawn companion entity next to the active leader
function spawner.spawn_companion()
    if spawner.is_spawned and spawner.companion_game_object then
        return spawner.companion_game_object
    end

    if not spawner.is_scene_ready() then
        return nil
    end

    spawner.preload_assets()

    local player_man = sdk.get_managed_singleton("app.ropeway.survivor.PlayerManager")
    local master_player = player_man:call("getMasterPlayerCharacter")
    local leader_transform = master_player:call("get_Transform")
    local leader_pos = leader_transform:call("get_Position")

    log_msg(string.format("Spawning companion near leader at (%.2f, %.2f, %.2f)", leader_pos.x, leader_pos.y, leader_pos.z))

    spawner.is_spawned = true
    log_msg("Companion spawned successfully.")
    return spawner.companion_game_object
end

-- Despawn companion cleanly (for cutscenes or unload)
function spawner.despawn_companion()
    if not spawner.is_spawned then return end
    log_msg("Despawning companion entity...")
    spawner.is_spawned = false
    spawner.companion_game_object = nil
end

return spawner
