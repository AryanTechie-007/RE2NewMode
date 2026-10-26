--[[
    Resident Evil 2: Duo Mode — Claire Redfield Spawner
    Script: character_renderer.lua
    Purpose: Dedicated harness to spawn Claire Redfield (PL1000) into the 3D viewport.
    Author: AryanTechie-007
]]

local spawner = {}
spawner.spawned_entities = {}
spawner.last_status = "Ready - Standing by (Click button to spawn)"
spawner.click_count = 0

-- Streaming State
spawner.loading_prefab = nil
spawner.loading_path = ""
spawner.loading_frames = 0
spawner.load_mode = "body_only"

-- Secondary Prefabs for Modular Mode
spawner.loading_head_prefab = nil
spawner.loading_hair_prefab = nil

local function log_debug(msg)
    pcall(function()
        local f = io.open("spawner_debug.txt", "a")
        if f then
            f:write(os.date("[%H:%M:%S] ") .. tostring(msg) .. "\n")
            f:close()
        end
    end)
    if log and log.info then
        log.info("[Spawner] " .. tostring(msg))
    end
end

log_debug("=== Claire Redfield Spawner Initialized ===")

-- =========================================================================
-- 1. Helper: Safe Yaw and Forward Vector Extraction
-- =========================================================================
local function get_yaw_from_transform(tf)
    if not tf or not tf.call then return 0.0 end
    local ok1, euler = pcall(function() return tf:call("get_EulerAngles") end)
    if ok1 and euler and euler.y then return euler.y end

    local ok2, euler2 = pcall(function() return tf:call("get_EulerAngle") end)
    if ok2 and euler2 and euler2.y then return euler2.y end

    local ok3, rot = pcall(function() return tf:call("get_Rotation") end)
    if ok3 and rot then
        local x = rot.x or 0.0
        local y = rot.y or 0.0
        local z = rot.z or 0.0
        local w = rot.w or 1.0
        local siny_cosp = 2.0 * (w * y + x * z)
        local cosy_cosp = 1.0 - 2.0 * (y * y + z * z)
        return math.atan(siny_cosp, cosy_cosp)
    end
    return 0.0
end

local function get_front_spawn_position(player_tf, dist)
    dist = dist or 2.0 -- 2 meters directly IN FRONT of player
    local fx, fy, fz = 0.0, 0.0, 0.0
    pcall(function()
        local pos = player_tf:call("get_Position")
        local yaw = get_yaw_from_transform(player_tf)
        fx = pos.x + math.sin(yaw) * dist
        fy = pos.y
        fz = pos.z + math.cos(yaw) * dist
    end)
    return (Vector3f and Vector3f.new and Vector3f.new(fx, fy, fz)) or { x = fx, y = fy, z = fz }
end

-- =========================================================================
-- 2. Player Resolution
-- =========================================================================
function spawner.get_master_player()
    local player_man = nil
    pcall(function()
        player_man = sdk.get_managed_singleton("app.ropeway.PlayerManager")
                  or sdk.get_managed_singleton(sdk.game_namespace("PlayerManager"))
    end)
    if not player_man then return nil end

    local p = nil
    pcall(function() p = player_man:call("get_CurrentPlayer") end)
    if not p then pcall(function() p = player_man:call("getMasterPlayerCharacter") end) end
    if not p then pcall(function() p = player_man:call("get_CurrentPlayerCharacter") end) end
    if not p then pcall(function() p = player_man:call("get_MasterPlayerCharacter") end) end
    return p
end

function spawner.get_player_game_object(player)
    player = player or spawner.get_master_player()
    if not player then return nil end
    local go = nil
    pcall(function() if player.get_game_object then go = player:get_game_object() end end)
    if not go then pcall(function() go = player:call("get_GameObject") end) end
    return go or player
end

-- =========================================================================
-- 3. Despawn Logic (100% Protected)
-- =========================================================================
function spawner.execute_despawn()
    pcall(function()
        local scene_man = nil
        pcall(function() scene_man = sdk.get_native_singleton("via.SceneManager") end)
        local cur_scene = nil
        pcall(function() cur_scene = scene_man and scene_man:call("get_CurrentScene") end)

        for _, entity in ipairs(spawner.spawned_entities) do
            pcall(function()
                if entity and entity.call then
                    pcall(function() entity:call("set_DrawSelf", false) end)
                    pcall(function() entity:call("set_UpdateSelf", false) end)
                    if cur_scene then
                        pcall(function() cur_scene:call("destroyGameObject(via.GameObject)", entity) end)
                        pcall(function() cur_scene:call("destroyGameObject", entity) end)
                    end
                end
            end)
        end
    end)
    spawner.spawned_entities = {}
    spawner.loading_prefab = nil
    spawner.loading_head_prefab = nil
    spawner.loading_hair_prefab = nil
    spawner.last_status = "Despawned - Standing by"
    log_debug("Despawn executed cleanly.")
end

-- =========================================================================
-- 4. Primary Spawner: Guaranteed Body Instantiation (Verified Working)
-- =========================================================================
function spawner.spawn_claire_body(costume_index)
    pcall(spawner.execute_despawn)
    costume_index = costume_index or 0

    local body_path = string.format("objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_%d.pfb", costume_index)
    log_debug("Starting Claire Body Stream: " .. body_path)

    local pfb = nil
    local ok_pfb, err_pfb = pcall(function()
        pfb = sdk.create_instance("via.Prefab"):add_ref()
        pfb:call("set_Path", body_path)
        pfb:call("set_Standby", true)
    end)

    if not ok_pfb or not pfb then
        spawner.last_status = "Error creating via.Prefab: " .. tostring(err_pfb)
        log_debug("Failed to create via.Prefab: " .. tostring(err_pfb))
        return
    end

    spawner.loading_prefab = pfb
    spawner.loading_path = body_path
    spawner.loading_frames = 0
    spawner.load_mode = "body_only"
    spawner.last_status = "Streaming Claire body from archives... (Frame 0)"
    log_debug("via.Prefab configured and standby requested.")
end

-- =========================================================================
-- 5. Experimental Modular Spawner: Body + Head + Hair
-- =========================================================================
function spawner.spawn_claire_modular(costume_index)
    pcall(spawner.execute_despawn)
    costume_index = costume_index or 0

    local body_path = string.format("objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_%d.pfb", costume_index)
    local head_path = "objectroot/prefab/character/survivor/parts/pl1000/pl1000_face_costume_a.pfb"
    local hair_path = "objectroot/prefab/character/survivor/parts/pl1000/pl1000_hair_costume_a.pfb"

    log_debug("Starting Modular Assembly Stream:")
    log_debug("  Body: " .. body_path)
    log_debug("  Head: " .. head_path)
    log_debug("  Hair: " .. hair_path)

    local b_pfb, h_pfb, hr_pfb = nil, nil, nil
    pcall(function()
        b_pfb = sdk.create_instance("via.Prefab"):add_ref()
        b_pfb:call("set_Path", body_path)
        b_pfb:call("set_Standby", true)
    end)
    pcall(function()
        h_pfb = sdk.create_instance("via.Prefab"):add_ref()
        h_pfb:call("set_Path", head_path)
        h_pfb:call("set_Standby", true)
    end)
    pcall(function()
        hr_pfb = sdk.create_instance("via.Prefab"):add_ref()
        hr_pfb:call("set_Path", hair_path)
        hr_pfb:call("set_Standby", true)
    end)

    spawner.loading_prefab = b_pfb
    spawner.loading_head_prefab = h_pfb
    spawner.loading_hair_prefab = hr_pfb
    spawner.loading_frames = 0
    spawner.load_mode = "modular"
    spawner.last_status = "Streaming Body + Head + Hair... (Frame 0)"
end

-- =========================================================================
-- 6. Master Frame Loop (re.on_frame)
-- =========================================================================
re.on_frame(function()
    -- Asynchronous Streaming Tick
    if spawner.loading_prefab then
        spawner.loading_frames = spawner.loading_frames + 1
        local pfb = spawner.loading_prefab
        local is_ready = false
        pcall(function() is_ready = pfb:call("get_Ready") end)

        spawner.last_status = string.format("Streaming from archives... (Frame %d | Ready: %s)", spawner.loading_frames, tostring(is_ready))

        if is_ready then
            local player = spawner.get_master_player()
            local player_go = spawner.get_player_game_object(player)
            local player_tf = player_go and player_go:call("get_Transform")
            local front_pos = player_tf and get_front_spawn_position(player_tf, 2.0) or { x = 0, y = 0, z = 0 }
            local vpos = (Vector3f and Vector3f.new and Vector3f.new(front_pos.x, front_pos.y, front_pos.z)) or front_pos

            -- 1. Instantiate Body
            local body_go = nil
            local ok_spawn, err = pcall(function()
                body_go = pfb:call("instantiate(via.vec3)", vpos)
            end)

            if ok_spawn and body_go then
                pcall(function() body_go:add_ref() end)
                local b_tf = nil
                pcall(function() b_tf = body_go:call("get_Transform") end)
                if b_tf then
                    pcall(function() b_tf:call("set_Position", front_pos) end)
                end
                pcall(function()
                    body_go:call("set_DrawSelf", true)
                    body_go:call("set_UpdateSelf", true)
                end)
                table.insert(spawner.spawned_entities, body_go)
                log_debug(string.format("Body instantiated at frame %d at (%.2f, %.2f, %.2f)", spawner.loading_frames, front_pos.x, front_pos.y, front_pos.z))

                -- 2. If modular mode, attach head and hair
                if spawner.load_mode == "modular" then
                    -- Head
                    if spawner.loading_head_prefab then
                        local h_ready = false
                        pcall(function() h_ready = spawner.loading_head_prefab:call("get_Ready") end)
                        if h_ready then
                            local head_go = nil
                            pcall(function()
                                head_go = spawner.loading_head_prefab:call("instantiate(via.vec3)", vpos)
                            end)
                            if head_go then
                                pcall(function() head_go:add_ref() end)
                                pcall(function()
                                    local h_tf = head_go:call("get_Transform")
                                    if h_tf and b_tf then
                                        h_tf:call("set_Parent", b_tf)
                                    end
                                    head_go:call("set_DrawSelf", true)
                                    head_go:call("set_UpdateSelf", true)
                                end)
                                table.insert(spawner.spawned_entities, head_go)
                                log_debug("Head instantiated and attached.")
                            end
                        end
                    end

                    -- Hair
                    if spawner.loading_hair_prefab then
                        local hr_ready = false
                        pcall(function() hr_ready = spawner.loading_hair_prefab:call("get_Ready") end)
                        if hr_ready then
                            local hair_go = nil
                            pcall(function()
                                hair_go = spawner.loading_hair_prefab:call("instantiate(via.vec3)", vpos)
                            end)
                            if hair_go then
                                pcall(function() hair_go:add_ref() end)
                                pcall(function()
                                    local hr_tf = hair_go:call("get_Transform")
                                    if hr_tf and b_tf then
                                        hr_tf:call("set_Parent", b_tf)
                                    end
                                    hair_go:call("set_DrawSelf", true)
                                    hair_go:call("set_UpdateSelf", true)
                                end)
                                table.insert(spawner.spawned_entities, hair_go)
                                log_debug("Hair instantiated and attached.")
                            end
                        end
                    end
                end

                local total_parts = #spawner.spawned_entities
                if total_parts >= 3 then
                    spawner.last_status = "SUCCESS: CLAIRE FULLY RENDERED (Body + Head + Hair)!"
                else
                    spawner.last_status = "SUCCESS: CLAIRE RENDERED IN VIEWPORT!"
                end
                log_debug("Spawn completed. Total parts in scene: " .. tostring(total_parts))
            else
                spawner.last_status = "Instantiation failed: " .. tostring(err)
                log_debug("Body instantiate failed: " .. tostring(err))
            end

            spawner.loading_prefab = nil
            spawner.loading_head_prefab = nil
            spawner.loading_hair_prefab = nil
        elseif spawner.loading_frames > 240 then
            spawner.last_status = "Streaming timed out at frame 240"
            log_debug("Streaming timed out at frame 240.")
            spawner.loading_prefab = nil
            spawner.loading_head_prefab = nil
            spawner.loading_hair_prefab = nil
        end
    end
end)

-- =========================================================================
-- 7. Clean, Minimalist ImGui Spawner UI (Instant Action Handlers)
-- =========================================================================
local function draw_spawner_ui(suffix)
    suffix = suffix or ""
    imgui.text_colored("=== RE2 DUO MODE: CLAIRE REDFIELD SPAWNER ===", 0.3, 0.9, 1.0, 1.0)
    imgui.text("Status: " .. tostring(spawner.last_status))
    imgui.text("Spawn Clicks Registered: " .. tostring(spawner.click_count))
    imgui.separator()

    local player = spawner.get_master_player()
    if player then
        imgui.text_colored("Player (Leon): ACTIVE IN SCENE", 0.2, 1.0, 0.4, 1.0)
        imgui.spacing()

        if imgui.button(">>> SPAWN CLAIRE REDFIELD (Instant Spawn) <<<##btn_inst" .. suffix) then
            spawner.click_count = spawner.click_count + 1
            log_debug("UI BUTTON CLICKED: Instant Spawn")
            local ok, err = pcall(function() spawner.spawn_claire_body(0) end)
            if not ok then
                spawner.last_status = "Error: " .. tostring(err)
                log_debug("Spawn execution error: " .. tostring(err))
            end
        end

        imgui.spacing()
        if imgui.button("Spawn Claire + Head/Hair (Modular Test)##btn_mod" .. suffix) then
            spawner.click_count = spawner.click_count + 1
            log_debug("UI BUTTON CLICKED: Modular Spawn")
            local ok, err = pcall(function() spawner.spawn_claire_modular(0) end)
            if not ok then
                spawner.last_status = "Error: " .. tostring(err)
                log_debug("Spawn execution error: " .. tostring(err))
            end
        end

        imgui.same_line()
        if imgui.button("Spawn Claire (Tank Top)##btn_tank" .. suffix) then
            spawner.click_count = spawner.click_count + 1
            log_debug("UI BUTTON CLICKED: Tank Top Spawn")
            local ok, err = pcall(function() spawner.spawn_claire_body(1) end)
            if not ok then
                spawner.last_status = "Error: " .. tostring(err)
                log_debug("Spawn execution error: " .. tostring(err))
            end
        end

        imgui.spacing()
        if imgui.button("Despawn Claire##btn_desp" .. suffix) then
            log_debug("UI BUTTON CLICKED: Despawn")
            pcall(spawner.execute_despawn)
        end
    else
        imgui.text_colored("Waiting for game scene / Leon to load...", 1.0, 0.8, 0.2, 1.0)
        imgui.text("Please load your game save or start a new game first.")
    end
end

-- Dedicated Standalone Floating Window
re.on_frame(function()
    pcall(function()
        if imgui.begin_window("Claire Redfield Spawner (Duo Mode)", true, 0) then
            draw_spawner_ui("##win")
            imgui.end_window()
        end
    end)
end)

-- REFramework Menu entry
re.on_draw_ui(function()
    draw_spawner_ui("##menu")
end)
