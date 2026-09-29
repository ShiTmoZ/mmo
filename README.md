# Ashen Sanctum

A hardcore 1v1 / 2v2 PvP skirmish Action RPG combining the tactical depth of classic **Warcraft 3 / World of Warcraft arena rotations** with the deliberate animation commitment and invulnerability-frame dodging of **Dark Souls**. Built on **Godot 4.3** with the lightweight GL Compatibility renderer for high-framerate competitive execution.

---

## Architecture Overview

```
ashen-sanctum/
├── .github/workflows/
│   └── build_windows.yml       # Headless CI/CD Windows x86_64 export
├── export_presets.cfg          # Windows Desktop embedded release preset
├── project.godot               # Project configuration, autoloads, input bindings
├── scenes/
│   ├── arena.tscn              # 30m circular stone colosseum with team spawn anchors
│   ├── lobby.tscn              # ENet connection and host/join interface
│   ├── player.tscn             # CharacterBody3D with MultiplayerSynchronizer
│   └── ui/
│       └── CombatHUD.tscn      # Vitals, target frame, cast bar, action bar
└── scripts/
    ├── core/
    │   ├── GameData.gd         # Autoload: Enums, stats, and 10 balanced spell blueprints
    │   └── NetworkManager.gd   # Autoload: ENet peer lifecycle, spawn orchestration
    ├── combat/
    │   └── CastSystem.gd       # Server-authoritative cast timer, LoS raycasts, interrupts
    ├── entities/
    │   └── Player.gd           # FSM, movement, dodge roll i-frames, targeting
    └── ui/
        ├── CombatHUD.gd        # Real-time UI updates, interrupt flashes, CD sweeps
        └── Lobby.gd            # Lobby network dispatch controller
```

---

## Core Mechanics

### 1. Finite State Machine (FSM)
Every character operates under strict states:
* `IDLE` / `MOVING`: Standard locomotion with 8-directional movement and smooth yaw interpolation.
* `CASTING`: Character is rooted in place while channeling spells with cast times. Interruption resets the character to `IDLE` and triggers a school lockout.
* `DODGE_ROLLING`: Consumes stamina to launch the character in the moving direction at 3x speed for 0.35s. The first 0.20s grants complete invulnerability (`_is_invulnerable = true`).
* `STUNNED`: Complete loss of control caused by poise/stagger depletion or crowd control.
* `DEAD`: Player defeat and disablement.

### 2. Server-Authoritative Hit Registration & Interrupts
* **Line of Sight & Range:** Hits are validated on the server using PhysicsServer3D raycasts against arena geometry before applying damage or healing.
* **School Lockout:** Successfully landing an interrupt (e.g. `Counterspell`) against a player while in `CASTING` state abruptly halts the cast, flashes their cast bar red with an `INTERRUPTED!` notification, and locks out that specific spell school for 3.0 seconds.

---

## Default Controls

| Action | Key / Input | Description |
| :--- | :--- | :--- |
| **Move Forward** | `W` | Move character toward north |
| **Move Backward** | `S` | Move character toward south |
| **Move Left** | `A` | Move character toward west |
| **Move Right** | `D` | Move character toward east |
| **Dodge Roll** | `Space` | 0.35s roll with 0.20s i-frame window (Stamina cost: 25) |
| **Select Target** | `Left Click` | 3D raycast to select opponent |
| **Cycle Target** | `Tab` | Cycles through living enemy combatants |
| **Spell Slot 1** | `1` | Casts assigned primary spell (Default: `Fireball`) |
| **Spell Slot 2** | `2` | Casts assigned utility spell (Default: `Frost Nova`) |
| **Spell Slot 3** | `3` | Casts assigned interrupt spell (Default: `Counterspell`) |

---

## Spell Roster (`GameData.gd`)

| ID | Spell | School | Cast Time | Cooldown | Mana | Base Dmg | Base Heal | Tactical Role |
| :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **1** | Fireball | Fire | 1.8s | 3.0s | 30 | 85 | - | Heavy ranged damage |
| **2** | Frost Nova | Frost | Instant | 12.0s | 25 | 45 | - | Close-range burst + interrupt |
| **3** | Arcane Blast | Arcane | 2.5s | 4.0s | 40 | 120 | - | High-risk nuclear cast |
| **4** | Shadow Bolt | Shadow | 2.0s | 3.5s | 35 | 95 | - | Mid-range direct attrition |
| **5** | Flash Heal | Holy | 1.5s | 5.0s | 50 | - | 120 | Emergency life preservation |
| **6** | Counterspell | Arcane | Instant | 24.0s | 20 | - | - | Instant kick + 3s school lockout |
| **7** | Wrath | Nature | 1.5s | 2.5s | 25 | 70 | - | Fast low-mana ranged poke |
| **8** | Holy Shock | Holy | Instant | 6.0s | 30 | 60 | 60 | Instant hybrid heal or strike |
| **9** | Blizzard | Frost | 3.0s | 8.0s | 60 | 150 | - | Channeled area punishment |
| **10** | Mind Flay | Shadow | Instant | 3.0s | 20 | 55 | - | Fast finisher against low HP |

---

## Testing & Running

### Option A: Download Automated Windows Release
Every commit automatically compiles via GitHub Actions.
1. Navigate to the [Actions tab](https://github.com/ShiTmoZ/mmo/actions).
2. Select the latest successful workflow run.
3. Download the **`AshenSanctum-Windows-x86_64`** artifact.
4. Extract the `.zip` and launch `AshenSanctum.exe`.

### Option B: Local 2-Client Testing
1. Launch Instance 1: Click **Host (Port 7777)** to start the local listen server.
2. Launch Instance 2: Leave the IP as `127.0.0.1` and click **Join (Port 7777)**.
3. Test target selection (`Left Click` / `Tab`), spell casting, interrupt windows, and dodging attacks during the 0.20s i-frame window.

### Option C: Dedicated Headless Server
To host on a remote headless Linux server without rendering overhead:
```bash
./godot --headless -- --server
```

---

## Planned Enhancements
* **Parry / Riposte Window:** Introduce an active 0.15s parry state (`Right Click`) that reflects physical attacks and triggers heavy stagger on the attacker.
* **Class Profiles:** Dynamic loadouts for Templar, Cleric, and Spellblade presets.
* **PvE Encounter Engine:** The Stone Colossus boss rush arena.
