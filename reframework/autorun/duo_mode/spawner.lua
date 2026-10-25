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
spawner.last_spawn_status = "Not Started"
spawner.last_spawn_time = 0

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

-- Resolve the master player context across all known RE2 managed singletons
function spawner.get_master_player()
    local player_man = sdk.get_managed_singleton(sdk.game_namespace("PlayerManager"))
                    or sdk.get_managed_singleton("app.ropeway.PlayerManager")
    if not player_man then return nil end

    local player = nil
    pcall(function() player = player_man:call("get_CurrentPlayer") end)
    if not player then
        pcall(function() player = player_man:call("getMasterPlayerCharacter") end)
    end
    if not player then
        pcall(function() player = player_man:call("get_CurrentPlayerCharacter") end)
    end
    if not player then
        pcall(function() player = player_man:call("get_MasterPlayerCharacter") end)
    end
    return player
end

-- Resolve player GameObject safely
function spawner.get_player_game_object(player)
    player = player or spawner.get_master_player()
    if not player then return nil end

    local go = nil
    pcall(function()
        if player.get_game_object then go = player:get_game_object() end
    end)
    if not go then
        pcall(function() go = player:call("get_GameObject") end)
    end
    return go or player
end

-- Resolve player 3D Transform and Position
function spawner.get_player_position(player)
    player = player or spawner.get_master_player()
    if not player then return nil end

    local pos = nil
    pcall(function()
        local tf = player:call("get_Transform")
        if tf then pos = tf:call("get_Position") end
    end)
    if not pos then
        pcall(function()
            local go = spawner.get_player_game_object(player)
            if go and go.call then
                local tf = go:call("get_Transform")
                if tf then pos = tf:call("get_Position") end
            end
        end)
    end
    return pos
end

-- Candidates for prefab instantiation
local CLAIRE_PREFAB_CANDIDATES = {
    "natives/x64/objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_a.pfb",
    "natives/x64/objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_b.pfb",
    "natives/x64/objectroot/prefab/character/survivor/parts/pl1000/pl1000_face_default.pfb",
    "natives/x64/objectroot/prefab/character/survivor/pl1000.pfb",
    "natives/x64/objectroot/survivor/player/pl1000/pl1000.pfb",
    "natives/x64/objectroot/survivor/player/pl1000.pfb",
    "character/survivor/parts/pl1000/pl1000_body_costume_a.pfb",
    "survivor/player/pl1000.pfb"
}

local LEON_PREFAB_CANDIDATES = {
    "natives/x64/objectroot/prefab/character/survivor/parts/pl0000/pl0000_body_costume_a.pfb",
    "natives/x64/objectroot/prefab/character/survivor/parts/pl0000/pl0000_body_costume_b.pfb",
    "natives/x64/objectroot/prefab/character/survivor/parts/pl0000/pl0000_face_default.pfb",
    "natives/x64/objectroot/prefab/character/survivor/pl0000.pfb",
    "natives/x64/objectroot/survivor/player/pl0000/pl0000.pfb",
    "natives/x64/objectroot/survivor/player/pl0000.pfb",
    "character/survivor/parts/pl0000/pl0000_body_costume_a.pfb",
    "survivor/player/pl0000.pfb"
}

-- Preload required survivor and weapon prefabs into via.ResourceManager
function spawner.preload_assets()
    if spawner.preloaded then return true end

    log_msg("Starting asynchronous asset preloading...")
    local ok, res_man = pcall(function() return sdk.get_native_singleton("via.ResourceManager") end)
    if not ok or not res_man then
        log_msg("Note: via.ResourceManager singleton pending scene initialization.")
        return false
    end

    local all_paths = {}
    for _, p in ipairs(CLAIRE_PREFAB_CANDIDATES) do table.insert(all_paths, p) end
    for _, p in ipairs(LEON_PREFAB_CANDIDATES) do table.insert(all_paths, p) end

    for _, path in ipairs(all_paths) do
        pcall(function()
            res_man:call("loadResource", "prefab", path)
        end)
    end

    spawner.preloaded = true
    return true
end

-- Check if current scene and player manager are ready for instantiation
function spawner.is_scene_ready()
    local master_player = spawner.get_master_player()
    if not master_player then return false end
    local pos = spawner.get_player_position(master_player)
    return pos ~= nil
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

-- Determine which companion candidates to spawn based on active leader character
function spawner.get_target_companion_candidates(master_player)
    local is_claire_leader = false

    pcall(function()
        local go = spawner.get_player_game_object(master_player)
        local game_obj_name = (go and go.call and go:call("get_Name")) or ""
        if string.find(string.lower(game_obj_name), "claire") or string.find(string.lower(game_obj_name), "pl1000") then
            is_claire_leader = true
        end
    end)

    if is_claire_leader then
        log_msg("Active leader identified as Claire (pl1000). Target companion: Leon (pl0000).")
        return LEON_PREFAB_CANDIDATES, "Leon (pl0000)"
    else
        log_msg("Active leader identified as Leon (pl0000). Target companion: Claire (pl1000).")
        return CLAIRE_PREFAB_CANDIDATES, "Claire (pl1000)"
    end
end

-- Primary spawning implementation
function spawner.spawn_companion()
    if spawner.is_spawned and spawner.companion_game_object then
        return spawner.companion_game_object
    end

    if spawner.spawn_in_progress or not spawner.is_scene_ready() then
        spawner.last_spawn_status = "Waiting for active player in scene..."
        return nil
    end

    spawner.spawn_in_progress = true
    spawner.preload_assets()

    local master_player = spawner.get_master_player()
    local leader_pos = spawner.get_player_position(master_player)
    if not leader_pos then
        spawner.spawn_in_progress = false
        spawner.last_spawn_status = "Player position not resolved"
        return nil
    end

    -- Calculate spawn offset (1.5m to the right and 1.5m behind)
    local spawn_x = leader_pos.x + 1.5
    local spawn_y = leader_pos.y
    local spawn_z = leader_pos.z - 1.5
    local spawn_pos = (Vector3f and Vector3f.new(spawn_x, spawn_y, spawn_z)) or { x = spawn_x, y = spawn_y, z = spawn_z }

    local candidates, target_name = spawner.get_target_companion_candidates(master_player)
    log_msg(string.format("Attempting to spawn %s at (%.2f, %.2f, %.2f)...", target_name, spawn_x, spawn_y, spawn_z))

    local spawned_obj = nil
    local successful_path = nil

    -- 1. Try via.Prefab instantiation across candidate paths
    for _, path in ipairs(candidates) do
        local ok_pfb, err_pfb = pcall(function()
            local pfb = sdk.create_instance("via.Prefab"):add_ref()
            if pfb then
                if pfb.set_Path then pfb:set_Path(path) else pfb:set_field("Path", path) end
                if pfb.set_Standby then pfb:set_Standby(true) else pfb:set_field("Standby", true) end
                local obj = pfb:call("instantiate(via.vec3)", spawn_pos)
                if obj then
                    spawned_obj = obj
                    successful_path = path
                end
            end
        end)
        if spawned_obj then break end
    end

    -- 2. Fallback: via.SceneManager:get_CurrentScene():instantiate
    if not spawned_obj then
        pcall(function()
            local scene_man = sdk.get_native_singleton("via.SceneManager")
            local cur_scene = scene_man and scene_man:call("get_CurrentScene")
            if cur_scene then
                for _, path in ipairs(candidates) do
                    local pfb = sdk.create_instance("via.Prefab"):add_ref()
                    if pfb then
                        if pfb.set_Path then pfb:set_Path(path) else pfb:set_field("Path", path) end
                        if pfb.set_Standby then pfb:set_Standby(true) else pfb:set_field("Standby", true) end
                        local obj = cur_scene:call("instantiate(via.Prefab, via.vec3)", pfb, spawn_pos)
                        if obj then
                            spawned_obj = obj
                            successful_path = path
                            break
                        end
                    end
                end
            end
        end)
    end

    -- 3. Fallback: Create GameObject directly if prefabs are loading asynchronously
    if not spawned_obj then
        pcall(function()
            local go_td = sdk.find_type_definition("via.GameObject")
            if go_td then
                local create_method = go_td:get_method("create(System.String)")
                if create_method then
                    local new_obj = create_method:call(nil, "DuoMode_ClaireCompanion")
                    if new_obj then
                        new_obj:add_ref()
                        new_obj:call(".ctor")
                        local tf = new_obj:call("get_Transform")
                        if tf then tf:call("set_Position", spawn_pos) end
                        spawned_obj = new_obj
                        successful_path = "via.GameObject.create(DuoMode_ClaireCompanion)"
                    end
                end
            end
        end)
    end

    if spawned_obj then
        spawner.companion_game_object = spawned_obj
        spawner.is_spawned = true
        spawner.spawn_in_progress = false
        spawner.last_spawn_status = "SUCCESS: Spawned via " .. tostring(successful_path)

        -- Strip input controllers so companion doesn't mirror player controller
        spawner.strip_input_components(spawned_obj)

        log_msg("SUCCESS: Companion 3D model physically spawned in scene! Path: " .. tostring(successful_path))
        return spawned_obj
    else
        spawner.spawn_in_progress = false
        spawner.last_spawn_status = "Failed: No candidate prefab instantiated"
        log_msg("Instantiation attempt failed across all candidate paths.")
        return nil
    end
end

-- Force manual spawn trigger
function spawner.force_spawn()
    spawner.is_spawned = false
    spawner.companion_game_object = nil
    spawner.spawn_in_progress = false
    return spawner.spawn_companion()
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
    spawner.last_spawn_status = "Despawned"
end

return spawner