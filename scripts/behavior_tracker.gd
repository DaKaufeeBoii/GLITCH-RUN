extends RefCounted
class_name BehaviorTracker
## Records recent combat behavior in a bounded rolling window with temporal decay.
## Computes normalized player style metrics, accuracy, movement consistency,
## and tactical efficacy counters.

const WINDOW_DURATION := 45.0
const MIN_COMBAT_TIME_FOR_DATA := 8.0

var total_combat_time := 0.0
var dash_timestamps: Array[float] = []
var damage_timestamps: Array[Dictionary] = []

# Continuous time accumulators
var close_range_time := 0.0
var long_range_time := 0.0
var stationary_firing_time := 0.0
var mobile_firing_time := 0.0
var total_firing_time := 0.0

# Movement direction & consistency tracking
var last_movement_vector := Vector2.ZERO
var directional_consistency_accum := 0.0
var directional_samples_count := 0

# Shooting accuracy tracking
var shots_fired := 0
var shots_hit := 0

# Tactical efficacy and threat tracking
var damage_by_enemy_family: Dictionary = {
	"CHASER": 0,
	"SHOOTER": 0,
	"DASHER": 0,
	"BOSS": 0,
	"HAZARD": 0,
	"UNKNOWN": 0
}
var kills_by_player_tactic: Dictionary = {
	"BLASTER": 0,
	"DASH_STATIC": 0,
	"SNIPE": 0,
	"POINT_BLANK": 0
}


func reset() -> void:
	total_combat_time = 0.0
	dash_timestamps.clear()
	damage_timestamps.clear()
	close_range_time = 0.0
	long_range_time = 0.0
	stationary_firing_time = 0.0
	mobile_firing_time = 0.0
	total_firing_time = 0.0
	last_movement_vector = Vector2.ZERO
	directional_consistency_accum = 0.0
	directional_samples_count = 0
	shots_fired = 0
	shots_hit = 0
	for k in damage_by_enemy_family.keys():
		damage_by_enemy_family[k] = 0
	for k in kills_by_player_tactic.keys():
		kills_by_player_tactic[k] = 0


func record_dash(current_run_time: float) -> void:
	dash_timestamps.append(current_run_time)
	_trim_timestamps(current_run_time)


func record_damage_taken(
	amount: int,
	current_run_time: float,
	enemy_family: String = "UNKNOWN",
	attack_pattern: String = "CONTACT"
) -> void:
	damage_timestamps.append({
		"time": current_run_time,
		"amount": amount,
		"family": enemy_family,
		"pattern": attack_pattern
	})
	if enemy_family in damage_by_enemy_family:
		damage_by_enemy_family[enemy_family] += amount
	else:
		damage_by_enemy_family["UNKNOWN"] += amount
	_trim_timestamps(current_run_time)


func record_shot_fired() -> void:
	shots_fired += 1


func record_shot_hit() -> void:
	shots_hit += 1


func record_enemy_kill(_enemy_family: String, player_dist: float, is_dash_kill: bool = false) -> void:
	if is_dash_kill:
		kills_by_player_tactic["DASH_STATIC"] += 1
	elif player_dist > 280.0:
		kills_by_player_tactic["SNIPE"] += 1
	elif player_dist < 100.0:
		kills_by_player_tactic["POINT_BLANK"] += 1
	else:
		kills_by_player_tactic["BLASTER"] += 1


func update(
	delta: float,
	player_pos: Vector2,
	player_vel: Vector2,
	enemies: Array[Node2D],
	firing: bool,
	current_run_time: float
) -> void:
	if enemies.is_empty():
		return

	total_combat_time += delta

	# Apply exponential decay so recent behavior overrides outdated habits
	if total_combat_time > WINDOW_DURATION:
		var decay := exp(-delta / WINDOW_DURATION)
		close_range_time *= decay
		long_range_time *= decay
		stationary_firing_time *= decay
		mobile_firing_time *= decay
		total_firing_time *= decay
		directional_consistency_accum *= decay
		directional_samples_count = maxi(1, int(float(directional_samples_count) * decay))

	# Movement consistency analysis (dot product between successive movement headings)
	if player_vel.length() > 30.0:
		var current_heading := player_vel.normalized()
		if last_movement_vector.length() > 0.1:
			var dot := current_heading.dot(last_movement_vector) # -1.0 (reversal) to 1.0 (straight)
			var normalized_dot := (dot + 1.0) * 0.5 # 0.0 (erratic) to 1.0 (smooth)
			directional_consistency_accum += normalized_dot
			directional_samples_count += 1
		last_movement_vector = current_heading

	# Check closest enemy distance
	var min_dist := 9999.0
	for enemy in enemies:
		if is_instance_valid(enemy):
			var d := player_pos.distance_to(enemy.global_position)
			if d < min_dist:
				min_dist = d

	if min_dist < 160.0:
		close_range_time += delta
	elif min_dist > 250.0:
		long_range_time += delta

	if firing:
		total_firing_time += delta
		if player_vel.length() < 40.0:
			stationary_firing_time += delta
		else:
			mobile_firing_time += delta

	_trim_timestamps(current_run_time)


func _trim_timestamps(current_run_time: float) -> void:
	var threshold := current_run_time - WINDOW_DURATION
	while not dash_timestamps.is_empty() and dash_timestamps[0] < threshold:
		dash_timestamps.pop_front()
	while not damage_timestamps.is_empty() and damage_timestamps[0].time < threshold:
		damage_timestamps.pop_front()


func get_profile() -> Dictionary:
	var has_data := total_combat_time >= MIN_COMBAT_TIME_FOR_DATA
	if not has_data:
		return {
			"has_data": false,
			"mobility": 0.5,
			"ranged": 0.5,
			"aggression": 0.5,
			"turret": 0.5,
			"accuracy": 0.5,
			"movement_consistency": 0.5,
			"damage_per_min": 0.0,
			"dashes_per_min": 0.0,
			"dash_interval_avg": 0.0,
			"shots_fired": 0,
			"shots_hit": 0,
			"effective_enemy_types": damage_by_enemy_family.duplicate(),
			"successful_player_tactics": kills_by_player_tactic.duplicate()
		}

	var active_window := minf(total_combat_time, WINDOW_DURATION)
	var window_in_minutes := maxf(0.1, active_window / 60.0)

	# 1. Mobility score: dashes per minute (0 to 10 dashes/min mapped to 0.0 - 1.0)
	var dashes_per_min := float(dash_timestamps.size()) / window_in_minutes
	var mobility_score := clampf(dashes_per_min / 9.0, 0.0, 1.0)

	# 2. Ranged score: ratio of long-range positioning
	var range_denom := close_range_time + long_range_time
	var ranged_score := (long_range_time / range_denom) if range_denom > 0.1 else 0.5

	# 3. Aggression score: close proximity time ratio
	var aggression_score := clampf(close_range_time / maxf(1.0, total_combat_time), 0.0, 1.0) * 2.0
	aggression_score = clampf(aggression_score, 0.0, 1.0)

	# 4. Turret score: stationary firing ratio
	var turret_score := (stationary_firing_time / total_firing_time) if total_firing_time > 1.0 else 0.2

	# 5. Accuracy score: hits / shots fired (bounded 0.0 to 1.0, default 0.5 if no shots yet)
	var accuracy_score := 0.5
	if shots_fired > 0:
		accuracy_score = clampf(float(shots_hit) / float(shots_fired), 0.0, 1.0)

	# 6. Movement consistency: average directional continuity (0.0 = erratic evasions, 1.0 = linear kiting)
	var consistency_score := 0.5
	if directional_samples_count > 0:
		consistency_score = clampf(directional_consistency_accum / float(directional_samples_count), 0.0, 1.0)

	# 7. Average dash interval
	var avg_dash_interval := 0.0
	if dash_timestamps.size() >= 2:
		var sum_diffs := 0.0
		for i in range(1, dash_timestamps.size()):
			sum_diffs += (dash_timestamps[i] - dash_timestamps[i - 1])
		avg_dash_interval = sum_diffs / float(dash_timestamps.size() - 1)

	# 8. Damage received rate
	var total_dmg := 0
	for entry in damage_timestamps:
		total_dmg += entry.amount
	var damage_per_min := float(total_dmg) / window_in_minutes

	return {
		"has_data": true,
		"mobility": mobility_score,
		"ranged": ranged_score,
		"aggression": aggression_score,
		"turret": turret_score,
		"accuracy": accuracy_score,
		"movement_consistency": consistency_score,
		"damage_per_min": damage_per_min,
		"dashes_per_min": dashes_per_min,
		"dash_interval_avg": avg_dash_interval,
		"shots_fired": shots_fired,
		"shots_hit": shots_hit,
		"effective_enemy_types": damage_by_enemy_family.duplicate(),
		"successful_player_tactics": kills_by_player_tactic.duplicate()
	}


func get_combat_metrics() -> Dictionary:
	var prof := get_profile()
	var total_t := maxf(0.1, total_combat_time)
	return {
		"moving_time_ratio": clampf((mobile_firing_time + (total_combat_time - total_firing_time) * 0.7) / total_t, 0.0, 1.0),
		"avg_distance_to_enemy": 300.0 if prof.ranged > 0.65 else (130.0 if prof.aggression > 0.6 else 210.0),
		"firing_time_ratio": clampf(total_firing_time / total_t, 0.0, 1.0),
		"dash_count": dash_timestamps.size(),
		"damage_taken": damage_timestamps.size(),
		"accuracy": prof.accuracy,
		"movement_consistency": prof.movement_consistency,
		"profile": prof
	}
