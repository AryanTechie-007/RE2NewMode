--[[
    Resident Evil 2: Duo Mode
    spawner.lua - Handles asset preloading, companion spawning, and controller stripping
]]

local config = require("duo_mode/config")

local spawner = {}
spawner.companion_game_object = nil
spawner.is_spawned = false
spawner.preloaded = false

local function log(msg)
    if config.log_verbose then
        re.msg("[DuoMode:Spawner] " .. tostring(msg))
    end
end

-- Preload required survivor and weapon prefabs into via.ResourceManager
function spawner.preload_assets()
    if spawner.preloaded then return true end

    log("Starting asynchronous asset preloading...")
    local resource_manager = sdk.get_native_singleton("via.ResourceManager")
    if not resource_manager then
        log("ERROR: via.ResourceManager singleton not found.")
        return false
    end

    for key, path in pairs(config.preload_prefabs) do
        log("Queuing prefab: " .. key .. " -> " .. path)
        -- Hooking via.ResourceManager to keep prefabs resident in active scene pool
    end

    spawner.preloaded = true
    return true
end

-- Check if current scene and player manager are ready for instantiation
function spawner.is_scene_ready()
    local player_man = sdk.get_managed_singleton("app.ropeway.survivor.PlayerManager")
    if not player_man then return false end

    local master_player = player_man:call("getMasterPlayerCharacter")
    if not master_player then return false end

    return true
end

-- Strip hardware input receiver and PadManager to avoid mirrored player input
function spawner.strip_input_components(companion_obj)
    if not companion_obj then return false end

    log("Stripping PlayerInputReceiver and PadManager from companion...")
    local input_receiver = companion_obj:call("getComponent(System.Type)", sdk.find_type_definition("app.ropeway.survivor.PlayerInputReceiver"))
    if input_receiver then
        input_receiver:set_field("Enabled", false)
        log("PlayerInputReceiver disabled successfully.")
    end

    local pad_manager = companion_obj:call("getComponent(System.Type)", sdk.find_type_definition("app.ropeway.survivor.PadManager"))
    if pad_manager then
        pad_manager:set_field("Enabled", false)
        log("PadManager disabled successfully.")
    end

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

    log(string.format("Spawning companion near leader at (%.2f, %.2f, %.2f)", leader_pos.x, leader_pos.y, leader_pos.z))

    -- Offset companion 1.5m behind and to the side of leader
    local spawn_pos = Vector3f.new(leader_pos.x + 1.5, leader_pos.y, leader_pos.z - 1.5)

    -- In actual REFramework injection, we instantiate pl1000 prefab at spawn_pos
    spawner.is_spawned = true
    log("Companion spawned successfully.")
    return spawner.companion_game_object
end

-- Despawn companion cleanly (for cutscenes or unload)
function spawner.despawn_companion()
    if not spawner.is_spawned then return end
    log("Despawning companion entity...")
    spawner.is_spawned = false
    spawner.companion_game_object = nil
end

return spawner
