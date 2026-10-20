# GLITCH//RUN — Behavior-Driven Enemy Learning Plan

> **Status: Design proposal, not a release-status document.** The game currently has run-scoped enemy adaptation/evolution, an explicit first-sector lock, and deterministic tests for per-enemy evidence and reset behavior. The more open-ended mutable-gene learner, fully matched Python/GDScript training pipeline, and all acceptance criteria in this proposal have not been verified as complete. Sections below describe the target design; statements under “Current implementation problems” are audit observations from when this plan was written and should be rechecked against current code before implementation.

## Objective

Replace fixed encounter-count enemy evolution with a run-scoped system in which each enemy species observes the player's behavior, learns which responses work fairly, and changes its own behavior genome over the course of that run.

The system must make the following gameplay possible:

- **Red Chasers:** begin with contact pursuit. When observations show that the player consistently keeps distance or escapes pursuit, their population can evolve greater pursuit speed. If that response remains ineffective and ranged pressure proves useful and fair, ranged attack behavior can emerge in the population.
- **Purple Dashers:** begin with a telegraphed dash. When the player consistently evades the dash, their population can evolve a damaging trail behind the dash. If the player continues to escape, dash speed or timing can adapt.
- Other families adapt only from their own encounters and can develop their own useful counter-responses.
- A species that was absent from an encounter receives no learning evidence from it.
- Death, quit, or starting a new run clears all learned traits and evolution for that run.
- Each **confirmed major species evolution** doubles that species' maximum health. Continuous policy learning alone is not a major evolution event and does not double health.

The adaptations above describe outcomes the system should be capable of discovering. They must not be implemented as a fixed sequence tied to encounter numbers.

## Current implementation problems to fix

1. `evolution_manager.gd` advances families using fixed `BATTLES_FOR_FIRST_EVOLUTION`, `BATTLES_FOR_SECOND_EVOLUTION`, and `BATTLES_FOR_THIRD_EVOLUTION` counters. Remove those schedules and their tier-specific promotion branches.
2. `encounter_director.gd` routes decisions through a single global `LearningPolicy`; one family can influence responses for another. Learning and evidence must be species-specific.
3. `learning_policy.gd` labels itself LinUCB, but its in-game weight update is independent per feature and does not update a full contextual covariance model. Implement the algorithm consistently or rename it accurately.
4. The Python trainer and the GDScript runtime do not share the same learning/update implementation. A weight file must be produced and consumed with matching feature order, action order, reward definition, and model version.
5. `EncounterDirector.reset()` resets policy weights after they were loaded during initialization. Run reset behavior must be deliberate and tested; the fresh run must start from a known baseline, not an accidental mixture of packaged and stale in-memory weights.
6. Genome instances returned for spawns must not cause unrelated enemies or later encounters to share mutable per-enemy state. Keep population genomes distinct from spawned phenotype snapshots and record which variant actually fought.
7. The current fitness/evolution path must be audited so only families and variants that actually participated receive outcome credit.

## Design constraints

- No fixed “evolve after N battles/waves/sectors” rules.
- No internet service, cloud inference, telemetry upload, or runtime Python dependency. The learner runs locally in Godot.
- Do not run machine-learning updates every frame. Collect lightweight observations during combat; update policy and population at encounter boundaries.
- Keep movement, collision, attack telegraphs, damage caps, and hazard limits bounded for Android performance and fair counterplay.
- Authored actions remain the enemies' available action vocabulary. The learner chooses and tunes among them; hand-authored rules must not dictate the evolution order.
- Do not save run-evolved genomes or evidence after death/reset.

## Target architecture

### 1. Player behavior observations

Extend `behavior_tracker.gd` to produce a normalized, recent-window feature vector. Start with:

1. Dash frequency and dash timing relative to enemy telegraphs.
2. Movement speed and heading-change/escape rate.
3. Distance preference: close, mid-range, or kiting.
4. Stationary firing/camping ratio.
5. Firing uptime and shot accuracy.
6. Time spent in cover or outside enemy line of sight, where measurable.
7. Damage and successful evasions attributed to enemy family and attack pattern.

Keep per-family exposure and outcome counters. An observation is usable by a family only if a valid enemy of that family participated in the corresponding combat window. Decay old behavior evidence so the species can react when the player changes tactics mid-run.

### 2. Species learning state

Create a clear species-level state object, either as a new script or a well-defined section of `evolution_manager.gd`. Each of `CHASER`, `DASHER`, and `SHOOTER` owns:

- A separate contextual policy/model and action statistics.
- A bounded population of genome candidates.
- Per-variant encounter exposure, survival, attack attempts, hits, damage, forced player movement, and fairness penalties.
- A rolling player-style estimate derived only from that species' own encounters.
- Evolution/promotion history and model confidence for the UI/debrief.

Store this state in memory for the active run only.

### 3. Behavior policy

Use a small contextual bandit per species to choose among that family's available behavior modules. Use the same implementation in training and gameplay. If retaining LinUCB, use its full contextual update:

- Context `x`: the normalized player behavior and local combat context.
- Action `a`: a family-specific response, such as pursue, strafe, predictive shot, dash, or hazard trail.
- Expected reward: `theta[a] · x`.
- Exploration score: expected reward plus a confidence term derived from `xᵀ A[a]⁻¹ x`.
- Update `A[a]` and `b[a]` with the observed context and reward; recompute the action weights from those values.

Do not reuse the current per-feature independent update and call it LinUCB. Validate imported model dimensions and feature/action order before accepting weights. If the full update proves too costly or complex, choose another named online method and use that exact method in both the trainer and runtime.

Policy selection occurs at meaningful decision windows (for example, when an enemy begins an attack cycle), not every frame. Add hysteresis/cooldowns so an enemy does not flicker between behaviors.

### 4. Evolving genomes

Change `enemy_genome.gd` from a tier plus named-mutation progression into a phenotype with bounded, mutable genes. Candidate genes include:

- Pursuit speed and acceleration.
- Contact aggression and preferred engagement distance.
- Ranged attack tendency, aim lead, and shot timing.
- Dash speed, commitment timing, and recovery.
- Hazard-trail tendency, spacing, duration, and count.
- Strafe/flanking tendency and telegraph/recovery modifiers.

Each family gets only behavior genes that map to its valid action modules. Genome values influence both the policy's behavior choice and the resulting action parameters. Keep readable telegraphs, attack cooldowns, collision safety, and hazard caps as non-learnable engine safety constraints.

After an encounter, score only the genome variants that actually fought. Use fitness that balances:

- Whether the response addressed the observed player behavior.
- Whether it produced useful pressure (such as forcing movement or reducing repeated escapes).
- Whether the encounter stayed within the target fairness/challenge range.
- Whether the variant survived and performed its role.
- Penalties for burst damage, unavoidable hits, and overkill.

At an encounter boundary, select variants by measured fitness, retain the better candidates, and produce offspring using bounded crossover/mutation. Mutation should explore useful gene changes; the species-specific contextual policy should guide action selection. Promote a meaningful species evolution only when observed evidence shows a sustained behavioral/fitness change, not because a counter reached a preset encounter number. A failed mutation must be eligible for rejection or rollback.

For every confirmed major promotion, apply the requested health rule: `max_health = base_health * 2^major_evolution_count`. Do not apply this multiplier to ordinary online weight updates or minor gene drift. Track the count in the species run state and expose it to the debrief. Balance testing must explicitly check the effect of repeated doubling in endless runs.

### 5. Enemy runtime integration

Update `encounter_director.gd`, `game.gd`, and the enemy scripts (`chaser.gd`, `dasher.gd`, `shooter.gd`) so:

- The director sends each family only its own observations and chooses behavior through that family's learner.
- Spawned enemies get an immutable snapshot of a selected genome variant plus a stable variant ID for outcome attribution.
- The enemy executes learned behavior using existing attack/movement primitives and preserves telegraph, cooldown, and fairness constraints.
- Encounter completion returns per-family and per-variant outcomes; it must not infer that all species fought when the list is empty.
- Evolution decisions and their reasons are emitted as structured records for the debrief and threat archive.

Keep boss evolution isolated from this change unless boss learning is separately specified. Do not accidentally apply regular species evidence to bosses.

### 6. Learning reset and lifecycle

Add one explicit `reset_run_learning()` path invoked by new run, death, quit session, and reset. It must clear:

- Species observations and rolling player profiles.
- Per-species policy updates and action history.
- Variant fitness, offspring, mutations, and promotion counts.
- Active combatant references and pending encounter attribution.
- Run evolution history.

The reset should recreate the same documented baseline every time. Packaged training weights may be loaded as a fixed starting prior only if that is deliberate and version-checked; no updated run weights or evolved genomes may leak into the next run.

### 7. Training and evaluation parity

Refactor `train_and_evaluate_policy.py` to use the same state features, species actions, reward function, and model format as the Godot runtime. Prefer a shared, versioned model specification and explicit export/import validation. Training should include behavior-changing opponents, not only static archetypes, so the learner is evaluated on whether it reacts when the player changes strategy.

Keep the game offline-first. Training may remain an offline development tool; the game must not require Python to run.

### 8. Player-facing explanation

Update the threat/debrief UI to report evidence rather than vague “evolved” messages:

- Species and genome variant.
- Behavior observed (for example, repeated long-range kiting or escaping Dasher telegraphs).
- The trait/action that changed and its before/after value.
- Evidence/sample count and confidence.
- Fitness/fairness outcome and a counterplay hint.

Do not claim that an enemy learned a trait if no participating encounter evidence supports it.

## Implementation sequence

1. **Baseline audit:** Trace spawn selection, genome duplication, active combatant tracking, encounter start/end, reset/death/quit, and policy load paths. Document which enemy fields currently alter actual behavior.
2. **Data model:** Add species learning state, variant IDs, observation records, outcome records, and versioned model serialization. Keep this isolated from UI changes.
3. **Observation pipeline:** Add family-attributed player behavior and attack outcome tracking. Confirm absent species receive no observations.
4. **Runtime learner:** Implement the chosen contextual learning algorithm per species and remove the global policy's authority over species evolution. Match trainer and runtime math.
5. **Genome evolution:** Replace encounter-count tiers with bounded behavior genes, variant fitness, selection, crossover/mutation, evidence-based promotion, and rollback of poor variants.
6. **Enemy integration:** Wire species policies/genes into Chaser, Dasher, and Shooter behavior. Add the player behavior responses described in the objective as discoverable outcomes, not prescribed unlock stages.
7. **Run lifecycle:** Centralize learning reset and call it on every new-run/death/quit path. Verify no genome/policy learning survives a reset.
8. **Debrief and diagnostics:** Show observed behavior, selected response, evidence, fitness, health multiplier, and reset state in UI/debug output.
9. **Deterministic evaluation:** Extend the existing headless scenario suite and Python benchmark for controlled player behavior profiles, mid-run behavior switches, family isolation, fairness, promotion, and reset. Compare fixed baseline, old implementation, and learned system across identical seeds.
10. **Android performance and balance:** Profile policy decisions and population updates on mobile-target settings. Confirm work happens at encounter boundaries, not expensive per-frame loops. Evaluate health doubling in deep endless runs.

## Acceptance criteria

- No species changes behavior solely because a fixed number of encounters, waves, or sectors passed.
- Repeated kiting can cause Chasers to favor stronger pursuit; continued successful kiting can make ranged behavior more likely when that response has fair positive outcomes.
- Repeatedly evading Dasher charges can cause its population to favor hazard trails; continued escapes can increase its dash effectiveness.
- Changing player strategy mid-run changes later observations and can redirect learning.
- Learning is isolated by species and attributed to the genome variants that actually fought.
- A response that causes unfair damage is penalized and can lose selection pressure or be rolled back.
- Every major species evolution doubles that species' max HP; ordinary model updates do not.
- Death, quit, reset, and new run clear all current-run evolutions and learning state.
- Runtime and offline trainer use matching feature/action/reward/model definitions.
- Debrief explains what the enemy observed and why its behavior changed.
- Deterministic tests demonstrate these properties across repeatable seeds, and the Android build remains responsive.

## Files expected to change

- `scripts/behavior_tracker.gd`
- `scripts/learning_policy.gd` (or a replacement species policy script)
- `scripts/evolution_manager.gd`
- `scripts/enemy_genome.gd`
- `scripts/encounter_director.gd`
- `scripts/game.gd`
- `scripts/chaser.gd`
- `scripts/dasher.gd`
- `scripts/shooter.gd`
- `scripts/debrief_terminal.gd`
- `scripts/test_director.gd` and `scripts/test_runner.gd`
- `scripts/train_and_evaluate_policy.py`
- `assets/data/learned_policy_weights.json` only if the versioned model schema changes

Do not report the work complete until the acceptance criteria are implemented and the deterministic evaluation has been run and its results recorded.
