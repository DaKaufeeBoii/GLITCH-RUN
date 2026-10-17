# GLITCH//RUN — Implementation Plan

**Engine:** Godot 4.7.2 stable  
**Language:** GDScript  
**Target:** Offline-first, single-player Android action roguelite  
**Current control target:** Landscape, twin-stick style on touch screens

This plan tracks the current prototype, the next playable milestones, and later work that should wait until the core game is enjoyable. Complete milestones in order; the time estimates from the original concept are targets, not release deadlines.

## Product goals

- Make movement, aiming, shooting, and dodging satisfying before adding complex systems.
- Keep the first version small enough for a solo developer to finish.
- Make adaptive enemy tactics visible, gradual, and fair.
- Keep the core game playable offline, with no required account, server, or AI service.
- Describe the first director as **adaptive game AI**. Claim machine learning only after training and evaluating an actual model.

## Current project structure

```text
project.godot
scenes/
  main.tscn
  player/player.tscn
  enemies/chaser.tscn
  weapons/projectile.tscn
scripts/
  game.gd
  player.gd
  chaser.gd
  projectile.gd
  mobile_controls.gd
README.md
plan.md
```

The project currently uses simple drawn shapes. Keep placeholder visuals until combat and controls have been tried in the editor and on a phone.

## Progress

- [x] Create the Godot 4.7 project and set the main scene.
- [x] Add one bounded combat room with a grid, player, and chasing enemy.
- [x] Add movement, aiming, firing, dash, health, enemy damage, elimination count, death, and restart.
- [x] Add keyboard/mouse controls and virtual touch controls for movement, aim/fire, and dash.
- [x] Add a README with opening instructions and controls.
- [ ] Open in Godot 4.7.2, run the main scene, and fix any import, parse, or runtime issues.
- [ ] Install the first Android build on a physical device and tune touch controls.

## Milestone 0 — Confirm the first playable slice

**Purpose:** Catch engine-side issues and check that the prototype is fun to control.

1. Open the project folder in Godot 4.7.2 stable.
2. Let the editor import project files and resolve any reported script or scene errors.
3. Run `res://scenes/main.tscn`.
4. Check that the player moves with WASD and the arrow keys, aims and fires with the mouse, and dashes with Shift or Space.
5. Defeat the chaser; confirm it respawns and the elimination count increments.
6. Allow the enemy to damage the player; confirm health reaches zero, the run ends, and restart starts a clean run.
7. Tune movement speed, weapon cadence, enemy speed, collision spacing, and damage cooldown based on how it feels.
8. Configure Android export templates and SDK paths, export a development build, and try it on a physical phone.
9. Check that the touch stick moves, the right-side touch aims and fires, and the dash control works while moving.

**Exit condition:** The project opens without errors and a player can move, fight, take damage, die, and restart on desktop and Android.

## Milestone 1 — Complete a full run

**Purpose:** Turn the single-room prototype into a small roguelite loop without procedural-generation complexity.

1. Add a `RunState` owner for current health, score, room index, upgrades, and run completion.
2. Create six to eight hand-authored room templates with clear boundaries and spawn points.
3. Add room transitions and a fixed or shuffled sequence of rooms.
4. Add two more basic enemy types. Give each one a distinct attack pattern and a readable warning.
5. Add reward selection after a cleared room, initially choosing from two or three upgrade cards.
6. Create six to nine upgrades that meaningfully change weapons, movement, survivability, or damage.
7. Add one boss with a small number of telegraphed attacks.
8. Add run results that distinguish defeat from boss victory and allow instant restart.
9. Ensure every transition clears temporary projectiles, timers, and enemy state and preserves only intended run data.

**Exit condition:** A run has multiple rooms, a reward choice, a boss, a win/loss result, and a clean restart.

## Milestone 2 — Add the adaptive director

**Purpose:** Make the game's main differentiator understandable and fair using rules that can be tested.

### Track player behavior

1. Add a `BehaviorTracker` that records recent combat behavior in a rolling 30–60 second window.
2. Track only the signals needed for the first tactics:
   - Dashes per minute.
   - Ranged damage divided by total damage.
   - Time spent close to enemies divided by combat time.
   - Time spent firing while mostly stationary.
   - Damage received per minute, for difficulty and fairness checks.
3. Normalize mobility, ranged, and aggression scores to values from 0 to 1.
4. Treat insufficient data as unknown; do not interpret a zero as proof of a different preferred style.
5. Reset run-scoped observations when a new run begins.

### Select and apply tactics

1. Add an `AdaptiveDirector` that receives the current behavior profile, room difficulty, enemy budget, and recent tactics.
2. Start with three authored counters:
   - High mobility: delayed predictive attacks or attacks that limit escape routes.
   - High ranged reliance: a flanker or a slowly advancing shielded enemy.
   - High close-range aggression: marked area-denial zones and repositioning pressure.
3. Select tactics with weighted choice rather than a rigid profile-to-counter mapping.
4. Give tactics cooldowns and limits so the same response does not repeat every room.
5. Validate each selection against room space, difficulty limits, warning time, and available escape routes.
6. Show a brief on-screen adaptation message when the director changes tactics.
7. Record whether a tactic repeatedly causes unavoidable hits; lower its future selection weight when its outcomes are unfair.
8. Add deterministic test scenarios for high-mobility, ranged, aggressive, mixed, and insufficient-data profiles.

**Exit condition:** Deliberately different play styles trigger different tactics, each tactic is telegraphed, and no tactic changes an encounter instantly or removes counterplay.

## Milestone 3 — Make the run legible and replayable

1. Add the main menu, pause flow, settings, and a clear end-of-run screen.
2. Improve hit feedback with brief invulnerability flashes, knockback where appropriate, sound, and readable warnings.
3. Improve upgrade descriptions so the player understands the effect before choosing.
4. Explain director changes in player-facing language rather than exposing raw scores.
5. Add local save data for settings and a small set of permanent unlocks.
6. Keep temporary run data separate from persistent unlocks; validate save loading when the file is missing or incomplete.
7. Check text size, touch target size, contrast, pause behavior, and resume-from-background behavior on a phone.

**Exit condition:** A first-time player can start a run, understand the controls and upgrade choices, pause, finish a run, and start another.

## Milestone 4 — Art, audio, and performance pass

1. Establish a compact pixel-art palette: deep navy environments, cyan player effects, magenta upgrades, and red enemy warnings.
2. Choose a consistent sprite and tile scale based on phone readability.
3. Replace placeholder shapes only after the combat silhouettes and attack warnings are clear.
4. Add distinct firing, hit, dash, upgrade, boss, and director-adaptation cues.
5. Profile on a lower-end Android phone while rooms contain the largest intended number of enemies and projectiles.
6. Reuse or clean up short-lived projectiles and visual effects if profiling shows allocation or frame-time issues.
7. Check performance, heat, battery use, loading, and readability at more than one screen size.

**Exit condition:** The game remains readable and responsive in the busiest intended encounter on target phones.

## Milestone 5 — Playtest and tune

1. Recruit a small group of testers after the full run is playable.
2. Observe whether players understand movement, dash timing, enemy warnings, upgrades, and director adaptations without coaching.
3. Record bugs and confusion separately from balance feedback.
4. Compare deaths, boss completion, damage taken, tactic exposure, perceived fairness, and voluntary replay.
5. Fix crashes, broken transitions, and unavoidable attacks before adding content.
6. Repeat the playtest after major balance or control changes.

**Exit condition:** Testers can complete or fail runs reliably, can explain the adaptive mechanic, and do not identify recurring unavoidable damage as a core frustration.

## Milestone 6 — Prepare an Android release candidate

1. Confirm the package name, app icon, orientation, supported aspect ratios, and minimum device requirements.
2. Recheck Android export configuration and produce a signed Android App Bundle for store distribution.
3. Test clean install, upgrade install, save persistence, pause/resume, audio focus, and restart on physical devices.
4. Prepare store screenshots, short gameplay footage, description, privacy disclosures, and support contact details.
5. Add optional rewarded ads only after the game is stable and only if the placement does not interrupt normal play.
6. Consider cosmetics or an ad-free purchase only after retention and player interest are established.
7. Check current store requirements and fees before publishing.

**Exit condition:** A release candidate installs cleanly, completes full runs without blocking defects, and has the required store materials.

## Milestone 7 — Optional genuine ML experiment

**Do this after the rule-based director and core game are stable.**

1. Define the research question: does a learned policy improve enjoyment or fairness over the rule-based director?
2. Use consent-based, minimal gameplay data from controlled tests; avoid collecting identifiers that are not needed.
3. Build offline Python feature vectors from the tracked behavior metrics and room context.
4. Define clear labels or outcomes and split scenarios into training and held-out evaluation sets.
5. Train a small classifier or policy experiment and compare it against both the fixed director and the rule-based adaptive baseline.
6. Evaluate fairness, deaths, completion, perceived difficulty, and voluntary replay; report the limits of a small sample.
7. Integrate a model only if it measurably improves the experience. Keep a rule-based fallback and avoid a network inference dependency.
8. If a model is shipped, document its format, evaluation, runtime cost, and exactly what the game does with it.

**Exit condition:** The project can show reproducible evidence that the learned approach adds value. Otherwise, keep the rule-based director and describe it accurately as adaptive game AI.

## Scope to defer

- Online multiplayer, accounts, cloud saves, or a paid backend.
- LLM-controlled enemies or online AI inference.
- Training on player data as a live service.
- Large open worlds, many biomes, or hundreds of rooms.
- Multiple characters, complex inventories, crafting, or battle passes.
- Ads, subscriptions, and paid items before the core loop is stable.

## Useful evidence for a portfolio

- A short gameplay video and screenshots from an Android device.
- A README with controls, architecture, setup, and build steps.
- A diagram of the run loop and adaptive-director data flow.
- A description of behavior metrics and counterplay rules.
- Comparison scenarios for fixed and adaptive director behavior.
- Test results for behavior scoring, tactic selection, and run transitions.
- Real-device performance notes.
- Python notebooks and evaluation results only if a real ML experiment is completed.
