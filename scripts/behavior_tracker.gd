extends RefCounted
class_name BehaviorTracker
## Records recent combat behavior in a rolling window and computes normalized player style metrics.

const WINDOW_DURATION := 45.0
const MIN_COMBAT_TIME_FOR_DATA := 12.0

var total_combat_time := 0.0
var dash_timestamps: Array[float] = []
var damage_timestamps: Array[Dictionary] = []

# Continuous time accumulators
var close_range_time := 0.0
var long_range_time := 0.0
var stationary_firing_time := 0.0
var mobile_firing_time := 0.0
var total_firing_time := 0.0


func reset() -> void:
	total_combat_time = 0.0
	dash_timestamps.clear()
	damage_timestamps.clear()
	close_range_time = 0.0
	long_range_time = 0.0
	stationary_firing_time = 0.0
	mobile_firing_time = 0.0
	total_firing_time = 0.0


func record_dash(current_run_time: float) -> void:
	dash_timestamps.append(current_run_time)
	_trim_timestamps(current_run_time)


func record_damage_taken(amount: int, current_run_time: float) -> void:
	damage_timestamps.append({ "time": current_run_time, "amount": amount })
	_trim_timestamps(current_run_time)


func update(delta: float, player_pos: Vector2, player_vel: Vector2, enemies: Array[Node2D], firing: bool, current_run_time: float) -> void:
	if enemies.is_empty():
		return

	total_combat_time += delta

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
			"damage_per_min": 0.0,
			"dashes_per_min": 0.0
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

	# 5. Damage received rate
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
		"damage_per_min": damage_per_min,
		"dashes_per_min": dashes_per_min
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
		"profile": prof
	}
