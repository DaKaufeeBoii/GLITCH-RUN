extends RefCounted
class_name EvolutionManager
## Multi-layered enemy evolution and population manager.
## Implements:
##   Layer A: Tactical adaptation coordination.
##   Layer B: Family & individual specialization with trade-offs.
##   Layer C: Population evolution across encounters (fitness tracking, bounded mutation, retention).

const ENEMY_GENOME_SCRIPT := preload("res://scripts/enemy_genome.gd")

const POOL_SIZE_PER_FAMILY := 3
const MUTATION_PERTURBATION := 0.08 # Max 8% trait adjustment per generational mutation

var generation := 1
var active_genomes: Dictionary = {
	"CHASER": [],
	"SHOOTER": [],
	"DASHER": []
}

var evolution_history: Array[Dictionary] = []
var active_combatants: Array[RefCounted] = []


func _init() -> void:
	reset()


func reset() -> void:
	generation = 1
	evolution_history.clear()
	active_combatants.clear()
	_seed_initial_populations()


func _seed_initial_populations() -> void:
	active_genomes["CHASER"].clear()
	active_genomes["SHOOTER"].clear()
	active_genomes["DASHER"].clear()

	for i in range(POOL_SIZE_PER_FAMILY):
		var chaser_g = ENEMY_GENOME_SCRIPT.new("CHASER", 1)
		chaser_g.variant_name = "Chaser Alpha-%d" % (i + 1)
		active_genomes["CHASER"].append(chaser_g)

		var shooter_g = ENEMY_GENOME_SCRIPT.new("SHOOTER", 1)
		shooter_g.variant_name = "Shooter Sentry-%d" % (i + 1)
		active_genomes["SHOOTER"].append(shooter_g)

		var dasher_g = ENEMY_GENOME_SCRIPT.new("DASHER", 1)
		dasher_g.variant_name = "Dasher Interceptor-%d" % (i + 1)
		active_genomes["DASHER"].append(dasher_g)


func get_genome_for_spawn(family: String) -> RefCounted:
	if not active_genomes.has(family) or active_genomes[family].is_empty():
		var fallback_g = ENEMY_GENOME_SCRIPT.new(family, generation)
		return fallback_g

	var pool: Array = active_genomes[family]
	# Sort pool by fitness descending
	pool.sort_custom(func(a, b) -> bool:
		return a.fitness_score > b.fitness_score
	)
	var chosen: RefCounted = pool[0] if randf() < 0.70 else pool[randi() % pool.size()]
	if not chosen in active_combatants:
		active_combatants.append(chosen)
	return chosen


func register_spawned_combatant(genome: RefCounted) -> void:
	if genome and not genome in active_combatants:
		active_combatants.append(genome)


func process_encounter_end(
	sector_index: int,
	_damage_taken_by_player: int,
	combat_duration: float,
	player_profile: Dictionary,
	_selected_tactic: String
) -> Array[Dictionary]:
	## Evaluates combat outcomes, updates Layer B specialization and Layer C population fitness.
	## Returns a list of newly applied mutations and evolutionary adaptations.
	var new_adaptations: Array[Dictionary] = []

	# 1. Update fitness for active combatants
	for g in active_combatants:
		g.combat_time_active += combat_duration
		g.encounters_survived += 1
		g.calculate_fitness()

	# 2. Layer B: Individual & Family Specialization
	# Evaluate if player tactics warrant specific named counter-mutations
	var mob: float = float(player_profile.get("mobility", 0.5))
	var rng: float = float(player_profile.get("ranged", 0.5))
	var _tur: float = float(player_profile.get("turret", 0.5))
	var player_tactics: Dictionary = player_profile.get("successful_player_tactics", {})

	# High Mobility -> Shooters gain PREDICTIVE_OPTICS & Dashers gain ION_HAZARD_TRAIL
	if mob > 0.55:
		var shooter_mutated := false
		for g in active_genomes["SHOOTER"]:
			if not g.has_mutation("PREDICTIVE_OPTICS"):
				g.apply_named_mutation("PREDICTIVE_OPTICS")
				shooter_mutated = true
		if shooter_mutated:
			var record := {
				"sector": sector_index + 1,
				"family": "SHOOTER",
				"mutation": "PREDICTIVE_OPTICS",
				"tradeoff": "Lead aiming calibrated; attack cycle lengthened +25%",
				"reason": "Player high mobility (%.2f dashes/min)" % player_profile.get("dashes_per_min", 0.0)
			}
			evolution_history.append(record)
			new_adaptations.append(record)

		var dasher_mutated := false
		for g in active_genomes["DASHER"]:
			if not g.has_mutation("ION_HAZARD_TRAIL"):
				g.apply_named_mutation("ION_HAZARD_TRAIL")
				dasher_mutated = true
		if dasher_mutated:
			var record := {
				"sector": sector_index + 1,
				"family": "DASHER",
				"mutation": "ION_HAZARD_TRAIL",
				"tradeoff": "Hazard energy dropped on charge; telegraph warning widened +20%",
				"reason": "Player dynamic kiting detected"
			}
			evolution_history.append(record)
			new_adaptations.append(record)

	# Perimeter Camping / Ranged Play -> Chasers develop PINCER_WINGS
	if rng > 0.55:
		var chaser_mutated := false
		for g in active_genomes["CHASER"]:
			if not g.has_mutation("PINCER_WINGS"):
				g.apply_named_mutation("PINCER_WINGS")
				chaser_mutated = true
		if chaser_mutated:
			var record := {
				"sector": sector_index + 1,
				"family": "CHASER",
				"mutation": "PINCER_WINGS",
				"tradeoff": "Pincer flanking angle expanded; direct approach speed relaxed -10%",
				"reason": "Player perimeter camping (long range ratio %.2f)" % rng
			}
			evolution_history.append(record)
			new_adaptations.append(record)

	# Heavy Static Blink Dash Kills -> Dashers & Chasers acquire STATIC_GROUNDING
	if int(player_tactics.get("DASH_STATIC", 0)) >= 3:
		var static_mutated := false
		for g in active_genomes["DASHER"]:
			if not g.has_mutation("STATIC_GROUNDING"):
				g.apply_named_mutation("STATIC_GROUNDING")
				static_mutated = true
		if static_mutated:
			var record := {
				"sector": sector_index + 1,
				"family": "DASHER",
				"mutation": "STATIC_GROUNDING",
				"tradeoff": "Takes 40% less dash shock damage; chassis weight reduces speed -8%",
				"reason": "Player relying heavily on Static Blink contact damage"
			}
			evolution_history.append(record)
			new_adaptations.append(record)

	# 3. Layer C: Population Evolution Across Encounters
	# Apply generational selection, bounded mutation, and culling
	generation += 1
	for family in ["CHASER", "SHOOTER", "DASHER"]:
		_evolve_family_pool(family, sector_index, new_adaptations)

	active_combatants.clear()
	return new_adaptations


func _evolve_family_pool(family: String, sector_index: int, _new_adaptations: Array[Dictionary]) -> void:
	var pool: Array = active_genomes[family]
	if pool.size() < 2:
		return

	# Sort pool by fitness descending
	pool.sort_custom(func(a, b) -> bool:
		return a.fitness_score > b.fitness_score
	)

	# The top performer is retained (Elitism)
	var top_performer: RefCounted = pool[0]

	# Replace the lowest performer with a mutated offspring of the top performer
	var offspring: RefCounted = top_performer.duplicate_genome()
	offspring.generation = generation
	offspring.encounters_survived = 0
	offspring.damage_dealt_to_player = 0
	offspring.combat_time_active = 0.0
	offspring.fitness_score = 0.0

	# Bounded numerical perturbation (prevent stat inflation!)
	var delta_aggression := randf_range(-MUTATION_PERTURBATION, MUTATION_PERTURBATION)
	var delta_flanking := randf_range(-MUTATION_PERTURBATION, MUTATION_PERTURBATION)
	var delta_prediction := randf_range(-MUTATION_PERTURBATION, MUTATION_PERTURBATION)

	offspring.aggression += delta_aggression
	offspring.flanking_tendency += delta_flanking
	offspring.prediction_strength += delta_prediction

	# Enforce hard bounded limits
	offspring.clamp_all_traits()
	offspring.variant_name = "%s Gen-%d" % [family.capitalize(), generation]

	# Replace lowest performer in pool
	pool[pool.size() - 1] = offspring

	var lineage_entry := {
		"sector": sector_index + 1,
		"family": family,
		"mutation": "POPULATION_SPECIATION",
		"tradeoff": "Bounded generational trait perturbation (Gen %d)" % generation,
		"reason": "Top variant %s reproduced; least effective variant culled" % top_performer.variant_name
	}
	evolution_history.append(lineage_entry)


func get_active_mutations_summary() -> Array[String]:
	var summary: Array[String] = []
	for family in active_genomes:
		for g in active_genomes[family]:
			for m in g.active_mutations:
				var desc := "%s: %s" % [family, m]
				if not desc in summary:
					summary.append(desc)
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
		"active_genomes": families_dict,
		"history": evolution_history.duplicate(true)
	}
