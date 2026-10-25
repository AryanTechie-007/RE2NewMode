# Resident Evil 2: Duo Mode (Leon & Claire)

A single-player dual-protagonist overhaul mod for **Resident Evil 2 Remake (2019)** built on **REFramework** (Lua).

Experience the events of Raccoon City with Leon and Claire fighting side-by-side following their meeting at the courtyard back gate. Control the leader while your partner provides tactical support, unlocks doors with character-specific keys, offloads excess inventory, and reacts to the horror with contextual banter.

---

## Key Features

* **Single-Player Duo Dynamic:** Control Leon or Claire with the companion following seamlessly via root-motion synthetic locomotion along NavMesh paths.
* **Tactical Command Wheel:** Issue instant orders via an in-game radial menu (`Follow`, `Hold Position`, `Cover Fire`).
* **Smart Door Interception:** If your companion carries the required key (e.g., Claire holding the Heart Key while you play Leon), they step up, call it out, and unlock the door without clunky character swaps.
* **Dual-Bag Inventory & Contextual Offload:** When your inventory is full, offload supplies directly to your partner with a single button press. Inspect both inventories side-by-side in the pause menu.
* **Real Survival Horror Resource Stakes:** Companion consumes actual inventory bullets and calls out *"I'm out!"* when dry.
* **Downed & Revive Mechanic:** If your partner's health hits zero, they drop to their knees with a 45-second bleed-out timer. Revive them with a Green Herb or First Aid Spray.
* **Dynamic Banter Engine:** Contextual dialogue responding to safe room downtime (intimate whispers), combat panic, health status, and environment lore.
* **Harmonized Canon Storyline:** Resolves the campaign divergence (RPD together, walkie-talkie separation during the Garage/Orphanage, Sewers Safe Room reunion, and a climactic back-to-back Super Tyrant $\to$ G-Phase 4 dual boss finale).

---

## Repository Structure

```
RE2NewMode/
├── modinfo.ini                              # Fluffy Mod Manager metadata
├── README.md                                # Project documentation
├── docs/
│   └── SPECIFICATION_14_DAYS.md            # Comprehensive 14-day production specification
├── reframework/
│   ├── autorun/
│   │   ├── duo_mode.lua                    # Main entry point & ImGui dev menu
│   │   └── duo_mode/
│   │       ├── config.lua                  # Tunables, toggles, keys, timings
│   │       ├── spawner.lua                 # Day 1: Asset preloader & companion spawner
│   │       ├── locomotion.lua              # Day 2: Synthetic stick root-motion math
│   │       ├── portal_defense.lua          # Day 3: RoomID mismatch & elevator kinematic parenting
│   │       ├── fsm.lua                     # Day 4: Companion Finite State Machine
│   │       ├── command_wheel.lua           # Day 4: ImGui tactical radial order wheel
│   │       └── test_harness.lua            # Day 14: Automated QA regression test suite
│   └── plugins/
│       └── miniaudio_bridge/               # Day 9: Lightweight C++ plugin for loose .wav streaming
│           ├── CMakeLists.txt
│           └── main.cpp
└── .gitignore
```

---

## Automated QA Regression Test Suite

To eliminate testing fatigue, this mod includes an in-engine automated test harness (`test_harness.lua`) that validates critical engine math and edge cases:

1. Open REFramework in-game (`Insert` key).
2. Expand **Script Generated UI** $\to$ **RE2: Duo Mode**.
3. Click **"Run Automated Test Harness"**.
4. Checks:
   * **SyntheticStickMath:** Asserts waypoint transformation into companion-local yaw coordinates.
   * **PortalRoomMismatch:** Validates door closure room culling fail-safe.
   * **FSMDownedTransition:** Asserts incapacitation and bleed-out timer logic.
   * **SaveSlotIndexing:** Verifies multi-slot save isolation (`save_state_slot_%02d.json`).

---

## Installation

### Prerequisites
1. [REFramework](https://github.com/praydog/REFramework) installed in your Resident Evil 2 directory (`dinput8.dll`).
2. [Fluffy Mod Manager 5000](https://www.fluffyquack.com/).

### Instructions
1. Download or clone this repository.
2. Place the folder into `FluffyModManager/Games/RE2R/Mods/`.
3. Launch Fluffy Mod Manager and enable **Resident Evil 2: Duo Mode**.
4. Boot the game.

---

## 14-Day Production Specification

For the deep-dive architectural specification, engine trap mitigations, and development breakdown, see [docs/SPECIFICATION_14_DAYS.md](docs/SPECIFICATION_14_DAYS.md).

---

## License & Credits

* **Author:** AryanTechie-007
* **Framework:** Powered by praydog's REFramework.
