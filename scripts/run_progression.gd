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

const DEFAULT_ROOMS_PER_SECTOR := 5
const MIN_SECTOR_WAVES := 3
const MAX_SECTOR_WAVES := 5

var run_depth: int = 1 # Monotonically increasing room steps taken across entire run
var sector_index: int = 1
var room_index: int = 0 # 0 to rooms_per_sector - 1
var rooms_per_sector: int = DEFAULT_ROOMS_PER_SECTOR

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
	sector_index = 1
	room_index = 0
	rooms_per_sector = DEFAULT_ROOMS_PER_SECTOR
	_init_sector_wave_schedule()
	current_wave = 1
	waves_in_room = 1


func _init_sector_wave_schedule() -> void:
	sector_waves_completed = 0
	# Schedule exactly 3, 4, or 5 regular waves per sector based on difficulty and sector depth
	match difficulty:
		"EASY":
			sector_total_waves = 3
		"HARD", "HYPERGRID":
			sector_total_waves = 4 if sector_index == 1 else 5
		_: # NORMAL
			if sector_index == 1:
				sector_total_waves = 3
			elif sector_index == 2:
				sector_total_waves = 4
			else:
				sector_total_waves = 5


static func derive_sector_seed(base_seed: int, sector: int) -> int:
	var s := ((base_seed << 5) ^ (sector * 31337) ^ 0x5DEECE66D) & 0x7FFFFFFF
	return s if s != 0 else 1337


func get_current_sector_seed() -> int:
	return derive_sector_seed(base_run_seed, sector_index)


func is_boss_chamber() -> bool:
	return room_index >= rooms_per_sector - 1


func is_sector_regular_waves_complete() -> bool:
	return sector_waves_completed >= sector_total_waves


func calculate_waves_for_current_room(room_type: String) -> int:
	## Distributes scheduled sector waves to combat rooms.
	## Non-wave rooms (START, RECOVERY, SHOP, GIFT) have 0 waves.
	## Boss is a separate end-of-sector encounter (1 boss wave).
	match room_type:
		"START", "RECOVERY", "SHOP", "GIFT":
			waves_in_room = 0
			current_wave = 0
			return 0
		"BOSS":
			waves_in_room = 1
			current_wave = 1
			return 1
		_: # COMBAT, ELITE
			var remaining_sector_waves: int = sector_total_waves - sector_waves_completed
			if remaining_sector_waves <= 0:
				# All scheduled regular waves for this sector have already been cleared!
				waves_in_room = 0
				current_wave = 0
				return 0
			# Combat room consumes scheduled wave (1 wave per room visit)
			waves_in_room = 1
			current_wave = 1
			return waves_in_room


func calculate_spawn_budget(wave: int) -> int:
	var base_count := 3
	match difficulty:
		"EASY":
			base_count = 2
		"HARD", "HYPERGRID":
			base_count = 4
		_:
			base_count = 3

	var depth_bonus := clampi(int(float(run_depth) / 3.0), 0, 4)
	var wave_bonus := clampi(wave - 1, 0, 2)
	var total_budget: int = clampi(base_count + depth_bonus + wave_bonus, 2, 9)
	return total_budget


func complete_current_wave() -> void:
	## Call when a combat wave in a combat/elite room is cleared
	if current_wave > 0 and sector_waves_completed < sector_total_waves:
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
	if room_index >= rooms_per_sector:
		sector_index += 1
		room_index = 0
		is_new_sector = true
		_init_sector_wave_schedule()
		sector_changed.emit(sector_index, get_current_sector_seed())

	room_changed.emit(room_index, rooms_per_sector, sector_index, run_depth)
	return {
		"is_new_sector": is_new_sector,
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
