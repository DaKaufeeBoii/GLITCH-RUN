extends RefCounted
class_name EvolutionManager
## Multi-layered enemy evolution and population manager for GLITCH//RUN.
## Implements:
##   1. Strict Species Evidence Isolation (species evolve ONLY from their own battle data).
##   2. Explicit Gameplay Progression Tiers (Tier 0 baseline, Tier 1 learned ability, Tier 2 advanced capability).
##   3. Strict Health Doubling Invariant (1x base at Tier 0, 2x at Tier 1, 4x at Tier 2).
##   4. Run-Scoped Lifetime (reset on death/restart/new run, zero cross-run persistence).

const ENEMY_GENOME_SCRIPT := preload("res://scripts/enemy_genome.gd")

const POOL_SIZE_PER_FAMILY := 3
const MUTATION_PERTURBATION := 0.08 # Max 8% trait adjustment per generational mutation
const BATTLES_FOR_FIRST_EVOLUTION := 2
const BATTLES_FOR_SECOND_EVOLUTION := 4
const BATTLES_FOR_THIRD_EVOLUTION := 6

var generation := 1
var active_genomes: Dictionary = {
	"CHASER": [],
	"SHOOTER": [],
	"DASHER": []
}

var species_evidence: Dictionary = {}
var evolution_history: Array[Dictionary] = []
var active_combatants: Array[RefCounted] = []


func _init() -> void:
	reset()


func reset() -> void:
	generation = 1
	evolution_history.clear()
	active_combatants.clear()
	species_evidence = {
		"CHASER": {
			"encounters_fought": 0,
			"combat_time": 0.0,
			"player_kited_count": 0,
			"last_bred_encounter": 0,
			"damage_dealt": 0,
			"tier": 0,
			"history": []
		},
		"DASHER": {
			"encounters_fought": 0,
			"combat_time": 0.0,
			"damage_dealt": 0,
			"player_dash_count": 0,
			"last_bred_encounter": 0,
			"tier": 0,
			"history": []
		},
		"SHOOTER": {
			"encounters_fought": 0,
			"combat_time": 0.0,
			"damage_dealt": 0,
			"last_bred_encounter": 0,
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


func get_species_tier(family: String) -> int:
	return int(species_evidence.get(family, {}).get("tier", 0))


func get_species_health_multiplier(family: String) -> int:
	var t: int = get_species_tier(family)
	if family == "SHOOTER":
		if t <= 1:
			return 1
		elif t == 2:
			return 2
		else:
			return 4
	elif family == "DASHER":
		if t <= 2:
			return 1
		else:
			return 3
	return int(pow(2, mini(t, 2)))


func process_encounter_end(
	sector_index: int,
	_damage_taken_by_player: int,
	combat_duration: float,
	player_profile: Dictionary,
	_selected_tactic: String
) -> Array[Dictionary]:
	## Evaluates combat outcomes under strict species evidence isolation.
	## A species evolves ONLY from evidence gathered in its own battles.
	var new_adaptations: Array[Dictionary] = []

	# 1. Update fitness metrics for active combatants
	for g in active_combatants:
		g.combat_time_active += combat_duration
		g.encounters_survived += 1
		g.calculate_fitness()

	# 2. Identify which families participated in this battle
	var active_families: Dictionary = {}
	for g in active_combatants:
		if "family" in g:
			active_families[g.family] = true

	# Callers may supply an explicit family list, but an empty encounter must never
	# be treated as evidence that every species fought.
	if active_families.is_empty():
		for f in player_profile.get("active_families", []):
			active_families[f] = true

	# 3. Process Species Evidence & Distinct Evolution Paths

	# --- RED CHASER PROGRESSION ---
	if active_families.has("CHASER") and species_evidence.has("CHASER"):
		var ev: Dictionary = species_evidence["CHASER"]
		ev.encounters_fought += 1
		ev.combat_time += combat_duration

		var ranged_ratio: float = float(player_profile.get("ranged", 0.5))
		var mobility_ratio: float = float(player_profile.get("mobility", 0.5))
		if ranged_ratio >= 0.60 and mobility_ratio >= 0.50:
			ev.player_kited_count += 1

		# Tier 0 -> Tier 1: Enhanced Pursuit Speed (+45%) & 2x Health
		if ev.tier == 0 and ev.encounters_fought >= BATTLES_FOR_FIRST_EVOLUTION:
			ev.tier = 1
			for g in active_genomes["CHASER"]:
				g.tier = 1
				g.apply_named_mutation("RAPID_PURSUIT")
			var record := {
				"sector": sector_index + 1,
				"family": "CHASER",
				"tier": 1,
				"mutation": "RAPID_PURSUIT",
				"health_mult": "2x (6 HP)",
				"tradeoff": "Pursuit speed +45% (135 px/s), max armor doubled to 6 HP",
				"reason": "After %d Chaser battles, long-range movement and repeated dodging met the adaptation threshold." % ev.encounters_fought,
				"counter": "Cut back across pursuit trajectory; use arena obstacles to break line of chase."
			}
			evolution_history.append(record)
			new_adaptations.append(record)
			ev.history.append(record)

		# Tier 1 -> Tier 2: Teaches it to aim and shoot laser & 4x Health
		elif ev.tier == 1 and ev.encounters_fought >= BATTLES_FOR_SECOND_EVOLUTION:
			ev.tier = 2
			for g in active_genomes["CHASER"]:
				g.tier = 2
				g.apply_named_mutation("CRIMSON_BLASTER")
			var record := {
				"sector": sector_index + 1,
				"family": "CHASER",
				"tier": 2,
				"mutation": "CRIMSON_BLASTER",
				"health_mult": "4x (12 HP)",
				"tradeoff": "Learned to aim and shoot crimson laser projectiles, max armor doubled to 12 HP",
				"reason": "Chasers engaged across %d battle(s). Evolved crimson laser projectile attack." % ev.encounters_fought,
				"counter": "Watch for the 0.65s laser telegraph; aim locks at 0.25s remaining, allowing dash evasion."
			}
			evolution_history.append(record)
			new_adaptations.append(record)
			ev.history.append(record)

	# --- PURPLE DASHER PROGRESSION ---
	if active_families.has("DASHER") and species_evidence.has("DASHER"):
		var ev: Dictionary = species_evidence["DASHER"]
		ev.encounters_fought += 1
		ev.combat_time += combat_duration

		# Tier 0 -> Tier 1: Speed + Hazard Mines
		if ev.tier == 0 and ev.encounters_fought >= BATTLES_FOR_FIRST_EVOLUTION:
			ev.tier = 1
			for g in active_genomes["DASHER"]:
				g.tier = 1
				g.apply_named_mutation("ION_HAZARD_TRAIL")
			var record := {
				"sector": sector_index + 1,
				"family": "DASHER",
				"tier": 1,
				"mutation": "ION_HAZARD_TRAIL",
				"health_mult": "1x (2 HP)",
				"tradeoff": "Lunge speed +25% (650 px/s) and drops electric hazard mines along dash path",
				"reason": "After %d Dasher battles with repeated player dash responses, the species adapted its attack path." % ev.encounters_fought,
				"counter": "Avoid walking directly in Dasher wake; lure Dashers into open perimeter corridors."
			}
			evolution_history.append(record)
			new_adaptations.append(record)
			ev.history.append(record)

		# Tier 1 -> Tier 2: Even More Speed (Hyper Speed Lunge)
		elif ev.tier == 1 and ev.encounters_fought >= BATTLES_FOR_SECOND_EVOLUTION:
			ev.tier = 2
			for g in active_genomes["DASHER"]:
				g.tier = 2
				g.apply_named_mutation("OVERCLOCKED_THRUSTERS")
			var record := {
				"sector": sector_index + 1,
				"family": "DASHER",
				"tier": 2,
				"mutation": "OVERCLOCKED_THRUSTERS",
				"health_mult": "1x (2 HP)",
				"tradeoff": "Overclocked hyper-lunge speed +57% (820 px/s), maintaining mine deployment",
				"reason": "Surviving Dashers analyzed %d battle(s). Evolved hyper-speed interception thrusters." % ev.encounters_fought,
				"counter": "Telegraph window remains readable; wait for telegraph commitment before dodging."
			}
			evolution_history.append(record)
			new_adaptations.append(record)
			ev.history.append(record)

		# Tier 2 -> Tier 3: Reinforced Armor Plating (3x Health)
		elif ev.tier == 2 and ev.encounters_fought >= BATTLES_FOR_THIRD_EVOLUTION:
			ev.tier = 3
			for g in active_genomes["DASHER"]:
				g.tier = 3
				g.apply_named_mutation("REINFORCED_CHASSIS")
			var record := {
				"sector": sector_index + 1,
				"family": "DASHER",
				"tier": 3,
				"mutation": "REINFORCED_CHASSIS",
				"health_mult": "3x (6 HP)",
				"tradeoff": "Reinforced armored chevron hull doubling armor to 6 HP, preserving hyper speed and mines",
				"reason": "Dashers persevered across %d battle(s). Evolved reinforced defensive plating." % ev.encounters_fought,
				"counter": "Focus high-damage burst fire or static dash damage on armored Dashers."
			}
			evolution_history.append(record)
			new_adaptations.append(record)
			ev.history.append(record)

	# --- AMBER SHOOTER PROGRESSION ---
	if active_families.has("SHOOTER") and species_evidence.has("SHOOTER"):
		var ev: Dictionary = species_evidence["SHOOTER"]
		ev.encounters_fought += 1
		ev.combat_time += combat_duration

		# Tier 0 -> Tier 1: Speed Buff (Maneuver & Strafe)
		if ev.tier == 0 and ev.encounters_fought >= BATTLES_FOR_FIRST_EVOLUTION:
			ev.tier = 1
			for g in active_genomes["SHOOTER"]:
				g.tier = 1
				g.apply_named_mutation("AGILE_STRAFE")
			var record := {
				"sector": sector_index + 1,
				"family": "SHOOTER",
				"tier": 1,
				"mutation": "AGILE_STRAFE",
				"health_mult": "1x (3 HP)",
				"tradeoff": "Repositioning & strafe speed +53% (115 px/s), bad aim remains uncalibrated",
				"reason": "Shooters analyzed player encounters across %d battle(s). Evolved agile thruster repositioning." % ev.encounters_fought,
				"counter": "Corner Shooters against arena walls and obstacles before they can kite away."
			}
			evolution_history.append(record)
			new_adaptations.append(record)
			ev.history.append(record)

		# Tier 1 -> Tier 2: Armor & Really Good Aim (Predictive Lead Aiming)
		elif ev.tier == 1 and ev.encounters_fought >= BATTLES_FOR_SECOND_EVOLUTION:
			ev.tier = 2
			for g in active_genomes["SHOOTER"]:
				g.tier = 2
				g.apply_named_mutation("PREDICTIVE_OPTICS")
			var record := {
				"sector": sector_index + 1,
				"family": "SHOOTER",
				"tier": 2,
				"mutation": "PREDICTIVE_OPTICS",
				"health_mult": "2x (6 HP)",
				"tradeoff": "Armor doubled to 6 HP and calibrated pinpoint predictive lead aiming optics",
				"reason": "Surviving Shooters analyzed %d encounter(s). Evolved precision lead targeting optics." % ev.encounters_fought,
				"counter": "Stop or change heading when laser telegraph locks; do not run in a straight line."
			}
			evolution_history.append(record)
			new_adaptations.append(record)
			ev.history.append(record)

		# Tier 2 -> Tier 3: Charged Particle Beam dealing 2 DMG & Heavy Armor (12 HP)
		elif ev.tier == 2 and ev.encounters_fought >= BATTLES_FOR_THIRD_EVOLUTION:
			ev.tier = 3
			for g in active_genomes["SHOOTER"]:
				g.tier = 3
				g.apply_named_mutation("HEAVY_BEAM")
			var record := {
				"sector": sector_index + 1,
				"family": "SHOOTER",
				"tier": 3,
				"mutation": "HEAVY_BEAM",
				"health_mult": "4x (12 HP)",
				"tradeoff": "Equipped with heavy charging particle beam dealing 2 HP damage, max armor doubled to 12 HP",
				"reason": "Shooters mastered long-range telemetry over %d battle(s). Synthesized 2-damage particle beam cannon." % ev.encounters_fought,
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

	# Replace lowest performer in pool
	pool[pool.size() - 1] = offspring


func get_active_mutations_summary() -> Array[String]:
	var summary: Array[String] = []
	for family in ["CHASER", "DASHER", "SHOOTER"]:
		var ev: Dictionary = species_evidence.get(family, {})
		var t: int = int(ev.get("tier", 0))
		var hp_mult := int(pow(2, t))
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
