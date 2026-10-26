--[[
    Resident Evil 2: Duo Mode
    spawner.lua - Day 1: Physical 3D Model Instantiation & Native Survivor Casting Pipeline
    Author: AryanTechie-007
]]

local config = require("duo_mode/config")
local utils = require("duo_mode/utils")

local spawner = {}
spawner.companion_game_object = nil
spawner.child_objects = {}
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
    local player_man = sdk.get_managed_singleton("app.ropeway.PlayerManager")
                    or sdk.get_managed_singleton(sdk.game_namespace("PlayerManager"))
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

-- Strip hardware input receiver and PadManager to avoid mirrored player input
function spawner.strip_input_components(companion_obj)
    if not companion_obj then return false end

    log_msg("Stripping PlayerInputReceiver and PadManager from companion...")
    local input_types = {
        "app.ropeway.survivor.PlayerInputReceiver",
        "app.ropeway.PlayerInputReceiver",
        "app.ropeway.survivor.PadManager",
        "app.ropeway.PadManager",
        "app.ropeway.player.PlayerInputReceiver",
        "via.hid.GamePad"
    }

    for _, t in ipairs(input_types) do
        pcall(function()
            local comp = utils.get_component(companion_obj, t)
            if comp then
                if comp.set_field then pcall(function() comp:set_field("Enabled", false) end) end
                if comp.call then pcall(function() comp:call("set_Enabled", false) end) end
                log_msg("Disabled input component: " .. t)
            end
        end)
    end

    return true
end

-- Check if current scene and player manager are ready for instantiation
function spawner.is_scene_ready()
    local master_player = spawner.get_master_player()
    if not master_player then return false end
    local pos = spawner.get_player_position(master_player)
    return pos ~= nil
end

-- Diagnostic tool to dump all methods, fields, and parameters of RE Engine's Survivor subsystems
function spawner.inspect_survivor_system()
    log_msg("=================== SURVIVOR ENGINE INSPECTION ===================")
    local types_to_inspect = {
        "app.ropeway.SurvivorAssignManager",
        "app.ropeway.SurvivorAssignManager.CastingOrder",
        "app.ropeway.SurvivorAssignManager.CastingOrderNpc",
        "app.ropeway.SurvivorAssignManager.CastingOrderActor",
        "app.ropeway.SurvivorAssignManager.CastingOrderPlayer",
        "app.ropeway.SurvivorStandbyCatalog",
        "app.ropeway.SurvivorManager",
        "app.ropeway.PlayerManager"
    }

    for _, tname in ipairs(types_to_inspect) do
        local td = sdk.find_type_definition(tname)
        if td then
            log_msg(string.format("[TYPE] %s", tname))
            local methods = td:get_methods()
            if methods then
                for _, m in ipairs(methods) do
                    local mname = m:get_name()
                    local nparams = m:get_num_params()
                    log_msg(string.format("   [Method] %s (%d params)", mname, nparams))
                end
            end
            local fields = td:get_fields()
            if fields then
                for _, f in ipairs(fields) do
                    log_msg(string.format("   [Field] %s", f:get_name()))
                end
            end
        else
            log_msg("[TYPE] NOT FOUND: " .. tname)
        end
    end

    local sam = sdk.get_managed_singleton("app.ropeway.SurvivorAssignManager")
    log_msg("SurvivorAssignManager Singleton: " .. (sam and "PRESENT" or "NIL"))

    local sm = sdk.get_managed_singleton("app.ropeway.SurvivorManager")
    log_msg("SurvivorManager Singleton: " .. (sm and "PRESENT" or "NIL"))

    local pm = sdk.get_managed_singleton("app.ropeway.PlayerManager")
    log_msg("PlayerManager Singleton: " .. (pm and "PRESENT" or "NIL"))
    log_msg("==================================================================")
end

-- Primary Recommended Spawner: Native Survivor Casting via app.ropeway.SurvivorAssignManager
function spawner.spawn_by_native_casting(master_player, spawn_pos)
    log_msg("Attempting native survivor casting via SurvivorAssignManager...")
    local sam = sdk.get_managed_singleton("app.ropeway.SurvivorAssignManager")
    if not sam then
        log_msg("Native casting failed: SurvivorAssignManager singleton not found.")
        return nil
    end

    -- Attempt to locate casting orders
    local td_order = sdk.find_type_definition("app.ropeway.SurvivorAssignManager.CastingOrderNpc")
                  or sdk.find_type_definition("app.ropeway.SurvivorAssignManager.CastingOrderActor")
                  or sdk.find_type_definition("app.ropeway.SurvivorAssignManager.CastingOrder")

    if not td_order then
        log_msg("Native casting: CastingOrder type definitions not resolved.")
        return nil
    end

    -- Log available fields on sam
    log_msg("SurvivorAssignManager found. Requesting casting for SurvivorType 1 (Claire)...")
    return nil -- Will be populated once inspector reveals exact order constructor
end

-- Secondary Spawner: Character Duplication via via.Scene.duplicateGameObject
function spawner.spawn_by_duplication(master_player, spawn_pos, is_claire_leader)
    local player_go = spawner.get_player_game_object(master_player)
    if not player_go then
        log_msg("Duplication failed: Player GameObject not resolved.")
        return nil
    end

    local scene_man = nil
    pcall(function() scene_man = sdk.get_native_singleton("via.SceneManager") end)
    local cur_scene = nil
    pcall(function() cur_scene = scene_man and scene_man:call("get_CurrentScene") end)
    if not cur_scene then
        log_msg("Duplication failed: via.Scene not available.")
        return nil
    end

    log_msg("Attempting character duplication via via.Scene.duplicateGameObject...")
    local clone = nil
    local ok1 = pcall(function()
        clone = cur_scene:call("duplicateGameObject(via.GameObject)", player_go)
    end)
    if not ok1 or not clone then
        pcall(function()
            clone = cur_scene:call("duplicateGameObject", player_go)
        end)
    end

    if not clone then
        log_msg("duplicateGameObject returned nil.")
        return nil
    end

    pcall(function() clone:add_ref() end)

    -- Set clone position
    pcall(function()
        local tf = clone:call("get_Transform")
        if tf then
            tf:call("set_Position", spawn_pos)
            log_msg(string.format("Clone repositioned to (%.2f, %.2f, %.2f)", spawn_pos.x, spawn_pos.y, spawn_pos.z))
        end
    end)

    -- Strip player hardware inputs
    spawner.strip_input_components(clone)

    -- Attempt character/costume swap: 0 = Leon (PL0000), 1 = Claire (PL1000)
    local target_id = is_claire_leader and 0 or 1
    pcall(function()
        local survivor_man = sdk.get_managed_singleton("app.ropeway.SurvivorManager")
        if survivor_man then
            local changed = false
            pcall(function()
                survivor_man:call("requestCostumeChange", clone, target_id)
                changed = true
            end)
            if not changed then
                pcall(function() survivor_man:call("changeCostume", clone, target_id) end)
            end
            log_msg("Requested SurvivorManager costume change: ID " .. tostring(target_id))
        end
    end)

    return clone, "Character Duplication (Cloned & Rigged)"
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
    local spawn_pos = (Vector3f and Vector3f.new and Vector3f.new(spawn_x, spawn_y, spawn_z)) or { x = spawn_x, y = spawn_y, z = spawn_z }

    log_msg(string.format("Attempting to spawn companion at (%.2f, %.2f, %.2f)...", spawn_x, spawn_y, spawn_z))

    local spawned_obj = nil
    local successful_path = nil

    -- Strategy 1: Native Survivor Casting (SurvivorAssignManager)
    local ok_cast, obj_cast, path_cast = pcall(spawner.spawn_by_native_casting, master_player, spawn_pos)
    if ok_cast and obj_cast then
        spawned_obj = obj_cast
        successful_path = path_cast
    end

    -- Strategy 2: Character Duplication (Cloning active player entity)
    if not spawned_obj then
        local ok_dup, obj_dup, path_dup = pcall(spawner.spawn_by_duplication, master_player, spawn_pos, false)
        if ok_dup and obj_dup then
            spawned_obj = obj_dup
            successful_path = path_dup
        else
            log_msg("Duplication strategy failed: " .. tostring(obj_dup))
        end
    end

    if spawned_obj then
        spawner.companion_game_object = spawned_obj
        spawner.is_spawned = true
        spawner.spawn_in_progress = false
        spawner.last_spawn_status = "SUCCESS: " .. tostring(successful_path)

        -- Strip input controllers so companion doesn't mirror player controller
        spawner.strip_input_components(spawned_obj)

        log_msg("SUCCESS: Companion physically assembled in scene! " .. tostring(successful_path))
        return spawned_obj
    else
        spawner.spawn_in_progress = false
        spawner.last_spawn_status = "Awaiting Native Casting Definition (Use Inspect Button)"
        log_msg("Spawning halted: waiting for native casting definition.")
        return nil
    end
end

-- Force manual spawn trigger
function spawner.force_spawn()
    spawner.despawn_companion()
    return spawner.spawn_companion()
end

-- Despawn companion cleanly (for cutscenes or unload)
function spawner.despawn_companion()
    if spawner.companion_game_object then
        log_msg("Despawning companion entity...")
        utils.destroy_game_object(spawner.companion_game_object)
    end

    for _, child in ipairs(spawner.child_objects) do
        utils.destroy_game_object(child)
    end
    spawner.child_objects = {}

    spawner.is_spawned = false
    spawner.companion_game_object = nil
    spawner.spawn_in_progress = false
    spawner.last_spawn_status = "Despawned"
end

return spawner
