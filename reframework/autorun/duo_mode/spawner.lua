--[[
    Resident Evil 2: Duo Mode
    spawner.lua - Day 1: Physical 3D Model Instantiation & Option 1 Component Assembly
    Author: AryanTechie-007
]]

local config = require("duo_mode/config")

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

-- Prefab and Mesh candidates for Claire (pl1000) and Leon (pl0000)
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

local CLAIRE_MESH_CANDIDATES = {
    "natives/x64/sectionroot/character/player/pl1000/pl1000/pl1000.mesh",
    "natives/x64/sectionroot/character/player/pl1000/pl1050/pl1050.mesh",
    "natives/x64/sectionroot/character/player/pl1000/pl1070/pl1070.mesh",
    "character/player/pl1000/pl1000/pl1000.mesh",
    "natives/x64/character/survivor/pl1000/pl1000.mesh",
    "natives/x64/objectroot/character/survivor/pl1000/pl1000_body.mesh",
    "natives/x64/objectroot/character/survivor/pl1000/pl1000.mesh"
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
    for _, p in ipairs(CLAIRE_MESH_CANDIDATES) do table.insert(all_paths, p) end

    for _, path in ipairs(all_paths) do
        pcall(function()
            res_man:call("loadResource", "prefab", path)
            res_man:call("loadResource", "mesh", path)
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

-- Helper: Attach component by name to a GameObject
local function add_component(game_obj, type_name)
    local td = sdk.find_type_definition(type_name)
    if not td then
        log_msg("Cannot find TypeDefinition for: " .. type_name)
        return nil
    end

    local rt = td:get_runtime_type()
    local comp = nil
    pcall(function()
        comp = game_obj:call("createComponent(System.Type)", rt)
    end)
    if comp then
        comp:add_ref()
        log_msg("Added component: " .. type_name)
    else
        log_msg("Failed to add component: " .. type_name)
    end
    return comp
end

-- Option 1 Component Assembly: Bind MeshResource to Mesh component
function spawner.bind_mesh_resource(mesh_comp, master_player)
    if not mesh_comp then return false end

    local holder = nil
    local bound_path = nil

    -- 1. Try candidate paths for Claire mesh
    for _, path in ipairs(CLAIRE_MESH_CANDIDATES) do
        pcall(function()
            local res = sdk.create_resource("via.render.MeshResource", path)
            if res then
                res = res:add_ref()
                local h = res:create_holder("via.render.MeshResourceHolder")
                if h then
                    holder = h:add_ref()
                    bound_path = path
                end
            end
        end)
        if holder then break end
    end

    -- 2. Fallback: Clone master player's loaded MeshResourceHolder if specific path not found
    if not holder and master_player then
        pcall(function()
            local p_go = spawner.get_player_game_object(master_player)
            local p_mesh = p_go and p_go:call("getComponent(System.Type)", sdk.find_type_definition("via.render.Mesh"):get_runtime_type())
            if p_mesh then
                local h = p_mesh:call("get_Mesh") or (p_mesh.getMesh and p_mesh:getMesh())
                if h then
                    holder = h
                    bound_path = "MasterPlayer.LoadedMeshResourceHolder"
                    log_msg("Using master player MeshResourceHolder as fallback model.")
                end
            end
        end)
    end

    if holder then
        pcall(function() mesh_comp:call("setMesh", holder) end)
        pcall(function() mesh_comp:call("set_Mesh", holder) end)
        pcall(function() mesh_comp:set_field("Enabled", true) end)
        pcall(function() mesh_comp:call("set_DrawMesh", true) end)
        log_msg("Mesh successfully configured via " .. tostring(bound_path))
        return true, bound_path
    end

    return false, nil
end

-- Option 1 Component Assembly: Bind Motion tree for locomotion animations
function spawner.bind_motion_resource(motion_comp, master_player)
    if not motion_comp or not master_player then return false end
    pcall(function()
        local p_go = spawner.get_player_game_object(master_player)
        local p_motion = p_go and p_go:call("getComponent(System.Type)", sdk.find_type_definition("via.motion.Motion"):get_runtime_type())
        if p_motion then
            local tree = p_motion:call("get_Tree")
            if tree then
                motion_comp:call("set_Tree", tree)
                log_msg("Synchronized Motion Tree from master player.")
            end
        end
    end)
    return true
end

-- Option 1 Component Assembly: Configure CharacterController capsule
function spawner.bind_character_controller(cc_comp, master_player)
    if not cc_comp or not master_player then return false end
    pcall(function()
        local p_go = spawner.get_player_game_object(master_player)
        local p_cc = p_go and p_go:call("getComponent(System.Type)", sdk.find_type_definition("via.physics.CharacterController"):get_runtime_type())
        if p_cc then
            local radius = p_cc:call("get_Radius") or 0.35
            local height = p_cc:call("get_Height") or 1.75
            cc_comp:call("set_Radius", radius)
            cc_comp:call("set_Height", height)
            log_msg("Configured CharacterController capsule collision.")
        end
    end)
    return true
end

-- Option 1 Component Assembly: Attach modular child mesh (Face, Hair)
function spawner.attach_child_mesh(parent_obj, child_name, mesh_path)
    local go_td = sdk.find_type_definition("via.GameObject")
    if not go_td then return nil end
    local create_method = go_td:get_method("create(System.String)")
    if not create_method then return nil end

    local child_obj = create_method:call(nil, child_name)
    if not child_obj then return nil end
    child_obj:add_ref()
    child_obj:call(".ctor")

    local child_tf = child_obj:call("get_Transform")
    local parent_tf = parent_obj:call("get_Transform")
    if child_tf and parent_tf then
        pcall(function() child_tf:call("set_Parent", parent_tf) end)
    end

    local mesh_td = sdk.find_type_definition("via.render.Mesh")
    if mesh_td then
        local mesh_comp = child_obj:call("createComponent(System.Type)", mesh_td:get_runtime_type())
        if mesh_comp then
            mesh_comp:add_ref()
            pcall(function()
                local res = sdk.create_resource("via.render.MeshResource", mesh_path)
                if res then
                    res = res:add_ref()
                    local holder = res:create_holder("via.render.MeshResourceHolder"):add_ref()
                    pcall(function() mesh_comp:call("setMesh", holder) end)
                    pcall(function() mesh_comp:call("set_Mesh", holder) end)
                    pcall(function() mesh_comp:set_field("Enabled", true) end)
                end
            end)
        end
    end

    table.insert(spawner.child_objects, child_obj)
    return child_obj
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

    -- 3. Option 1 Component Assembly: Create GameObject and attach Mesh, Motion, and CharacterController
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

                        -- Option 1 Component Assembly Pipeline:
                        -- A. CharacterController
                        local cc_comp = add_component(new_obj, "via.physics.CharacterController")
                        spawner.bind_character_controller(cc_comp, master_player)

                        -- B. Motion (locomotion blend trees)
                        local motion_comp = add_component(new_obj, "via.motion.Motion")
                        spawner.bind_motion_resource(motion_comp, master_player)

                        -- C. Mesh (3D geometry and materials)
                        local mesh_comp = add_component(new_obj, "via.render.Mesh")
                        local mesh_ok, bound_path = spawner.bind_mesh_resource(mesh_comp, master_player)

                        -- D. Modular sub-parts: Face & Hair child objects
                        pcall(function()
                            spawner.attach_child_mesh(new_obj, "Claire_Face", "natives/x64/sectionroot/character/player/pl1000/pl1050/pl1050.mesh")
                            spawner.attach_child_mesh(new_obj, "Claire_Hair", "natives/x64/sectionroot/character/player/pl1000/pl1070/pl1070.mesh")
                        end)

                        spawned_obj = new_obj
                        successful_path = "Option 1 Component Assembly (Mesh: " .. tostring(bound_path) .. ")"
                    end
                end
            end
        end)
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
        spawner.last_spawn_status = "Failed: Component assembly could not allocate entity"
        log_msg("Instantiation attempt failed.")
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
        pcall(function()
            spawner.companion_game_object:call("destroy")
        end)
    end

    for _, child in ipairs(spawner.child_objects) do
        pcall(function() child:call("destroy") end)
    end
    spawner.child_objects = {}

    spawner.is_spawned = false
    spawner.companion_game_object = nil
    spawner.spawn_in_progress = false
    spawner.last_spawn_status = "Despawned"
end

return spawner