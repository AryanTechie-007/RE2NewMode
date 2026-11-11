# Technical Handover & Architecture Status Report

**Project:** Resident Evil 2 Remake — Single-Player Dual-Protagonist Overhaul Mod (`Duo Mode`)  
**Repository:** [AryanTechie-007/RE2NewMode](https://github.com/AryanTechie-007/RE2NewMode) (Branch: `main`)  
**Workspace Directory:** `D:\Gamesregarding` (Git repository root)  
**Live Game Sandbox:** `D:\Games\RE2_DuoMode_Sandbox` (Standalone game installation with REFramework `dinput8.dll`)  
**Baseline Release Tag:** `v0.1-baseline` (Permanent historical branch: `legacy/working-baseline`)  
**Current Milestone:** Milestone 0 (Consolidation Complete) & Milestone 1 (Animation Research Spike — Harness v1.5.1 Safety Edition)  
**Date:** November 11, 2026  

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

## 4. Milestone 1 Animation Research Lab (`animation_lab.lua` v1.5.1 Safety Edition)

To prevent speculative reflection calls from destabilizing the core companion, [`animation_lab.lua`](file:///D:/Gamesregarding/reframework/autorun/animation_lab.lua) runs three independent experiments with strict, non-optimistic success criteria, event-level telemetry, and safety barriers:

1. **Experiment A (Native Survivor Casting):**
   - Probes `app.ropeway.SurvivorAssignManager`, `SurvivorManager`, and `SurvivorStandbyCatalog`.
   - **v1.5.1 Safety Architecture:**
     - **Separation of Concerns:** Passive reflection (`lab.run_experiment_a_reflect`) is completely separated from casting invocation (`lab.run_experiment_a_cast`). Reflection discovers types, singletons, fields, and method signatures without invoking `standby` or `applyCastingRequest`.
     - **Explicit Controlled Invocation:** User explicitly selects `PlayerType` (Claire `1000`, Leon `0`, Ada `2000`), `CastingReason` (InitialSet `1`, Debug `8`, None `0`), and `OfferMode` (Normal `0`). Invokes exactly one call per click.
     - **Scene Diffing & Companion Exclusion:** Snapshots all existing GameObject pointers before calling `standby`. Cross-checks post-call scene objects and categorically excludes any pre-existing pointer or entity in `_G.duo_spawner`. Never reports PASS on an existing Claire object.
     - **Optional Apply Trigger:** `SurvivorManager:applyCastingRequest()` is an independent, user-triggered action.
2. **Experiment B (GameObject & Control Duplication):**
   - Evaluates cloning via `via.Scene.duplicateGameObject`.
   - **v1.5.1 Safety Architecture:**
     - **Inert Static Prop Target:** Strictly forbids targeting Claire, player, or camera entities. Scans active scene chunk for verified inert static props (e.g. `sm00_...` static meshes with only `via.Transform` and `via.render.Mesh`, lacking all camera, light, input, and player components).
     - **Pre-Established Identity & Cleanup Route:** Identifies target name, pointer, and verifies `destroyGameObject` capability before attempting duplication.
     - **Strict Sequential Cleanup:** Strictly invokes one destruction route at a time (Route 1: `cur_scene:destroyGameObject`). Queries `get_Valid() == false` before attempting fallback (Route 2: static `via.GameObject.destroy`). Never invokes Route 2 if Route 1 succeeded, and never reports success until `get_Valid() == false` is confirmed.
3. **Experiment C (Claire Motion Playback & Stalled Frame Investigation):**
   - Investigates why prefab motion stalled at frame 0.00.
   - **v1.5.1 Safety Architecture:**
     - **Snapshot & Restoration:** Full snapshot of all original Motion and Layer 0 parameters (`Play`, `Pause`, `Speed`, `Weight`, `Frame`, `MotionID`, `BankID`, `MotionBankAsset`) before any mutation. Safe restoration (`lab.restore_experiment_c_state`) is automatically executed upon test completion, exception, or via manual UI button.
     - **Capability Reflection:** Audits setter availability (`set_Play`, `set_Pause`, `set_Speed`, `set_Weight`, `set_Frame`) before attempting invocation.
     - **No Silent Bank Substitution:** Inspects Claire's native `MotionBankAsset`. If nil, playback is cleanly blocked unless the user explicitly checks `Allow Cross-Bank Assignment` in the UI.
     - **Three-Tier Verification Criteria:**
       - **Tier 1 (Frame-Step Acceptance):** Probes whether `set_Frame(12.5)` mutates memory timeline float and immediately restores original frame (`FRAME_STEP_ACCEPTED` vs `FRAME_STEP_REJECTED`).
       - **Tier 2 (Frame Progression):** Monitors timeline progression over 45 game frames (`FRAME_PROGRESSION_VERIFIED` vs `PLAYBACK_STALLED`).
       - **Tier 3 (Viewport Visual Confirmation):** Viewport operator confirmation checkbox (`PLAYBACK_AND_VISUAL_VERIFIED`).

---

## 5. Live Game Testing & Verification

The compiled and consolidated scripts are deployed directly to the test sandbox:
* **Source:** `D:\Gamesregarding\reframework\autorun\`
* **Target Sandbox:** `D:\Games\RE2_DuoMode_Sandbox\reframework\autorun\`
* **Telemetry Data:** `reframework/data/duo_mode/animation_lab_session_v151.csv` and `animation_lab_log.txt`

### In-Game Safe Test Execution Order:
1. Launch `D:\Games\RE2_DuoMode_Sandbox\Resident Evil 2.exe`.
2. Load an active gameplay save with Leon (e.g. RPD Main Hall).
3. Press **Insert** to open the REFramework overlay menu.
4. Under **Script Generated UI**:
   - **Open Animation Research Lab Window:**
     - **Phase 1 (Completely Safe / Passive):**
       1. Tab 2 (Exp A): Click `Step 1: Run Passive Reflection Probe (SAFE)`.
       2. Tab 4 (Exp C): Click `1. Inspect Target & Original Animation Settings`.
     - **Phase 2 (Harmless Single Probes):**
       3. Tab 3 (Exp B): Click `1. Run Control Test (Inert Static Prop)`. Checks if inert prop duplication and sequential cleanup succeed.
       4. Tab 4 (Exp C): Click `Run Frame-Step Probe (Test set_Frame 12.5 & Auto-Restore)`.
     - **Phase 3 (Controlled Companion Playback):**
       5. Under quick bridge: Click `Spawn Claire in Front of Leon` (using M0 baseline spawner).
       6. Tab 4 (Exp C): Click `1. Inspect Target` (locks onto Claire Prefab Body).
       7. If Claire native bank is nil and you wish to test Leon's bank asset, check `Allow Cross-Bank Assignment`.
       8. Click `Play Stance / Idle (ID 160)` and observe 45-frame progression. If motion visually plays in viewport, check `Visual Animation Confirmed`.
       9. Click `Restore Original Animation Settings` when finished.
     - **Phase 4 (Explicit Casting & Duplication Tests):**
       10. Tab 2 (Exp A): Select PL1000 (Claire) + InitialSet (1) + Normal (0), then click `Execute Single Controlled Standby Call`.
       11. Tab 3 (Exp B): Click `2. Spawn Duplicate Player Actor` (optional, tested only if control test succeeds). Click `Destroy Test Clone` immediately after.
