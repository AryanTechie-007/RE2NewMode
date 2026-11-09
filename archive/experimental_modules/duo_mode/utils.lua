--[[
    Resident Evil 2: Duo Mode
    utils.lua - Robust RE Engine IL2CPP Reflection and Math Helpers
    Author: AryanTechie-007
]]

local utils = {}

-- Safely resolve and retrieve a component from a GameObject
-- Handles runtime type extraction and guards against System.ArgumentNullException
function utils.get_component(game_obj, type_name)
    if not game_obj then return nil end

    -- Check if REFramework GameObject exposes native get_component
    if game_obj.get_component then
        local ok, comp = pcall(function() return game_obj:get_component(type_name) end)
        if ok and comp then return comp end
    end

    if not game_obj.call then return nil end

    local td = sdk.find_type_definition(type_name)
    if not td then return nil end

    local rt = nil
    pcall(function() rt = td:get_runtime_type() end)
    if not rt then return nil end

    local comp = nil
    pcall(function()
        comp = game_obj:call("getComponent(System.Type)", rt)
    end)
    return comp
end

-- Safely retrieve Euler Yaw (radians) from a via.Transform or Quaternion
-- Supports via.Transform:get_EulerAngles(), get_EulerAngle(), and raw Quaternion (x,y,z,w) math
function utils.get_transform_yaw(transform)
    if not transform then return 0.0 end

    -- 1. If passed an object with .call (such as via.Transform)
    if transform.call then
        -- Try via.Transform:get_EulerAngles()
        local ok1, euler1 = pcall(function() return transform:call("get_EulerAngles") end)
        if ok1 and euler1 and euler1.y and not (euler1.y ~= euler1.y) then
            return euler1.y
        end

        -- Try via.Transform:get_EulerAngle()
        local ok2, euler2 = pcall(function() return transform:call("get_EulerAngle") end)
        if ok2 and euler2 and euler2.y and not (euler2.y ~= euler2.y) then
            return euler2.y
        end

        -- Try via.Transform:get_Rotation() which returns Quaternion struct {x, y, z, w}
        local ok3, rot = pcall(function() return transform:call("get_Rotation") end)
        if ok3 and rot then
            return utils.quaternion_to_yaw(rot)
        end
    end

    -- 2. If directly passed a Quaternion or Euler table
    if type(transform) == "table" or type(transform) == "userdata" then
        if transform.y and not transform.w then
            return transform.y
        elseif transform.w then
            return utils.quaternion_to_yaw(transform)
        end
    end

    return 0.0
end

-- Converts a Quaternion struct {x, y, z, w} to Euler Yaw (rotation around Y-axis)
function utils.quaternion_to_yaw(q)
    if not q then return 0.0 end
    local x = q.x or 0.0
    local y = q.y or 0.0
    local z = q.z or 0.0
    local w = q.w or 1.0

    -- Standard Y-up yaw formula: atan2(2(wy + xz), 1 - 2(y^2 + z^2))
    local siny_cosp = 2.0 * (w * y + x * z)
    local cosy_cosp = 1.0 - 2.0 * (y * y + z * z)
    local yaw = math.atan(siny_cosp, cosy_cosp)
    if yaw ~= yaw then return 0.0 end -- NaN check
    return yaw
end

-- Safely destroy or deactivate a GameObject without throwing argument count errors
function utils.destroy_game_object(game_obj)
    if not game_obj then return end

    -- Immediately hide and freeze the object
    pcall(function()
        if game_obj.call then
            pcall(function() game_obj:call("set_DrawSelf", false) end)
            pcall(function() game_obj:call("set_UpdateSelf", false) end)
        end
    end)

    -- Try via.Scene:destroyGameObject(via.GameObject)
    pcall(function()
        local scene_man = sdk.get_native_singleton("via.SceneManager")
        local cur_scene = scene_man and scene_man:call("get_CurrentScene")
        if cur_scene then
            local ok = pcall(function() cur_scene:call("destroyGameObject(via.GameObject)", game_obj) end)
            if not ok then
                pcall(function() cur_scene:call("destroyGameObject", game_obj) end)
            end
        end
    end)

    -- Try static via.GameObject.destroy(via.GameObject)
    pcall(function()
        local go_td = sdk.find_type_definition("via.GameObject")
        if go_td then
            local destroy_m = go_td:get_method("destroy(via.GameObject)")
            if destroy_m then
                destroy_m:call(nil, game_obj)
            end
        end
    end)
end

return utils
