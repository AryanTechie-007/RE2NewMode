--[[
    Resident Evil 2: Duo Mode
    inventory_manager.lua - Day 6: Dual-Bag Inventory & Contextual "Hold This" Offloading
    Author: AryanTechie-007
]]

local config = require("duo_mode/config")

local inventory_manager = {}

-- 8-slot companion inventory structure
inventory_manager.companion_slots = {}
for i = 1, 8 do
    inventory_manager.companion_slots[i] = {
        item_id = 0,
        count = 0,
        name = "Empty"
    }
end

local function log_msg(msg)
    if config.log_verbose then
        if log and log.info then
            log.info("[DuoMode:Inv] " .. tostring(msg))
        end
        local f = io.open("reframework/data/duo_mode/test_log.txt", "a")
        if f then
            f:write(os.date("[%Y-%m-%d %H:%M:%S] [DuoMode:Inv] ") .. tostring(msg) .. "\n")
            f:close()
        end
    end
end

-- Find first empty slot in companion bag
function inventory_manager.get_first_empty_slot()
    for i = 1, 8 do
        if inventory_manager.companion_slots[i].item_id == 0 then
            return i
        end
    end
    return nil -- Bag full
end

-- Add item to companion bag
function inventory_manager.add_item(item_id, count, item_name)
    local slot = inventory_manager.get_first_empty_slot()
    if not slot then
        log_msg("Cannot add item: Companion bag is completely full (8/8 slots).")
        return false
    end

    inventory_manager.companion_slots[slot] = {
        item_id = item_id,
        count = count or 1,
        name = item_name or ("Item_" .. tostring(item_id))
    }
    log_msg(string.format("Item added to companion slot %d: %s (Count: %d)", slot, inventory_manager.companion_slots[slot].name, count or 1))
    return true
end

-- Remove item from companion bag
function inventory_manager.remove_item(slot_index)
    if slot_index < 1 or slot_index > 8 then return false end
    inventory_manager.companion_slots[slot_index] = {
        item_id = 0,
        count = 0,
        name = "Empty"
    }
    return true
end

-- Check if companion has a specific item
function inventory_manager.has_item(item_id)
    for i = 1, 8 do
        if inventory_manager.companion_slots[i].item_id == item_id then
            return true, i
        end
    end
    return false, nil
end

-- Draw Docked Dual-Bag ImGui Menu when native inventory is open
function inventory_manager.draw_ui()
    local is_inv_open = false
    pcall(function()
        local inv_menu = sdk.get_managed_singleton("app.ropeway.survivor.InventoryMenu")
        if inv_menu then
            is_inv_open = inv_menu:call("isOpen") or false
        end
    end)

    -- Also show if debug mode is active
    if not is_inv_open and not config.debug_mode then return end

    local viewport = imgui.get_main_viewport()
    local win_pos = Vector2f.new(viewport.Size.x - 360, 120)
    imgui.set_next_window_pos(win_pos, 1, Vector2f.new(0, 0))
    imgui.set_next_window_size(Vector2f.new(340, 420), 1)

    if imgui.begin_window("Partner Inventory", nil, 1 | 2 | 32) then -- NoTitleBar, NoResize, AutoResize
        imgui.text_colored("COMPANION INVENTORY (8 SLOTS)", 0.2, 0.9, 1.0, 1.0)
        imgui.separator()
        imgui.spacing()

        for i = 1, 8 do
            local slot = inventory_manager.companion_slots[i]
            local label = string.format("[%d] %s", i, slot.name)
            if slot.item_id ~= 0 then
                label = label .. string.format(" (x%d)", slot.count)
                imgui.text_colored(label, 1.0, 1.0, 0.4, 1.0)
                imgui.same_line()
                if imgui.button("Take##" .. i) then
                    log_msg("Player took item from companion: " .. slot.name)
                    inventory_manager.remove_item(i)
                end
            else
                imgui.text_colored(label, 0.5, 0.5, 0.5, 1.0)
            end
        end

        imgui.spacing()
        imgui.separator()
        if imgui.button("Test: Give Handgun Ammo (x30)") then
            inventory_manager.add_item(1001, 30, "Handgun Ammo")
        end
        imgui.same_line()
        if imgui.button("Clear Bag") then
            for i = 1, 8 do inventory_manager.remove_item(i) end
        end

        imgui.end_window()
    end
end

return inventory_manager
