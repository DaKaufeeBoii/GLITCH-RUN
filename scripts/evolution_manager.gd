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


func _seed_initial_populations() -> void:
	active_genomes["CHASER"].clear()
	active_genomes["SHOOTER"].clear()
	active_genomes["DASHER"].clear()

	for i in range(POOL_SIZE_PER_FAMILY):
		var chaser_g = ENEMY_GENOME_SCRIPT.new("CHASER", 1)
		chaser_g.variant_name = "Chaser Alpha-%d" % (i + 1)
		chaser_g.variant_id = "CHASER-v0-%02d" % (i + 1)
		active_genomes["CHASER"].append(chaser_g)

		var shooter_g = ENEMY_GENOME_SCRIPT.new("SHOOTER", 1)
		shooter_g.variant_name = "Shooter Sentry-%d" % (i + 1)
		shooter_g.variant_id = "SHOOTER-v0-%02d" % (i + 1)
		active_genomes["SHOOTER"].append(shooter_g)

		var dasher_g = ENEMY_GENOME_SCRIPT.new("DASHER", 1)
		dasher_g.variant_name = "Dasher Interceptor-%d" % (i + 1)
		dasher_g.variant_id = "DASHER-v0-%02d" % (i + 1)
		active_genomes["DASHER"].append(dasher_g)


func get_genome_for_spawn(family: String) -> RefCounted:
	## Returns an independent phenotype snapshot for a spawned combatant.
	## Prevents per-enemy runtime state from leaking across encounters.
	if not active_genomes.has(family) or active_genomes[family].is_empty():
		var fallback_g = ENEMY_GENOME_SCRIPT.new(family, generation)
		fallback_g.variant_id = "%s-fallback-%04d" % [family, randi() % 10000]
		return fallback_g

	# Query species learning policy to select counter-action
	var policy: RefCounted = species_policies.get(family)
	if policy:
		var ev: Dictionary = species_evidence.get(family, {})
		var ctx: Array[float] = [
			1.0,
			clampf(float(ev.get("mobility_evidence", 0.5)), 0.0, 1.0),
			clampf(float(ev.get("kited_evidence", 0.5)), 0.0, 1.0),
			clampf(float(ev.get("camp_evidence", 0.5)), 0.0, 1.0),
			clampf(float(ev.get("rush_evidence", 0.5)), 0.0, 1.0),
			0.0
		]
		var decision: Dictionary = policy.select_action(ctx)
		deployed_actions[family] = decision.action_id

	var pool: Array = active_genomes[family]
	pool.sort_custom(func(a, b) -> bool:
		return a.fitness_score > b.fitness_score
	)
	var parent: RefCounted = pool[0] if randf() < 0.70 else pool[randi() % pool.size()]

	# Produce isolated snapshot with stable attribution ID
	var snapshot: RefCounted = parent.duplicate_genome()
	var t: int = get_species_tier(family)
	snapshot.tier = t

	# Ensure confirmed major evolution mutations are present on spawned phenotype
	if family == "CHASER":
		if t >= 1 and not snapshot.active_mutations.has("RAPID_PURSUIT"):
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
	if not snapshot in active_combatants:
		active_combatants.append(snapshot)
	return snapshot


func register_spawned_combatant(genome: RefCounted) -> void:
	if genome and not genome in active_combatants:
		active_combatants.append(genome)


func get_species_tier(family: String) -> int:
	return int(species_evidence.get(family, {}).get("tier", 0))


func get_species_health_multiplier(family: String) -> int:
	## Health doubling invariant: every confirmed major evolution doubles max health.
	## max_health = base_health * 2^tier
	var t: int = get_species_tier(family)
	return int(pow(2, t))


func process_encounter_end(
	sector_index: int,
	damage_taken_by_player: int,
	combat_duration: float,
	player_profile: Dictionary,
	_selected_tactic: String,
	tracker: RefCounted = null
) -> Array[Dictionary]:
	## Evaluates combat outcomes under strict species evidence isolation.
	## A species evolves ONLY when its own observed battle data justifies adaptation.
	var new_adaptations: Array[Dictionary] = []

	# 1. Update fitness metrics for active combatant snapshots
	for g in active_combatants:
		g.combat_time_active += combat_duration
		g.encounters_survived += 1
		g.calculate_fitness()

	# 2. Identify which families actively participated in this encounter
	var active_families: Dictionary = {}
	for g in active_combatants:
		if "family" in g:
			active_families[g.family] = true

	if active_families.is_empty():
		for f in player_profile.get("active_families", []):
			active_families[f] = true

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

		var policy: RefCounted = species_policies.get(family)
		var ctx: Array[float] = policy.extract_context(fam_prof)
		var deployed_act: int = deployed_actions.get(family, -1)
		if deployed_act < 0:
			var dec: Dictionary = policy.select_action(ctx)
			deployed_act = dec.action_id

		var reward: float = policy.compute_reward(damage_taken_by_player, combat_duration, fam_prof, deployed_act)
		policy.update_policy(reward)

		# Evaluate learned adaptations based on observed evidence
		if family == "CHASER":
			var ranged_val: float = float(fam_prof.get("ranged", 0.5))
			var mob_val: float = float(fam_prof.get("mobility", 0.5))
			var kited_val: float = maxf(ranged_val, float(fam_prof.get("kited_ratio", 0.0)))
			var is_kited: bool = (kited_val >= 0.55 or mob_val >= 0.55)

			if is_kited:
				ev.kited_evidence += (kited_val - 0.40)
			else:
				ev.kited_evidence = maxf(0.0, ev.kited_evidence - 0.30)

			# Major Evolution Tier 0 -> Tier 1: Rapid Pursuit (requires sustained kiting evidence)
			if ev.tier == 0 and ev.kited_evidence >= 0.75 and is_kited:
				ev.tier = 1
				for g in active_genomes["CHASER"]:
					g.tier = 1
					g.apply_named_mutation("RAPID_PURSUIT")
				for g in active_combatants:
					if g.family == "CHASER":
						g.tier = 1
						g.apply_named_mutation("RAPID_PURSUIT")
				var record := {
					"sector": sector_index + 1,
					"family": "CHASER",
					"tier": 1,
					"mutation": "RAPID_PURSUIT",
					"health_mult": "2x (6 HP)",
					"tradeoff": "Pursuit speed +45% (135 px/s), max armor doubled to 6 HP",
					"reason": "Chasers observed sustained long-range kiting (%.0f%% standoff). Policy deployed rapid pursuit." % (kited_val * 100.0),
					"counter": "Cut back across pursuit trajectory; use arena obstacles to break line of chase."
				}
				evolution_history.append(record)
				new_adaptations.append(record)
				ev.history.append(record)

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

	# 4. Generational population breeding and trait perturbation
	generation += 1
	for family in ["CHASER", "SHOOTER", "DASHER"]:
		_evolve_family_pool(family, sector_index)

	active_combatants.clear()
	return new_adaptations


func _evolve_family_pool(family: String, _sector_index: int) -> void:
	var pool: Array = active_genomes[family]
	if pool.size() < 2:
		return

	# Sort pool by fitness descending
	pool.sort_custom(func(a, b) -> bool:
		return a.fitness_score > b.fitness_score
	)

	# Retain top performer (Elitism)
	var top_performer: RefCounted = pool[0]

	# Produce offspring inheriting parent's tier and mutations
	var offspring: RefCounted = top_performer.duplicate_genome()
	offspring.generation = generation
	offspring.encounters_survived = 0
	offspring.damage_dealt_to_player = 0
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

	# Replace lowest performer in pool
	pool[pool.size() - 1] = offspring


func get_active_mutations_summary() -> Array[String]:
	var summary: Array[String] = []
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
