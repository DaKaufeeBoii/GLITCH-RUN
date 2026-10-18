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


func _apply_family_defaults() -> void:
	match family:
		"CHASER":
			preferred_distance = 60.0
			aggression = 1.0
			flanking_tendency = 0.0
			prediction_strength = 0.0
			evasion_tendency = 0.1
			coordination_tendency = 0.6
			attack_timing_mult = 1.0
			variant_name = "Chaser Alpha"
		"SHOOTER":
			preferred_distance = 210.0
			aggression = 0.90
			flanking_tendency = 0.1
			prediction_strength = 0.0
			evasion_tendency = 0.4
			coordination_tendency = 0.4
			attack_timing_mult = 1.0
			variant_name = "Shooter Sentry"
		"DASHER":
			preferred_distance = 180.0
			aggression = 1.10
			flanking_tendency = 0.0
			prediction_strength = 0.0
			evasion_tendency = 0.2
			coordination_tendency = 0.3
			attack_timing_mult = 1.0
			variant_name = "Dasher Interceptor"
		"BOSS":
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
		"PREDICTIVE_OPTICS":
			# Tradeoff: Strong lead prediction, but +25% attack interval (slower cycle)
			prediction_strength = clampf(prediction_strength + 0.55, MIN_PREDICTION, MAX_PREDICTION)
			attack_timing_mult = clampf(attack_timing_mult * 1.25, MIN_ATTACK_TIMING, MAX_ATTACK_TIMING)
			active_mutations.append(mut_name)
			variant_name = variant_name + " [Optics]"
			return true

		"PINCER_WINGS":
			# Tradeoff: Wide pincer flanking angle, but -10% direct aggression
			flanking_tendency = clampf(flanking_tendency + 0.55, MIN_FLANKING, MAX_FLANKING)
			aggression = clampf(aggression * 0.90, MIN_AGGRESSION, MAX_AGGRESSION)
			active_mutations.append(mut_name)
			variant_name = variant_name + " [Pincer]"
			return true

		"ION_HAZARD_TRAIL":
			# Tradeoff: Leaves ionized electric trail on dash, but +20% longer telegraph window
			attack_timing_mult = clampf(attack_timing_mult * 1.20, MIN_ATTACK_TIMING, MAX_ATTACK_TIMING)
			active_mutations.append(mut_name)
			variant_name = variant_name + " [IonTrail]"
			return true

		"RAPID_THRUSTERS":
			# Tradeoff: +20% movement speed, but -20% evasion
			aggression = clampf(aggression + 0.20, MIN_AGGRESSION, MAX_AGGRESSION)
			evasion_tendency = clampf(evasion_tendency - 0.20, MIN_EVASION, MAX_EVASION)
			active_mutations.append(mut_name)
			variant_name = variant_name + " [Overclock]"
			return true

		"STATIC_GROUNDING":
			# Tradeoff: 40% resistance to player dash zaps, but -8% movement speed
			damage_multipliers["dash"] = 0.60
			aggression = clampf(aggression * 0.92, MIN_AGGRESSION, MAX_AGGRESSION)
			active_mutations.append(mut_name)
			variant_name = variant_name + " [Insulated]"
			return true

		"DEFENSIVE_STRIKE":
			# Tradeoff: +30% evasive strafing, but -12% direct aggression
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

	# 1. Chaser behavioral application
	if family == "CHASER":
		if "move_speed" in enemy_node:
			enemy_node.move_speed = 92.0 * aggression
		if "flank_angle" in enemy_node:
			# Flank angle up to 0.75 radians (~43 degrees)
			enemy_node.flank_angle = flanking_tendency * 0.70
			if flanking_tendency > 0.15:
				enemy_node.set("is_flanker", true)

	# 2. Shooter behavioral application
	elif family == "SHOOTER":
		if "lead_prediction" in enemy_node:
			enemy_node.lead_prediction = prediction_strength
		if "move_speed" in enemy_node:
			enemy_node.move_speed = 82.0 * aggression
		if "ideal_distance" in enemy_node:
			enemy_node.ideal_distance = preferred_distance

	# 3. Dasher behavioral application
	elif family == "DASHER":
		if "patrol_speed" in enemy_node:
			enemy_node.patrol_speed = 95.0 * aggression
		if "lunge_speed" in enemy_node:
			enemy_node.lunge_speed = 560.0 * aggression
		if "has_hazard_trail" in enemy_node:
			enemy_node.has_hazard_trail = has_mutation("ION_HAZARD_TRAIL")

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
