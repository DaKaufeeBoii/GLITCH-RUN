extends RefCounted
class_name EvolutionManager
## Multi-layered behavior-driven enemy evolution and population manager for GLITCH//RUN.
## Implements:
##   1. Behavior-Driven Evolution (species evolve strictly when player behavior evidence requires it,
##      never solely because a fixed number of battles passed).
##   2. Strict Species Evidence Isolation (species evolve ONLY from their own battle data).
##   3. Phenotype Snapshot Spawning (spawned enemies receive isolated genome copies, preventing state leakage).
##   4. Strict Health Invariant (each confirmed major evolution doubles that species' max HP).
##   5. Run-Scoped Lifetime (reset_run_learning purges all learned traits on death/quit/restart).

const ENEMY_GENOME_SCRIPT := preload("res://scripts/enemy_genome.gd")
const LEARNING_POLICY_SCRIPT := preload("res://scripts/learning_policy.gd")

const POOL_SIZE_PER_FAMILY := 3
const MUTATION_PERTURBATION := 0.08 # Max 8% trait adjustment per generational mutation

var generation := 1
var active_genomes: Dictionary = {
	"CHASER": [],
	"SHOOTER": [],
	"DASHER": []
}

var species_policies: Dictionary = {}
var species_evidence: Dictionary = {}
var evolution_history: Array[Dictionary] = []
var active_combatants: Array[RefCounted] = []
var current_biome: int = 2
var run_evolution_unlocked := false
var per_enemy_evolution_mode := false
var strict_sector_lock := false
var combatant_records: Dictionary = {}
var decision_history: Array[Dictionary] = []
var next_instance_id := 1
var encounter_id := 0
var last_mutation_selection: Dictionary = {}


func _init() -> void:
	reset()


func reset() -> void:
	reset_run_learning()


var deployed_actions: Dictionary = {}


func reset_run_learning() -> void:
	## Resets all species learning states, policies, active genomes, and history to a clean baseline.
	generation = 1
	evolution_history.clear()
	active_combatants.clear()
	deployed_actions.clear()
	combatant_records.clear()
	decision_history.clear()
	next_instance_id = 1
	encounter_id = 0
	last_mutation_selection.clear()
	run_evolution_unlocked = false
	per_enemy_evolution_mode = false

	species_policies = {
		"CHASER": LEARNING_POLICY_SCRIPT.new("CHASER"),
		"DASHER": LEARNING_POLICY_SCRIPT.new("DASHER"),
		"SHOOTER": LEARNING_POLICY_SCRIPT.new("SHOOTER")
	}

	species_evidence = {
		"CHASER": {
			"encounters_fought": 0,
			"combat_time": 0.0,
			"kited_evidence": 0.0,
			"camp_evidence": 0.0,
			"damage_dealt": 0,
			"tier": 0,
			"history": []
		},
		"DASHER": {
			"encounters_fought": 0,
			"combat_time": 0.0,
			"damage_dealt": 0,
			"evasion_evidence": 0.0,
			"tier": 0,
			"history": []
		},
		"SHOOTER": {
			"encounters_fought": 0,
			"combat_time": 0.0,
			"damage_dealt": 0,
			"rush_evidence": 0.0,
			"mobility_evidence": 0.0,
			"camp_evidence": 0.0,
			"tier": 0,
			"history": []
		}
	}
	_seed_initial_populations()


func unlock_after_first_sector() -> void:
	## Called only after the first complete sector has been cleared.
	run_evolution_unlocked = true
	per_enemy_evolution_mode = true


func is_evolution_enabled() -> bool:
	# Runtime managers always require the explicit first-sector unlock. Direct
	# legacy/simulation callers retain the old biome-based pathway.
	if strict_sector_lock:
		return run_evolution_unlocked
	return run_evolution_unlocked or current_biome > 1


func _seed_initial_populations() -> void:
	active_genomes["CHASER"].clear()
	active_genomes["SHOOTER"].clear()
	active_genomes["DASHER"].clear()

	for i in range(POOL_SIZE_PER_FAMILY):
		var chaser_g = ENEMY_GENOME_SCRIPT.new("CHASER", 1)
		chaser_g.variant_name = "Chaser Alpha-%d" % (i + 1)
		chaser_g.variant_id = "CHASER-v0-%02d" % (i + 1)
		chaser_g.candidate_id = "CHASER-candidate-%02d" % (i + 1)
		active_genomes["CHASER"].append(chaser_g)

		var shooter_g = ENEMY_GENOME_SCRIPT.new("SHOOTER", 1)
		shooter_g.variant_name = "Shooter Sentry-%d" % (i + 1)
		shooter_g.variant_id = "SHOOTER-v0-%02d" % (i + 1)
		shooter_g.candidate_id = "SHOOTER-candidate-%02d" % (i + 1)
		active_genomes["SHOOTER"].append(shooter_g)

		var dasher_g = ENEMY_GENOME_SCRIPT.new("DASHER", 1)
		dasher_g.variant_name = "Dasher Interceptor-%d" % (i + 1)
		dasher_g.variant_id = "DASHER-v0-%02d" % (i + 1)
		dasher_g.candidate_id = "DASHER-candidate-%02d" % (i + 1)
		active_genomes["DASHER"].append(dasher_g)


func get_genome_for_spawn(family: String) -> RefCounted:
	## Returns an independent phenotype snapshot for a spawned combatant.
	## Prevents per-enemy runtime state from leaking across encounters.
	# First-sector spawns are rebuilt from family defaults instead of copying a
	# population candidate. This prevents stale traits, mutations, or tier data
	# from leaking into the tutorial sector through any spawn route.
	if not is_evolution_enabled():
		var baseline: RefCounted = ENEMY_GENOME_SCRIPT.new(family, 1)
		baseline.variant_name = "%s Base" % family.capitalize()
		baseline.variant_id = "%s-base-v1" % family
		baseline.candidate_id = ""
		baseline.source_candidate_id = ""
		baseline.instance_id = "%s-base-%06d" % [family, next_instance_id]
		next_instance_id += 1
		return baseline
	if not active_genomes.has(family) or active_genomes[family].is_empty():
		var fallback_g = ENEMY_GENOME_SCRIPT.new(family, generation)
		fallback_g.variant_id = "%s-fallback-%04d" % [family, randi() % 10000]
		return fallback_g

	var pool: Array = active_genomes[family]
	pool.sort_custom(func(a, b) -> bool:
		return a.fitness_score > b.fitness_score
	)
	var parent: RefCounted = _select_unexposed_candidate(pool) if per_enemy_evolution_mode else (pool[0] if randf() < 0.70 else pool[randi() % pool.size()])

	# Produce isolated snapshot with stable attribution ID
	var snapshot: RefCounted = parent.duplicate_genome()
	snapshot.source_candidate_id = parent.candidate_id
	snapshot.instance_id = "%s-enemy-%06d" % [family, next_instance_id]
	next_instance_id += 1
	snapshot.encounters_survived = 0
	snapshot.damage_dealt_to_player = 0
	snapshot.damage_received = 0
	snapshot.player_dashes_forced = 0
	snapshot.combat_time_active = 0.0
	snapshot.fitness_score = 0.0
	var t: int = get_species_tier(family)
	if not per_enemy_evolution_mode:
		snapshot.tier = t
	else:
		snapshot.variant_id = "%s-v%d-%04d" % [family, snapshot.tier + 1, randi() % 10000]
		_prepare_species_decision(family, snapshot)
		register_spawned_combatant(snapshot)
		return snapshot

	# Ensure confirmed major evolution mutations are present on spawned phenotype
	if family == "CHASER":
		if t >= 1 and not snapshot.active_mutations.has("RAPID_PURSUIT") and not snapshot.active_mutations.has("PINCER_WINGS"):
			snapshot.apply_named_mutation("RAPID_PURSUIT")
		if t >= 2 and not snapshot.active_mutations.has("CRIMSON_BLASTER"):
			snapshot.apply_named_mutation("CRIMSON_BLASTER")
	elif family == "DASHER":
		if t >= 1 and not snapshot.active_mutations.has("ION_HAZARD_TRAIL"):
			snapshot.apply_named_mutation("ION_HAZARD_TRAIL")
		if t >= 2 and not snapshot.active_mutations.has("OVERCLOCKED_THRUSTERS"):
			snapshot.apply_named_mutation("OVERCLOCKED_THRUSTERS")
		if t >= 3 and not snapshot.active_mutations.has("REINFORCED_CHASSIS"):
			snapshot.apply_named_mutation("REINFORCED_CHASSIS")
	elif family == "SHOOTER":
		if t >= 1 and not snapshot.active_mutations.has("AGILE_STRAFE"):
			snapshot.apply_named_mutation("AGILE_STRAFE")
		if t >= 2 and not snapshot.active_mutations.has("PREDICTIVE_OPTICS"):
			snapshot.apply_named_mutation("PREDICTIVE_OPTICS")
		if t >= 3 and not snapshot.active_mutations.has("HEAVY_BEAM"):
			snapshot.apply_named_mutation("HEAVY_BEAM")

	snapshot.variant_id = "%s-v%d-%04d" % [family, snapshot.tier + 1, randi() % 10000]
	_prepare_species_decision(family, snapshot)
	register_spawned_combatant(snapshot)
	return snapshot


func _select_unexposed_candidate(pool: Array) -> RefCounted:
	## Spread same-room spawns across independent memory lineages before reusing one.
	var already_deployed: Dictionary = {}
	for combatant in active_combatants:
		already_deployed[str(combatant.source_candidate_id)] = true
	var available: Array[RefCounted] = []
	for candidate in pool:
		if not already_deployed.has(str(candidate.candidate_id)):
			available.append(candidate)
	if not available.is_empty():
		return available[randi() % available.size()]
	return pool[randi() % pool.size()]


func _prepare_species_decision(family: String, snapshot: RefCounted) -> void:
	if per_enemy_evolution_mode:
		var memory: Dictionary = snapshot.individual_experience
		var context: Array[float] = [
			1.0,
			clampf(float(memory.get("evasion", 0.0)) / 2.0, 0.0, 1.0),
			clampf(float(memory.get("kiting", 0.0)) / 2.0, 0.0, 1.0),
			clampf(float(memory.get("camping", 0.0)) / 2.0, 0.0, 1.0),
			clampf(float(memory.get("rushing", 0.0)) / 2.0, 0.0, 1.0),
			0.0
		]
		var action := "CONTACT_PURSUIT" if family == "CHASER" else ("DIRECT_LUNGE" if family == "DASHER" else "STANDARD_VOLLEY")
		if family == "CHASER":
			if snapshot.has_mutation("CRIMSON_BLASTER"): action = "CRIMSON_BLASTER"
			elif snapshot.has_mutation("PINCER_WINGS"): action = "FLANKING_PINCER"
			elif snapshot.has_mutation("RAPID_PURSUIT"): action = "RAPID_PURSUIT"
		elif family == "DASHER":
			if snapshot.has_mutation("REINFORCED_CHASSIS"): action = "REINFORCED_CHASSIS"
			elif snapshot.has_mutation("OVERCLOCKED_THRUSTERS"): action = "OVERCLOCKED_THRUSTERS"
			elif snapshot.has_mutation("ION_HAZARD_TRAIL"): action = "ION_HAZARD_TRAIL"
		elif family == "SHOOTER":
			if snapshot.has_mutation("HEAVY_BEAM"): action = "HEAVY_BEAM"
			elif snapshot.has_mutation("PREDICTIVE_OPTICS"): action = "PREDICTIVE_OPTICS"
			elif snapshot.has_mutation("AGILE_STRAFE"): action = "AGILE_STRAFE"
		snapshot.policy_action_name = action
		var policy: RefCounted = species_policies.get(family)
		snapshot.policy_action_id = policy.action_names.find(action) if policy != null else -1
		snapshot.policy_context = context
		return
	var policy: RefCounted = species_policies.get(family)
	if policy == null:
		return
	var evidence: Dictionary = species_evidence.get(family, {})
	var context: Array[float] = [
		1.0,
		clampf(float(evidence.get("mobility_evidence", 0.0)), 0.0, 1.0),
		clampf(float(evidence.get("kited_evidence", 0.0)), 0.0, 1.0),
		clampf(float(evidence.get("camp_evidence", 0.0)), 0.0, 1.0),
		clampf(float(evidence.get("rush_evidence", 0.0)), 0.0, 1.0),
		0.0
	]
	var eligible := _get_executable_actions(family, snapshot)
	var decision: Dictionary = policy.select_action(context, 5, 5, true, eligible)
	snapshot.policy_action_id = int(decision.get("action_id", -1))
	snapshot.policy_action_name = str(decision.get("action_name", ""))
	snapshot.policy_context = context.duplicate()


func _get_executable_actions(family: String, genome: RefCounted) -> Array[String]:
	var actions: Array[String] = []
	match family:
		"CHASER":
			actions.append("CONTACT_PURSUIT")
			if genome.has_mutation("RAPID_PURSUIT"):
				actions.append("RAPID_PURSUIT")
			if genome.has_mutation("PINCER_WINGS"):
				actions.append("FLANKING_PINCER")
			if genome.has_mutation("CRIMSON_BLASTER"):
				actions.append("CRIMSON_BLASTER")
		"DASHER":
			actions.append("DIRECT_LUNGE")
			if genome.has_mutation("ION_HAZARD_TRAIL"):
				actions.append("ION_HAZARD_TRAIL")
			if genome.has_mutation("OVERCLOCKED_THRUSTERS"):
				actions.append("OVERCLOCKED_THRUSTERS")
			if genome.has_mutation("REINFORCED_CHASSIS"):
				actions.append("REINFORCED_CHASSIS")
		"SHOOTER":
			actions.append("STANDARD_VOLLEY")
			if genome.has_mutation("AGILE_STRAFE"):
				actions.append("AGILE_STRAFE")
			if genome.has_mutation("PREDICTIVE_OPTICS"):
				actions.append("PREDICTIVE_OPTICS")
			if genome.has_mutation("HEAVY_BEAM"):
				actions.append("HEAVY_BEAM")
	return actions


func _select_chaser_first_evolution(evidence: Dictionary) -> String:
	last_mutation_selection.erase("CHASER")
	var eligible_mutations: Array[String] = []
	var eligible_actions: Array[String] = []
	if float(evidence.get("kited_evidence", 0.0)) >= 0.75:
		eligible_mutations.append("RAPID_PURSUIT")
		eligible_actions.append("RAPID_PURSUIT")
	if float(evidence.get("camp_evidence", 0.0)) >= 0.75:
		eligible_mutations.append("PINCER_WINGS")
		eligible_actions.append("FLANKING_PINCER")
	if eligible_mutations.is_empty():
		return ""

	var policy: RefCounted = species_policies.get("CHASER")
	if policy == null:
		last_mutation_selection["CHASER"] = {
			"action_id": -1,
			"action_name": "",
			"eligible_mutations": eligible_mutations.duplicate(),
			"context": [],
			"reason": "Single eligible mutation; policy unavailable"
		}
		return eligible_mutations[0]
	var context: Array[float] = [
		1.0,
		0.0,
		clampf(float(evidence.get("kited_evidence", 0.0)) / 2.0, 0.0, 1.0),
		clampf(float(evidence.get("camp_evidence", 0.0)) / 2.0, 0.0, 1.0),
		0.0,
		0.0
	]
	if eligible_mutations.size() == 1:
		var only_action := eligible_actions[0]
		last_mutation_selection["CHASER"] = {
			"action_id": policy.action_names.find(only_action),
			"action_name": only_action,
			"eligible_mutations": eligible_mutations.duplicate(),
			"context": context.duplicate(),
			"reason": "Only eligible mutation matched accumulated behavior evidence"
		}
		return eligible_mutations[0]
	var decision: Dictionary = policy.select_action(context, 5, 5, true, eligible_actions)
	var selected_action := str(decision.get("action_name", ""))
	var action_index := eligible_actions.find(selected_action)
	if action_index < 0:
		return ""
	last_mutation_selection["CHASER"] = {
		"action_id": int(decision.get("action_id", -1)),
		"action_name": selected_action,
		"eligible_mutations": eligible_mutations.duplicate(),
		"context": context.duplicate(),
		"reason": str(decision.get("reason", "Contextual policy selection"))
	}
	return eligible_mutations[action_index]


func _apply_chaser_first_evolution(mutation: String, sector_index: int, kited_value: float, camp_value: float) -> Dictionary:
	if mutation not in ["RAPID_PURSUIT", "PINCER_WINGS"]:
		return {}
	var ev: Dictionary = species_evidence["CHASER"]
	var next_tier := 1
	var applied := false
	for candidate in active_genomes["CHASER"]:
		if candidate.apply_named_mutation(mutation):
			applied = true
	for combatant in active_combatants:
		if combatant.family == "CHASER":
			combatant.apply_named_mutation(mutation)
	if not applied:
		return {}
	ev["tier"] = next_tier
	var is_pincer := mutation == "PINCER_WINGS"
	var decision_record: Dictionary = last_mutation_selection.get("CHASER", {})
	var record := {
		"sector": sector_index + 1,
		"family": "CHASER",
		"tier": next_tier,
		"mutation": mutation,
		"health_mult": "2x (6 HP)",
		"tradeoff": "Pincer flank pressure with reduced aggression" if is_pincer else "Pursuit speed +45% (135 px/s)",
		"reason": "Contextual policy selected %s from eligible mutations after observed player behavior (kite %.0f%%, camp %.0f%%)." % [mutation, kited_value * 100.0, camp_value * 100.0],
		"counter": "Break line of sight and change position to disrupt coordinated pursuit." if is_pincer else "Cut across the pursuit path and use arena obstacles to break the chase.",
		"eligible_mutations": decision_record.get("eligible_mutations", [mutation]),
		"policy_action_id": decision_record.get("action_id", -1),
		"policy_action": decision_record.get("action_name", ""),
		"policy_context": decision_record.get("context", []),
		"selection_reason": decision_record.get("reason", "Only one species-compatible mutation met the evidence gate")
	}
	evolution_history.append(record)
	ev.history.append(record)
	return record


func register_spawned_combatant(genome: RefCounted, enemy: Node2D = null) -> void:
	if genome == null:
		return
	if not genome in active_combatants:
		active_combatants.append(genome)
	var id: String = str(genome.instance_id)
	if id.is_empty():
		id = "enemy-%06d" % next_instance_id
		next_instance_id += 1
		genome.instance_id = id
	if not combatant_records.has(id):
		combatant_records[id] = {
			"encounter_id": encounter_id,
			"family": genome.family,
			"instance_id": id,
			"candidate_id": genome.source_candidate_id,
			"selected_action": genome.policy_action_name,
			"action_id": genome.policy_action_id,
			"context": genome.policy_context.duplicate(),
			"action_applied": false,
			"spawned_at": Time.get_ticks_msec() / 1000.0,
			"survival_seconds": -1.0,
			"defeated": false,
			"outcome_recorded": false
		}
	var record: Dictionary = combatant_records[id]
	if is_instance_valid(enemy):
		record["spawned_at"] = Time.get_ticks_msec() / 1000.0
		record["enemy"] = weakref(enemy)
		record["action_applied"] = _action_is_applied(genome, enemy, str(record.get("selected_action", "")))


func _action_is_applied(genome: RefCounted, enemy: Node2D, action: String) -> bool:
	if not is_instance_valid(enemy) or action.is_empty():
		return false
	match action:
		"CONTACT_PURSUIT": return "move_speed" in enemy and float(enemy.move_speed) > 0.0
		"RAPID_PURSUIT": return "move_speed" in enemy and float(enemy.move_speed) >= 134.0
		"FLANKING_PINCER": return "is_flanker" in enemy and bool(enemy.is_flanker)
		"CRIMSON_BLASTER": return "has_ranged_attack" in enemy and bool(enemy.has_ranged_attack)
		"DIRECT_LUNGE": return "lunge_speed" in enemy and float(enemy.lunge_speed) > 0.0
		"ION_HAZARD_TRAIL": return "has_hazard_trail" in enemy and bool(enemy.has_hazard_trail)
		"OVERCLOCKED_THRUSTERS": return "lunge_speed" in enemy and float(enemy.lunge_speed) >= 819.0
		"REINFORCED_CHASSIS": return "max_health" in enemy and int(enemy.max_health) >= genome.base_max_health * 8
		"STANDARD_VOLLEY": return "burst_count" in enemy and int(enemy.burst_count) >= 1
		"AGILE_STRAFE": return "move_speed" in enemy and float(enemy.move_speed) >= 114.0
		"PREDICTIVE_OPTICS": return "lead_prediction" in enemy and float(enemy.lead_prediction) >= 0.99
		"HEAVY_BEAM": return "has_beam_attack" in enemy and bool(enemy.has_beam_attack)
	return false


func record_combatant_defeated(genome: RefCounted, enemy: Node2D = null) -> void:
	if genome == null:
		return
	var record: Dictionary = combatant_records.get(str(genome.instance_id), {})
	if record.is_empty() or bool(record.get("defeated", false)):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var started := float(record.get("spawned_at", now))
	record["survival_seconds"] = maxf(0.0, now - started)
	record["defeated"] = true
	if is_instance_valid(enemy):
		record["enemy"] = weakref(enemy)


func get_species_tier(family: String) -> int:
	if not is_evolution_enabled():
		return 0
	if per_enemy_evolution_mode:
		var highest_tier := 0
		for candidate in active_genomes.get(family, []):
			highest_tier = maxi(highest_tier, int(candidate.tier))
		return highest_tier
	return int(species_evidence.get(family, {}).get("tier", 0))


func get_species_health_multiplier(family: String) -> int:
	## Health doubling invariant: every confirmed major evolution doubles max health.
	## max_health = base_health * 2^tier
	if not is_evolution_enabled():
		return 1
	var t: int = get_species_tier(family)
	return int(pow(2, t))


func process_encounter_end(
	sector_index: int,
	damage_taken_by_player: int,
	combat_duration: float,
	player_profile: Dictionary,
	_selected_tactic: String,
	tracker: RefCounted = null,
	biome_index: int = -1,
	encounter_completed: bool = true
) -> Array[Dictionary]:
	## Evaluates combat outcomes under strict species evidence isolation.
	## A species evolves ONLY when its own observed battle data justifies adaptation.
	if biome_index > 0:
		current_biome = biome_index
	if not is_evolution_enabled():
		active_combatants.clear()
		combatant_records.clear()
		deployed_actions.clear()
		return []

	var new_adaptations: Array[Dictionary] = []
	var active_families: Dictionary = {}
	var family_counts: Dictionary = {"CHASER": 0, "DASHER": 0, "SHOOTER": 0}
	encounter_id += 1
	for combatant in active_combatants:
		var combatant_family := str(combatant.family)
		if species_evidence.has(combatant_family):
			family_counts[combatant_family] = int(family_counts.get(combatant_family, 0)) + 1

	# Aggregate each spawned snapshot back to its source population candidate.
	# Enemy death time is recorded by the game loop; uninstantiated test records
	# use the supplied encounter duration as a deterministic simulation interval.
	for g in active_combatants:
		var record: Dictionary = combatant_records.get(str(g.instance_id), {})
		var survival_seconds := float(record.get("survival_seconds", -1.0))
		if survival_seconds < 0.0:
			var enemy_ref = record.get("enemy")
			var enemy = enemy_ref.get_ref() if enemy_ref is WeakRef else null
			if is_instance_valid(enemy):
				survival_seconds = maxf(0.0, Time.get_ticks_msec() / 1000.0 - float(record.get("spawned_at", 0.0)))
			else:
				survival_seconds = maxf(0.0, combat_duration)
		g.combat_time_active = survival_seconds
		var defeated := bool(record.get("defeated", false))
		if not defeated:
			g.encounters_survived = 1
		g.calculate_fitness()
		var family: String = str(g.family)
		if not species_evidence.has(family):
			continue
		var candidate: RefCounted = _find_candidate(family, str(record.get("candidate_id", g.source_candidate_id)))
		if candidate:
			active_families[family] = true
			candidate.combat_time_active += survival_seconds
			candidate.damage_dealt_to_player += g.damage_dealt_to_player
			candidate.damage_received += g.damage_received
			candidate.player_dashes_forced += g.player_dashes_forced
			candidate.evaluated_encounters += 1
			if not defeated:
				candidate.encounters_survived += 1
			candidate.calculate_fitness()
			if per_enemy_evolution_mode and tracker and tracker.has_method("consume_enemy_experience"):
				var personal_profile: Dictionary = tracker.consume_enemy_experience(str(g.instance_id))
				if not personal_profile.is_empty():
					var personal_evolution: Dictionary = _process_candidate_experience(candidate, personal_profile, sector_index)
					if not personal_evolution.is_empty():
						new_adaptations.append(personal_evolution)

		var policy: RefCounted = species_policies.get(family)
		var action_id := int(record.get("action_id", g.policy_action_id))
		var action_applied := bool(record.get("action_applied", false))
		var context: Array[float] = []
		for context_value in record.get("context", g.policy_context):
			context.append(float(context_value))
		var valid_outcome := action_applied and action_id >= 0 and not bool(record.get("outcome_recorded", false))
		if valid_outcome and policy and context.size() == policy.FEATURE_DIM:
			var outcome := {
				"valid": true,
				"damage_dealt": g.damage_dealt_to_player,
				"damage_received": g.damage_received,
				"survival_seconds": survival_seconds,
				"dashes_forced": g.player_dashes_forced,
				"player_damage_taken": float(damage_taken_by_player) / maxf(1.0, float(family_counts.get(family, 1))),
				"encounter_completed": encounter_completed,
				"encounter_failed": not encounter_completed
			}
			var reward: float = policy.compute_outcome_reward(outcome)
			policy.update_policy_for_decision(action_id, context, reward)
			record["outcome_recorded"] = true
			record["reward"] = reward
			record["survival_seconds"] = survival_seconds
			record["damage_dealt"] = g.damage_dealt_to_player
			record["damage_received"] = g.damage_received
			decision_history.append(record.duplicate(true))

	# The live game uses independent per-candidate memories after sector 1. Do not
	# run the legacy family-wide promotion or breeding path in that mode.
	if per_enemy_evolution_mode:
		active_combatants.clear()
		combatant_records.clear()
		deployed_actions.clear()
		return new_adaptations

	# 3. Process Species Evidence & Contextual Learning per active family
	for family in ["CHASER", "DASHER", "SHOOTER"]:
		if not active_families.has(family) or not species_evidence.has(family):
			continue

		var ev: Dictionary = species_evidence[family]
		ev.encounters_fought += 1
		ev.combat_time += combat_duration

		# Extract family-specific observation profile
		var fam_prof: Dictionary = {}
		if tracker != null and tracker.has_method("get_family_profile"):
			fam_prof = tracker.get_family_profile(family)
		elif player_profile.has(family) and player_profile[family] is Dictionary:
			fam_prof = player_profile[family]
		else:
			fam_prof = player_profile

		# Evaluate learned adaptations based on observed evidence
		if family == "CHASER":
			var ranged_val: float = float(fam_prof.get("ranged", 0.5))
			var mob_val: float = float(fam_prof.get("mobility", 0.5))
			var kited_val: float = maxf(ranged_val, float(fam_prof.get("kited_ratio", 0.0)))
			var is_kited: bool = (kited_val >= 0.55 or mob_val >= 0.55)
			var camp_val: float = float(fam_prof.get("turret", 0.0))
			ev.camp_evidence = minf(3.0, float(ev.get("camp_evidence", 0.0)) + maxf(0.0, camp_val - 0.40)) if camp_val >= 0.45 else maxf(0.0, float(ev.get("camp_evidence", 0.0)) - 0.30)

			if is_kited:
				ev.kited_evidence += (kited_val - 0.40)
			else:
				ev.kited_evidence = maxf(0.0, ev.kited_evidence - 0.30)

			# Major Evolution Tier 0 -> Tier 1: Rapid Pursuit (requires sustained kiting evidence)
			if ev.tier == 0 and (ev.kited_evidence >= 0.75 or ev.camp_evidence >= 0.75):
				var selected_mutation := _select_chaser_first_evolution(ev)
				var chaser_evolution := _apply_chaser_first_evolution(selected_mutation, sector_index, kited_val, camp_val)
				if not chaser_evolution.is_empty():
					new_adaptations.append(chaser_evolution)

			# Major Evolution Tier 1 -> Tier 2: Crimson Blaster (continued kiting escapes pursuit)
			elif ev.tier == 1 and ev.kited_evidence >= 1.60 and is_kited:
				ev.tier = 2
				for g in active_genomes["CHASER"]:
					g.tier = 2
					g.apply_named_mutation("CRIMSON_BLASTER")
				for g in active_combatants:
					if g.family == "CHASER":
						g.tier = 2
						g.apply_named_mutation("CRIMSON_BLASTER")
				var record := {
					"sector": sector_index + 1,
					"family": "CHASER",
					"tier": 2,
					"mutation": "CRIMSON_BLASTER",
					"health_mult": "4x (12 HP)",
					"tradeoff": "Learned to aim and shoot crimson laser projectiles, max armor doubled to 12 HP",
					"reason": "Player consistently maintained escape distance despite pursuit. Contextual policy deployed crimson laser blaster.",
					"counter": "Watch for the 0.65s laser telegraph; aim locks at 0.25s remaining, allowing dash evasion."
				}
				evolution_history.append(record)
				new_adaptations.append(record)
				ev.history.append(record)

		elif family == "DASHER":
			var mob_val: float = float(fam_prof.get("mobility", 0.5))
			var dashes_min: float = float(fam_prof.get("dashes_per_min", 0.0))
			var is_evading: bool = (mob_val >= 0.45 or dashes_min >= 2.0)

			if is_evading:
				ev.evasion_evidence += (mob_val - 0.35)
			else:
				ev.evasion_evidence = maxf(0.0, ev.evasion_evidence - 0.30)

			# Major Evolution Tier 0 -> Tier 1: Ion Hazard Trail (requires dash evasion evidence)
			if ev.tier == 0 and ev.evasion_evidence >= 0.75 and is_evading:
				ev.tier = 1
				for g in active_genomes["DASHER"]:
					g.tier = 1
					g.apply_named_mutation("ION_HAZARD_TRAIL")
				for g in active_combatants:
					if g.family == "DASHER":
						g.tier = 1
						g.apply_named_mutation("ION_HAZARD_TRAIL")
				var record := {
					"sector": sector_index + 1,
					"family": "DASHER",
					"tier": 1,
					"mutation": "ION_HAZARD_TRAIL",
					"health_mult": "2x (4 HP)",
					"tradeoff": "Lunge speed +25% (650 px/s) and drops electric hazard mines along dash path, armor doubled to 4 HP",
					"reason": "Dashers observed repeated dash evasion (%.0f%% mobility). Synthesized ion hazard trail." % (mob_val * 100.0),
					"counter": "Avoid walking directly in Dasher wake; lure Dashers into open perimeter corridors."
				}
				evolution_history.append(record)
				new_adaptations.append(record)
				ev.history.append(record)

			# Major Evolution Tier 1 -> Tier 2: Overclocked Hyper Thrusters
			elif ev.tier == 1 and ev.evasion_evidence >= 1.60 and is_evading:
				ev.tier = 2
				for g in active_genomes["DASHER"]:
					g.tier = 2
					g.apply_named_mutation("OVERCLOCKED_THRUSTERS")
				for g in active_combatants:
					if g.family == "DASHER":
						g.tier = 2
						g.apply_named_mutation("OVERCLOCKED_THRUSTERS")
				var record := {
					"sector": sector_index + 1,
					"family": "DASHER",
					"tier": 2,
					"mutation": "OVERCLOCKED_THRUSTERS",
					"health_mult": "4x (8 HP)",
					"tradeoff": "Overclocked hyper-lunge speed +57% (820 px/s), max armor doubled to 8 HP",
					"reason": "Player repeatedly escaped baseline lunge trajectories. Overclocked thrusters.",
					"counter": "Telegraph window remains readable; wait for telegraph commitment before dodging."
				}
				evolution_history.append(record)
				new_adaptations.append(record)
				ev.history.append(record)

			# Major Evolution Tier 2 -> Tier 3: Reinforced Armor Chassis
			elif ev.tier == 2 and ev.evasion_evidence >= 2.50 and is_evading:
				ev.tier = 3
				for g in active_genomes["DASHER"]:
					g.tier = 3
					g.apply_named_mutation("REINFORCED_CHASSIS")
				for g in active_combatants:
					if g.family == "DASHER":
						g.tier = 3
						g.apply_named_mutation("REINFORCED_CHASSIS")
				var record := {
					"sector": sector_index + 1,
					"family": "DASHER",
					"tier": 3,
					"mutation": "REINFORCED_CHASSIS",
					"health_mult": "8x (16 HP)",
					"tradeoff": "Reinforced armored chevron hull doubling armor to 16 HP, preserving hyper speed and mines",
					"reason": "Dashers persevered against repeated counter-attacks. Evolved reinforced defensive plating.",
					"counter": "Focus high-damage burst fire or static dash damage on armored Dashers."
				}
				evolution_history.append(record)
				new_adaptations.append(record)
				ev.history.append(record)

		elif family == "SHOOTER":
			var agg_val: float = float(fam_prof.get("aggression", 0.5))
			var mob_val: float = float(fam_prof.get("mobility", 0.5))
			var sta_val: float = float(fam_prof.get("turret", 0.5))

			if agg_val >= 0.45 or mob_val >= 0.55:
				ev.rush_evidence += (maxf(agg_val, mob_val) - 0.40)
			if mob_val >= 0.45:
				ev.mobility_evidence += (mob_val - 0.40)
			if sta_val >= 0.45:
				ev.camp_evidence += (sta_val - 0.40)

			# Major Evolution Tier 0 -> Tier 1: Agile Strafe (player rushing / evasive mobility)
			if ev.tier == 0 and ev.rush_evidence >= 0.75:
				ev.tier = 1
				for g in active_genomes["SHOOTER"]:
					g.tier = 1
					g.apply_named_mutation("AGILE_STRAFE")
				for g in active_combatants:
					if g.family == "SHOOTER":
						g.tier = 1
						g.apply_named_mutation("AGILE_STRAFE")
				var record := {
					"sector": sector_index + 1,
					"family": "SHOOTER",
					"tier": 1,
					"mutation": "AGILE_STRAFE",
					"health_mult": "2x (6 HP)",
					"tradeoff": "Repositioning & strafe speed +53% (115 px/s), max armor doubled to 6 HP",
					"reason": "Shooters analyzed player rushing behavior. Evolved agile thruster repositioning.",
					"counter": "Corner Shooters against arena walls and obstacles before they can kite away."
				}
				evolution_history.append(record)
				new_adaptations.append(record)
				ev.history.append(record)

			# Major Evolution Tier 1 -> Tier 2: Precision Lead Optics (player mobility / dodging)
			elif ev.tier == 1 and (ev.mobility_evidence >= 1.60 or ev.rush_evidence >= 1.60):
				ev.tier = 2
				for g in active_genomes["SHOOTER"]:
					g.tier = 2
					g.apply_named_mutation("PREDICTIVE_OPTICS")
				for g in active_combatants:
					if g.family == "SHOOTER":
						g.tier = 2
						g.apply_named_mutation("PREDICTIVE_OPTICS")
				var record := {
					"sector": sector_index + 1,
					"family": "SHOOTER",
					"tier": 2,
					"mutation": "PREDICTIVE_OPTICS",
					"health_mult": "4x (12 HP)",
					"tradeoff": "Armor doubled to 12 HP and calibrated pinpoint predictive lead aiming optics",
					"reason": "Shooters measured player movement velocity. Evolved precision lead targeting optics.",
					"counter": "Stop or change heading when laser telegraph locks; do not run in a straight line."
				}
				evolution_history.append(record)
				new_adaptations.append(record)
				ev.history.append(record)

			# Major Evolution Tier 2 -> Tier 3: Charged Particle Beam (player camping / cover)
			elif ev.tier == 2 and ev.camp_evidence >= 0.75:
				ev.tier = 3
				for g in active_genomes["SHOOTER"]:
					g.tier = 3
					g.apply_named_mutation("HEAVY_BEAM")
				for g in active_combatants:
					if g.family == "SHOOTER":
						g.tier = 3
						g.apply_named_mutation("HEAVY_BEAM")
				var record := {
					"sector": sector_index + 1,
					"family": "SHOOTER",
					"tier": 3,
					"mutation": "HEAVY_BEAM",
					"health_mult": "8x (24 HP)",
					"tradeoff": "Equipped with heavy charging particle beam dealing 2 HP damage, max armor doubled to 24 HP",
					"reason": "Shooters analyzed stationary/camping player behavior. Synthesized heavy particle beam.",
					"counter": "Watch for the red/amber widening charging ray; dash perpendicularly right as beam fires."
				}
				evolution_history.append(record)
				new_adaptations.append(record)
				ev.history.append(record)

	# Breed only families with actual spawned combatants and valid observations.
	if active_families.is_empty():
		active_combatants.clear()
		combatant_records.clear()
		deployed_actions.clear()
		return []
	generation += 1
	for family in ["CHASER", "SHOOTER", "DASHER"]:
		if active_families.has(family):
			_evolve_family_pool(family, sector_index)

	active_combatants.clear()
	combatant_records.clear()
	deployed_actions.clear()
	if decision_history.size() > 120:
		decision_history = decision_history.slice(decision_history.size() - 120)
	return new_adaptations


func _process_candidate_experience(candidate: RefCounted, observation: Dictionary, sector_index: int) -> Dictionary:
	## Deterministic, authored evolution rules fed only by this candidate's own
	## spawned enemy observations. One candidate can evolve while its siblings do not.
	if float(observation.get("exposure_seconds", 0.0)) < 3.0:
		return {}
	var memory: Dictionary = candidate.individual_experience.duplicate(true)
	memory["encounters"] = int(memory.get("encounters", 0)) + 1
	memory["kiting"] = minf(4.0, float(memory.get("kiting", 0.0)) + maxf(0.0, float(observation.get("kiting_ratio", 0.0)) - 0.35))
	memory["camping"] = minf(4.0, float(memory.get("camping", 0.0)) + maxf(0.0, float(observation.get("camping_ratio", 0.0)) - 0.30))
	var dash_evidence := minf(0.6, float(observation.get("nearby_dashes", 0)) * 0.22)
	memory["evasion"] = minf(4.0, float(memory.get("evasion", 0.0)) + maxf(0.0, float(observation.get("evasive_ratio", 0.0)) - 0.30) + dash_evidence)
	memory["rushing"] = minf(4.0, float(memory.get("rushing", 0.0)) + maxf(0.0, float(observation.get("rushing_ratio", 0.0)) - 0.20))
	candidate.individual_experience = memory

	var mutation := ""
	match str(candidate.family):
		"CHASER":
			if candidate.tier == 0:
				if float(memory["camping"]) >= 0.65 and float(memory["camping"]) > float(memory["kiting"]):
					mutation = "PINCER_WINGS"
				elif float(memory["kiting"]) >= 0.75:
					mutation = "RAPID_PURSUIT"
			elif candidate.tier == 1 and float(memory["kiting"]) >= 1.45:
				mutation = "CRIMSON_BLASTER"
		"DASHER":
			if candidate.tier == 0 and float(memory["evasion"]) >= 0.70:
				mutation = "ION_HAZARD_TRAIL"
			elif candidate.tier == 1 and float(memory["evasion"]) >= 1.45:
				mutation = "OVERCLOCKED_THRUSTERS"
			elif candidate.tier == 2 and float(memory["evasion"]) >= 2.10:
				mutation = "REINFORCED_CHASSIS"
		"SHOOTER":
			if candidate.tier == 0 and float(memory["rushing"]) >= 0.65:
				mutation = "AGILE_STRAFE"
			elif candidate.tier == 1 and float(memory["evasion"]) >= 1.30:
				mutation = "PREDICTIVE_OPTICS"
			elif candidate.tier == 2 and float(memory["camping"]) >= 0.80:
				mutation = "HEAVY_BEAM"
	if mutation.is_empty() or not candidate.apply_named_mutation(mutation):
		return {}
	candidate.generation = generation
	candidate.variant_id = "%s-v%d-%04d" % [candidate.family, candidate.tier + 1, randi() % 10000]
	var health_multiplier := int(pow(2.0, candidate.tier))
	var counterplay := "Change your spacing and movement rhythm; this individual adapted to the behavior it encountered."
	match mutation:
		"RAPID_PURSUIT": counterplay = "Use corners and obstacles to break pursuit lines."
		"PINCER_WINGS": counterplay = "Keep moving; this Chaser learned to flank stationary targets."
		"CRIMSON_BLASTER": counterplay = "Break line of sight and dash after its firing telegraph commits."
		"ION_HAZARD_TRAIL": counterplay = "Avoid the route it just dashed through."
		"OVERCLOCKED_THRUSTERS": counterplay = "Bait the lunge, then dodge after its telegraph."
		"REINFORCED_CHASSIS": counterplay = "Use high burst damage or dash attacks against its armor."
		"AGILE_STRAFE": counterplay = "Cut off its escape path with arena geometry."
		"PREDICTIVE_OPTICS": counterplay = "Change direction during the aim telegraph."
		"HEAVY_BEAM": counterplay = "Move laterally when the beam charge begins."
	var record := {
		"sector": sector_index + 1,
		"family": str(candidate.family),
		"candidate_id": str(candidate.candidate_id),
		"variant_id": str(candidate.variant_id),
		"tier": candidate.tier + 1,
		"internal_evolution_count": candidate.tier,
		"mutation": mutation,
		"health_mult": "%dx" % health_multiplier,
		"reason": "This individual accumulated encounter evidence: kite %.2f, camp %.2f, evade %.2f, rush %.2f across %d exposures." % [memory["kiting"], memory["camping"], memory["evasion"], memory["rushing"], memory["encounters"]],
		"counter": counterplay,
		"evidence": memory.duplicate(true)
	}
	evolution_history.append(record)
	return record


func _find_candidate(family: String, candidate_id: String) -> RefCounted:
	if candidate_id.is_empty():
		return null
	for candidate in active_genomes.get(family, []):
		if candidate.candidate_id == candidate_id:
			return candidate
	return null


func _evolve_family_pool(family: String, _sector_index: int) -> void:
	var pool: Array = active_genomes[family]
	if pool.size() < 2:
		return
	var evaluated: Array[RefCounted] = []
	for candidate in pool:
		if int(candidate.evaluated_encounters) > 0:
			evaluated.append(candidate)
	if evaluated.is_empty():
		return

	# Select parents only from candidates with measured combat outcomes.
	evaluated.sort_custom(func(a, b) -> bool:
		return a.fitness_score > b.fitness_score
	)

	# Retain top performer (Elitism)
	var top_performer: RefCounted = evaluated[0]

	# Produce offspring inheriting parent's tier and mutations
	var offspring: RefCounted = top_performer.duplicate_genome()
	offspring.generation = generation
	offspring.encounters_survived = 0
	offspring.evaluated_encounters = 0
	offspring.damage_dealt_to_player = 0
	offspring.damage_received = 0
	offspring.combat_time_active = 0.0
	offspring.fitness_score = 0.0

	# Bounded trait perturbation
	var delta_aggression := randf_range(-MUTATION_PERTURBATION, MUTATION_PERTURBATION)
	var delta_flanking := randf_range(-MUTATION_PERTURBATION, MUTATION_PERTURBATION)

	offspring.aggression += delta_aggression
	offspring.flanking_tendency += delta_flanking
	offspring.clamp_all_traits()
	offspring.variant_name = "%s Gen-%d" % [family.capitalize(), generation]
	offspring.variant_id = "%s-v%d-%04d" % [family, offspring.tier + 1, randi() % 10000]
	offspring.parent_candidate_id = top_performer.candidate_id
	offspring.candidate_id = "%s-candidate-g%d-%06d" % [family, generation, randi() % 1000000]
	offspring.source_candidate_id = ""
	offspring.instance_id = ""
	offspring.policy_action_id = -1
	offspring.policy_action_name = ""
	offspring.policy_context.clear()

	# Replace an unevaluated candidate first; otherwise replace the weakest observed candidate.
	var replace_index := -1
	for i in range(pool.size()):
		if int(pool[i].evaluated_encounters) == 0:
			replace_index = i
			break
	if replace_index < 0:
		pool.sort_custom(func(a, b) -> bool: return a.fitness_score < b.fitness_score)
		replace_index = 0
	pool[replace_index] = offspring


func get_active_mutations_summary() -> Array[String]:
	var summary: Array[String] = []
	if not is_evolution_enabled():
		return summary
	if per_enemy_evolution_mode:
		for family in ["CHASER", "DASHER", "SHOOTER"]:
			for candidate in active_genomes.get(family, []):
				if int(candidate.tier) <= 0:
					continue
				var mutations: Array[String] = candidate.active_mutations
				summary.append("%s / %s [Tier %d | %dx HP]: %s" % [family, candidate.candidate_id, int(candidate.tier) + 1, int(pow(2, candidate.tier)), ", ".join(mutations)])
		return summary
	for family in ["CHASER", "DASHER", "SHOOTER"]:
		var ev: Dictionary = species_evidence.get(family, {})
		var t: int = int(ev.get("tier", 0))
		var hp_mult: int = get_species_health_multiplier(family)
		if t > 0:
			var muts: Array[String] = []
			for g in active_genomes.get(family, []):
				for m in g.active_mutations:
					if not m in muts:
						muts.append(m)
			var mut_str: String = ", ".join(muts) if not muts.is_empty() else "Evolved"
			summary.append("%s [Tier %d | %dx HP]: %s" % [family, t, hp_mult, mut_str])
	return summary


func export_evolution_data() -> Dictionary:
	var families_dict := {}
	for f in active_genomes:
		var list := []
		for g in active_genomes[f]:
			list.append(g.to_dict())
		families_dict[f] = list

	return {
		"generation": generation,
		"species_evidence": species_evidence.duplicate(true),
		"active_genomes": families_dict,
		"history": evolution_history.duplicate(true)
	}
