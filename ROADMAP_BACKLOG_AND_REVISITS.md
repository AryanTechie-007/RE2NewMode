# RE2 Duo Mode — Development Backlog & Revisit Items

**Repository:** `https://github.com/AryanTechie-007/RE2NewMode`  
**Current Milestone:** Day 4: Companion Command FSM & Tactical Radial Wheel  
**Last Updated:** October 26, 2026  

---

## 📌 Items Scheduled for Revisit

The following technical items have been deferred during Phase 1 to prioritize core gameplay stability, player agency, and the interactive command loop:

### 1. Character Locomotion Animation (Walking / Running Leg Cycles)
* **Current Status:**
  - Claire utilizes smooth coordinate gliding (`move_transform_safely`) with speed lerping, camera flank waypoint tracking, and anti-overshoot dampening.
  - Skinned mesh rendering, material shaders, facial blendshapes, eye tracking, and dynamic clothing physics (`SurvivorChainController`, tie/cloth physics) are 100% active and verified in-game.
* **Why Deferred:**
  - Instantiating raw costume `.pfb` prefabs provides visual rendering and skeleton hierarchy, but does not allocate an active character motion state machine (`via.motion.Motion` / `MotionFsm2`).
  - Calling low-level `via.motion.TreeLayer.changeMotion` directly on an unconfigured prefab threw an internal RE Engine C++ exception (`KiUserExceptionDispatcher`).
* **Revisit Action Plan:**
  - Implement full character casting through `app.ropeway.SurvivorAssignManager` (`CastType.Npc`) or explore cloning the active survivor entity (`via.Scene.duplicateGameObject`) with hardware input stripping to inherit the engine's pre-allocated blend trees and root-motion graphs.
  - Bind locomotion FSM states (`FOLLOW`, `WAIT`, `COVER`) to stride frequency and stance animations.

---

### 2. Costume Swapping & Classic Red Jacket Assembly
* **Current Status:**
  - Claire currently spawns in `costume_a` (Noir DLC Outfit — white shirt, black trousers, suspenders, tie).
  - This outfit was selected because it is a self-contained, single-piece skinned body mesh (`MeshNum > 0`), ensuring reliable rendering without missing limbs.
* **Why Deferred:**
  - In *Resident Evil 2 Remake*, the iconic Red Jacket (`pl1000_body_costume_0.pfb` and `costume_1.pfb`) is designed by Capcom as an empty root container (`MeshNum = 0`) that dynamically attaches modular child meshes via `SurvivorMeshPartsController`. Spawning the root alone leaves only the knife sheath on the floor.
* **Revisit Action Plan:**
  - Build a modular child parts assembler utilizing `SurvivorMeshPartsController` to load and bind all individual clothing pieces (Red Jacket, undershirt, holster, boots, belt).
  - Add an in-game ImGui dropdown menu allowing the player to swap between **Classic Red Jacket** and **Noir Detective** outfits at will.

---

### 3. Room & Safe Room Friendly Name Telemetry
* **Current Status:**
  - Continuous telemetry runs every frame via `re.on_frame` querying `app.ropeway.StayAreaController`.
  - Rubber-band distance ($> 10\text{ m}$) and vertical elevation separation ($|dy| > 3.2\text{ m}$) catch-up teleports are operational.
* **Revisit Action Plan:**
  - Build a lookup table mapping internal area/room numbers to human-readable names (e.g., `Area 101` $\to$ `"RPD Main Hall"`, `Area 104` $\to$ `"West Office"`, `Area 107` $\to$ `"Dark Room (Safe Room)"`).
  - Hook safe room triggers directly to the Day 10 dynamic banter engine.

---

### 4. Input Conflict Resolution: Camera Reset vs. Command Wheel
* **Identified Conflict:**
  - In RE2 Remake on PC, `Middle Mouse Button` (`VK_MBUTTON / 0x04`) natively triggers **Reset Camera View / Center Camera**.
  - Using Middle Mouse Button for the Command Wheel causes the camera to violently snap center whenever the player tries to issue an order.
* **Resolution in Day 4:**
  - Rebind default Command Wheel key to **`T`** (`0x54`, "Tactical / Team Orders").
  - Provide alternative selectable keybinds in the settings UI:
    * `T` (Default, no native conflict)
    * `G` (Guard / Commands)
    * `Q` (Quick Command)
    * `Caps Lock`
    * `Mouse 4 / Mouse 5` (Side thumb buttons)
    * `RB / R1` (Gamepad default)
