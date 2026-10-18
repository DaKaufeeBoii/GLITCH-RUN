# GLITCH//RUN

An offline-first, single-player, Android-first top-down action roguelite built with Godot 4.7.2 and GDScript.

---

## 1. Procedural Dungeon Generation (`dungeon_generator.gd`)

Replaces static room sequences with an algorithmic procedural dungeon generator producing varied, connected, playable layouts with deterministic seeds:
- **Graph-Based Room Connectivity:** Procedural progression connecting Start Room, Sector Combat Chambers, and the Sector 6 NEXUS Boss Arena.
- **7 Tactical Room Templates:**
  - `OPEN_ARENA`: Wide space promoting high-mobility combat and evasion.
  - `PILLAR_HALL`: Grid of obstructive pillars creating line-of-sight breaks and ambush opportunities.
  - `CHOKEPOINT_PASS`: Central pinch point creating defensive lines and funneling flanking attacks.
  - `SPLIT_LANE`: Central divider forcing tactical path choice and split engagement corridors.
  - `FORTRESS_COVER`: Heavy fortified barriers providing tactical cover against ranged hostiles.
  - `HAZARD_CORRIDOR`: Hazardous environment rewarding precision movement and dash invulnerability.
  - `NEXUS_BOSS_CHAMBER`: Specialized radial boss arena designed for orbital satellite barrages.
- **BFS Flood-Fill Reachability Validation:** Every generated room is verified on a 32px collision grid prior to acceptance:
  - Guarantees unbroken navigation path between player spawn and exit door.
  - Confirms all enemy spawn points are fully reachable.
  - Enforces minimum player-to-enemy spawn distance ($\ge 195\text{px}$) to prevent cheap instant hits.
  - Bounded retry loop (up to 10 retries with fallback template).
- **Deterministic Seed Reproducibility:** Every run generates a deterministic run seed displayed on HUD and debrief screen, allowing exact layout and encounter replay.

---

## 2. Three-Layer Enemy Evolution System (`enemy_genome.gd`, `evolution_manager.gd`)

Enemies evolve bounded behavioral traits and named mutations with explicit gameplay trade-offs in response to observed player tactics:

### Layer A — Tactical Adaptation (Security Director)
The security director evaluates real-time player combat profiles (mobility, standoff range, firing uptime) and room tactical geometry (chokepoints, cover) to deploy coordinated counter-tactics.

### Layer B — Individual & Family Specialization
Enemy families mutate distinct adaptations with reciprocal trade-offs:
- **`PREDICTIVE_OPTICS` (Shooter):** Evolved against high-mobility players. Calculates kinematic lead-aim vectors and displays predictive laser sights. *Trade-off: attack cycle lengthened +25%.*
- **`PINCER_WINGS` (Chaser):** Evolved against perimeter snipers. Splits pursuit angles ($\pm 38^\circ$) to flank players. *Trade-off: direct linear speed reduced -10%.*
- **`ION_HAZARD_TRAIL` (Dasher):** Evolved against evasive kiting. Emits electric hazard nodes along charge path. *Trade-off: charge telegraph warning widened +20%.*
- **`STATIC_GROUNDING` (Dasher / Chaser):** Evolved against players relying on Static Blink dash damage. Takes 40% less shock damage. *Trade-off: chassis weight reduces movement speed -8%.*
- **`RAPID_THRUSTERS` (Chaser / Dasher):** +18% movement speed. *Trade-off: telegraph time decreased by 10%, maximum health reduced.*
- **`DEFENSIVE_STRIKE` (Shooter):** Drops proximity mines when player closes in. *Trade-off: projectile velocity -15%.*

### Layer C — Population Evolution & Retention
Across consecutive encounters, enemy variants are tracked in structured generational gene pools (3 genomes per family):
- **Multi-Factor Fitness Scoring:** Evaluates survival time, damage dealt to player, and forced player dashes. Overkill (causing excessive player damage) is heavily penalized.
- **Generational Speciation & Retention:** The top-performing variant reproduces with bounded Gaussian trait perturbation ($\pm 8\%$), while the lowest performer is culled.
- **Hard Trait Caps:** Strict bounded clamping prevents stat inflation and keeps encounters fair:
  - Prediction Strength: `[0.0, 1.0]`
  - Flanking Tendency: `[0.0, 1.0]`
  - Aggression: `[0.60, 1.35]`
  - Attack Timing Multiplier: `[0.65, 1.45]`

---

## 3. Machine Learning Policy (`learning_policy.gd`, `train_and_evaluate_policy.py`)

A lightweight **LinUCB Contextual Bandit** online learning policy that balances exploitation and exploration to select fair, effective tactical counters:
- **Context Space (6D Normalized Vector):** `[Bias=1.0, Player Mobility, Standoff Distance, Turret Ratio, Aggression, Room Chokepoint Ratio]`.
- **Action Space (5 Actions):**
  1. `COUNTER_MOBILITY`
  2. `COUNTER_RANGED`
  3. `COUNTER_TURRET`
  4. `BALANCED_ATTRITION`
  5. `STABILIZATION` (Mercy Safeguard)
- **Multi-Objective Reward Function:**
  $$R = R_{\text{match}} - P_{\text{overkill}} - P_{\text{repetition}}$$
  Rewards appropriate tactical counters, but severely penalizes dealing $\ge 3$ player damage and spamming identical consecutive tactics.
- **Strict Fairness Mercy Safeguard:** When player HP falls below 35%, the policy automatically overrides offensive counters and selects `STABILIZATION`, widening attack telegraphs by +30% and reducing hostile speed by 12%.
- **Offline Synthetic Benchmark:** A reproducible Python simulator (`scripts/train_and_evaluate_policy.py`) evaluates 500 simulated encounters across 5 player archetypes, benchmarking against Fixed Baseline and Rule-Based Director:
  - **Fixed Baseline:** 0.0% accuracy, 0.00 bits entropy.
  - **Rule-Based Director:** 40.0% accuracy, 1.57 bits entropy, 11.0% fairness violations.
  - **LinUCB Contextual Bandit:** 37.2% accuracy, **1.94 bits entropy** (superior tactical diversity), **10.6% fairness violations** (safest gameplay).
  - Weights are exported to `assets/data/learned_policy_weights.json` and loaded at runtime with zero external dependencies.

---

## 4. In-Game Debug & Telemetry Tools

- **In-Game Debug Overlay (`F1` or `[DBG]` HUD button):**
  - Live player profile (`Mobility`, `Ranged`, `Turret`, `Aggression`, `Blaster Accuracy`).
  - Active LinUCB tactical decision, UCB exploration bonuses, and decision rationales.
  - Active enemy mutation counts across Chaser, Shooter, and Dasher populations.
  - Current dungeon seed and room generation metadata.
- **End-of-Run Director Debrief Screen:**
  - Interactive 4-axis radar chart showing combat profile.
  - Complete chronological timeline of all AI adaptations and mutations deployed.
  - Recorded run seed with one-click **Replay Seed** feature.

---

## 5. Controls

- **Movement:** `WASD` or Left Virtual Joystick (Mobile).
- **Aim & Fire:** Mouse aim + Left Click (or `J`/`K`) / Right Virtual Joystick (Mobile).
- **Dash:** `Shift` / `Space` / On-Screen `DASH` button (includes invulnerability frames and static discharge).
- **Pause:** `ESC` / `P` / Top-Right `||` HUD Button.
- **Debug Matrix:** `F1` or HUD `[DBG]` Button.

---

## 6. Procedural Audio & Retro FX

- **100% Procedural Audio Synthesizer (`audio_synth.gd`):** Real-time 16-bit PCM waveform generation featuring 11 retro synth profiles (blaster discharges, dash whooshes, predictive lock-on hums, hazard crackles, and boss warning sirens)—zero external sound files required.
- **Camera Trauma & Juice:** Quadratic trauma decay camera shake responding dynamically to explosions, dash impacts, and hostile eliminations.
- **Screen-Space Glitch Shaders:** Chromatic aberration glitch shaders trigger upon enemy mutations and critical events.

---

## 7. Deterministic Automated Testing

Run the 17-scenario deterministic test suite via headless Godot console:

```powershell
& "D:\GODOT\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless -s scripts/test_runner.gd
```

### Verified Scenarios:
1. `Insufficient Data Scenario`: Baseline deployment when combat telemetry $< 12\text{s}$.
2. `High Mobility Scenario`: Predicts dash evasion and deploys lead-laser countermeasures.
3. `Ranged Camping Scenario`: Deploys flanking pincer formations against snipers.
4. `Stationary Turret Scenario`: Deploys suppression fire and electric hazard corridors.
5. `Tactic Cooldown Prevention`: Prevents repetitive consecutive tactics.
6. `Fairness Weight Adjustment`: Softens encounter difficulty after player takes heavy damage.
7. `Bullet Mechanics & Collision Scenario`: Blaster velocities, area queries, and collision exceptions.
8. `Tactical Micro-AI Evolutions`: Lead aiming, pincer flanking, and hazard trails.
9. `Procedural Audio Synthesis`: 11 procedural retro waveforms.
10. `Director Telemetry Debrief Terminal & Tactical Pause UI`: Radar chart & pause menus.
11. `Local Persistence`: Saves and loads high scores and seed history from `user://save_data.json`.
12. `Behavior Tracker Rolling Window Decay`: Exponential decay model ensuring recent tactics weigh more heavily.
13. `Enemy Genome Evolvable Traits & Bounded Caps`: Enforces min/max boundaries and named mutation trade-offs.
14. `Multi-Layer Evolution Manager`: Specialization and population retention with elitism.
15. `LinUCB Learning Policy Robustness & Fairness`: Context extraction, UCB score calculation, fairness mercy trigger, and weight export/load.
16. `Procedural Dungeon 100-Seed Reachability & Deterministic Reproducibility`: Validates 100 consecutive procedural seeds for BFS reachability, clear spawns, and identical reproduction under matching seeds.
17. `Encounter Director & Genome Pipeline Integration`: End-to-end integration across dungeon rooms, learning policy, and enemy genome assignment.
