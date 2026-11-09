# Resident Evil 2: Duo Mode (Leon & Claire)

A single-player dual-protagonist companion mod for **Resident Evil 2 Remake (2019)** built on **REFramework** (Lua).

Duo Mode creates a story-driven companion experience where Claire accompanies Leon through the RPD and beyond. Rather than simulating a full independent co-op player with complex AI, the project prioritizes narrative cohesion, contextual character reactions, and reliable companion traversal across the game world.

---

## 🧭 Project Development Philosophy & Rules

1. **Rule 1 — No Imaginary Functionality:** Every feature is explicitly tagged with one of four verified statuses:
   - `Implemented and tested in-game`
   - `Partially implemented`
   - `Experimental`
   - `Planned`
   *(Unit tests running on mocked Lua tables do not qualify as in-game verification.)*
2. **Rule 2 — No Speculative RE Engine APIs in Production:** Experimental engine APIs must be tested in an isolated research environment before being integrated into the authoritative runtime.
3. **Rule 3 — Always Maintain a Playable Build:** Every development milestone leaves the game in a playable, crash-free state with a fallback to proven locomotion.

---

## 📊 Feature Status Breakdown

| System / Feature | Status | In-Game Reality & Technical Notes |
| :--- | :--- | :--- |
| **Claire 3D Prefab Spawning** | `Implemented and tested in-game` | Multi-part streaming pipeline instantiates Body, Head, and Hair without crash. Spawns Noir outfit (`costume_a`). |
| **Companion Gliding Locomotion** | `Implemented and tested in-game` | NaN-safe transform translation with anti-overshoot dampening, speed lerping, and camera-flank waypoint tracking. |
| **Room Portal Catch-Up** | `Implemented and tested in-game` | Queries `app.ropeway.StayAreaController`; snaps companion through closed doors to prevent room culling voids. |
| **Elevator Kinematic Parenting** | `Implemented and tested in-game` | Parents companion `via.Transform` to moving elevator platform hierarchy. |
| **Cutscene Actor Protection** | `Implemented and tested in-game` | Hooks `CutsceneManager` to hide companion during cinematics and repositions them on scene resume. |
| **Rubber-Band Teleportation** | `Implemented and tested in-game` | Prevents companion from falling behind in unloaded geometry (> 10m horizontal or > 3.2m vertical). |
| **Tactical Command Wheel** | `Implemented and tested in-game` | Radial overlay menu (`FOLLOW`, `WAIT`, `COVER`) with 0.4x bullet-time slowdown via `app.ropeway.TimeManager`. |
| **Multi-Layer HID Input Polling** | `Implemented and tested in-game` | Native `via.hid.Keyboard` + `via.hid.GamePad` polling with fallback to REFramework input. Supports Hold & Toggle modes. |
| **FSM State Machine** | `Implemented and tested in-game` | Manages `FOLLOW`, `WAIT`, and `COVER` tether formations and orientation. |
| **Player Duplication Spawner** | `Implemented and tested in-game` | Pathway B spawner clones player GameObject and strips hardware input components. |
| **Leg Walking/Running Animation** | `Partially implemented` | Motion bank linking assigns Leon's bank asset to Claire, but MotionFsm2 transitions require active character controller allocation. |
| **Animation Research Lab** | `Experimental` | Standalone isolated test harness (`animation_lab.lua`) testing Native NPC Casting, Duplication, and Motion Playback. |
| **RPD Story Scenario Engine** | `Planned (Milestone 3)` | Scripted sequence: Courtyard meeting $\to$ Back gate entry $\to$ Main Hall $\to$ Safe Room dialogue. |
| **Contextual Subtitles / Banter** | `Planned (Milestone 5)` | Text overlay for environmental observations, puzzle callouts, and safe room dialogue. Audio bridge postponed. |
| **Door Key Interception** | `Planned (Milestone 4)` | Companion-assisted door unlocks for character-specific keys (e.g. Heart Key). |
| **Combat Reactions & Weapon Firing** | `Planned (Milestone 4)` | Initial focus on threat facing and reactive cover; true damaging projectiles deferred until damage pipeline is hooked. |
| **Dual Inventory / Resource Offload** | `Planned (Milestone 4)` | Simple companion item carrying interface deferred until after story prototype is playable. |
| **Companion Health & Revive** | `Planned (Milestone 4)` | Hooking into native damage events deferred until core story flow is complete. |

---

## 🗺️ Implementation Roadmap

* **Milestone 0: Stabilization & Consolidation** *(Current)*
  - Permanent baseline branch (`legacy/working-baseline`) and tag (`v0.1-baseline`).
  - Disable parallel runtime (`duo_mode.lua` archived); `character_renderer.lua` is the single authoritative companion controller.
  - Single central `re.on_frame` update loop with scene-unload cleanup.
* **Milestone 1: Animation Spike (Research Lab)**
  - Three isolated experiments in `animation_lab.lua`:
    1. *Experiment A:* Native NPC casting via `SurvivorAssignManager` / `SurvivorStandbyCatalog`.
    2. *Experiment B:* Character duplication via `via.Scene.duplicateGameObject` with component survival audit.
    3. *Experiment C:* Direct `via.motion.Motion` layer manipulation and playback.
  - Time-boxed evaluation with required concrete evidence before any engine changes enter production.
* **Milestone 2: Companion Experience Refinement**
  - Trailing distance smoothing, corridor navigation, hallway avoidance, obstacle nudging, and threat-facing behavior.
* **Milestone 3: Story Engine & Scenario Scripting (First Playable Story Release)**
  - Lightweight scenario trigger engine.
  - Vertical slice: Courtyard meeting $\to$ Back Gate $\to$ Main Hall $\to$ West Office $\to$ Dark Room Safe Room dialogue.
* **Milestone 4: Doors, Combat & Survival Mechanics**
  - Companion door interaction hook.
  - Threat detection, combat callouts, and real damaging fire.
  - Downed state and green herb / spray revive.
* **Milestone 5: Dialogue, Audio & Presentation**
  - Contextual dialogue subtitles and safe room interactions.
  - External audio streaming evaluation.
* **Milestone 6: Campaign Expansion**
  - RPD $\to$ Garage/Orphanage separation $\to$ Sewers reunion $\to$ NEST dual finale.

---

## 📁 Repository Structure

```
RE2NewMode/
├── modinfo.ini                               # Fluffy Mod Manager metadata
├── README.md                                 # Project documentation & status
├── HANDOVER.md                               # Technical diagnosis & resolved bugs
├── ROADMAP_BACKLOG_AND_REVISITS.md           # Engineering backlog & deferred items
├── archive/
│   └── experimental_modules/                 # Archived Days 1–14 stub modules & tests
│       ├── duo_mode.lua                      # Archived duplicate runtime
│       └── duo_mode/                         # Archived stub modules (inventory, combat, audio)
└── reframework/
    ├── autorun/
    │   ├── character_renderer.lua            # Authoritative companion runtime & single update loop
    │   └── animation_lab.lua                 # Milestone 1 isolated animation research harness
    ├── data/
    │   └── duo_mode/                         # Runtime logs, diagnostics, and telemetry
    └── plugins/
        └── miniaudio_bridge/                 # Postponed C++ audio bridge skeleton
```

---

## 🚀 Installation & Usage

### Prerequisites
1. [REFramework](https://github.com/praydog/REFramework) installed in your Resident Evil 2 directory (`dinput8.dll`).
2. [Fluffy Mod Manager 5000](https://www.fluffyquack.com/).

### Installation
1. Clone or download this repository.
2. Place the folder into `FluffyModManager/Games/RE2R/Mods/`.
3. Enable **Resident Evil 2: Duo Mode** in Fluffy Mod Manager.
4. Launch the game.

### In-Game Controls
* **Insert:** Toggle REFramework overlay menu.
* **T (Default) / Gamepad R1:** Open / toggle the Tactical Command Wheel.
* **1 / 2 / 3:** Issue commands (`Follow Me`, `Hold Position`, `Take Cover`).

---

## 🔬 Running the Animation Research Lab

1. Launch Resident Evil 2 and load into a playable Leon game.
2. Press **Insert** to open REFramework.
3. Under **Script Generated UI**, check **"Open Animation Research Lab Window"**.
4. Test Experiments A, B, and C independently and inspect live diagnostics without affecting companion gameplay.

---

## 📜 Credits & License

* **Author:** AryanTechie-007
* **Framework:** Powered by praydog's REFramework.
