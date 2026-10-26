--[[
    Resident Evil 2: Duo Mode — Claire Redfield Spawner
    Script: character_renderer.lua
    Purpose: Dedicated harness to spawn Claire Redfield (Body, Face, Hair) into the 3D viewport.
    Author: AryanTechie-007
]]

local spawner = {}
spawner.spawned_entities = {}
spawner.last_status = "Ready - Standing by (Click button to spawn)"
spawner.click_count = 0

-- Multi-Part Streaming State
spawner.body_pfb = nil
spawner.head_pfb = nil
spawner.hair_pfb = nil
spawner.streaming = false
spawner.stream_frames = 0
spawner.mode = "full" -- "full" or "body_only"

-- Exact Verified Character Paths (from RE2 archives)
local PATH_BODY = "objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_0.pfb"
local PATH_HEAD = "objectroot/prefab/character/survivor/parts/pl1000/pl1000_face_costume_a.pfb"
local PATH_HAIR = "objectroot/prefab/character/survivor/parts/pl1000/pl1000_hair_costume_a.pfb"

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

log_debug("=== Claire Redfield Spawner Loaded ===")

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
-- 3. Despawn Logic
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
    spawner.body_pfb = nil
    spawner.head_pfb = nil
    spawner.hair_pfb = nil
    spawner.streaming = false
    spawner.stream_frames = 0
    spawner.last_status = "Despawned - Standing by"
    log_debug("Despawn executed cleanly.")
end

-- =========================================================================
-- 4. Initiate Spawner Pipeline
-- =========================================================================
function spawner.start_spawn(mode)
    spawner.execute_despawn()
    spawner.mode = mode or "full"
    spawner.streaming = true
    spawner.stream_frames = 0

    log_debug("Starting Claire Spawn Pipeline (Mode: " .. spawner.mode .. "):")
    log_debug("  Body: " .. PATH_BODY)
    if spawner.mode == "full" then
        log_debug("  Head: " .. PATH_HEAD)
        log_debug("  Hair: " .. PATH_HAIR)
    end

    -- Create Body Prefab
    pcall(function()
        local b = sdk.create_instance("via.Prefab"):add_ref()
        b:call("set_Path", PATH_BODY)
        b:call("set_Standby", true)
        spawner.body_pfb = b
    end)

    -- Create Head and Hair Prefabs if full mode
    if spawner.mode == "full" then
        pcall(function()
            local h = sdk.create_instance("via.Prefab"):add_ref()
            h:call("set_Path", PATH_HEAD)
            h:call("set_Standby", true)
            spawner.head_pfb = h
        end)
        pcall(function()
            local hr = sdk.create_instance("via.Prefab"):add_ref()
            hr:call("set_Path", PATH_HAIR)
            hr:call("set_Standby", true)
            spawner.hair_pfb = hr
        end)
    end

    spawner.last_status = "Streaming Claire assets into memory... (Frame 0)"
end

-- =========================================================================
-- 5. Master Frame Loop (re.on_frame)
-- =========================================================================
re.on_frame(function()
    if spawner.streaming and spawner.body_pfb then
        spawner.stream_frames = spawner.stream_frames + 1

        local player = spawner.get_master_player()
        local player_go = spawner.get_player_game_object(player)
        local player_tf = player_go and player_go:call("get_Transform")
        local front_pos = player_tf and get_front_spawn_position(player_tf, 2.0) or { x = 0, y = 0, z = 0 }
        local vpos = (Vector3f and Vector3f.new and Vector3f.new(front_pos.x, front_pos.y, front_pos.z)) or front_pos

        -- Attempt instantiation of Body on every frame
        local body_obj = nil
        local ok_b = pcall(function()
            body_obj = spawner.body_pfb:call("instantiate(via.vec3)", vpos)
        end)

        if ok_b and body_obj then
            pcall(function() body_obj:add_ref() end)
            local b_tf = nil
            pcall(function() b_tf = body_obj:call("get_Transform") end)
            if b_tf then
                pcall(function() b_tf:call("set_Position", front_pos) end)
            end
            pcall(function()
                body_obj:call("set_DrawSelf", true)
                body_obj:call("set_UpdateSelf", true)
            end)
            table.insert(spawner.spawned_entities, body_obj)
            log_debug(string.format("Body instantiated at frame %d at (%.2f, %.2f, %.2f)", spawner.stream_frames, front_pos.x, front_pos.y, front_pos.z))

            -- If Full mode, instantiate and attach Head & Hair
            if spawner.mode == "full" then
                -- Head
                if spawner.head_pfb then
                    local head_obj = nil
                    pcall(function() head_obj = spawner.head_pfb:call("instantiate(via.vec3)", vpos) end)
                    if head_obj then
                        pcall(function() head_obj:add_ref() end)
                        pcall(function()
                            local h_tf = head_obj:call("get_Transform")
                            if h_tf and b_tf then
                                h_tf:call("set_Parent", b_tf)
                            end
                            head_obj:call("set_DrawSelf", true)
                            head_obj:call("set_UpdateSelf", true)
                        end)
                        table.insert(spawner.spawned_entities, head_obj)
                        log_debug("Head instantiated and attached to Body.")
                    else
                        log_debug("Head instantiate returned nil at frame " .. tostring(spawner.stream_frames))
                    end
                end

                -- Hair
                if spawner.hair_pfb then
                    local hair_obj = nil
                    pcall(function() hair_obj = spawner.hair_pfb:call("instantiate(via.vec3)", vpos) end)
                    if hair_obj then
                        pcall(function() hair_obj:add_ref() end)
                        pcall(function()
                            local hr_tf = hair_obj:call("get_Transform")
                            if hr_tf and b_tf then
                                hr_tf:call("set_Parent", b_tf)
                            end
                            hair_obj:call("set_DrawSelf", true)
                            hair_obj:call("set_UpdateSelf", true)
                        end)
                        table.insert(spawner.spawned_entities, hair_obj)
                        log_debug("Hair instantiated and attached to Body.")
                    else
                        log_debug("Hair instantiate returned nil at frame " .. tostring(spawner.stream_frames))
                    end
                end
            end

            local total_parts = #spawner.spawned_entities
            if total_parts >= 3 then
                spawner.last_status = "SUCCESS: CLAIRE FULLY RENDERED (Body + Head + Hair)!"
            else
                spawner.last_status = "SUCCESS: CLAIRE RENDERED IN VIEWPORT!"
            end
            log_debug(string.format("Spawn completed! Total parts active: %d", total_parts))

            spawner.streaming = false
            spawner.body_pfb = nil
            spawner.head_pfb = nil
            spawner.hair_pfb = nil
        else
            spawner.last_status = string.format("Streaming assets... (Frame %d/300)", spawner.stream_frames)

            -- Periodic log every 30 frames
            if spawner.stream_frames % 30 == 0 then
                log_debug(string.format("Streaming in progress: frame %d, instantiate returned nil", spawner.stream_frames))
            end

            if spawner.stream_frames > 300 then
                spawner.streaming = false
                spawner.body_pfb = nil
                spawner.head_pfb = nil
                spawner.hair_pfb = nil
                spawner.last_status = "Streaming timed out at frame 300"
                log_debug("Streaming timed out at frame 300.")
            end
        end
    end
end)

-- =========================================================================
-- 6. Clean, Minimalist ImGui Spawner UI
-- =========================================================================
local function draw_spawner_ui(suffix)
    suffix = suffix or ""
    imgui.text_colored("=== RE2 DUO MODE: CLAIRE REDFIELD SPAWNER ===", 0.3, 0.9, 1.0, 1.0)
    imgui.text("Status: " .. tostring(spawner.last_status))
    imgui.text("Spawn Requests: " .. tostring(spawner.click_count))
    imgui.separator()

    local player = spawner.get_master_player()
    if player then
        imgui.text_colored("Player (Leon): ACTIVE IN SCENE", 0.2, 1.0, 0.4, 1.0)
        imgui.spacing()

        if imgui.button(">>> SPAWN CLAIRE REDFIELD (Full Character) <<<##btn_full" .. suffix) then
            spawner.click_count = spawner.click_count + 1
            log_debug("UI BUTTON CLICKED: Full Character Spawn")
            spawner.start_spawn("full")
        end

        imgui.spacing()
        if imgui.button("Spawn Claire Body Only (Instant Test)##btn_body" .. suffix) then
            spawner.click_count = spawner.click_count + 1
            log_debug("UI BUTTON CLICKED: Body Only Spawn")
            spawner.start_spawn("body_only")
        end

        imgui.same_line()
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
