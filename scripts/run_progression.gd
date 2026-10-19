extends RefCounted
class_name RunProgression
## Manages sector-level wave scheduling, room advancement, and depth progression for GLITCH//RUN.
## Enforces exactly 3–5 regular combat waves total per sector (distributed across combat rooms).
## Non-wave rooms: START, RECOVERY, SHOP, GIFT.
## Boss is a separate end-of-sector encounter after the regular waves.

signal wave_changed(current_wave: int, total_waves: int)
signal room_changed(room_index: int, total_rooms: int, sector: int, depth: int)
signal sector_changed(new_sector: int, sector_seed: int)
signal sector_waves_cleared()
signal biome_changed(new_biome: int, biome_name: String)

const DEFAULT_ROOMS_PER_SECTOR := 5
const MIN_SECTOR_WAVES := 3
const MAX_SECTOR_WAVES := 5
const MAX_WAVES_PER_ROOM := 5
const MAX_OPTIONAL_ROOMS_PER_SECTOR := 3
const SECTORS_PER_BIOME := 3
const BIOME_DATA_SCRIPT := preload("res://scripts/biome_data.gd")

var run_depth: int = 1 # Monotonically increasing room steps taken across entire run
var current_biome: int = 1
var sector_index: int = 1
var room_index: int = 0 # 0 to rooms_per_sector - 1
var rooms_per_sector: int = DEFAULT_ROOMS_PER_SECTOR
var optional_rooms_per_sector: int = 0

# Sector-level wave schedule (3–5 regular waves total per sector)
var sector_total_waves: int = 3
var sector_waves_completed: int = 0

# Room-level wave state
var current_wave: int = 1
var waves_in_room: int = 1

var difficulty: String = "NORMAL" # "EASY", "NORMAL", "HARD", "HYPERGRID"
var base_run_seed: int = 1337
var is_endless: bool = true


func _init(p_run_seed: int = 1337, p_difficulty: String = "NORMAL") -> void:
	base_run_seed = p_run_seed
	difficulty = p_difficulty
	reset()


func reset() -> void:
	run_depth = 1
	current_biome = 1
	sector_index = 1
	room_index = 0
	rooms_per_sector = DEFAULT_ROOMS_PER_SECTOR
	_init_sector_wave_schedule()
	current_wave = 1
	waves_in_room = 1


func _init_sector_wave_schedule() -> void:
	sector_waves_completed = 0
	# Schedule 3 to 5 regular waves per sector dynamically across the run (never fixed to 5)
	match difficulty:
		"EASY":
			sector_total_waves = 3
		"HARD", "HYPERGRID":
			var s_rng := RandomNumberGenerator.new()
			s_rng.seed = (get_current_sector_seed() ^ 0x66B21) & 0x7FFFFFFF
			sector_total_waves = 4 if sector_index == 1 else s_rng.randi_range(4, 5)
		_: # NORMAL
			if sector_index == 1:
				sector_total_waves = 3
			elif sector_index == 2:
				sector_total_waves = 4
			else:
				var s_rng := RandomNumberGenerator.new()
				s_rng.seed = (get_current_sector_seed() ^ 0x66B21) & 0x7FFFFFFF
				sector_total_waves = s_rng.randi_range(MIN_SECTOR_WAVES, MAX_SECTOR_WAVES)

	# Keep the opening floor readable and predictable. Later floors can roll zero
	# perk rooms or a seeded mix of up to three service rooms.
	if sector_index <= 1:
		optional_rooms_per_sector = 0
	else:
		var layout_rng := RandomNumberGenerator.new()
		layout_rng.seed = (get_current_sector_seed() ^ 0x4D4150) & 0x7FFFFFFF
		optional_rooms_per_sector = layout_rng.randi_range(0, MAX_OPTIONAL_ROOMS_PER_SECTOR)
	rooms_per_sector = 2 + sector_total_waves + optional_rooms_per_sector


static func derive_sector_seed(base_seed: int, sector: int) -> int:
	var s := ((base_seed << 5) ^ (sector * 31337) ^ 0x5DEECE66D) & 0x7FFFFFFF
	return s if s != 0 else 1337


func get_current_sector_seed() -> int:
	return derive_sector_seed(base_run_seed, sector_index)


func is_boss_chamber() -> bool:
	return room_index >= rooms_per_sector - 1


func is_middle_sector() -> bool:
	return sector_index == 2


func is_final_sector() -> bool:
	return sector_index >= SECTORS_PER_BIOME


func is_mid_boss_encounter() -> bool:
	return is_middle_sector() and is_boss_chamber()


func is_final_boss_encounter() -> bool:
	return is_final_sector() and is_boss_chamber()


func get_current_biome_data() -> Dictionary:
	return BIOME_DATA_SCRIPT.get_biome(current_biome)


func is_sector_regular_waves_complete() -> bool:
	return sector_waves_completed >= sector_total_waves


func calculate_waves_for_current_room(_room_type: String = "", one_encounter_per_room: bool = false) -> int:
	## Calculates combat wave count for each chamber.
	## Every chamber guarantees enemy combat engagements (never 0 waves).
	## Combat & Elite rooms always have 3–5 waves procedurally (never 1 wave).
	if one_encounter_per_room:
		waves_in_room = 1
	else:
		match _room_type:
			"START", "RECOVERY", "SHOP", "GIFT", "BOSS":
				waves_in_room = 1
			_: # COMBAT, ELITE
				var r_rng := RandomNumberGenerator.new()
				r_rng.seed = (get_current_sector_seed() + run_depth * 41) & 0x7FFFFFFF
				if difficulty == "EASY":
					waves_in_room = r_rng.randi_range(2, 3)
				elif difficulty in ["HARD", "HYPERGRID"]:
					waves_in_room = r_rng.randi_range(4, 5)
				else:
					# Procedurally vary in range 3 to 5 (never fixed to 5, never collapsed to 1)
					waves_in_room = r_rng.randi_range(3, 5)

	current_wave = 1
	return waves_in_room


func calculate_spawn_budget(wave: int) -> int:
	## Swarm spawn budget scaling with difficulty:
	## Challenging by default, with higher difficulty tiers escalating hostile numbers.
	var base_count := 5
	var min_budget := 4
	var max_budget := 12
	match difficulty:
		"EASY":
			base_count = 3
			min_budget = 3
			max_budget = 7
		"HARD":
			base_count = 7
			min_budget = 6
			max_budget = 14
		"HYPERGRID":
			base_count = 9
			min_budget = 8
			max_budget = 16
		_: # NORMAL (Challenging default)
			base_count = 5
			min_budget = 4
			max_budget = 12

	var depth_bonus := clampi(int(float(run_depth) / 2.5), 0, 4)
	var wave_bonus := clampi(wave - 1, 0, 3)
	var total_budget: int = clampi(base_count + depth_bonus + wave_bonus, min_budget, max_budget)
	return total_budget


func complete_current_wave(is_scheduled_wave: bool = true) -> void:
	## Optional combat rooms do not advance the sector's mandatory wave schedule.
	if is_scheduled_wave and current_wave > 0 and sector_waves_completed < sector_total_waves:
		sector_waves_completed += 1
		if sector_waves_completed >= sector_total_waves:
			sector_waves_cleared.emit()


func advance_wave() -> bool:
	if current_wave < waves_in_room:
		current_wave += 1
		wave_changed.emit(current_wave, waves_in_room)
		return true
	return false


func advance_room(target_room: int = -1) -> Dictionary:
	run_depth += 1
	if target_room >= 0:
		room_index = target_room
	else:
		room_index += 1
	current_wave = 1

	var is_new_sector := false
	var is_new_biome := false
	if room_index >= rooms_per_sector:
		sector_index += 1
		room_index = 0
		is_new_sector = true
		if sector_index > SECTORS_PER_BIOME:
			current_biome += 1
			sector_index = 1
			is_new_biome = true
			var b_data := get_current_biome_data()
			biome_changed.emit(current_biome, b_data.get("name", "NEON PROTOCOL"))
		_init_sector_wave_schedule()
		sector_changed.emit(sector_index, get_current_sector_seed())

	room_changed.emit(room_index, rooms_per_sector, sector_index, run_depth)
	return {
		"is_new_sector": is_new_sector,
		"is_new_biome": is_new_biome,
		"biome": current_biome,
		"sector": sector_index,
		"room": room_index,
		"depth": run_depth,
		"sector_seed": get_current_sector_seed(),
		"sector_total_waves": sector_total_waves,
		"sector_waves_completed": sector_waves_completed
	}


func get_difficulty_multipliers() -> Dictionary:
	var speed_mult := 1.0
	var telegraph_mult := 1.0
	var depth_factor := minf(0.20, float(run_depth - 1) * 0.015)
	speed_mult += depth_factor
	telegraph_mult = maxf(0.75, 1.0 - depth_factor * 0.8)

	if difficulty == "EASY":
		speed_mult *= 0.90
		telegraph_mult *= 1.15
	elif difficulty == "HARD" or difficulty == "HYPERGRID":
		speed_mult *= 1.10
		telegraph_mult *= 0.90

	return {
		"speed_mult": clampf(speed_mult, 0.80, 1.25),
		"telegraph_mult": clampf(telegraph_mult, 0.70, 1.30)
	}
