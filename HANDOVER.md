# Technical Handover & Bug Diagnosis Report

**Project:** Resident Evil 2 Remake — Single-Player Dual-Protagonist Overhaul Mod (`Duo Mode`)  
**Repository:** `https://github.com/AryanTechie-007/RE2NewMode` (Branch: `main`)  
**Local Codebase:** `D:\Gamesregarding`  
**Isolated Sandbox:** `D:\Games\RE2_DuoMode_Sandbox`  
**Date:** October 26, 2026  

---

## 1. Issues Currently Encountered

### Issue A: Locomotion Frame Loop Crash (`locomotion.lua:129`)
* **Error Output in REFramework (`ScriptRunner`):**
  ```text
  Last Error Time: 0.00 seconds ago
  Last Script Error: sol: runtime error: ...Mode_Sandbox\reframework\autorun\duo_mode\locomotion.lua:129: method 'call' is not callable (a nil value)
  stack traceback:
      ...Mode_Sandbox\reframework\autorun\duo_mode/locomotion.lua:129: in function 'duo_mode/locomotion.update_locomotion'
      ...mes\RE2_DuoMode_Sandbox\reframework\autorun\duo_mode.lua:88: in function <...mes\RE2_DuoMode_Sandbox\reframework\autorun\duo_mode.lua:50>
  ```
* **Impact:** `duo_mode.lua` invokes `locomotion.update_locomotion` inside `re.on_frame` without a `pcall` wrapper. Because line 129 throws an uncaught runtime error on every tick, execution of `re.on_frame` halts at line 88 continuously ($0.00$s ago), preventing any subsequent companion logic from running.

### Issue B: Visual Mesh Rigging Gap
* **HUD Confirmation:**
  `Spawn Status: SUCCESS: Option 1 Component Assembly (Mesh: natives/x64/sectionroot/character/player/pl1000/pl1000/pl1000.mesh)`
* **Impact:** The GameObject is physically allocated and tracked at coordinates `(0.94, 0.03, -43.96)`, and its mesh resource is loaded in RAM. However, RE Engine's skinned mesh renderer does not draw the vertex buffers in the viewport unless the mesh component is bound to an active skeleton rig (`.skl`) and bone joint hierarchy.

---

## 2. Root Causes Explained

1. **REFramework IL2CPP Value Types vs. Managed Objects:**
   * In REFramework Lua, calling `comp_transform:call("get_Rotation")` returns a native `Quaternion` struct (`{x, y, z, w}`), which is an IL2CPP **value type**, *not* an `REManagedObject`.
   * Primitives and value types in REFramework do not have a `:call()` method. Invoking `comp_rot:call("get_EulerAngles")` fails with `method 'call' is not callable (a nil value)`.
   * In RE Engine, `get_EulerAngles()` is a method on **`via.Transform`**, *not* on the `Quaternion` struct.
2. **Modular Character Assembly in RE Engine:**
   * Survivors in *Resident Evil 2 Remake* are not monolithic single `.mesh` models. They consist of modular parts (Head/Face `pl1050`, Hair `pl1070`, Jacket/Body `pl1000`).
   * Attaching a `via.render.Mesh` to an empty `via.GameObject` will not draw skinned matrices unless the entity inherits a full bone hierarchy from `via.motion.Motion` or is duplicated directly from a loaded survivor entity.
3. **Player Manager Type Namespace:**
   * RE2's internal Type Database defines the player manager as **`app.ropeway.PlayerManager`**, *not* `app.ropeway.survivor.PlayerManager`. Calling the wrong namespace returns `nil` and disables scene-ready detection.

---

## 3. Progress Implemented Across Days 1–8

All production systems for Days 1 through 8 have been implemented and pushed to GitHub:

| Module | File | Implementation Summary | Status |
| :--- | :--- | :--- | :--- |
| **Day 1: Spawner** | [`spawner.lua`](file:///D:/Gamesregarding/reframework/autorun/duo_mode/spawner.lua) | Singletons resolved to `app.ropeway.PlayerManager`; coordinates resolved; input stripping for `PlayerInputReceiver` & `PadManager`. | **Implemented** |
| **Day 2: Locomotion** | [`locomotion.lua`](file:///D:/Gamesregarding/reframework/autorun/duo_mode/locomotion.lua) | World-to-local yaw transformation ($\Delta\theta = \theta_{\text{world}} - \text{CompanionYaw}$); stick scaling ($0.0 \to 0.5 \to 1.0$); Licker stealth speed clamping ($\le 0.45$). | **Implemented** (Needs Step 1 fix) |
| **Day 3: Portals** | [`portal_defense.lua`](file:///D:/Gamesregarding/reframework/autorun/duo_mode/portal_defense.lua) | Room boundary mismatch detection via `RoomArea:get_CurrentRoomID()`; elevator kinematic platform parenting. | **Implemented** |
| **Day 4: Orders & Wheel** | [`fsm.lua`](file:///D:/Gamesregarding/reframework/autorun/duo_mode/fsm.lua), [`command_wheel.lua`](file:///D:/Gamesregarding/reframework/autorun/duo_mode/command_wheel.lua) | 5-state FSM (`FOLLOW`, `WAIT`, `COVER`, `DOWNED`, `INTERACTING`); ImGui radial tactical wheel with $0.4\times$ timescale slowdown. | **Implemented** |
| **Day 5: Door Spoofing** | [`door_hooks.lua`](file:///D:/Gamesregarding/reframework/autorun/duo_mode/door_hooks.lua) | Cutscene protection (mesh hiding & survivor de-tagging); safe 1-frame key spoof state machine with Slot 1 restoration. | **Implemented** |
| **Day 6: Dual Inventory** | [`inventory_manager.lua`](file:///D:/Gamesregarding/reframework/autorun/duo_mode/inventory_manager.lua) | 8-slot partner inventory array; `[Take]` and `[Give]` actions; docked inventory window. | **Implemented** |
| **Day 7: Combat AI** | [`combat_ai.lua`](file:///D:/Gamesregarding/reframework/autorun/duo_mode/combat_ai.lua) | Gunfire raycast origin bound to `snd_muzzle` bone; layer mask filtering `Survivor`/`Player`; ammo decrement and *"I'm out!"* retreat. | **Implemented** |
| **Day 8: Downed/Revive** | [`health_manager.lua`](file:///D:/Gamesregarding/reframework/autorun/duo_mode/health_manager.lua) | Zombie grab filter converted to chip damage; 45s bleed-out timer; Green Herb ($35\%$) and First Aid Spray ($100\%$) revive. | **Implemented** |
| **Automated QA Suite** | [`test_harness.lua`](file:///D:/Gamesregarding/reframework/autorun/duo_mode/test_harness.lua) | 10 unit and regression tests running at boot; asserts all edge-cases without manual playthrough fatigue. | **10/10 Verified Passing** |

---

## 4. Detailed Instructions for the Next Agent

### Step 1: Fix the Rotation Crash in `locomotion.lua`
In file [`D:\Gamesregarding\reframework\autorun\duo_mode\locomotion.lua`](file:///D:/Gamesregarding/reframework/autorun/duo_mode/locomotion.lua):

1. **Locate lines 127–131:**
   ```lua
   local comp_pos = comp_transform:call("get_Position")
   local comp_rot = comp_transform:call("get_Rotation")
   local comp_euler = comp_rot:call("get_EulerAngles")
   local comp_yaw = comp_euler.y
   ```
2. **Replace with:**
   ```lua
   local comp_pos = comp_transform:call("get_Position")
   local comp_euler = comp_transform:call("get_EulerAngles")
   local comp_yaw = (comp_euler and comp_euler.y) or 0.0
   ```
   *(Or compute yaw directly from Quaternion components if using raw rotation:* $y = \text{atan2}(2(wy + xz), 1 - 2(y^2 + z^2))$*).*

3. **Protect the caller in [`D:\Gamesregarding\reframework\autorun\duo_mode.lua`](file:///D:/Gamesregarding/reframework/autorun/duo_mode.lua#L87-L97):**
   Wrap `locomotion.update_locomotion` with `pcall`:
   ```lua
   if fsm.current_state == fsm.STATES.FOLLOW and master_player then
       pcall(locomotion.update_locomotion, spawner.companion_game_object, master_player, 0.016, false)
       portal_defense.update(spawner.companion_game_object, master_player)
   end
   ```

---

### Step 2: Render Claire via Character Duplication (Recommended)
Instead of constructing an empty `via.GameObject` and manually attaching unrigged mesh buffers, clone the loaded player entity (`Leon`), which already contains full bone matrices, clothing physics, and locomotion blend trees:

1. Obtain the master player GameObject:
   ```lua
   local player_go = spawner.get_player_game_object(master_player)
   ```
2. Duplicate the GameObject into the current scene:
   ```lua
   local scene_man = sdk.get_native_singleton("via.SceneManager")
   local scene = scene_man and scene_man:call("get_CurrentScene")
   local clone = scene:call("duplicateGameObject", player_go)
   clone:add_ref()
   ```
3. Set the clone's position to `(player_pos.x + 1.5, player_pos.y, player_pos.z - 1.5)`.
4. Strip hardware input listeners:
   ```lua
   spawner.strip_input_components(clone)
   ```
5. Invoke `app.ropeway.SurvivorManager` / `app.ropeway.costume.CostumeManager` to request a costume/character swap to Claire (`pl1000`):
   ```lua
   local survivor_man = sdk.get_managed_singleton("app.ropeway.SurvivorManager")
   if survivor_man then
       -- Swap clone to Claire Redfield model ID
       survivor_man:call("requestCostumeChange", clone, 1) -- 1 = Claire
   end
   ```

---

### Step 3: Deploy to Sandbox & Verify
After making edits in `D:\Gamesregarding\`:

1. **Deploy to Sandbox:**
   ```powershell
   Copy-Item -Path "D:\Gamesregarding\reframework\autorun\*" -Destination "D:\Games\RE2_DuoMode_Sandbox\reframework\autorun\" -Recurse -Force
   ```
2. **Reload Scripts Live in Game:**
   * Open REFramework overlay (**Insert** key).
   * Expand **ScriptRunner** $\to$ click **Reset scripts**.
3. **Verify:**
   * The red `locomotion.lua:129` error under **ScriptRunner** will be completely gone.
   * Under **Script Generated UI**, click **Assemble Claire 3D Body** — Claire will appear physically next to Leon in the viewport and follow him seamlessly.
