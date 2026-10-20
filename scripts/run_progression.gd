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

var current_floor: int = 1 # 1 to total_floors_in_sector
var total_floors_in_sector: int = 3 # Always odd: 3, 5, or 7 floors per sector
var completed_floors_total: int = 0 # Run-wide floor count used for paced evolution milestones
var seed_play_time: float = 0.0

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
	current_floor = 1
	completed_floors_total = 0
	room_index = 0
	rooms_per_sector = DEFAULT_ROOMS_PER_SECTOR
	update_sector_floors(seed_play_time)
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


func get_current_floor_seed() -> int:
	## Keep floors reproducible while ensuring each floor in one sector has a distinct map.
	var floor_seed := ((get_current_sector_seed() * 1103515245) ^ (current_floor * 0x45D9F3B) ^ 0x27D4EB2D) & 0x7FFFFFFF
	return floor_seed if floor_seed != 0 else 1337


func update_sector_floors(play_time_seconds: float = -1.0) -> int:
	## Enforces an odd number of floors (3, 5, or 7) based on play time in the current seed.
	if play_time_seconds >= 0.0:
		seed_play_time = play_time_seconds

	if seed_play_time < 180.0:
		total_floors_in_sector = 3
	elif seed_play_time < 450.0:
		total_floors_in_sector = 5
	else:
		total_floors_in_sector = 7
	return total_floors_in_sector


func set_sector_floors(count: int) -> void:
	## Explicit setter enforcing odd floor bounds [3, 7]
	var odd_count: int = count if count % 2 != 0 else count + 1
	total_floors_in_sector = clampi(odd_count, 3, 7)


func is_boss_floor() -> bool:
	## Determines if current floor features a boss encounter:
	## 3 floors: Boss spawns ONLY at floor 3 (last floor).
	## 5 floors: Mid-boss at floor 3, final boss at floor 5.
	## 7 floors: Mid-boss at floor 4, final boss at floor 7.
	match total_floors_in_sector:
		3:
			return current_floor == 3
		5:
			return current_floor == 3 or current_floor == 5
		7:
			return current_floor == 4 or current_floor == 7
		_:
			return current_floor >= total_floors_in_sector


func is_mid_boss_encounter() -> bool:
	if not is_boss_floor():
		return false
	if total_floors_in_sector == 5:
		return current_floor == 3
	elif total_floors_in_sector == 7:
		return current_floor == 4
	return false


func is_final_boss_encounter() -> bool:
	return is_boss_floor() and current_floor == total_floors_in_sector


func is_boss_chamber() -> bool:
	return is_boss_floor() and room_index >= rooms_per_sector - 1


func is_middle_sector() -> bool:
	return sector_index == 2


func is_final_sector() -> bool:
	return sector_index >= SECTORS_PER_BIOME


func get_current_biome_data() -> Dictionary:
	return BIOME_DATA_SCRIPT.get_biome(current_biome)


func is_sector_regular_waves_complete() -> bool:
	return sector_waves_completed >= sector_total_waves


static func compute_performance_rating(current_hp: int, max_hp: int, profile: Dictionary) -> float:
	## Evaluates player gameplay competence & stress based on health, damage rate, and accuracy.
	## Returns a normalized rating: < 0.85 = struggling (grant mercy), 1.0 = balanced, > 1.25 = dominating.
	var hp_ratio: float = float(current_hp) / float(maxi(1, max_hp))
	var accuracy: float = float(profile.get("accuracy", 0.5))
	var dpm: float = float(profile.get("damage_per_min", 0.0))

	var rating := 1.0

	# Health factor
	if hp_ratio >= 0.80:
		rating += (hp_ratio - 0.70) * 0.4
	elif hp_ratio <= 0.40:
		rating -= (0.50 - hp_ratio) * 0.8

	# Damage rate factor (high damage taken lowers rating significantly)
	if dpm > 5.0:
		rating -= 0.35
	elif dpm > 3.0:
		rating -= 0.20
	elif dpm == 0.0 and profile.get("has_data", false):
		rating += 0.15

	# Accuracy factor
	if profile.get("has_data", false):
		if accuracy > 0.65:
			rating += 0.15
		elif accuracy < 0.30:
			rating -= 0.15

	return clampf(rating, 0.4, 1.8)


func calculate_waves_for_current_room(_room_type: String = "", one_encounter_per_room: bool = false, performance_factor: float = 1.0) -> int:
	## Calculates combat wave count for each chamber.
	## Floor 1 (run_depth <= 3): begins easy with mostly 1 or 2 waves.
	## Floor 2+ (run_depth >= 4): scales progressively (3 to 5 waves).
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
					if run_depth <= 3:
						waves_in_room = 2
					else:
						waves_in_room = r_rng.randi_range(2, 3)
				elif difficulty in ["HARD", "HYPERGRID"]:
					waves_in_room = r_rng.randi_range(4, 5)
				else: # NORMAL (Starts gentle on Floor 1, ramps up slowly)
					if run_depth <= 3:
						# Beginning of game: 2 waves for accessible introductory pacing
						waves_in_room = 2
					elif run_depth <= 6:
						waves_in_room = 3
					elif run_depth <= 11:
						waves_in_room = r_rng.randi_range(3, 4)
					else:
						waves_in_room = r_rng.randi_range(3, 5)

					# Dynamic difficulty adjustment:
					# If player is struggling, keep waves gentle
					if performance_factor < 0.8 and waves_in_room > 2 and run_depth <= 8:
						waves_in_room = maxi(2, waves_in_room - 1)

	current_wave = 1
	return waves_in_room


func calculate_spawn_budget(wave: int, performance_factor: float = 1.0) -> int:
	## Swarm spawn budget scaling with difficulty & player performance:
	## Starts gentle (3 enemies on Floor 1), scaling up slowly with depth.
	var base_count := 4
	var min_budget := 3
	var max_budget := 12
	match difficulty:
		"EASY":
			base_count = 3
			min_budget = 3
			max_budget = 7
		"HARD":
			base_count = 6
			min_budget = 5
			max_budget = 14
		"HYPERGRID":
			base_count = 8
			min_budget = 7
			max_budget = 16
		_: # NORMAL (Starts gentle on Floor 1, ramps up slowly)
			if sector_index == 1 or run_depth <= 3:
				base_count = 3
				min_budget = 3
				max_budget = 5
			elif sector_index == 2:
				base_count = 4
				min_budget = 3
				max_budget = 8
			else:
				base_count = 5
				min_budget = 4
				max_budget = 12

	# Gradual depth bonus: +1 enemy per ~3.5 rooms
	var depth_bonus := clampi(int(float(run_depth) / 3.5), 0, 4)
	var wave_bonus := clampi(wave - 1, 0, 2)

	# Dynamic difficulty adjustment:
	# Struggling player -> -1 hostile
	# Dominating player -> +1 hostile
	var perf_adjust := 0
	if performance_factor < 0.85:
		perf_adjust = -1
	elif performance_factor > 1.25:
		perf_adjust = 1

	var total_budget: int = clampi(base_count + depth_bonus + wave_bonus + perf_adjust, min_budget, max_budget)
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


func advance_floor() -> Dictionary:
	## Advances to the next floor in the current sector, or triggers new sector/biome when all floors are cleared.
	completed_floors_total += 1
	run_depth += 1
	current_floor += 1
	room_index = 0
	current_wave = 1

	var is_new_sector := false
	var is_new_biome := false

	if current_floor > total_floors_in_sector:
		sector_index += 1
		current_floor = 1
		is_new_sector = true
		if sector_index > SECTORS_PER_BIOME:
			current_biome += 1
			sector_index = 1
			is_new_biome = true
			var b_data := get_current_biome_data()
			biome_changed.emit(current_biome, b_data.get("name", "NEON PROTOCOL"))
		update_sector_floors(seed_play_time)
		_init_sector_wave_schedule()
		sector_changed.emit(sector_index, get_current_sector_seed())

	room_changed.emit(room_index, rooms_per_sector, sector_index, run_depth)
	return {
		"is_new_floor": true,
		"floor": current_floor,
		"total_floors": total_floors_in_sector,
		"completed_floors_total": completed_floors_total,
		"is_new_sector": is_new_sector,
		"is_new_biome": is_new_biome,
		"biome": current_biome,
		"sector": sector_index,
		"room": room_index,
		"depth": run_depth,
		"sector_seed": get_current_sector_seed(),
		"is_boss_floor": is_boss_floor(),
		"is_mid_boss": is_mid_boss_encounter(),
		"is_final_boss": is_final_boss_encounter()
	}


func get_difficulty_multipliers(performance_factor: float = 1.0) -> Dictionary:
	var speed_mult := 1.0
	var telegraph_mult := 1.0
	var depth_factor := minf(0.20, float(run_depth - 1) * 0.015)
	speed_mult += depth_factor
	telegraph_mult = maxf(0.75, 1.0 - depth_factor * 0.8)

	if difficulty == "EASY" or sector_index == 1:
		speed_mult *= 0.90
		telegraph_mult *= 1.15
	elif difficulty == "HARD" or difficulty == "HYPERGRID":
		speed_mult *= 1.10
		telegraph_mult *= 0.90

	# Dynamic difficulty scaling based on player gameplay
	if performance_factor < 0.85:
		# Player struggling: grant mercy
		speed_mult *= 0.88
		telegraph_mult *= 1.25
	elif performance_factor > 1.25:
		# Player dominating: slight speed and reaction challenge
		speed_mult *= 1.05
		telegraph_mult *= 0.92

	return {
		"speed_mult": clampf(speed_mult, 0.75, 1.30),
		"telegraph_mult": clampf(telegraph_mult, 0.65, 1.45)
	}
