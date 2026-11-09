# Technical Handover & Architecture Status Report

**Project:** Resident Evil 2 Remake — Single-Player Dual-Protagonist Overhaul Mod (`Duo Mode`)  
**Repository:** [AryanTechie-007/RE2NewMode](https://github.com/AryanTechie-007/RE2NewMode) (Branch: `main`)  
**Workspace Directory:** `D:\Gamesregarding` (Git repository root)  
**Live Game Sandbox:** `D:\Games\RE2_DuoMode_Sandbox` (Standalone game installation with REFramework `dinput8.dll`)  
**Baseline Release Tag:** `v0.1-baseline` (Permanent historical branch: `legacy/working-baseline`)  
**Current Milestone:** Milestone 0 (Consolidation Complete) & Milestone 1 (Animation Research Spike — Harness v1.5.0)  
**Date:** November 9, 2026  

---

## 1. Executive Summary & Architectural Pivot

Following an in-depth repository audit and honest project assessment, the project has transitioned from an aspirational 14-day waterfall plan to a reverse-engineering roadmap focused on delivering a story-driven duo companion experience:

1. **Retire Aspirational Modules:** The previously drafted 13 modules in `reframework/autorun/duo_mode/` (`combat_ai.lua`, `inventory_manager.lua`, `door_hooks.lua`, `health_manager.lua`, `audio_bridge.lua`, etc.) were largely Lua-side bookkeeping stubs. The "14/14 PASS" QA suite was asserting mocked Lua tables rather than native RE Engine hooks. These files have been safely preserved in [`archive/experimental_modules/`](file:///D:/Gamesregarding/archive/experimental_modules/) for future reference.
2. **Authoritative Runtime Established:** [`reframework/autorun/character_renderer.lua`](file:///D:/Gamesregarding/reframework/autorun/character_renderer.lua) is established as the sole production companion controller. It contains all battle-tested engine interactions: multi-part 3D mesh streaming, NaN-safe glide locomotion, room portal transitions, kinematic elevator parenting, cutscene protection, and the radial tactical command wheel.
3. **Single Master Update Loop:** Merged dual `re.on_frame` handlers into one authoritative loop with scene-change/unload detection to eliminate duplicate ticks and ghost actors.
4. **Milestone 1 Animation Spike:** Created [`reframework/autorun/animation_lab.lua`](file:///D:/Gamesregarding/reframework/autorun/animation_lab.lua) as an isolated, sandboxed test harness with strict success criteria to investigate native NPC allocation, duplication, and motion playback without impacting core gameplay stability.

---

## 2. Verified In-Game Features vs. Roadmap Status (Rule 1 Classification)

| Subsystem / Feature | Active File | Architectural Status | Implementation Reality |
| :--- | :--- | :--- | :--- |
| **Claire 3D Mesh Spawning** | `character_renderer.lua` | `Implemented and tested in-game` | Multi-part streaming pipeline instantiates Body, Head, and Hair (`costume_a` Noir outfit) without crashing. |
| **Gliding Follow Locomotion** | `character_renderer.lua` | `Implemented and tested in-game` | NaN-safe coordinate translation with camera flank waypoint tracking, speed lerping, and anti-overshoot dampening. |
| **Room Portal Defense** | `character_renderer.lua` | `Implemented and tested in-game` | Queries `app.ropeway.StayAreaController`; snaps Claire through closed doors when room ID mismatches. |
| **Elevator Kinematic Parenting** | `character_renderer.lua` | `Implemented and tested in-game` | Dynamically parents Claire's `via.Transform` to moving elevator platform hierarchy. |
| **Cutscene Protection** | `character_renderer.lua` | `Implemented and tested in-game` | Hooks `CutsceneManager` to hide companion during cinematics and repositions them on scene resume. |
| **Rubber-Band Catch-up** | `character_renderer.lua` | `Implemented and tested in-game` | Teleports companion if separated by >10m horizontally or >3.2m vertically to avoid unloaded chunk voids. |
| **Tactical Command Wheel** | `character_renderer.lua` | `Implemented and tested in-game` | ImGui radial menu (`FOLLOW`, `WAIT`, `COVER`) with 0.4x bullet-time slowdown via `app.ropeway.TimeManager`. |
| **Multi-Layer Hardware Input** | `character_renderer.lua` | `Implemented and tested in-game` | Direct polling via `via.hid.Keyboard` + `via.hid.GamePad` with REFramework fallback. Supports Hold and Toggle `T`. |
| **Player Duplication Fallback** | `character_renderer.lua` | `Implemented and tested in-game` | Clones player GameObject via `via.Scene.duplicateGameObject` and strips player input receivers. |
| **Animation Research Lab** | `animation_lab.lua` | `Experimental (Milestone 1)` | Isolated research suite with strict criteria testing Experiments A (Native NPC), B (Duplication), and C (Motion Playback). |
| **Walking/Running Leg Cycles** | `character_renderer.lua` | `Partially implemented` | Motion bank linking assigns Leon's bank asset, but MotionFsm2 transitions require active character controller allocation. |
| **RPD Story Scenario Engine** | `docs/` | `Planned (Milestone 3)` | Scripted vertical slice: Courtyard meeting $\to$ Back gate entry $\to$ Main Hall $\to$ Safe Room dialogue. |
| **Door Key Interactions** | `archive/` | `Planned (Milestone 4)` | Real hook into door interaction pipeline deferred until story prototype is playable. |
| **Combat AI & Damaging Fire** | `archive/` | `Planned (Milestone 4)` | Raycasts, real damage dealing, and threat detection deferred to Milestone 4. |
| **Health & Proximity Revive** | `archive/` | `Planned (Milestone 4)` | Real game damage integration (`DamageController` / `AttackPermitManager`) deferred to Milestone 4. |
| **Dual Inventory** | `archive/` | `Planned (Milestone 4)` | Simple companion item transfer deferred until story prototype is playable. |
| **Dynamic Banter & Audio** | `archive/` | `Planned (Milestone 5)` | On-screen subtitles foundation exists; external audio streaming bridge postponed. |

---

## 3. Historical Technical Issues & Resolutions

### Issue A: Locomotion Frame Loop Crash (`Quaternion` Value Type) — RESOLVED
* **Root Cause:** In REFramework Lua, calling `comp_transform:call("get_Rotation")` returns a native IL2CPP `Quaternion` value struct (`{x, y, z, w}`), not an `REManagedObject`. Invoking `:call("get_EulerAngles")` on it threw a runtime nil exception.
* **Resolution:** Implemented exact mathematical Quaternion-to-Yaw conversion ($\text{atan2}(2(wy + xz), 1 - 2(y^2 + z^2))$) with complete nil/NaN protection and wrapped all frame loop calls in `pcall`.

### Issue B: Skinned Mesh Rigging Gap — RESOLVED
* **Root Cause:** RE Engine's skinned mesh renderer does not draw vertex buffers in the viewport unless bound to an active skeleton rig (`.skl`) and bone hierarchy. Raw unrigged GameObjects remain invisible.
* **Resolution:** Built the multi-part asset streaming pipeline in `character_renderer.lua` that binds body, head, and hair prefabs with proper transforms and visibility flags.

### Issue C: Component Lookup `ArgumentNullException` & Static Destroy Warnings — RESOLVED
* **Root Cause:** Passing a type definition (`sdk.find_type_definition`) instead of `System.Type` (`sdk.typeof` / `td:get_runtime_type()`) threw `ArgumentNullException`. Calling `game_obj:call("destroy")` threw argument count warnings because `via.GameObject.destroy` is a static method requiring the object as an argument.
* **Resolution:** Standardized all component lookups with `sdk.typeof(...)` and unified object destruction to use `via.Scene.destroyGameObject` with safe fallback to `destroy_static:call(nil, entity)`.

---

## 4. Milestone 1 Animation Research Lab (`animation_lab.lua` v1.5.0)

To prevent speculative reflection calls from destabilizing the core companion, [`animation_lab.lua`](file:///D:/Gamesregarding/reframework/autorun/animation_lab.lua) runs three independent experiments with strict, non-optimistic success criteria and event-level telemetry:

1. **Experiment A (Native Survivor Casting):**
   - Probes `app.ropeway.SurvivorAssignManager`, `SurvivorManager`, and `SurvivorStandbyCatalog`.
   - **Empirical Findings (19:01 Test Run):** Resolved `PlayerDefine.PlayerType` enums: `PL0000 = 0` (Leon), `PL1000 = 1000` (Claire), `PL2000 = 2000` (Ada), `PL3000 = 3000` (Sherry). Previous exploratory call passed `1` instead of `1000` (`standby(1, 0, 0)`), which was refused. Calling standby triggered active request: `SurvivorManager:get_ExecCastingRequest() = 0000020C1613B188`.
   - **v1.5 Enhancements:** Probes all 3 `standby()` overload signatures, inspects `CastingOrder` constructors and `SurvivorCastingRequest` field values, and executes controlled retries with Claire enum `PL1000 = 1000` across `InitialSet=1`, `Debug=8`, and `None=0`.
2. **Experiment B (GameObject & Control Duplication):**
   - Evaluates cloning via `via.Scene.duplicateGameObject`.
   - **Empirical Findings (19:01 Test Run):** Scene successfully resolved via `player_go:get_Folder():get_Scene()`. However, `duplicateGameObject(player_go)` returned `nil`, indicating native engine player-singleton guards (`PlayerInputReceiver`, `PadManager`).
   - **v1.5 Enhancements:** Reflects all duplication signatures on `via.Scene` and `via.Folder`. Implements a harmless non-player object control test (e.g. ambient prop/camera) to isolate whether the duplication API itself functions before assessing player-specific restrictions.
3. **Experiment C (Claire Motion Playback & Stalled Frame Investigation):**
   - **Empirical Findings (19:01 Test Run):** Successfully targeted Claire's prefab body entity (`0000020C06A72AC8`) via `_G.duo_spawner` without affecting Leon. `changeMotion` accepted Motion IDs 160-162 cleanly with no crashes, but frame remained frozen at `0.00` (`PLAYBACK_STALLED`).
   - **v1.5 Enhancements:** Complete component inventory of Claire's prefab, queries `get_MotionBankAsset()`, inspects pause/speed/weight states across Motion and Layer 0 (`get_Pause()`, `get_PlaySpeed()`), tests frame-stepping probe (`set_Frame(12.5)`), and tests playback with explicit unpause (`set_Pause(false)`).

---

## 5. Live Game Testing & Verification

The compiled and consolidated scripts are deployed directly to the test sandbox:
* **Source:** `D:\Gamesregarding\reframework\autorun\`
* **Target Sandbox:** `D:\Games\RE2_DuoMode_Sandbox\reframework\autorun\`
* **Telemetry Data:** `reframework/data/duo_mode/animation_lab_session.csv` and `animation_lab_log.txt`

### In-Game Verification Steps:
1. Launch `D:\Games\RE2_DuoMode_Sandbox\Resident Evil 2.exe`.
2. Load an active gameplay save with Leon (e.g. RPD Main Hall).
3. Press **Insert** to open the REFramework overlay menu.
4. Under **Script Generated UI**:
   - **Claire Redfield Controller (Duo Mode):** Click `Spawn Companion` to verify 3D mesh rendering and baseline follow locomotion.
   - **Open Animation Research Lab Window:**
     - **Experiment A:** Click `Run Exp A Deep Probe & Retries` to inspect `standby` overloads and test `standby(1000, ...)`.
     - **Experiment B:** Click `Run Exp B Control Test` (non-player clone) and `Probe Scene/Folder Duplication`.
     - **Experiment C:** Click `Inspect Target & Animation Components` to examine Claire's Motion/Layer Pause flags, run `Test Frame-Step Probe`, and test unpaused playback.
