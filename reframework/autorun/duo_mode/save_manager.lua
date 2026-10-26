--[[
    Resident Evil 2: Duo Mode
    save_manager.lua - Day 13: ScenarioManager Serialization & Multi-Slot Save Persistence
    Author: AryanTechie-007
]]

local config = require("duo_mode/config")
local inventory_manager = require("duo_mode/inventory_manager")
local health_manager = require("duo_mode/health_manager")
local fsm = require("duo_mode/fsm")

local save_manager = {}

local function log_msg(msg)
    if config.log_verbose then
        if log and log.info then
            log.info("[DuoMode:Save] " .. tostring(msg))
        end
        local f = io.open("reframework/data/duo_mode/test_log.txt", "a")
        if f then
            f:write(os.date("[%Y-%m-%d %H:%M:%S] [DuoMode:Save] ") .. tostring(msg) .. "\n")
            f:close()
        end
    end
end

-- Resolve isolated save file path for given native slot ID
function save_manager.get_save_path(slot_id)
    if slot_id == 99 then
        return "reframework/data/duo_mode/save_state_scenario_transition.json"
    end
    return string.format("reframework/data/duo_mode/save_state_slot_%02d.json", slot_id or 1)
end

-- Encode table to JSON string
local function json_encode(tbl)
    if json and json.dump_string then
        return json.dump_string(tbl)
    end
    -- Lightweight JSON serializer fallback
    local parts = {}
    table.insert(parts, "{")
    local first = true
    for k, v in pairs(tbl) do
        if not first then table.insert(parts, ",") end
        first = false
        if type(v) == "table" then
            table.insert(parts, string.format('"%s":%s', tostring(k), json_encode(v)))
        elseif type(v) == "number" then
            table.insert(parts, string.format('"%s":%s', tostring(k), tostring(v)))
        elseif type(v) == "boolean" then
            table.insert(parts, string.format('"%s":%s', tostring(k), v and "true" or "false"))
        else
            table.insert(parts, string.format('"%s":"%s"', tostring(k), tostring(v):gsub('"', '\\"')))
        end
    end
    table.insert(parts, "}")
    return table.concat(parts)
end

-- Decode JSON string to table
local function json_decode(str)
    if not str or str == "" then return nil end
    if json and json.load_string then
        return json.load_string(str)
    end
    -- Fallback regex parser for critical values
    local data = {}
    local hp = str:match('"hp":%s*(%d+)')
    if hp then data.hp = tonumber(hp) end
    local state = str:match('"state":%s*(%d+)')
    if state then data.state = tonumber(state) end
    return data
end

-- Serialize live companion state to disk
function save_manager.save_slot(slot_id)
    slot_id = slot_id or 1
    local path = save_manager.get_save_path(slot_id)
    log_msg(string.format("Saving companion state to slot %02d (%s)...", slot_id, path))

    local slots_data = {}
    for i = 1, 8 do
        local slot = inventory_manager.companion_slots[i]
        if slot and slot.item_id > 0 then
            table.insert(slots_data, {
                slot = i,
                id = slot.item_id,
                count = slot.count,
                name = slot.name
            })
        end
    end

    local payload = {
        slot_id = slot_id,
        saved_at = os.date("%Y-%m-%d %H:%M:%S"),
        hp = health_manager.current_hp,
        max_hp = health_manager.max_hp,
        state = fsm.current_state,
        inventory = slots_data
    }

    local serialized = json_encode(payload)
    local f = io.open(path, "w")
    if f then
        f:write(serialized)
        f:close()
        log_msg(string.format("SUCCESS: Companion state persisted to slot %02d.", slot_id))
        return true
    else
        log_msg(string.format("ERROR: Failed to write save file: %s", path))
        return false
    end
end

-- Deserialize companion state from disk
function save_manager.load_slot(slot_id)
    slot_id = slot_id or 1
    local path = save_manager.get_save_path(slot_id)
    log_msg(string.format("Loading companion state from slot %02d (%s)...", slot_id, path))

    local f = io.open(path, "r")
    if not f then
        log_msg(string.format("No save file found for slot %02d. Using active default state.", slot_id))
        return false
    end

    local content = f:read("*a")
    f:close()

    local data = json_decode(content)
    if not data then
        log_msg(string.format("ERROR: Could not parse save file %s.", path))
        return false
    end

    -- Restore Health
    if data.hp then
        health_manager.current_hp = data.hp
        health_manager.is_downed = (data.hp <= 0)
    end

    -- Restore FSM State
    if data.state then
        fsm.set_state(data.state)
    end

    -- Restore Inventory
    if data.inventory and type(data.inventory) == "table" then
        for i = 1, 8 do inventory_manager.remove_item(i) end
        for _, item in ipairs(data.inventory) do
            if item.id and item.count then
                inventory_manager.companion_slots[item.slot or 1] = {
                    item_id = item.id,
                    count = item.count,
                    name = item.name or "Item"
                }
            end
        end
    end

    log_msg(string.format("SUCCESS: Companion state restored from slot %02d (HP: %d).", slot_id, health_manager.current_hp))
    return true
end

-- Save state specifically for Cross-Campaign Boss Climax Transition
function save_manager.save_scenario_transition()
    log_msg("Saving state for Cross-Campaign Super Tyrant -> G4 scenario jump...")
    return save_manager.save_slot(99)
end

-- Load state after Cross-Campaign stage re-init
function save_manager.load_scenario_transition()
    log_msg("Restoring state after Cross-Campaign transition...")
    return save_manager.load_slot(99)
end

return save_manager
