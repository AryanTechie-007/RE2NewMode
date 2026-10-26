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

-- =========================================================================
-- 1. Costume Presets (Default: Classic Red Leather Jacket)
-- =========================================================================
spawner.costumes = {
    {
        id = "classic",
        name = "Classic Jacket (Costume 1)",
        body = "objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_1.pfb",
        head = "objectroot/prefab/character/survivor/parts/pl1000/pl1000_face_costume_1.pfb",
        hair = "objectroot/prefab/character/survivor/parts/pl1000/pl1000_hair_costume_1.pfb",
        body_exists = false,
        head_exists = false,
        hair_exists = false,
    },
    {
        id = "noir",
        name = "Noir DLC (Costume A)",
        body = "objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_a.pfb",
        head = "objectroot/prefab/character/survivor/parts/pl1000/pl1000_face_costume_a.pfb",
        hair = "objectroot/prefab/character/survivor/parts/pl1000/pl1000_hair_costume_a.pfb",
        body_exists = false,
        head_exists = false,
        hair_exists = false,
    },
    {
        id = "alternate",
        name = "Alternate (Costume 2)",
        body = "objectroot/prefab/character/survivor/parts/pl1000/pl1000_body_costume_2.pfb",
        head = "objectroot/prefab/character/survivor/parts/pl1000/pl1000_face_costume_1.pfb",
        hair = "objectroot/prefab/character/survivor/parts/pl1000/pl1000_hair_costume_1.pfb",
        body_exists = false,
        head_exists = false,
        hair_exists = false,
    }
}
spawner.selected_costume_idx = 1 -- Default: Classic Jacket (Costume 1)

-- Streaming State
spawner.body_pfb = nil
spawner.head_pfb = nil
spawner.hair_pfb = nil
spawner.streaming = false
spawner.stream_frames = 0
spawner.mode = "full"

local function log_debug(msg)
    pcall(function()
        local f = io.open("reframework/data/spawner_debug.txt", "a")
        if f then
            f:write(os.date("[%H:%M:%S] ") .. tostring(msg) .. "\n")
            f:close()
        end
    end)
    pcall(function()
        local f2 = io.open("spawner_debug.txt", "a")
        if f2 then
            f2:write(os.date("[%H:%M:%S] ") .. tostring(msg) .. "\n")
            f2:close()
        end
    end)
    if log and log.info then
        log.info("[Spawner] " .. tostring(msg))
    end
end

-- =========================================================================
-- 2. Transform Math & Safe Position Setters
-- =========================================================================
local function set_transform_position(tf, x, y, z)
    if not tf then return false end
    -- 1. RETransform:set_position with Vector4f
    local v4 = Vector4f and Vector4f.new and Vector4f.new(x, y, z, 1.0)
    if v4 and tf.set_position then
        local ok1 = pcall(function() tf:set_position(v4, false) end)
        if ok1 then return true end
        local ok2 = pcall(function() tf:set_position(v4) end)
        if ok2 then return true end
    end

    -- 2. RETransform:set_position with Vector3f
    local v3 = Vector3f and Vector3f.new and Vector3f.new(x, y, z)
    if v3 and tf.set_position then
        local ok3 = pcall(function() tf:set_position(v3, false) end)
        if ok3 then return true end
    end

    -- 3. via.Transform:call("set_Position(via.vec3)", ...)
    if tf.call then
        if v3 then
            local ok4 = pcall(function() tf:call("set_Position(via.vec3)", v3) end)
            if ok4 then return true end
            local ok5 = pcall(function() tf:call("set_Position", v3) end)
            if ok5 then return true end
        end
        if v4 then
            local ok6 = pcall(function() tf:call("set_Position(via.vec3)", v4) end)
            if ok6 then return true end
            local ok7 = pcall(function() tf:call("set_Position", v4) end)
            if ok7 then return true end
        end
    end
    return false
end

local function get_transform_position(tf)
    if not tf then return nil end
    if tf.get_position then
        local ok, p = pcall(function() return tf:get_position() end)
        if ok and p and p.x then return { x = p.x, y = p.y, z = p.z } end
    end
    if tf.call then
        local ok, p = pcall(function() return tf:call("get_Position") end)
        if ok and p and p.x then return { x = p.x, y = p.y, z = p.z } end
    end
    return nil
end

local function get_yaw_from_transform(tf)
    if not tf then return 0.0 end
    if tf.get_rotation then
        local ok, rot = pcall(function() return tf:get_rotation() end)
        if ok and rot and rot.w then
            local x = rot.x or 0.0
            local y = rot.y or 0.0
            local z = rot.z or 0.0
            local w = rot.w or 1.0
            local siny = 2.0 * (w * y + x * z)
            local cosy = 1.0 - 2.0 * (y * y + z * z)
            return math.atan(siny, cosy)
        end
    end
    if tf.call then
        local ok1, euler = pcall(function() return tf:call("get_EulerAngles") end)
        if ok1 and euler and euler.y then return euler.y end
        local ok2, rot = pcall(function() return tf:call("get_Rotation") end)
        if ok2 and rot and rot.w then
            local x = rot.x or 0.0
            local y = rot.y or 0.0
            local z = rot.z or 0.0
            local w = rot.w or 1.0
            local siny = 2.0 * (w * y + x * z)
            local cosy = 1.0 - 2.0 * (y * y + z * z)
            return math.atan(siny, cosy)
        end
    end
    return 0.0
end

local function get_front_spawn_position(player_tf, dist)
    dist = dist or 2.0
    local p = get_transform_position(player_tf) or { x = 0.0, y = 0.0, z = 0.0 }
    local yaw = get_yaw_from_transform(player_tf)
    local fx = p.x + math.sin(yaw) * dist
    local fy = p.y
    local fz = p.z + math.cos(yaw) * dist
    return { x = fx, y = fy, z = fz }
end

-- =========================================================================
-- 3. Scan and Resolve Valid Costume Files
-- =========================================================================
local function check_file_exist(path)
    if not path then return false end
    local exists = false
    pcall(function()
        local pfb = sdk.create_instance("via.Prefab"):add_ref()
        pfb:call("set_Path", path)
        exists = pfb:call("get_Exist")
    end)
    return exists
end

function spawner.scan_all_candidates()
    log_debug("=== Scanning RE2 Pak Archives for Claire Costumes ===")
    for i, c in ipairs(spawner.costumes) do
        c.body_exists = check_file_exist(c.body)
        c.head_exists = check_file_exist(c.head)
        c.hair_exists = check_file_exist(c.hair)
        log_debug(string.format("  [%s] Body: %s (%s) | Head: %s (%s) | Hair: %s (%s)",
            c.name,
            tostring(c.body_exists), tostring(c.body),
            tostring(c.head_exists), tostring(c.head),
            tostring(c.hair_exists), tostring(c.hair)))
    end

    -- If classic jacket body exists, make sure selected is 1
    if spawner.costumes[1].body_exists then
        spawner.selected_costume_idx = 1
    elseif spawner.costumes[2].body_exists then
        spawner.selected_costume_idx = 2
    end
    log_debug("Default selected costume: " .. spawner.costumes[spawner.selected_costume_idx].name)
end

-- =========================================================================
-- 4. Player Resolution
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
-- 5. Despawn Logic
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
-- 6. Initiate Spawner Pipeline
-- =========================================================================
function spawner.start_spawn(mode)
    spawner.execute_despawn()
    spawner.mode = mode or "full"

    local costume = spawner.costumes[spawner.selected_costume_idx] or spawner.costumes[1]
    local body_path = costume.body
    local head_path = costume.head_exists and costume.head or spawner.costumes[1].head
    local hair_path = costume.hair_exists and costume.hair or spawner.costumes[1].hair

    log_debug(string.format("Starting Claire Spawn Pipeline [%s] (Mode: %s):", costume.name, spawner.mode))
    log_debug("  Body: " .. tostring(body_path))
    if spawner.mode == "full" then
        log_debug("  Head: " .. tostring(head_path))
        log_debug("  Hair: " .. tostring(hair_path))
    end

    -- Create Body Prefab
    pcall(function()
        local b = sdk.create_instance("via.Prefab"):add_ref()
        b:call("set_Path", body_path)
        b:call("set_Standby", true)
        spawner.body_pfb = b
    end)

    -- Create Head and Hair Prefabs if full mode
    if spawner.mode == "full" and head_path then
        pcall(function()
            local h = sdk.create_instance("via.Prefab"):add_ref()
            h:call("set_Path", head_path)
            h:call("set_Standby", true)
            spawner.head_pfb = h
        end)
    end
    if spawner.mode == "full" and hair_path then
        pcall(function()
            local hr = sdk.create_instance("via.Prefab"):add_ref()
            hr:call("set_Path", hair_path)
            hr:call("set_Standby", true)
            spawner.hair_pfb = hr
        end)
    end

    spawner.streaming = true
    spawner.stream_frames = 0
    spawner.last_status = "Streaming " .. costume.name .. " assets... (Frame 0)"
end

-- =========================================================================
-- 7. Master Frame Loop (re.on_frame)
-- =========================================================================
re.on_frame(function()
    if spawner.streaming and spawner.body_pfb then
        spawner.stream_frames = spawner.stream_frames + 1

        local player = spawner.get_master_player()
        local player_go = spawner.get_player_game_object(player)
        local player_tf = player_go and player_go:call("get_Transform")
        local front_pos = player_tf and get_front_spawn_position(player_tf, 2.0) or { x = 0, y = 0, z = 0 }
        local vpos = (Vector3f and Vector3f.new and Vector3f.new(front_pos.x, front_pos.y, front_pos.z))
                  or (Vector4f and Vector4f.new and Vector4f.new(front_pos.x, front_pos.y, front_pos.z, 1.0))
                  or front_pos

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
                set_transform_position(b_tf, front_pos.x, front_pos.y, front_pos.z)
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

            local c_name = spawner.costumes[spawner.selected_costume_idx].name
            local total_parts = #spawner.spawned_entities
            if total_parts >= 3 then
                spawner.last_status = string.format("SUCCESS: CLAIRE (%s) FULLY RENDERED!", c_name)
            else
                spawner.last_status = string.format("SUCCESS: CLAIRE (%s) RENDERED (Parts: %d)!", c_name, total_parts)
            end
            log_debug(string.format("Spawn completed! Total parts active: %d", total_parts))

            spawner.streaming = false
            spawner.body_pfb = nil
            spawner.head_pfb = nil
            spawner.hair_pfb = nil
        else
            spawner.last_status = string.format("Streaming assets... (Frame %d/300)", spawner.stream_frames)

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

-- Initial scan on script load
pcall(spawner.scan_all_candidates)

-- =========================================================================
-- 8. Clean, Minimalist ImGui Spawner UI with Costume Selector
-- =========================================================================
local function draw_spawner_ui(suffix)
    suffix = suffix or ""
    imgui.text_colored("=== RE2 DUO MODE: CLAIRE REDFIELD SPAWNER ===", 0.3, 0.9, 1.0, 1.0)
    imgui.text("Status: " .. tostring(spawner.last_status))
    imgui.separator()

    -- Costume Selector Buttons
    imgui.text("Choose Claire's Outfit:")
    for idx, c in ipairs(spawner.costumes) do
        local is_selected = (spawner.selected_costume_idx == idx)
        local btn_label = (is_selected and "[*] " or "[ ] ") .. c.name .. "##cst_" .. tostring(idx) .. suffix
        if is_selected then
            imgui.push_style_color(21, 0.2, 0.6, 0.9, 1.0) -- Selected button color
        end
        if imgui.button(btn_label) then
            spawner.selected_costume_idx = idx
            log_debug("Costume selected: " .. c.name)
            if #spawner.spawned_entities > 0 then
                -- Respawn in new outfit immediately
                spawner.start_spawn("full")
            end
        end
        if is_selected then
            imgui.pop_style_color(1)
        end
        imgui.same_line()
    end
    imgui.new_line()

    local cur_c = spawner.costumes[spawner.selected_costume_idx]
    imgui.text_colored("Selected Outfit: " .. cur_c.name, 1.0, 0.85, 0.2, 1.0)
    imgui.separator()

    local player = spawner.get_master_player()
    if player then
        imgui.text_colored("Player (Leon): ACTIVE IN SCENE", 0.2, 1.0, 0.4, 1.0)
        imgui.spacing()

        if imgui.button(">>> SPAWN CLAIRE REDFIELD (Full Character) <<<##btn_full" .. suffix) then
            spawner.click_count = spawner.click_count + 1
            log_debug("UI BUTTON CLICKED: Full Character Spawn (" .. cur_c.name .. ")")
            spawner.start_spawn("full")
        end

        imgui.spacing()
        if imgui.button("Spawn Claire Body Only (Instant Test)##btn_body" .. suffix) then
            spawner.click_count = spawner.click_count + 1
            log_debug("UI BUTTON CLICKED: Body Only Spawn (" .. cur_c.name .. ")")
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

-- =========================================================================
-- 9. Global Interface for Companion Subsystems (Motion, AI, Audio)
-- =========================================================================
_G.DuoMode = _G.DuoMode or {}
_G.DuoMode.spawner = spawner
_G.DuoMode.get_companion_body = function()
    return spawner.spawned_entities and spawner.spawned_entities[1]
end
_G.DuoMode.get_companion_parts = function()
    return spawner.spawned_entities
end
_G.DuoMode.is_spawned = function()
    return spawner.spawned_entities and #spawner.spawned_entities > 0 and spawner.spawned_entities[1] ~= nil
end
