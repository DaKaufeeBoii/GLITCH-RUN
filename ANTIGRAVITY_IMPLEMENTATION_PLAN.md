# GLITCH//RUN — Adaptive Evolution, Explorable Sector Graphs & Session Controls Plan

All requested tasks have been fully implemented, integrated, and verified against all 45 deterministic regression scenarios in Godot 4.7.2.

---

## 1. Make enemy evolution real, observable, and run-scoped [COMPLETED]

### Implemented Behavior:
- **Baseline at Run Start**: Every run begins with Tier 0 baseline for all enemy species ($1\times$ base health, zero unlocked mutations).
- **Strict Species Evidence Isolation**:
  - Species evolve **strictly and only** from telemetry evidence gathered during their own battles during the active run (`scripts/evolution_manager.gd`).
  - If a species has not been encountered or engaged in combat, it remains at Tier 0 ($1\times$ HP, baseline attacks).
- **Guaranteed Health Invariant ($1\times, 2\times, 4\times$)**:
  - Tier 0: $1\times$ base health.
  - Tier 1: $2\times$ base health.
  - Tier 2: $4\times$ base health.
  - Calculated cleanly via `EnemyGenome.get_max_health()` ($base \times 2^{\text{tier}}$) and applied directly on spawn. Calling `apply_to_enemy` is strictly idempotent and never doubles health multiple times.
- **Species Evolution Progressions**:
  - **Red Chaser**:
    - *Tier 0*: Contact damage only. Base speed.
    - *Tier 1 (`RAPID_PURSUIT`)*: Unlocks after player kiting/escape evidence ($\ge 1$ encounter). Pursuit speed increases by $+35\%$ ($2\times$ max health).
    - *Tier 2 (`CRIMSON_BLASTER`)*: Unlocks after sustained combat ($\ge 2$ encounters). Equips forward-mounted emitter prongs and fires committed laser projectiles ($0.65\text{s}$ warning charge, $0.25\text{s}$ aim lock dodge window, visible telegraph beam, $4\times$ max health).
  - **Purple Dasher**:
    - *Tier 0*: Telegraphs and lunges at player. Leaves no hazards.
    - *Tier 1 (`ION_HAZARD_TRAIL`)*: Unlocks after player evasion evidence. Drops spaced, bounded (max 5) pulsing ion hazard spheres along dash path ($2\times$ max health).
    - *Tier 2 (`OVERCLOCKED_THRUSTERS`)*: Unlocks after $\ge 2$ encounters. Increases stalking and dash speed by $+25\%$ with distinct visual particle exhaust while preserving telegraph fairness ($4\times$ max health).
  - **Amber Shooter**:
    - *Tier 0*: Straight-line projectile aiming.
    - *Tier 1 (`PREDICTIVE_OPTICS`)*: Predictive velocity lead targeting optics ($2\times$ max health).
    - *Tier 2 (`BURST_VOLLEY`)*: Rapid 2-round burst volley with audio chirp ($4\times$ max health).
- **Run-Scoped Lifetime & Zero Cross-Run Persistence**:
  - Death, manual restart, or abort to main menu immediately invokes `evolution_manager.reset()`. All species tiers, active genomes, and encounter evidence are purged.
  - Evolutions persist seamlessly across room and sector transitions and tactical pause.
- **Debrief Telemetry**:
  - `scripts/debrief_terminal.gd` renders species tier, health multiplier, triggering battle evidence reason, and tactical counter-measures.

---

## 2. Restore Quit Session in the pause menu [COMPLETED]

### Implemented Behavior:
- **Dedicated Touch Button**: Added a dedicated `QUIT SESSION` button in `scripts/pause_menu.gd` with minimum touch height $\ge 48\text{dp}$, distinct from `RESTART RUN` and `ABORT TO MAIN MENU`.
- **Loss Warning Modal**: Pressing `QUIT SESSION` displays a high-contrast confirmation modal explicitly warning:
  `"TERMINATE APPLICATION // QUIT SESSION\nThe game will close and the active run and its evolutions will be lost."`
- **Safe Exit & Dismissal**:
  - Pressing `CONFIRM` unpauses the scene tree safely and calls `get_tree().quit()`.
  - Pressing `CANCEL` or Android Back / Escape dismisses the confirmation modal back to the pause screen without quitting.

---

## 3. Change waves to 3–5 total regular waves per sector [COMPLETED]

### Implemented Behavior:
- **Sector-Level Wave Budget**:
  - `scripts/run_progression.gd` calculates the exact regular wave count per sector:
    - Normal difficulty: Sector 1 = 3 waves, Sector 2 = 4 waves, Sector 3+ = 5 waves.
    - Easy: 3 waves. Hard: 4 waves.
- **Distribution Across Sector**:
  - Waves are distributed evenly across regular combat rooms in the sector. Visiting optional rooms does not multiply combat waves.
- **Non-Wave Room Identity**:
  - `START`, `SHOP`, `GIFT`, and `RECOVERY` rooms require 0 combat waves and allow instant traversal/interaction.
  - The `BOSS` encounter is a dedicated end-of-sector duel after all regular sector waves have concluded.
- **HUD & Telemetry Synchronization**:
  - HUD wave counter cleanly displays `"WAVE X / Y"` where $Y \in [3, 5]$, synchronizing room and sector progression.

---

## 4. Build larger, explorable sectors with shops and gift rooms [COMPLETED]

### Implemented Behavior:
- **Connected Graph Topology**:
  - `scripts/dungeon_generator.gd` generates 6-room connected sector graphs with branching paths (`START` $\to$ `COMBAT`/`SHOP`/`GIFT`/`RECOVERY`/`ELITE` $\to$ `BOSS`).
  - Guaranteed reachability verified across hundreds of seeds via deterministic BFS.
- **Interactive Shops & Gift Caches**:
  - `SHOP` depot: Sells 3 rotating subroutines for run bits (`50`–`65` bits each). Integrated into `scripts/game.gd` with touch UI.
  - `GIFT` vault: Offers 2 complimentary experimental subroutines (player selects 1).
  - Both respect stat caps and subroutine limits to prevent unbounded power scaling.
- **Tactical Mini-Map**:
  - `scripts/pause_menu.gd` displays real-time sector room topology with dedicated glyphs:
    `S: Start • ⚔: Combat • $: Shop • G: Gift • +: Recovery • ★: Elite • Ω: Boss`

---

## 5. Verification & Deterministic Scenarios [COMPLETED]

- All 45 regression scenarios in `scripts/test_director.gd` pass with 100% determinism:
  - `[PASS] Strict Species Evidence Isolation & Tier Evolutions (Speed, Laser, Hazards, Volley)`
  - `[PASS] Pause Menu Touch Quit Session & Loss Confirmation Flow Scenario`
  - `[PASS] Explorable Sector Graphs, Shop Kiosks & Gift Caches Scenario`
  - `--- ALL 45 DIRECTOR, EVOLUTION, STEERING, BOSS ROSTER, SETTINGS, UI & ANDROID HARDENING SCENARIOS PASSED DETERMINISTICALLY ---`
- Zero compiler errors, zero runtime warnings in Godot 4.7.2 headless execution.

