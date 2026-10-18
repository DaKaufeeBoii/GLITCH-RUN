extends RefCounted
class_name EnemyGenome
## Reusable trait genome and mutation data structure for evolving enemies.
## Encapsulates bounded numerical traits, named mutations with trade-offs,
## serialization, and behavioral application to enemy nodes.

# Trait Bounds
const MIN_PREDICTION := 0.0
const MAX_PREDICTION := 1.0

const MIN_FLANKING := 0.0
const MAX_FLANKING := 1.0

const MIN_AGGRESSION := 0.60
const MAX_AGGRESSION := 1.35

const MIN_EVASION := 0.0
const MAX_EVASION := 1.0

const MIN_DISTANCE := 60.0
const MAX_DISTANCE := 360.0

const MIN_ATTACK_TIMING := 0.65
const MAX_ATTACK_TIMING := 1.45

const MIN_COORDINATION := 0.0
const MAX_COORDINATION := 1.0

# Family & Variant Metadata
var family: String = "CHASER" # "CHASER", "SHOOTER", "DASHER", "BOSS"
var generation: int = 1
var variant_name: String = "Standard"
var variant_id: String = ""
var major_evolution_count: int = 0
var tier: int = 0: # Kept synchronized with major_evolution_count
	get:
		return major_evolution_count
	set(val):
		major_evolution_count = val
var base_max_health: int = 3

# Evolvable Numerical Traits
var prediction_strength: float = 0.0
var flanking_tendency: float = 0.0
var aggression: float = 1.0
var evasion_tendency: float = 0.0
var preferred_distance: float = 140.0
var attack_timing_mult: float = 1.0
var coordination_tendency: float = 0.5

# Damage Vulnerability / Resistance by source ("plasma", "dash", "hazard")
var damage_multipliers: Dictionary = {
	"plasma": 1.0,
	"dash": 1.0,
	"hazard": 1.0
}

# Named Mutations Active on this Genome
var active_mutations: Array[String] = []

# Lifetime encounter fitness metrics
var encounters_survived: int = 0
var damage_dealt_to_player: int = 0
var player_dashes_forced: int = 0
var combat_time_active: float = 0.0
var fitness_score: float = 0.0


func _init(p_family: String = "CHASER", p_generation: int = 1) -> void:
	family = p_family
	generation = p_generation
	_apply_family_defaults()


func get_max_health() -> int:
	if family == "SHOOTER":
		if tier == 0:
			return 3
		elif tier == 1:
			return 3
		elif tier == 2:
			return 6
		else:
			return 12
	elif family == "DASHER":
		if tier == 0:
			return 2
		elif tier == 1:
			return 2
		elif tier == 2:
			return 2
		else:
			return 6
	elif family == "CHASER":
		return base_max_health * int(pow(2, mini(tier, 2)))
	return base_max_health * int(pow(2, tier))


func _apply_family_defaults() -> void:
	match family:
		"CHASER":
			base_max_health = 3
			preferred_distance = 60.0
			aggression = 1.0
			flanking_tendency = 0.0
			prediction_strength = 0.0
			evasion_tendency = 0.1
			coordination_tendency = 0.6
			attack_timing_mult = 1.0
			variant_name = "Chaser Alpha"
		"SHOOTER":
			base_max_health = 3
			preferred_distance = 210.0
			aggression = 0.90
			flanking_tendency = 0.1
			prediction_strength = 0.0
			evasion_tendency = 0.4
			coordination_tendency = 0.4
			attack_timing_mult = 1.0
			variant_name = "Shooter Sentry"
		"DASHER":
			base_max_health = 2
			preferred_distance = 180.0
			aggression = 1.10
			flanking_tendency = 0.0
			prediction_strength = 0.0
			evasion_tendency = 0.2
			coordination_tendency = 0.3
			attack_timing_mult = 1.0
			variant_name = "Dasher Interceptor"
		"BOSS":
			base_max_health = 30
			preferred_distance = 220.0
			aggression = 1.15
			flanking_tendency = 0.2
			prediction_strength = 0.5
			evasion_tendency = 0.0
			coordination_tendency = 1.0
			attack_timing_mult = 1.0
			variant_name = "NEXUS Core"


func duplicate_genome() -> RefCounted:
	var copy = get_script().new(family, generation)
	copy.variant_name = variant_name
	copy.variant_id = variant_id
	copy.major_evolution_count = major_evolution_count
	copy.base_max_health = base_max_health
	copy.prediction_strength = prediction_strength
	copy.flanking_tendency = flanking_tendency
	copy.aggression = aggression
	copy.evasion_tendency = evasion_tendency
	copy.preferred_distance = preferred_distance
	copy.attack_timing_mult = attack_timing_mult
	copy.coordination_tendency = coordination_tendency
	copy.damage_multipliers = damage_multipliers.duplicate()
	copy.active_mutations = active_mutations.duplicate()
	copy.encounters_survived = encounters_survived
	copy.damage_dealt_to_player = damage_dealt_to_player
	copy.player_dashes_forced = player_dashes_forced
	copy.combat_time_active = combat_time_active
	copy.fitness_score = fitness_score
	return copy


func clamp_all_traits() -> void:
	prediction_strength = clampf(prediction_strength, MIN_PREDICTION, MAX_PREDICTION)
	flanking_tendency = clampf(flanking_tendency, MIN_FLANKING, MAX_FLANKING)
	aggression = clampf(aggression, MIN_AGGRESSION, MAX_AGGRESSION)
	evasion_tendency = clampf(evasion_tendency, MIN_EVASION, MAX_EVASION)
	preferred_distance = clampf(preferred_distance, MIN_DISTANCE, MAX_DISTANCE)
	attack_timing_mult = clampf(attack_timing_mult, MIN_ATTACK_TIMING, MAX_ATTACK_TIMING)
	coordination_tendency = clampf(coordination_tendency, MIN_COORDINATION, MAX_COORDINATION)
	for k in damage_multipliers.keys():
		damage_multipliers[k] = clampf(float(damage_multipliers[k]), 0.50, 1.50)


func has_mutation(mut_name: String) -> bool:
	return mut_name in active_mutations


func apply_named_mutation(mut_name: String) -> bool:
	if has_mutation(mut_name):
		return false # Mutation already present

	match mut_name:
		"RAPID_PURSUIT":
			# Chaser Tier 1: Gets faster pursuit (+45% speed), 2x HP
			tier = maxi(tier, 1)
			active_mutations.append(mut_name)
			variant_name = variant_name + " [Pursuit]"
			return true

		"CRIMSON_BLASTER":
			# Chaser Tier 2: Teaches it to aim and shoot laser, 4x HP
			tier = maxi(tier, 2)
			active_mutations.append(mut_name)
			variant_name = variant_name + " [Blaster]"
			return true

		"AGILE_STRAFE":
			# Shooter Tier 1: Speed buff (+move speed)
			tier = maxi(tier, 1)
			active_mutations.append(mut_name)
			variant_name = variant_name + " [Agile]"
			return true

		"PREDICTIVE_OPTICS":
			# Shooter Tier 2: Armor and really good aim (predictive lead aim), 2x HP
			tier = maxi(tier, 2)
			prediction_strength = 1.0
			attack_timing_mult = clampf(attack_timing_mult * 1.20, MIN_ATTACK_TIMING, MAX_ATTACK_TIMING)
			active_mutations.append(mut_name)
			variant_name = variant_name + " [Optics]"
			return true

		"HEAVY_BEAM", "BURST_VOLLEY":
			# Shooter Tier 3: Heavy particle beam dealing 2 damage, 4x HP
			tier = maxi(tier, 3)
			active_mutations.append(mut_name)
			variant_name = variant_name + " [HeavyBeam]"
			return true

		"ION_HAZARD_TRAIL":
			# Dasher Tier 1: Speed and hazard mines
			tier = maxi(tier, 1)
			active_mutations.append(mut_name)
			variant_name = variant_name + " [Mines]"
			return true

		"OVERCLOCKED_THRUSTERS":
			# Dasher Tier 2: Even more speed (hyper lunge)
			tier = maxi(tier, 2)
			active_mutations.append(mut_name)
			variant_name = variant_name + " [HyperSpeed]"
			return true

		"REINFORCED_CHASSIS":
			# Dasher Tier 3: Armor buff (doubled health)
			tier = maxi(tier, 3)
			active_mutations.append(mut_name)
			variant_name = variant_name + " [Armored]"
			return true

		"PINCER_WINGS":
			flanking_tendency = clampf(flanking_tendency + 0.55, MIN_FLANKING, MAX_FLANKING)
			aggression = clampf(aggression * 0.90, MIN_AGGRESSION, MAX_AGGRESSION)
			active_mutations.append(mut_name)
			variant_name = variant_name + " [Pincer]"
			return true

		"STATIC_GROUNDING":
			damage_multipliers["dash"] = 0.60
			aggression = clampf(aggression * 0.92, MIN_AGGRESSION, MAX_AGGRESSION)
			active_mutations.append(mut_name)
			variant_name = variant_name + " [Insulated]"
			return true

		"DEFENSIVE_STRIKE":
			evasion_tendency = clampf(evasion_tendency + 0.30, MIN_EVASION, MAX_EVASION)
			aggression = clampf(aggression * 0.88, MIN_AGGRESSION, MAX_AGGRESSION)
			active_mutations.append(mut_name)
			variant_name = variant_name + " [Skirmisher]"
			return true

	return false


func apply_to_enemy(enemy_node: Node2D) -> void:
	if not is_instance_valid(enemy_node):
		return

	# Bind genome reference
	enemy_node.set("genome", self)

	# Apply tier health calculation
	var calc_hp: int = get_max_health()
	if "max_health" in enemy_node:
		enemy_node.max_health = calc_hp
		enemy_node.health = calc_hp

	# 1. Chaser behavioral application
	if family == "CHASER":
		var speed: float = 92.0 * aggression
		if tier >= 1 or has_mutation("RAPID_PURSUIT"):
			speed = maxf(135.0, 135.0 * aggression)
		if "move_speed" in enemy_node:
			enemy_node.move_speed = speed
		if "has_ranged_attack" in enemy_node:
			enemy_node.has_ranged_attack = (tier >= 2 or has_mutation("CRIMSON_BLASTER"))
		if "flank_angle" in enemy_node:
			enemy_node.flank_angle = flanking_tendency * 0.70
			if flanking_tendency > 0.15:
				enemy_node.set("is_flanker", true)

	# 2. Shooter behavioral application
	elif family == "SHOOTER":
		var s_speed: float = 75.0 * aggression
		if tier >= 1 or has_mutation("AGILE_STRAFE"):
			s_speed = maxf(115.0, 115.0 * aggression)
		if "move_speed" in enemy_node:
			enemy_node.move_speed = s_speed

		if "lead_prediction" in enemy_node:
			if tier >= 2 or has_mutation("PREDICTIVE_OPTICS"):
				enemy_node.lead_prediction = 1.0
			else:
				enemy_node.lead_prediction = 0.0 # Bad aim at tier 0 and 1

		if "has_beam_attack" in enemy_node:
			enemy_node.has_beam_attack = (tier >= 3 or has_mutation("HEAVY_BEAM") or has_mutation("BURST_VOLLEY"))

		if "ideal_distance" in enemy_node:
			enemy_node.ideal_distance = preferred_distance

	# 3. Dasher behavioral application
	elif family == "DASHER":
		var p_spd: float = 95.0 * aggression
		var l_spd: float = 520.0 * aggression
		if tier >= 2 or has_mutation("OVERCLOCKED_THRUSTERS"):
			p_spd = maxf(150.0, 150.0 * aggression)
			l_spd = maxf(820.0, 820.0 * aggression)
		elif tier == 1 or has_mutation("ION_HAZARD_TRAIL"):
			p_spd = maxf(120.0, 120.0 * aggression)
			l_spd = maxf(650.0, 650.0 * aggression)

		if "patrol_speed" in enemy_node:
			enemy_node.patrol_speed = p_spd
		if "lunge_speed" in enemy_node:
			enemy_node.lunge_speed = l_spd
		if "has_hazard_trail" in enemy_node:
			enemy_node.has_hazard_trail = (tier >= 1 or has_mutation("ION_HAZARD_TRAIL"))

	# Generic modifiers
	if "damage_multipliers" in enemy_node:
		enemy_node.set("damage_multipliers", damage_multipliers.duplicate())


func calculate_fitness() -> float:
	# Explicit multi-objective fitness:
	# Rewards survival time, damage dealt, and pressure exerted (forced player dashes)
	# Penalizes excessive overkill (unfairness)
	var survival_reward := minf(combat_time_active, 30.0) * 0.10
	var damage_reward := float(damage_dealt_to_player) * 2.5
	var pressure_reward := float(player_dashes_forced) * 0.40

	var overkill_penalty := 0.0
	if damage_dealt_to_player >= 4:
		# Variant caused excessive damage; penalize to prevent degenerate stomps
		overkill_penalty = float(damage_dealt_to_player - 3) * 3.0

	fitness_score = maxf(0.0, survival_reward + damage_reward + pressure_reward - overkill_penalty)
	return fitness_score


func to_dict() -> Dictionary:
	return {
		"family": family,
		"generation": generation,
		"variant_name": variant_name,
		"tier": tier,
		"base_max_health": base_max_health,
		"prediction_strength": prediction_strength,
		"flanking_tendency": flanking_tendency,
		"aggression": aggression,
		"evasion_tendency": evasion_tendency,
		"preferred_distance": preferred_distance,
		"attack_timing_mult": attack_timing_mult,
		"coordination_tendency": coordination_tendency,
		"damage_multipliers": damage_multipliers.duplicate(),
		"active_mutations": active_mutations.duplicate(),
		"encounters_survived": encounters_survived,
		"damage_dealt_to_player": damage_dealt_to_player,
		"fitness_score": fitness_score
	}


static func from_dict(d: Dictionary) -> RefCounted:
	var script = load("res://scripts/enemy_genome.gd") as GDScript
	var g = script.new(d.get("family", "CHASER"), int(d.get("generation", 1)))
	g.variant_name = d.get("variant_name", "Standard")
	g.tier = int(d.get("tier", 0))
	g.base_max_health = int(d.get("base_max_health", 3))
	g.prediction_strength = float(d.get("prediction_strength", 0.0))
	g.flanking_tendency = float(d.get("flanking_tendency", 0.0))
	g.aggression = float(d.get("aggression", 1.0))
	g.evasion_tendency = float(d.get("evasion_tendency", 0.0))
	g.preferred_distance = float(d.get("preferred_distance", 140.0))
	g.attack_timing_mult = float(d.get("attack_timing_mult", 1.0))
	g.coordination_tendency = float(d.get("coordination_tendency", 0.5))
	g.damage_multipliers = d.get("damage_multipliers", { "plasma": 1.0, "dash": 1.0, "hazard": 1.0 })
	g.active_mutations.assign(d.get("active_mutations", []))
	g.encounters_survived = int(d.get("encounters_survived", 0))
	g.damage_dealt_to_player = int(d.get("damage_dealt_to_player", 0))
	g.fitness_score = float(d.get("fitness_score", 0.0))
	g.clamp_all_traits()
	return g

