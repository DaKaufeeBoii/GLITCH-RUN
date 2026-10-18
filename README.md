# GLITCH//RUN

An offline-first, single-player, Android-first top-down action roguelite built with **Godot 4.7.2** and **GDScript**.

---

## 1. Overview & Core Philosophy

**GLITCH//RUN** blends high-octane twin-stick evasion and projectile combat with an **adaptive evolutionary AI director**. As you fight through procedural sectors, the game analyzes your movement, range, fire uptime, and dash habits in real time—deploying telegraphed enemy mutations designed specifically to counter your playstyle while maintaining strict fairness and telegraph readability.

- **Engine:** Godot 4.7.2-stable (GL Compatibility renderer)
- **Target Platform:** Android (Sensor Landscape) & Desktop (Windows/Linux/macOS)
- **Networking:** 100% Offline-First. Zero network permissions, zero telemetry transmission, zero cloud accounts.
- **Save Storage:** Local internal device storage (`user://save_data.json`, `user://settings.json`, `user://logs/`).

---

## 2. Procedural Dungeon Generation (`dungeon_generator.gd`, `run_progression.gd`)

Replaces static room sequences with an algorithmic procedural dungeon generator producing connected, varied, deterministic layouts:
- **Monotonic Run Depth & Endless Progression:** Continuous sector graph progression supporting endless runs with 3–5 multi-wave combat encounters per room.
- **7 Tactical Room Templates:**
  - `OPEN_ARENA`: Expansive open floor promoting high-mobility evasion.
  - `PILLAR_HALL`: Dense pillar grid breaking lines of sight and facilitating ambushes.
  - `CHOKEPOINT_PASS`: Tight central funnel creating defensive pinch points.
  - `SPLIT_LANE`: Central divider forcing path selection and split engagements.
  - `FORTRESS_COVER`: Heavy fortified barriers providing tactical cover against ranged fire.
  - `HAZARD_CORRIDOR`: Tight hazardous space rewarding dash invulnerability.
  - `NEXUS_BOSS_CHAMBER`: Specialized radial arena designed for multi-phase boss battles.
- **BFS Flood-Fill Reachability Validation:** Every generated chamber is verified on a 32px collision grid prior to room acceptance:
  - Guarantees an unbroken navigation path between player spawn and all exits.
  - Confirms all enemy spawn points are reachable.
  - Enforces minimum player-to-enemy spawn distance ($\ge 195\text{px}$) to prevent cheap instant hits.
  - Retries up to 10 times with deterministic fallbacks.
- **Branching Route Decisions:** Clear a chamber to unlock holographic route portals (Recovery Node `+2 HP`, Elite Threat, Combat, or Sector Gateway).
- **Deterministic Seed Reproducibility:** Every run generates a deterministic run seed displayed on HUD and debrief screens for exact layout and encounter replay.

---

## 3. Three-Layer Enemy Evolution System (`enemy_genome.gd`, `evolution_manager.gd`)

Hostiles evolve bounded behavioral traits and authored mutations with reciprocal trade-offs:

### Layer A — Tactical Adaptation (Security Director)
The security director evaluates real-time player combat profiles (mobility, standoff range, firing uptime) and room tactical geometry (chokepoints, cover) to deploy coordinated counter-tactics:
- **Tactical Steering (`enemy_steering.gd`):** Obstacle avoidance via raycast whisker steering, line-of-sight checks, and target position prediction bounded by projectile flight times.
- **Flocking & Spatial Separation (`spatial_index.gd`):** Uniform spatial grid partitioning using squared distances preventing expensive square-root calls on mobile CPUs and preventing enemy clumping.
- **Squad Attack Tokens (`squad_coordinator.gd`):** Token-bucket attack coordinator that limits simultaneous incoming attacks and staggers fire to prevent unavoidable instant kills.

### Layer B — Individual & Family Specialization
Enemy families mutate distinct adaptations with explicit trade-offs:
- **`PREDICTIVE_OPTICS` (Shooter):** Calculates kinematic lead-aim vectors and displays predictive laser sights. *Trade-off: attack cycle lengthened +25%.*
- **`PINCER_WINGS` (Chaser):** Splits pursuit angles ($\pm 38^\circ$) to flank players. *Trade-off: direct linear speed reduced -10%.*
- **`ION_HAZARD_TRAIL` (Dasher):** Emits electric hazard nodes along charge path. *Trade-off: charge telegraph warning widened +20%.*
- **`STATIC_GROUNDING` (Dasher / Chaser):** Takes 40% less shock damage from player dash. *Trade-off: chassis weight reduces movement speed -8%.*
- **`RAPID_THRUSTERS` (Chaser / Dasher):** +18% movement speed. *Trade-off: telegraph time decreased by 10%, maximum health reduced.*
- **`DEFENSIVE_STRIKE` (Shooter):** Drops proximity mines when player closes in. *Trade-off: projectile velocity -15%.*

### Layer C — Population Evolution & Retention
Across consecutive encounters, enemy variants are tracked in structured generational gene pools (3 genomes per family):
- **Multi-Factor Fitness Scoring:** Evaluates survival time, damage dealt to player, and forced player dashes. Overkill (causing $\ge 3$ player damage) is heavily penalized.
- **Generational Speciation & Retention:** The top-performing variant reproduces with bounded Gaussian trait perturbation ($\pm 8\%$), while the lowest performer is culled.
- **Hard Trait Caps:** Strict bounded clamping prevents stat inflation and keeps encounters fair:
  - Prediction Strength: `[0.0, 1.0]`
  - Flanking Tendency: `[0.0, 1.0]`
  - Aggression: `[0.60, 1.35]`
  - Attack Timing Multiplier: `[0.65, 1.45]`

---

## 4. Boss Roster & Returning Boss Evolution (`boss_director.gd`, `boss_definition.gd`)

GLITCH//RUN features 3 mechanically distinct bosses managed by a run-seeded Boss Director:

1. **Nexus Overlord (`boss.gd`):** Singularity core utilizing radial tachyon barrages and high-speed directional crush dashes.
2. **Vector Sentinel (`boss_sentinel.gd`):** Orbital perimeter platform deploying sweeping quad laser beams and satellite shard drone defense matrices.
3. **Null Architect (`boss_architect.gd`):** Spatial containment boss with arena quadrant warping and high-voltage perimeter laser grids.

### Returning Boss Progression
- **Repetition Cooldown:** The same boss cannot appear in consecutive sectors.
- **Authored Mutation Tiers:** When a defeated boss recurs in deeper endless sectors, it unlocks authored phase mutations with built-in counter-windows (e.g., overdrive speed accompanied by widened telegraph recovery, or extra drone rings that drop repair cells upon destruction) rather than simple health or damage sponges.
- **Debrief Integration:** Complete boss encounter histories (boss ID, sector, depth, outcome, mutations) are recorded in the debrief telemetry terminal.

---

## 5. Machine Learning Policy (`learning_policy.gd`, `train_and_evaluate_policy.py`)

A lightweight **LinUCB Contextual Bandit** online learning policy balances exploitation and exploration:
- **Context Space (6D Normalized Vector):** `[Bias=1.0, Player Mobility, Standoff Distance, Turret Ratio, Aggression, Room Chokepoint Ratio]`.
- **Action Space (5 Actions):** `COUNTER_MOBILITY`, `COUNTER_RANGED`, `COUNTER_TURRET`, `BALANCED_ATTRITION`, `STABILIZATION` (Mercy Safeguard).
- **Strict Fairness Mercy Safeguard:** When player HP falls below 35%, the policy automatically overrides offensive counters and selects `STABILIZATION`, widening attack telegraphs by +30% and reducing hostile speed by 12%.
- **Pre-Trained Weights:** Shipped in `assets/data/learned_policy_weights.json` and executed locally with zero external network or Python dependencies.

---

## 6. Audio, Visuals & Quality of Life

- **Multi-Bus Audio Configuration (`SettingsManager`):** Independent `Master`, `Music`, and `SFX` audio buses with persistent decibel conversion and mute states.
- **Procedural Audio Synthesizer (`audio_synth.gd`):** Real-time 16-bit PCM waveform generation featuring 11 retro synth profiles (blaster discharges, dash whooshes, predictive lock-on hums, hazard crackles, boss sirens) and a 110 BPM cyber synthwave looping track.
- **Juice & Visual Feedback:** Quadratic camera trauma shake, chromatic aberration glitch shaders (`glitch.gdshader`), and a bounded procedural geometric debris emitter (`debris_emitter.gd`).
- **Touch-First Menus:** Minimum 48dp touch targets across all title, settings, how-to-play, threat archive, pause, and confirmation dialogs.
- **Safe Backgrounding:** Safe pause on `NOTIFICATION_APPLICATION_FOCUS_OUT` and `NOTIFICATION_APPLICATION_PAUSED`.
- **Android Back Navigation:** Modal dismissal $\to$ safe pause $\to$ title confirmation hierarchy.

---

## 7. Controls

| Action | Desktop (Keyboard & Mouse) | Mobile (Touchscreen) |
| :--- | :--- | :--- |
| **Movement** | `WASD` / Arrow Keys | Left Virtual Joystick |
| **Aim & Fire** | Mouse Aim + Left Click / `J` / `K` | Right Virtual Joystick (Hold to Aim/Fire) |
| **Phase Dash** | `Shift` / `Space` | On-Screen `DASH` Button |
| **Tactical Pause** | `ESC` / `P` | Top-Right `||` HUD Button (48x48dp) |
| **Debug Overlay** | `F1` | HUD `[DBG]` Button (48x48dp) |

---

## 8. Android Export & Building

See [docs/ANDROID_EXPORT.md](docs/ANDROID_EXPORT.md) for full instructions.

### Quick Debug APK Export:
```bash
# Ensure output directory exists
mkdir -p build/android

# Export debug APK using Godot 4.7.2 headless console
& "D:\GODOT\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless --export-debug "Android" build/android/glitch_run_debug.apk
```

---

## 9. Deterministic Automated Testing

Run the **42-scenario deterministic test suite** via headless Godot console:

```powershell
& "D:\GODOT\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless -s scripts/test_runner.gd
```

### Complete 42-Scenario Test Suite:
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
18. `Boss Dash Single-Hit Fairness`: Verifies single-hit collision flags during high-speed boss charges.
19. `Shooter Aim Lock During Telegraph`: Verifies aiming direction locks during telegraph window to permit dodging.
20. `RunState Idempotent Finalization`: Verifies victory/defeat finalization runs exactly once without state duplication.
21. `Run Progression Multi-Wave Scaling & Monotonic Depth`: Validates depth, room indices, and wave limits across sectors.
22. `Save Schema V2 Migration & Depth Persistence`: Backward compatibility migration from schema V1 to V2.
23. `Procedural Dungeon Branching Routes & Validated Exits`: Validates generation of multiple door routes per chamber.
24. `Independent Sub-Seed Determinism`: Verifies sector seed isolation from unrelated RNG consumption.
25. `RunState Endless Run History Bounding`: Ensures telemetry logs remain bounded in endless mode.
26. `Branching Route Room Advancement & Sector Gateway`: Room traversal and sector transition mechanics.
27. `AI Bounded Target Prediction & Dodge Window`: Clamped lead-aim angular bounds ensuring dodge windows.
28. `AI Obstacle Avoidance Steering & Line of Sight`: Raycast whisker obstacle avoidance and wall checks.
29. `AI Spatial Neighbor Separation & Bounded Capping`: Neighbor repulsion using squared distances without expensive sqrt calls.
30. `AI Squad Attack Budget Staggering & Fairness Mercy`: Token-bucket attack authorization preventing simultaneous projectile walls.
31. `Dasher Hazard Trail Capping & Spacing`: Bounds active electric hazards per room to prevent inescapable floors.
32. `Boss Definition Roster Registry`: Verifies valid registration of all 3 bosses (Overlord, Sentinel, Architect).
33. `Boss Director Rotation & Repetition Cooldown`: Verifies rotation and cooldown prevention across consecutive sectors.
34. `Returning Boss Mutation Tiers & Trade-offs`: Verifies authored mutation tiers and counterplay opportunities.
35. `Boss History Run Persistence & Bounding`: Verifies run-level boss encounter history logging and caps.
36. `Settings Persistence & Multi-Bus Audio Configuration`: Verifies Master/Music/SFX volumes and user://settings.json.
37. `Touch Navigation, Modals & Confirmation Flows`: Verifies 48dp button sizing, difficulty cycler, and confirmation dialogs.
38. `Android Export Preset Configuration & Touch Targets`: Validates package ID, orientation, SDK levels, and touch radii.
39. `Save File Corruption & Offline Recovery`: Verifies clean recovery and fallback when JSON files are corrupted.
40. `Android Back Key & Navigation Hierarchy`: Modal dismiss $\to$ pause $\to$ exit hierarchy validation.
41. `Mobile Debris & Particle Bounding`: Verifies active particle limits (`MAX_ACTIVE_SHARDS <= 64`).
42. `Offline QA Crash Logger & Diagnostics`: Verifies local diagnostics logging to user storage with zero PII.

---

## 10. Known Limitations & Architecture Notes

- **Offline-First:** No cloud synchronization, accounts, or multiplayer are present by design.
- **Local Saves:** Uninstalling or clearing app storage deletes local saves and records.
- **Single-Threaded Physics:** Godot 2D physics runs on the main thread for deterministic execution and mobile stability.
