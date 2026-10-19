# GLITCH//RUN — Implementation & Architecture Plan (Archived)

**Engine:** Godot 4.7.2 stable  
**Language:** GDScript  
**Target:** Offline-first, single-player Android action roguelite  
**Master Plan:** [ANTIGRAVITY_IMPLEMENTATION_PLAN.md](ANTIGRAVITY_IMPLEMENTATION_PLAN.md)  
**Export & Hardening Guide:** [docs/ANDROID_EXPORT.md](docs/ANDROID_EXPORT.md)  
**Privacy Policy:** [docs/PRIVACY.md](docs/PRIVACY.md)  

All 7 core milestones from `ANTIGRAVITY_IMPLEMENTATION_PLAN.md` have been executed, verified, and checked off with **51 deterministic test scenarios passing**.

---

## Complete Project Structure

```text
project.godot
export_presets.cfg
assets/
  data/
    learned_policy_weights.json
  ui/
    hearts.png (64x32 geometric health modules: full ruby diamond & depleted socket)
  environment/
    tileset.png (128x64 geometric cyber grid plate)
docs/
  ANDROID_EXPORT.md
  PRIVACY.md
scenes/
  main.tscn
  ui/
    main_menu.tscn
scripts/
  game.gd
  player.gd
  chaser.gd
  shooter.gd
  dasher.gd
  boss.gd
  boss_sentinel.gd
  boss_architect.gd
  boss_director.gd
  boss_definition.gd
  projectile.gd
  enemy_projectile.gd
  mobile_controls.gd
  run_state.gd
  run_progression.gd
  behavior_tracker.gd
  adaptive_director.gd
  encounter_director.gd
  evolution_manager.gd
  enemy_genome.gd
  learning_policy.gd
  dungeon_generator.gd
  enemy_steering.gd
  spatial_index.gd
  squad_coordinator.gd
  audio_synth.gd
  debris_emitter.gd
  hazard_node.gd
  settings_manager.gd
  crash_logger.gd
  main_menu.gd
  pause_menu.gd
  debrief_terminal.gd
  test_director.gd
  test_runner.gd
  asset_loader.gd
  train_and_evaluate_policy.py
README.md
ANTIGRAVITY_IMPLEMENTATION_PLAN.md
plan.md
```

---

## Milestone Execution Summary

- [x] **Milestone 0: Correctness & Project Baseline**
  - Resolved all GDScript warnings, shadowed variables, and area exceptions.
  - Cleaned up unused PNG assets and confirmed 100% procedurally drawn vector shapes.
  - Headless test runner operational (`scripts/test_runner.gd`).

- [x] **Milestone 1: Stable Endless Sector & Multi-Wave Progression**
  - Created `RunProgression` managing continuous depth, sector indices, and 3–5 multi-wave room loops.
  - Built 3-card upgrade drafting with 7 persistent perks.
  - Idempotent run finalization preventing duplicate victory/defeat calls.
  - Save schema V2 with backward-compatible migration for high depth and score records.

- [x] **Milestone 2: Navigable Procedural Maze & Room Generation**
  - Built `DungeonGenerator` with 7 tactical room templates and BFS flood-fill reachability validation.
  - Implemented branching route doors (Recovery, Elite, Combat, Boss Gateway).
  - Validated 100 consecutive procedural seeds for reachability and reproducibility.

- [x] **Milestone 3: Stronger, Fairer Enemy AI & Tactical Steering**
  - Raycast whisker steering with line-of-sight checks (`enemy_steering.gd`).
  - Spatial neighbor partitioning with squared-distance calculations (`spatial_index.gd`).
  - Token-bucket squad attack coordinator with fairness mercy overrides (`squad_coordinator.gd`).
  - Active hazard caps on electric trails (`hazard_node.gd`).

- [x] **Milestone 4: Boss Roster & Returning Boss Evolution**
  - Created `BossDefinition` and `BossDirector` with repetition cooldowns across consecutive sectors.
  - Implemented 3 distinct bosses: Nexus Overlord, Vector Sentinel, and Null Architect.
  - Authored returning boss mutation tiers with built-in counter-windows.
  - Complete encounter history logging in debrief terminal.

- [x] **Milestone 5: Touch Menus, Settings, Music & Quality of Life**
  - Rebuilt title and pause menus with 48dp+ touch targets, difficulty cycler, and confirmation dialogs.
  - Built `SettingsManager` with persisted Master/Music/SFX volume sliders, screen shake, and haptics.
  - Synthesized 110 BPM cyber synthwave looping track on dedicated `Music` bus.
  - Safe backgrounding pause and one-click replay seed terminal.

- [x] **Milestone 6: Android Hardening & Release Candidate**
  - Configured `export_presets.cfg` for Android (API 24 to 34, landscape, zero internet permissions).
  - Built offline local QA crash logger (`crash_logger.gd`) with automatic 256KB rotation.
  - Implemented Android back button navigation hierarchy.
  - Bounded debris particles (`MAX_ACTIVE_SHARDS <= 64`) and guarded save file corruption recovery.

- [x] **Milestone 7: Final Balance, Content & Documentation**
  - Behavior-driven enemy learning: replaced fixed encounter counters with live contextual bandit adaptation and multi-encounter evidence tracking.
  - Strict health doubling invariant: each confirmed major species evolution consistently doubles health (`base_health * 2^tier`).
  - Procedural sector expansion & guaranteed gift caches: explorable shops, gift rooms, and route branches across all layout sizes without unreachable rooms.
  - Reconciled wave schedule and 12 diverse squad compositions avoiding repeating past rosters.
  - Updated Android export configuration to API 36 (Android 16), version code 2, version 1.1.0, and documented closed testing workflows.

- [x] **Milestone 8: Roguelike Door-Controlled Upgrades & Universal Wave Combat**
  - Upgrades controlled directly by door selection: each forward door awards an un-capped subroutine upgrade or resource upon entry.
  - Procedural 1–3 door choices randomly selected per room with informative holographic floor badges.
  - Universal wave combat: eliminated 0-enemy break rooms; every chamber after calibration spawns hostile waves.
  - Direct touch and click navigation on unlocked doors alongside physical proximity entry.
  - All 52 automated deterministic test scenarios pass.

---

## Verification

Execute the full 52-scenario test suite via:
```powershell
& "D:\GODOT\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --headless -s scripts/test_runner.gd
```
Result: `--- ALL 52 DIRECTOR, EVOLUTION, STEERING, BOSS ROSTER, SETTINGS, UI & ANDROID HARDENING SCENARIOS PASSED DETERMINISTICALLY ---` (Exit code 0).
