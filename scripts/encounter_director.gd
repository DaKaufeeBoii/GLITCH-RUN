extends RefCounted
class_name EncounterDirector
## Coordinates encounter composition, integrating DungeonGenerator tactical context,
## BehaviorTracker metrics, LearningPolicy / AdaptiveDirector decisions, and EvolutionManager genomes.

const DUNGEON_GEN_SCRIPT := preload("res://scripts/dungeon_generator.gd")
const ADAPTIVE_DIRECTOR_SCRIPT := preload("res://scripts/adaptive_director.gd")
const LEARNING_POLICY_SCRIPT := preload("res://scripts/learning_policy.gd")
const EVOLUTION_MANAGER_SCRIPT := preload("res://scripts/evolution_manager.gd")

var adaptive_director: RefCounted
var learning_policy: RefCounted
var evolution_manager: RefCounted

var use_learning_policy := true


func _init() -> void:
	adaptive_director = ADAPTIVE_DIRECTOR_SCRIPT.new()
	learning_policy = LEARNING_POLICY_SCRIPT.new()
	evolution_manager = EVOLUTION_MANAGER_SCRIPT.new()

	# Try to load pre-trained offline weights if available
	learning_policy.load_from_json_file()


func reset() -> void:
	adaptive_director.reset()
	learning_policy.reset()
	evolution_manager.reset()


func prepare_encounter(
	room: RefCounted,
	player_profile: Dictionary,
	current_hp: int,
	max_hp: int
) -> Dictionary:
	## Analyzes room context & player profile, selects a fair tactical response,
	## and equips each enemy spawn with an evolved EnemyGenome.

	var room_idx: int = room.index
	var chokepoint_ratio: float = float(room.tactical_context.get("chokepoint_ratio", 0.0))
	var has_cover: bool = bool(room.tactical_context.get("has_cover", false))
	var flanking_lanes: int = int(room.tactical_context.get("flanking_lanes", 1))

	var chosen_tactic := "DEFAULT"
	var banner_title := "STANDARD DEPLOYMENT"
	var banner_sub := "Tactical matrix aligned."
	var speed_mult := 1.0
	var telegraph_mult := 1.0
	var pincer_active := false
	var shooter_lead := 0.0
	var hazard_trail := false

	# 1. Decide Tactic via LearningPolicy or AdaptiveDirector
	if room_idx == 0 or not player_profile.get("has_data", false):
		chosen_tactic = "DEFAULT"
		banner_title = "STANDARD DEPLOYMENT"
		banner_sub = "Observing combat subroutines..."
	elif use_learning_policy:
		var ctx_vec: Array[float] = learning_policy.extract_context(player_profile, chokepoint_ratio)
		var decision: Dictionary = learning_policy.select_action(ctx_vec, current_hp, max_hp)
		chosen_tactic = decision.action_name
		banner_title = "DIRECTOR // %s" % chosen_tactic.replace("_", " ")
		banner_sub = decision.reason

		match chosen_tactic:
			"COUNTER_MOBILITY":
				speed_mult = 1.05
				hazard_trail = true
				shooter_lead = 0.75
			"COUNTER_RANGED":
				speed_mult = 1.15
				pincer_active = true
				shooter_lead = 1.0
			"COUNTER_TURRET":
				telegraph_mult = 0.90
				hazard_trail = true
				pincer_active = true
				shooter_lead = 0.60
			"STABILIZATION":
				speed_mult = 0.88
				telegraph_mult = 1.30
				banner_title = "DIRECTOR PROTOCOL // COMBAT STABILIZATION"
				banner_sub = "Tactical mutations suspended • Telegraph windows widened +30%"
			"BALANCED_ATTRITION":
				speed_mult = 1.0
				telegraph_mult = 1.0
	else:
		var dir_decision: Dictionary = adaptive_director.evaluate_sector_tactics(
			player_profile,
			room_idx,
			current_hp,
			max_hp
		)
		chosen_tactic = dir_decision.tactic
		banner_title = dir_decision.banner_title
		banner_sub = dir_decision.banner_sub
		speed_mult = dir_decision.enemy_speed_mult
		telegraph_mult = dir_decision.enemy_telegraph_mult
		pincer_active = dir_decision.get("pincer_flanking", false)
		shooter_lead = dir_decision.get("shooter_lead", 0.0)
		hazard_trail = dir_decision.get("has_hazard_trail", false)

	# 2. Environmental Interplay: Modify response based on Room Geometry
	if flanking_lanes >= 3 and not pincer_active and player_profile.get("ranged", 0.5) > 0.45:
		# Multiple approach routes available in geometry: encourage flankers
		pincer_active = true

	if chokepoint_ratio > 0.60 and hazard_trail:
		# Narrow chokepoint: lengthen telegraph so hazard trail is not an inescapable killzone
		telegraph_mult = maxf(telegraph_mult, 1.25)

	# 3. Equip Enemies with Evolved Genomes
	var final_spawn_list: Array[Dictionary] = []
	for espawn in room.enemy_spawns:
		var family: String = espawn.type
		var genome: RefCounted = null
		if family in ["CHASER", "SHOOTER", "DASHER"]:
			genome = evolution_manager.get_genome_for_spawn(family)
			# Apply active tactical mutations
			if pincer_active and family == "CHASER":
				genome.apply_named_mutation("PINCER_WINGS")
			if shooter_lead > 0.0 and family == "SHOOTER":
				genome.apply_named_mutation("PREDICTIVE_OPTICS")
			if hazard_trail and family == "DASHER":
				genome.apply_named_mutation("ION_HAZARD_TRAIL")

		final_spawn_list.append({
			"type": espawn.type,
			"pos": espawn.pos,
			"flank_angle": espawn.flank_angle if pincer_active else 0.0,
			"genome": genome
		})

	return {
		"tactic": chosen_tactic,
		"banner_title": banner_title,
		"banner_sub": banner_sub,
		"enemy_speed_mult": speed_mult,
		"enemy_telegraph_mult": telegraph_mult,
		"pincer_active": pincer_active,
		"shooter_lead": shooter_lead,
		"hazard_trail": hazard_trail,
		"spawn_list": final_spawn_list
	}


func record_encounter_result(
	sector_index: int,
	damage_taken: int,
	combat_time: float,
	player_profile: Dictionary,
	chosen_tactic: String
) -> void:
	## Reports combat feedback to LearningPolicy, AdaptiveDirector, and EvolutionManager.
	adaptive_director.record_tactic_result(chosen_tactic, damage_taken)

	if use_learning_policy:
		var act_id: int = LEARNING_POLICY_SCRIPT.ACTION_NAMES.find(chosen_tactic)
		if act_id >= 0:
			var reward: float = learning_policy.compute_reward(damage_taken, combat_time, player_profile, act_id)
			learning_policy.update_policy(reward)

	evolution_manager.process_encounter_end(
		sector_index,
		damage_taken,
		combat_time,
		player_profile,
		chosen_tactic
	)
