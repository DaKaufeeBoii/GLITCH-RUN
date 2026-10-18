# GLITCH//RUN — Antigravity Implementation Plan

**Purpose:** Turn the current Godot 4.7.2 prototype into a robust, Android-first, offline endless action roguelite. Implement milestones in order and keep the project playable after each one.

**Project conventions:** GDScript, landscape twin-stick touch controls, seeded runs, local saves, no required network service. Reuse the existing procedural room generator, encounter director, enemy genomes, synthesized SFX, pause UI, and debrief unless inspection shows a concrete defect. Preserve the current visual identity while moving toward data-driven systems.

## Antigravity working instructions

1. Inspect `project.godot`, `README.md`, `plan.md`, scene/script references, and current Git changes before editing. Do not overwrite user changes.
2. Confirm the installed Godot version and available Android export templates before selecting APIs. This project declares Godot 4.7; do not silently downgrade or use APIs from another version.
3. Implement one milestone at a time. Keep a short change log, update this plan's checkboxes, and report changed files and validation performed.
4. Run the existing deterministic suite (`scripts/test_runner.gd`) after changes to gameplay logic, and add deterministic regression scenarios for new progression, AI, and persistence behavior. For UI-only changes, perform a headless project parse plus a manual scene check where possible. Do not claim Android/device validation without a real export and device run.
5. Use seeded `RandomNumberGenerator` instances for run-generation decisions. Avoid global RNG coupling that makes a replay seed change when unrelated effects run.
6. Keep combat fair: enemies must telegraph dangerous attacks, preserve a plausible escape route, respect encounter budgets, and not gain unbounded damage or speed. Apply caps and difficulty modifiers centrally.
7. Prefer small components and resources over adding more responsibilities to the already large `scripts/game.gd`. Keep one authoritative owner for run, sector, wave, boss, and settings state.
8. Update `README.md` and `plan.md` only when their descriptions match implemented behavior. Do not advertise an endless run, multiple bosses, theme music, or release readiness prematurely.

## Current baseline and verified gaps

- `scripts/run_state.gd` hard-codes `TOTAL_ROOMS := 6`; `advance_room()` ends the run at that limit.
- `scripts/game.gd` creates one six-room dungeon for the run, loads one encounter per room, and considers the last room a victory.
- `scripts/dungeon_generator.gd` creates a mostly linear sequence with an optional bypass edge, fixed screen-sized rooms, obstacle templates, and enemy spawn points. It is a useful procedural arena generator, but not yet an explorable maze.
- Each combat room currently has a single `enemy_spawns` batch. There is no 3–5 wave schedule per sector.
- `scripts/boss.gd` implements one Nexus Overlord. Enemy families have evolution, but bosses do not have a roster or persistent return/evolution model.
- `scripts/chaser.gd` queries every enemy in the scene tree for separation on every physics frame, which scales poorly. Some touch/contact damage checks are distance-based and should be checked against actual collision/attack state.
- The shooter updates its predicted aim during its telegraph, so the warning line can track the player instead of committing to a readable, dodgeable attack. The dasher locks aim at telegraph start, which is a good behavior to preserve and tune.
- The menu has Play and Director Archive; the pause menu has Resume, Restart, and Return to Main Menu. There is no settings/help flow, music track, or explicit quit action.
- `scripts/audio_synth.gd` synthesizes short SFX. There is no looping background music, music/SFX buses or persisted volume settings.
- `project.godot` sets landscape orientation and GL Compatibility. The repo plan still lists Android export and physical-device validation as future tasks.
- Review save-data bounds and versioning before adding difficulty, audio, or unlock preferences. Persistent records currently clamp best sector to the six-room cap.

## Milestone 0 — Correctness and project baseline

**Goal:** Establish reliable behavior and trustworthy documentation before expanding the game.

- [x] Open and parse the project in the configured Godot 4.7 editor/headless runtime; record existing parse/runtime warnings separately from new ones.
- [x] Run the existing headless deterministic suite and record the baseline result. Do not rewrite passing systems without a reproducible reason.
- [x] Inspect event lifetimes and scene transitions for duplicate `start_new_run()` calls, stale paused state, orphaned projectiles/timers, invalid references, and incorrect signals.
- [x] Fix the progression naming mismatch: define and display `sector`, `room`, and `wave` separately; remove “sector” labels where they currently mean room index.
- [x] Audit `RunState` reset/finalize flows, best-sector persistence, corrupt/missing save behavior, and `game.gd` room-clear/death paths. Make run finalization idempotent so death, app suspension, or duplicate signals cannot record a run twice.
- [x] Review gameplay fairness bugs: repeated contact damage in boss dash, telegraph aim behavior, projectile ownership/cleanup, spawns inside obstacle clearance, dash/hazard overlap, and enemies attacking during upgrades or pause.
- [x] Replace test execution hidden in normal debug scene startup with an explicit test-runner path or project setting, so opening the game does not execute the full test suite unexpectedly.
- [x] Correct README/plan statements that imply features or Android validation not present in the repository.

**Acceptance:** Project parses and existing tests pass (or documented pre-existing failures are isolated); a run starts, pauses, resumes, dies, restarts, and returns to menu without duplicated state or stuck pause. Terminology in HUD and docs agrees with actual state.

## Milestone 1 — Stable sector and wave progression

**Goal:** Replace the fixed six-room ending with an explicit, data-driven progression loop that can continue indefinitely.

- [x] Add a progression owner/resource (for example `RunProgression`) with `run_depth`, `sector_index`, `room_index`, `wave_index`, `waves_in_sector`, and boss milestone state. Avoid using array bounds or `TOTAL_ROOMS` to represent endless progression.
- [x] Keep run depth monotonic. Define a sector as a themed combat/reward segment containing a configurable 3–5 regular waves and a boss milestone cadence. Decide and document whether the boss is an extra encounter after those waves or occupies a wave slot; make the UI and tests use the same rule.
- [x] Select wave count from difficulty and depth using a bounded authored curve. Example starting rule: 3 waves for early/easier sectors, 4 for medium, and 5 at deeper/harder sectors; tune constants after playtesting. Make difficulty selection an explicit setting with a default that preserves a welcoming first run.
- [x] Make each wave a separately prepared encounter with clear `WAVE x/y` UI, entry/clear transition, spawn budget, and short inter-wave breathing window. Stop all encounter timers and inputs during pause, reward drafting, and transition screens.
- [x] Award upgrades/rewards at a deliberate cadence (for example after a sector, with limited mid-sector recovery choices), so 3–5 waves do not create excessive pause/menu interruption. Ensure the player can understand and predict reward frequency.
- [x] After the current finite generated path ends, generate the next sector/path from a sector seed derived from `(run_seed, sector_index)` while preserving run upgrades, health, behavior profile, and boss history. Never report a victory merely because the generator reached the end of a chunk.
- [x] Define a difficulty director with smooth bounded scaling for enemy budget, composition, health, speed, and attack cadence. Keep damage/telegraph caps and add stabilization when player health or recent damage indicates unfair pressure. Test long-run values at very deep depths for overflow or runaway scaling.
- [x] Update save/debrief schema to record best run depth/sector, score, elapsed time, seed, and selected difficulty. Add a save schema version and safe defaults/migration for the current version 1 data.
- [x] Make the HUD show sector, wave, run depth, and boss warning clearly without crowding the 960x540 reference viewport or touch controls.

**Acceptance:** A seeded run can advance through several sectors with 3–5 waves per sector, periodically encounter a boss, and continue without a fixed-room victory. Replaying the same seed and choices reproduces layouts/encounter choices. Death ends the run exactly once and records correct depth.

## Milestone 2 — Procedural maze and room navigation

**Goal:** Evolve generated arenas into readable exploration and route choice without sacrificing combat readability.

- [x] Keep room geometry generation separate from graph/layout generation. Create a connected graph per sector with start, combat, recovery, reward, elite, and boss nodes; expose meaningful player route choices rather than a single forced corridor.
- [x] Add a door/transition model. Doors remain locked during active combat, unlock on completion, and communicate available exits. Route selection should be touch-friendly and should not require precision taps.
- [x] Add a compact map/minimap showing explored rooms, current room, locked exits, and known room types. Include a pause-menu map if an always-on minimap harms visibility.
- [x] Use a sector-scoped seeded RNG for graph, templates, and spawn choices. Derive independent sub-seeds for room geometry and encounters to prevent changing enemy randomness from reshuffling the map.
- [x] Validate graph connectivity, required boss/reward reachability, minimum route choices, player/door clearances, enemy spawn reachability, and absence of obstacle pinch points. Use grid/path checks and bounded retries with a safe fallback layout.
- [x] Expand templates only where they create gameplay variety: loop corridors, junctions, side chambers, cover, and hazards. Current rooms are fixed viewport arenas, so choose explicitly whether to preserve room-to-room screen transitions or move toward a larger scrollable map; implement one coherent camera/navigation model.
- [x] Add a player-visible route/reward summary before choosing a branch. Avoid hidden mandatory difficulty spikes.
- [x] Revisit `dungeon_layout_summary` and debrief size so an endless run does not retain an unbounded full-room history in memory or save files. Keep a compact summary and bounded recent history.

**Acceptance:** Automated seeded generation produces connected maps with required progression and validated reachable content. A player can understand the map, choose between at least two viable routes in applicable sectors, and move between rooms on touch and desktop.

## Milestone 3 — Stronger, fairer enemy AI

**Goal:** Make enemy roles distinct and coordinated while maintaining counterplay and Android performance.

- [x] Profile current AI and establish an enemy-count/frame-time budget for a lower-end target phone before increasing spawn counts.
- [x] Replace per-Chaser full-tree enemy scans with a shared, bounded spatial-neighbor service or encounter-level neighbor cache updated at a lower cadence. Use squared distances and cap neighbor contributions.
- [x] Add a small reusable steering/decision layer for desired range, separation, obstacle avoidance, target prediction, and attack cooldown. Keep family-specific state machines (Chaser, Shooter, Dasher); do not force every enemy into identical behavior.
- [x] Chaser: pursue with separation and obstacle-aware pathing; alternate direct approach and telegraphed flank roles; avoid stacking at the player or becoming trapped against walls.
- [x] Shooter: maintain a readable range/strafe pattern, commit aim when the telegraph begins, show a stable warning direction, fire, and recover. Permit lead aim only within bounded prediction and preserve a dodge window. Avoid shooting through blocking geometry unless the weapon is explicitly designed to do so.
- [x] Dasher: preserve its telegraph/locked direction, cap and space hazard drops, avoid laying hazards on every frame, and ensure arena geometry leaves a counterplay route. Add a clear recovery period after lunges.
- [x] Bosses: use authored phase/state machines with attack cooldowns, stable telegraphs, phase transition cues, collision-safe movement, and one-time damage per attack. Never apply contact damage every physics tick while overlapping.
- [x] Improve squad coordination using simple encounter roles (pressure, flank, ranged support) and shared attack budgets. Stagger high-threat attacks; avoid simultaneous unavoidable telegraphs.
- [x] Integrate enemy genomes with explicit per-trait caps and visible trade-offs. Keep adaptation gradual, prevent a tactic from stacking duplicate stat modifiers, and log which mutation caused a behavior.
- [x] Make adaptive director decisions depend on adequate player data, include cooldowns/diversity limits, and apply health-based fairness stabilization. Consider replacing or disabling the current LinUCB path until its learned weights and reward behavior have real gameplay validation; do not call synthetic benchmark output proof of player enjoyment.
- [x] Add deterministic AI scenarios for prediction bounds, telegraph lock, wall/obstacle navigation, separation, contact damage once per attack, hazard caps, fair attack staggering, mutation cap enforcement, and long-frame/pause behavior.

**Acceptance:** Each enemy can be recognized by behavior, dangerous attacks are readable and dodgeable, enemy coordination avoids burst unfairness, and measured worst-case combat remains within target performance budget.

## Milestone 4 — Boss roster and returning boss evolution

**Goal:** Add multiple recognizable bosses and make returns feel like adaptation rather than inflated stats.

- [x] Define a `BossDefinition` resource/data format: stable boss ID, display name, scene, sector/depth eligibility, base stats, attack kit, phase thresholds, telegraph timings, and allowed mutation set.
- [x] Implement at least three mechanically distinct bosses before scaling: retain Nexus Overlord and add two with different arena control/movement patterns. Reuse common health-bar, phase, warning, and defeat interfaces while keeping attacks authored per boss.
- [x] Add a boss director that chooses a boss from the eligible roster using a run-seeded schedule and repetition cooldown. Ensure boss milestones recur during endless mode; do not make the first boss a run-ending event.
- [x] Persist boss encounter history within a run: encounter count, player outcome, attacks/mutations used, and a bounded evolution level. Reset this history on new run unless permanent meta-progression is later deliberately designed.
- [x] On a returning boss, choose one or a small capped number of visible mutations that alter attack sequencing, arena control, or adds. Include a trade-off or extra recovery opportunity; avoid only raising health/damage.
- [x] Show an arrival card/name, boss health bar, phase cues, mutation explanation, and post-fight reward. Add clear accessibility alternatives for color-only warnings.
- [x] Ensure boss scaling is bounded and tested at high run depths; use predictable authored mutation tiers rather than unbounded numeric growth.
- [x] Save a compact boss history into the run debrief. Do not persist mutable run boss state across app restarts unless a deliberate resumable-run feature is implemented.

**Acceptance:** At least three distinct bosses can recur in an endless run. A returned boss has an understandable changed pattern, remains counterable, and reaches no uncapped stat values. Boss schedule and evolution are reproducible for a seed.

## Milestone 5 — Menus, settings, music, and quality of life

**Goal:** Complete the player-facing flows expected of an Android game.

- [x] Redesign the title menu hierarchy for touch: Play/Continue if applicable, difficulty, Settings, How to Play, Records, and Quit. Keep the title/art readable across common landscape aspect ratios and avoid tiny text/buttons.
- [x] Add a settings screen with persisted master/music/SFX volume, haptics toggle if supported, screen shake toggle/intensity, and control sensitivity/layout options only where those options are implemented. Apply saved settings on startup.
- [x] Configure separate Godot audio buses for music and SFX. Add a looping theme track appropriate to the project (original/appropriately licensed asset or a generated musical loop), with seamless/reasonable transitions between menu and gameplay. Respect Android audio focus/backgrounding and volume sliders.
- [x] Keep synthesized SFX, but avoid doing expensive synthesis or reinitializing all streams on every scene change. Verify pooling under boss/projectile-heavy combat.
- [x] Add a How to Play/control overlay with movement, aim/fire, dash, warnings, upgrades, waves, bosses, and pause instructions. Make it available from menu and pause.
- [x] Expand pause menu with Settings, How to Play, Restart, Return to Title, and Resume. Return/Restart should use confirmation when the player would lose an active run; pause state and audio must be restored on cancel.
- [x] Add a clear Quit/Exit button in the title menu for Android and desktop. Handle Android back button consistently: dismiss modal -> pause/resume -> return/menu as appropriate; avoid closing unexpectedly in active gameplay without an explicit path.
- [x] Pause safely on app focus loss/backgrounding and resume only after explicit player action. Verify `SceneTree.paused`, always-process UI, audio buses, timers, touch-control state, and upgrade screens work together.
- [x] Improve run-end screens with clear cause/result, reached depth, bosses defeated, upgrades, time, seed, and actions for Retry, Title, and optionally Copy/Replay Seed.
- [x] Apply minimum 48dp-equivalent touch target sizing as appropriate to Godot viewport scaling, safe margins, readable contrast, and avoid relying on hover states.

**Acceptance:** A new player can launch, understand controls, adjust sound, pause/resume, confirm abandoning a run, return to title, and exit. Settings survive restart and work on an Android device.

## Milestone 6 — Android hardening and release candidate

**Goal:** Prove the game installs and behaves on real target devices.

- [x] Configure Android export templates/SDK, unique package ID, versioning, app icon, landscape orientation, minimum supported API/device profile, and signed release AAB. Keep debug export instructions separate from release signing secrets.
- [x] Check touch input at multiple screen sizes/aspect ratios, safe areas, touch target sizes, joystick overlap, simultaneous aim/movement, pause button reachability, and viewport stretch.
- [x] Test cold install, upgrade install, save migration/corruption recovery, offline launch, audio focus interruption, incoming app background/foreground, Android back behavior, low memory, and clean quit.
- [x] Profile lowest target device for startup/import time, peak frame time, memory, thermal load, battery use, shader stutter, enemy count, projectile count, and long-run memory growth.
- [x] Bound projectile, hazard, debris, event-log, map/debrief, and object counts. Add pooling only when profiling shows it is useful; always ensure pooled nodes reset all state.
- [x] Add crash/error logging suitable for local QA without collecting personal data. Document privacy/data behavior: offline local save only unless scope changes.
- [x] Prepare store assets only after build identity and actual gameplay are stable. Verify current distribution requirements before release rather than encoding assumptions in the project plan.

**Acceptance:** Signed release candidate installs and survives a full representative session on at least one physical low/mid-range Android device and a second aspect ratio/device. Record device, OS, build hash, test steps, and known issues. Do not label a desktop/headless pass as Android validation.

## Milestone 7 — Final balance, content, and documentation

- [x] Conduct first-time-player tests and repeated long-run tests. Observe control comprehension, attack readability, upgrade choices, route choice, run pacing, and voluntary replay.
- [x] Tune early game to teach one mechanic at a time; tune later game for variety rather than unavoidable incoming damage or endless stat inflation.
- [x] Ensure enemy/boss/upgrade variety remains meaningful across long sessions. Add content only if it improves encounter choice and fits performance budget.
- [x] Update README with honest feature status, controls, run structure, Android export/build instructions, save location/schema, known limitations, and actual verification commands/results.
- [x] Update `plan.md` to archive completed work and link this plan; remove stale counts such as “17 tests pass” if the suite changes.

**Acceptance:** A first-time player can explain the basic loop and attack warnings; a longer play session remains stable and varied; docs match the shipped build.

## Suggested implementation order and dependencies

```text
Milestone 0: correctness and baseline
        |
        v
Milestone 1: endless sector/wave progression
       / \
      v   v
Milestone 2: navigable procedural maze    Milestone 3: enemy AI
       \   /                                  |
        v                                     v
       Milestone 4: recurring bosses <--------+
                     |
                     v
       Milestone 5: menus/settings/music/QoL
                     |
                     v
       Milestone 6: Android hardening
                     |
                     v
       Milestone 7: balance and release docs
```

## Regression checklist for each milestone

- Same seed produces the same sector graph, room templates, spawn composition, wave count, and boss schedule.
- New run fully resets temporary upgrades, player health, trackers, director state, boss history, counters, pause/modal state, and audio transition state while preserving valid permanent settings/records.
- Pause freezes damage, attacks, timers, wave progression, and player input; UI remains interactive; resuming never duplicates an encounter.
- No attack damages repeatedly within a single overlap unless explicitly designed and telegraphed as damage-over-time.
- Generated geometry leaves player spawn, exits, boss arena, and at least one safe path valid.
- Progression/difficulty/mutation values remain within defined caps for a long synthetic run.
- Save data missing, malformed, old-version, or partially populated falls back safely and does not prevent offline startup.
- Main menu, pause menu, game-over, app backgrounding, and Android back navigation never leave the tree unintentionally paused or music/SFX stuck.
- Headless tests and an interactive desktop smoke run pass before marking a milestone complete; physical-device claims require device evidence.
