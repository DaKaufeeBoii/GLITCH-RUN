extends Node
## Central manager for the active roguelite run: health, room progression, upgrades, and score.

signal health_updated(current: int, maximum: int)
signal room_advanced(new_room_index: int, total_rooms: int)
signal upgrade_applied(upgrade_id: String)
signal run_completed(won: bool)

const TOTAL_ROOMS := 5
const RUN_PROGRESSION_SCRIPT := preload("res://scripts/run_progression.gd")

var progression: RefCounted

var current_health := 5
var max_health := 5
var current_sector := 1
var current_room_index := 0
var current_wave := 1
var waves_in_room := 1
var score := 0
var run_active := false
var run_won := false
var is_finalized := false
var run_time := 0.0

# Active stat multipliers and perks
var move_speed_mult := 1.0
var fire_interval_mult := 1.0
var damage_bonus := 0
var projectile_count := 1
var dash_cooldown_mult := 1.0
var dash_damage := false
var siphon_chance := 0.0
var active_upgrade_ids: Array[String] = []

# Persistent Run Statistics & Director Debrief History
const SAVE_FILE_PATH := "user://save_data.json"
const MAX_DUNGEON_HISTORY: int = 15
const MAX_LOG_HISTORY: int = 20
var best_depth := 1
var best_sector := 1
var best_score := 0
var best_time := 0.0
var difficulty := "NORMAL"
var tactics_log: Array[Dictionary] = []
var evolution_log: Array[Dictionary] = []
var dungeon_layout_summary: Array[Dictionary] = []
var boss_encounter_history: Array[Dictionary] = []
var current_seed := 1337


func _ready() -> void:
	progression = RUN_PROGRESSION_SCRIPT.new(current_seed, difficulty)
	load_persistent_data()


func load_persistent_data() -> void:
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		return
	var file := FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	if not file:
		return
	var json_str := file.get_as_text()
	file.close()

	var test_json := JSON.new()
	var err := test_json.parse(json_str)
	if err != OK or not (test_json.data is Dictionary):
		return

	var d: Dictionary = test_json.data
	var ver: int = int(d.get("version", 1))
	if ver == 1:
		best_depth = maxi(1, int(d.get("best_sector", 1)))
		best_sector = maxi(1, int(ceilf(float(best_depth) / 5.0)))
	else:
		best_depth = maxi(1, int(d.get("best_depth", 1)))
		best_sector = maxi(1, int(d.get("best_sector", 1)))
	best_score = maxi(0, int(d.get("best_score", 0)))
	best_time = maxf(0.0, float(d.get("best_time", 0.0)))
	difficulty = d.get("difficulty", "NORMAL")


func save_persistent_data() -> void:
	var file := FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if not file:
		return
	var d := {
		"version": 2,
		"best_depth": best_depth,
		"best_sector": best_sector,
		"best_score": best_score,
		"best_time": best_time,
		"difficulty": difficulty
	}
	file.store_string(JSON.stringify(d, "\t"))
	file.close()

const UPGRADE_CATALOG: Array[Dictionary] = [
	{
		"id": "OVERCLOCK",
		"title": "OVERCLOCK",
		"desc": "+35% Weapon Fire Rate",
		"flavor": "Bypasses plasma heatsinks for hyper-rapid cycles."
	},
	{
		"id": "HIGH_VOLTAGE",
		"title": "HIGH VOLTAGE",
		"desc": "+1 Shot Damage (-10% Fire Rate)",
		"flavor": "Supercharges plasma bolts with destructive kinetic force."
	},
	{
		"id": "SPLIT_PULSE",
		"title": "SPLIT PULSE",
		"desc": "Twin Projectile Volley",
		"flavor": "Calibrates dual muzzle convergence emitter."
	},
	{
		"id": "PHANTOM_DRIVE",
		"title": "PHANTOM DRIVE",
		"desc": "+25% Move Speed, -25% Dash CD",
		"flavor": "Over-tunes anti-inertial field thrusters."
	},
	{
		"id": "NANO_INFUSION",
		"title": "NANO INFUSION",
		"desc": "+2 Max HP & Instantly Heals 2 HP",
		"flavor": "Deploys regenerative biocircuit patches."
	},
	{
		"id": "STATIC_BLINK",
		"title": "STATIC BLINK",
		"desc": "Dash Zaps Enemies for 2 DMG",
		"flavor": "Leaves a razor-sharp ionized trail during blink."
	},
	{
		"id": "ENERGY_SIPHON",
		"title": "ENERGY SIPHON",
		"desc": "25% Chance to Reclaim 1 HP on Kill",
		"flavor": "Converts downed hostiles into usable repair cells."
	}
]

const UPGRADE_STACK_CAPS := {
	"OVERCLOCK": 3,
	"HIGH_VOLTAGE": 2,
	"SPLIT_PULSE": 1,
	"PHANTOM_DRIVE": 2,
	"NANO_INFUSION": 3,
	"STATIC_BLINK": 1,
	"ENERGY_SIPHON": 2
}


func start_new_run(p_seed: int = 0) -> void:
	max_health = 5
	current_health = max_health
	current_sector = 1
	current_room_index = 0
	current_wave = 1
	waves_in_room = 1
	score = 0
	run_time = 0.0
	run_active = true
	run_won = false
	is_finalized = false

	if p_seed != 0:
		current_seed = p_seed
	else:
		current_seed = int(Time.get_ticks_usec() ^ randi()) & 0x7FFFFFFF
		if current_seed == 0:
			current_seed = 1337

	if not progression:
		progression = RUN_PROGRESSION_SCRIPT.new(current_seed, difficulty)
	progression.base_run_seed = current_seed
	progression.difficulty = difficulty
	progression.reset()
	current_sector = progression.sector_index
	current_room_index = progression.room_index
	current_wave = progression.current_wave
	waves_in_room = progression.waves_in_room

	move_speed_mult = 1.0
	fire_interval_mult = 1.0
	damage_bonus = 0
	projectile_count = 1
	dash_cooldown_mult = 1.0
	dash_damage = false
	siphon_chance = 0.0
	active_upgrade_ids.clear()
	tactics_log.clear()
	evolution_log.clear()
	dungeon_layout_summary.clear()
	boss_encounter_history.clear()
	health_updated.emit(current_health, max_health)


func record_boss_encounter(boss_id: String, sector: int, depth: int, outcome: String, mutations: Array = []) -> void:
	boss_encounter_history.append({
		"boss_id": boss_id,
		"sector": sector,
		"depth": depth,
		"outcome": outcome,
		"mutations": mutations
	})
	if boss_encounter_history.size() > MAX_LOG_HISTORY:
		boss_encounter_history = boss_encounter_history.slice(boss_encounter_history.size() - MAX_LOG_HISTORY)


func record_tactic(sector: int, tactic_name: String, trigger_reason: String, mutations_desc: String) -> void:
	tactics_log.append({
		"sector": sector,
		"tactic": tactic_name,
		"reason": trigger_reason,
		"mutations": mutations_desc
	})
	if tactics_log.size() > MAX_LOG_HISTORY:
		tactics_log = tactics_log.slice(tactics_log.size() - MAX_LOG_HISTORY)


func set_evolution_log(history: Array) -> void:
	if history.size() > MAX_LOG_HISTORY:
		evolution_log.assign(history.slice(history.size() - MAX_LOG_HISTORY))
	else:
		evolution_log.assign(history.duplicate(true))


func record_room_summary(room_dict: Dictionary) -> void:
	dungeon_layout_summary.append(room_dict)
	if dungeon_layout_summary.size() > MAX_DUNGEON_HISTORY:
		dungeon_layout_summary = dungeon_layout_summary.slice(dungeon_layout_summary.size() - MAX_DUNGEON_HISTORY)


func finalize_run_stats(won: bool) -> void:
	if is_finalized:
		return
	is_finalized = true
	run_active = false
	run_won = won

	var cur_depth: int = progression.run_depth if progression else (current_room_index + 1)
	if cur_depth > best_depth:
		best_depth = cur_depth
	var cur_sec: int = progression.sector_index if progression else 1
	if cur_sec > best_sector:
		best_sector = cur_sec
	if score > best_score:
		best_score = score
	if won and (best_time == 0.0 or run_time < best_time):
		best_time = run_time
	save_persistent_data()


func get_random_upgrade_choices(count: int = 3) -> Array[Dictionary]:
	var available: Array[Dictionary] = []
	for item in UPGRADE_CATALOG:
		if get_upgrade_stack_count(item.id) >= get_upgrade_stack_cap(item.id):
			continue
		available.append(item)

	available.shuffle()
	if available.is_empty():
		return [{
			"id": "FIELD_REPAIR",
			"title": "FIELD REPAIR",
			"desc": "+1 HP",
			"flavor": "Restore one integrity point when every subroutine is fully stacked."
		}]
	return available.slice(0, mini(count, available.size()))


func get_upgrade_stack_count(upgrade_id: String) -> int:
	var stacks := 0
	for owned_id in active_upgrade_ids:
		if owned_id == upgrade_id:
			stacks += 1
	return stacks


func get_upgrade_stack_cap(upgrade_id: String) -> int:
	return int(UPGRADE_STACK_CAPS.get(upgrade_id, 0))


func apply_upgrade(upgrade_id: String) -> bool:
	if upgrade_id == "FIELD_REPAIR":
		heal(1)
		return true
	if get_upgrade_stack_cap(upgrade_id) <= 0 or get_upgrade_stack_count(upgrade_id) >= get_upgrade_stack_cap(upgrade_id):
		return false
	active_upgrade_ids.append(upgrade_id)
	match upgrade_id:
		"OVERCLOCK":
			fire_interval_mult = maxf(0.35, fire_interval_mult * 0.72)
		"HIGH_VOLTAGE":
			damage_bonus += 1
			fire_interval_mult *= 1.10
		"SPLIT_PULSE":
			projectile_count = 2
		"PHANTOM_DRIVE":
			move_speed_mult = minf(1.40, move_speed_mult * 1.16)
			dash_cooldown_mult = maxf(0.45, dash_cooldown_mult * 0.85)
		"NANO_INFUSION":
			max_health += 2
			current_health = mini(max_health, current_health + 2)
			health_updated.emit(current_health, max_health)
		"STATIC_BLINK":
			dash_damage = true
		"ENERGY_SIPHON":
			siphon_chance = minf(0.5, siphon_chance + 0.25)

	upgrade_applied.emit(upgrade_id)
	return true


func on_enemy_eliminated() -> bool:
	score += 1
	if siphon_chance > 0.0 and randf() < siphon_chance:
		if current_health < max_health:
			current_health = mini(max_health, current_health + 1)
			health_updated.emit(current_health, max_health)
			return true
	return false


func heal(amount: int) -> void:
	current_health = mini(max_health, current_health + amount)
	health_updated.emit(current_health, max_health)


func take_damage(amount: int) -> void:
	current_health = maxi(0, current_health - amount)
	health_updated.emit(current_health, max_health)
	if current_health <= 0:
		run_active = false
		run_won = false
		run_completed.emit(false)


func advance_room(target_room: int = -1) -> Dictionary:
	var result: Dictionary = progression.advance_room(target_room) if progression else {
		"is_new_sector": false,
		"sector": 1,
		"room": (target_room if target_room >= 0 else current_room_index + 1),
		"depth": current_room_index + 1,
		"sector_seed": current_seed
	}
	current_room_index = progression.room_index if progression else (target_room if target_room >= 0 else current_room_index + 1)
	current_sector = progression.sector_index if progression else 1
	current_wave = 1
	waves_in_room = progression.waves_in_room if progression else 1
	room_advanced.emit(current_room_index, progression.rooms_per_sector if progression else TOTAL_ROOMS)
	return result
