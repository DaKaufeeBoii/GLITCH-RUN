extends RefCounted
class_name RunProgression
## Manages endless sector, room, and wave progression for GLITCH//RUN.
## Replaces fixed 6-room caps with a monotonic depth and multi-wave loop.

signal wave_changed(current_wave: int, total_waves: int)
signal room_changed(room_index: int, total_rooms: int, sector: int, depth: int)
signal sector_changed(new_sector: int, sector_seed: int)

const DEFAULT_ROOMS_PER_SECTOR := 5
const MAX_WAVES_PER_ROOM := 5
const MIN_WAVES_PER_ROOM := 3

var run_depth: int = 1 # Monotonically increasing across entire run
var sector_index: int = 1
var room_index: int = 0 # 0 to rooms_per_sector - 1
var rooms_per_sector: int = DEFAULT_ROOMS_PER_SECTOR
var current_wave: int = 1
var waves_in_room: int = 1
var difficulty: String = "NORMAL" # "EASY", "NORMAL", "HARD"
var base_run_seed: int = 1337
var is_endless: bool = true


func _init(p_run_seed: int = 1337, p_difficulty: String = "NORMAL") -> void:
	base_run_seed = p_run_seed
	difficulty = p_difficulty
	reset()


func reset() -> void:
	run_depth = 1
	sector_index = 1
	room_index = 0
	rooms_per_sector = DEFAULT_ROOMS_PER_SECTOR
	current_wave = 1
	waves_in_room = 1


static func derive_sector_seed(base_seed: int, sector: int) -> int:
	## Deterministically derives unique seed per sector from base run seed
	var s := ((base_seed << 5) ^ (sector * 31337) ^ 0x5DEECE66D) & 0x7FFFFFFF
	return s if s != 0 else 1337


func get_current_sector_seed() -> int:
	return derive_sector_seed(base_run_seed, sector_index)


func is_boss_chamber() -> bool:
	return room_index >= rooms_per_sector - 1


func calculate_waves_for_current_room(room_type: String) -> int:
	if room_type == "START":
		waves_in_room = 1
	elif room_type == "BOSS" or is_boss_chamber():
		waves_in_room = 1
	else:
		# Bounded wave curve: 3 waves early, 4 waves mid, 5 waves deep
		if difficulty == "EASY":
			waves_in_room = 3
		elif difficulty == "HARD":
			waves_in_room = clampi(3 + int(run_depth / 4), 3, MAX_WAVES_PER_ROOM)
		else: # NORMAL
			if run_depth <= 3:
				waves_in_room = 3
			elif run_depth <= 7:
				waves_in_room = 4
			else:
				waves_in_room = 5
	current_wave = 1
	return waves_in_room


func calculate_spawn_budget(wave: int) -> int:
	## Returns enemy count budget for a specific wave
	var base_count := 3
	match difficulty:
		"EASY":
			base_count = 2
		"HARD":
			base_count = 4
		_:
			base_count = 3

	# Gradual scaling with depth and wave index
	var depth_bonus := clampi(int(run_depth / 3), 0, 4)
	var wave_bonus := clampi(wave - 1, 0, 2)
	var total_budget: int = clampi(base_count + depth_bonus + wave_bonus, 2, 9)
	return total_budget


func advance_wave() -> bool:
	## Advances to next wave in current room. Returns true if another wave exists, false if room is cleared.
	if current_wave < waves_in_room:
		current_wave += 1
		wave_changed.emit(current_wave, waves_in_room)
		return true
	return false


func advance_room(target_room: int = -1) -> Dictionary:
	## Advances room or triggers new sector when reaching end of sector chambers.
	run_depth += 1
	if target_room >= 0:
		room_index = target_room
	else:
		room_index += 1
	current_wave = 1

	var is_new_sector := false
	if room_index >= rooms_per_sector:
		sector_index += 1
		room_index = 0
		is_new_sector = true
		sector_changed.emit(sector_index, get_current_sector_seed())

	room_changed.emit(room_index, rooms_per_sector, sector_index, run_depth)
	return {
		"is_new_sector": is_new_sector,
		"sector": sector_index,
		"room": room_index,
		"depth": run_depth,
		"sector_seed": get_current_sector_seed()
	}


func get_difficulty_multipliers() -> Dictionary:
	## Returns speed and telegraph multipliers bounded for fairness
	var speed_mult := 1.0
	var telegraph_mult := 1.0

	# Smooth, bounded scaling with run depth
	var depth_factor := minf(0.20, float(run_depth - 1) * 0.015)
	speed_mult += depth_factor
	telegraph_mult = maxf(0.75, 1.0 - depth_factor * 0.8)

	if difficulty == "EASY":
		speed_mult *= 0.90
		telegraph_mult *= 1.15
	elif difficulty == "HARD":
		speed_mult *= 1.10
		telegraph_mult *= 0.90

	return {
		"speed_mult": clampf(speed_mult, 0.80, 1.25),
		"telegraph_mult": clampf(telegraph_mult, 0.70, 1.30)
	}
