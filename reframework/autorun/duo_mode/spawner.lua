--[[
    Resident Evil 2: Duo Mode
    spawner.lua - Day 1: Physical 3D Model Instantiation & Input Stripping
    Author: AryanTechie-007
]]

local config = require("duo_mode/config")

local spawner = {}
spawner.companion_game_object = nil
spawner.is_spawned = false
spawner.preloaded = false
spawner.spawn_in_progress = false

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
        pcall(function()
            log_msg("Preloading prefab resource: " .. key .. " -> " .. path)
            res_man:call("loadResource", "prefab", path)
        end)
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

-- Determine which companion prefab to spawn based on active leader character
function spawner.get_target_companion_prefab(master_player)
    local target_path = config.preload_prefabs.claire_body -- Default: Claire

    pcall(function()
        local game_obj_name = master_player:call("get_Name") or ""
        -- If player is pl1000 (Claire), spawn pl0000 (Leon)
        if string.find(string.lower(game_obj_name), "claire") or string.find(string.lower(game_obj_name), "pl1000") then
            target_path = config.preload_prefabs.leon_body
            log_msg("Active leader identified as Claire. Target companion: Leon (pl0000).")
        else
            log_msg("Active leader identified as Leon. Target companion: Claire (pl1000).")
        end
    end)

    return target_path
end

-- Spawn companion 3D entity next to the active leader
function spawner.spawn_companion()
    if spawner.is_spawned and spawner.companion_game_object then
        return spawner.companion_game_object
    end

    if spawner.spawn_in_progress or not spawner.is_scene_ready() then
        return nil
    end

    spawner.spawn_in_progress = true
    spawner.preload_assets()

    local player_man = sdk.get_managed_singleton("app.ropeway.survivor.PlayerManager")
    local master_player = player_man:call("getMasterPlayerCharacter")
    local leader_transform = master_player:call("get_Transform")
    local leader_pos = leader_transform:call("get_Position")

    -- Calculate spawn offset (1.5m to the right and 1.5m behind)
    local spawn_x = leader_pos.x + 1.5
    local spawn_y = leader_pos.y
    local spawn_z = leader_pos.z - 1.5
    local spawn_pos = Vector3f and Vector3f.new(spawn_x, spawn_y, spawn_z) or { x = spawn_x, y = spawn_y, z = spawn_z }

    local target_prefab_path = spawner.get_target_companion_prefab(master_player)
    log_msg(string.format("Instantiating 3D prefab '%s' at (%.2f, %.2f, %.2f)...", target_prefab_path, spawn_x, spawn_y, spawn_z))

    local spawned_obj = nil

    -- Primary RE Engine Instantiation: via.Prefab:instantiate
    local ok_inst, err_inst = pcall(function()
        local prefab = sdk.create_instance("via.Prefab"):add_ref()
        if prefab then
            prefab:set_field("Path", target_prefab_path)
            spawned_obj = prefab:call("instantiate(via.vec3)", spawn_pos)
        end
    end)

    -- Fallback Instantiation: via.SceneManager:instantiate
    if not spawned_obj then
        pcall(function()
            local scene_man = sdk.get_native_singleton("via.SceneManager")
            if scene_man then
                local current_scene = scene_man:call("get_CurrentScene")
                if current_scene then
                    local prefab = sdk.create_instance("via.Prefab"):add_ref()
                    prefab:set_field("Path", target_prefab_path)
                    spawned_obj = current_scene:call("instantiate(via.Prefab, via.vec3)", prefab, spawn_pos)
                end
            end
        end)
    end

    if spawned_obj then
        spawner.companion_game_object = spawned_obj
        spawner.is_spawned = true
        spawner.spawn_in_progress = false

        -- Strip input controllers so companion doesn't mirror player controller
        spawner.strip_input_components(spawned_obj)

        log_msg("SUCCESS: Companion 3D model physically spawned in scene!")
        return spawned_obj
    else
        spawner.spawn_in_progress = false
        log_msg("Instantiate attempt queued; awaiting next active scene frame.")
        return nil
    end
end

-- Despawn companion cleanly (for cutscenes or unload)
function spawner.despawn_companion()
    if not spawner.is_spawned then return end
    log_msg("Despawning companion entity...")
    if spawner.companion_game_object then
        pcall(function()
            spawner.companion_game_object:call("destroy")
        end)
    end
    spawner.is_spawned = false
    spawner.companion_game_object = nil
end

return spawner
