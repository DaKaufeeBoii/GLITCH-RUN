extends Node
## Central manager for the active roguelite run: health, room progression, upgrades, and score.

signal health_updated(current: int, maximum: int)
signal bits_updated(total_bits: int)
signal archive_bits_updated(total_bits: int)
signal room_advanced(new_room_index: int, total_rooms: int)
signal upgrade_applied(upgrade_id: String)
signal run_completed(won: bool)

const TOTAL_ROOMS := 5
const RUN_PROGRESSION_SCRIPT := preload("res://scripts/run_progression.gd")

var progression: RefCounted

var current_health := 5
var max_health := 5
var current_biome := 1
var current_sector := 1
var current_room_index := 0
var current_wave := 1
var waves_in_room := 1
var score := 0
var bits := 0
var archive_bits := 0
var selected_character_id := "OPERATIVE"
var unlocked_character_ids: Array[String] = ["OPERATIVE"]
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
var has_cryo_rounds := false
var has_acid_plasma := false
var has_arc_discharge := false
var has_tactical_reload := false
var max_ammo_bonus := 0
var reload_speed_mult := 1.0
var has_reactive_plating := false
var has_piercing_beam := false
var has_overdrive_protocol := false
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

const CHARACTER_CATALOG := {
	"OPERATIVE": {
		"title": "OPERATIVE",
		"role": "BALANCED RUNNER",
		"price": 0,
		"max_health": 5,
		"move_speed_mult": 1.0,
		"fire_interval_mult": 1.0,
		"desc": "Balanced movement, health, and twin-rail fire. The reliable starting build."
	},
	"BREACHER": {
		"title": "BREACHER",
		"role": "MELEE SPECIALIST",
		"price": 1000,
		"max_health": 6,
		"move_speed_mult": 1.08,
		"fire_interval_mult": 1.0,
		"desc": "Six integrity. Close-range arc strikes deal 2 base damage and ignore ammo."
	},
	"LONGSHOT": {
		"title": "LONGSHOT",
		"role": "SNIPER",
		"price": 3000,
		"max_health": 4,
		"move_speed_mult": 1.0,
		"fire_interval_mult": 1.55,
		"desc": "Four integrity. Shots hit harder and travel faster, with a slower firing cycle."
	}
}


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
	archive_bits = maxi(0, int(d.get("archive_bits", 0)))
	unlocked_character_ids = ["OPERATIVE"]
	for raw_id in d.get("unlocked_characters", ["OPERATIVE"]):
		var character_id := str(raw_id)
		if CHARACTER_CATALOG.has(character_id) and character_id not in unlocked_character_ids:
			unlocked_character_ids.append(character_id)
	selected_character_id = str(d.get("selected_character", "OPERATIVE"))
	if selected_character_id not in unlocked_character_ids:
		selected_character_id = "OPERATIVE"
	archive_bits_updated.emit(archive_bits)


func save_persistent_data() -> void:
	var file := FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if not file:
		return
	var d := {
		"version": 3,
		"best_depth": best_depth,
		"best_sector": best_sector,
		"best_score": best_score,
		"best_time": best_time,
		"difficulty": difficulty,
		"archive_bits": archive_bits,
		"unlocked_characters": unlocked_character_ids,
		"selected_character": selected_character_id
	}
	file.store_string(JSON.stringify(d, "\t"))
	file.close()

const UPGRADE_CATALOG: Array[Dictionary] = [
	{
		"id": "OVERCLOCK",
		"title": "OVERCLOCK",
		"desc": "+35% Weapon Fire Rate",
		"flavor": "Bypasses plasma heatsinks for hyper-rapid cycles.",
		"rarity": "COMMON"
	},
	{
		"id": "HIGH_VOLTAGE",
		"title": "HIGH VOLTAGE",
		"desc": "+1 Shot Damage (-10% Fire Rate)",
		"flavor": "Supercharges plasma bolts with destructive kinetic force.",
		"rarity": "UNCOMMON"
	},
	{
		"id": "SPLIT_PULSE",
		"title": "SPLIT PULSE",
		"desc": "Twin Projectile Volley",
		"flavor": "Calibrates dual muzzle convergence emitter.",
		"rarity": "UNCOMMON"
	},
	{
		"id": "PHANTOM_DRIVE",
		"title": "PHANTOM DRIVE",
		"desc": "+25% Move Speed, -25% Dash CD",
		"flavor": "Over-tunes anti-inertial field thrusters.",
		"rarity": "COMMON"
	},
	{
		"id": "NANO_INFUSION",
		"title": "NANO INFUSION",
		"desc": "+2 Max HP & Instantly Heals 2 HP",
		"flavor": "Deploys regenerative biocircuit patches.",
		"rarity": "COMMON"
	},
	{
		"id": "STATIC_BLINK",
		"title": "STATIC BLINK",
		"desc": "Dash Zaps Enemies for 2 DMG",
		"flavor": "Leaves a razor-sharp ionized trail during blink.",
		"rarity": "UNCOMMON"
	},
	{
		"id": "ENERGY_SIPHON",
		"title": "ENERGY SIPHON",
		"desc": "25% Chance to Reclaim 1 HP on Kill",
		"flavor": "Converts downed hostiles into usable repair cells.",
		"rarity": "UNCOMMON"
	},
	{
		"id": "CRYO_ROUNDS",
		"title": "CRYO MATRIX",
		"desc": "Shots Inflict 50% Cryo Slow for 3s",
		"flavor": "Sub-zero endothermic emitters chill enemy movement and thrusters.",
		"rarity": "RARE"
	},
	{
		"id": "ACID_PLASMA",
		"title": "ACID CORROSION",
		"desc": "Shots Inflict 1 DMG/sec for 3s",
		"flavor": "Microscopic nanite swarm eats through hostile armor plating.",
		"rarity": "RARE"
	},
	{
		"id": "ARC_DISCHARGE",
		"title": "ARC DISCHARGE",
		"desc": "Bolt Hits Shock Adjacent Hostiles for 1 DMG",
		"flavor": "Ionizes ambient atmosphere with devastating chain lightning.",
		"rarity": "RARE"
	},
	{
		"id": "TACTICAL_RELOAD",
		"title": "TACTICAL RELOAD",
		"desc": "Dash Instantly Refills Full Ammo Magazine",
		"flavor": "Kinetic recycler converts dash momentum directly into cell cartridges.",
		"rarity": "UNCOMMON"
	},
	{
		"id": "EXPANDED_BATTERY",
		"title": "EXPANDED BATTERY",
		"desc": "+8 Max Ammo Capacity & 35% Faster Reload",
		"flavor": "Installs high-density capacitors with micro-induction coils.",
		"rarity": "COMMON"
	},
	{
		"id": "REACTIVE_PLATING",
		"title": "REACTIVE PLATING",
		"desc": "Taking Damage Emits Stun EMP Shockwave",
		"flavor": "Discharges stored kinetic shock into a retaliatory concussive burst.",
		"rarity": "UNCOMMON"
	},
	{
		"id": "PIERCING_BEAM",
		"title": "PIERCING BEAM",
		"desc": "Bolts Pierce Through 1 Hostile",
		"flavor": "Accelerates plasma cores to relativistic penetrative speeds.",
		"rarity": "UNCOMMON"
	},
	{
		"id": "OVERDRIVE_PROTOCOL",
		"title": "OVERDRIVE PROTOCOL",
		"desc": "+50% DMG & +25% Fire Rate when at <= 2 HP",
		"flavor": "Emergency governor override unlocks lethal emergency output.",
		"rarity": "RARE"
	}
]

const UPGRADE_STACK_CAPS := {
	"OVERCLOCK": 3,
	"HIGH_VOLTAGE": 2,
	"SPLIT_PULSE": 1,
	"PHANTOM_DRIVE": 2,
	"NANO_INFUSION": 3,
	"STATIC_BLINK": 1,
	"ENERGY_SIPHON": 2,
	"CRYO_ROUNDS": 1,
	"ACID_PLASMA": 1,
	"ARC_DISCHARGE": 1,
	"TACTICAL_RELOAD": 1,
	"EXPANDED_BATTERY": 2,
	"REACTIVE_PLATING": 1,
	"PIERCING_BEAM": 1,
	"OVERDRIVE_PROTOCOL": 1
}

const UPGRADE_RARITY_CHANCES := {"COMMON": 70, "UNCOMMON": 24, "RARE": 6}


func start_new_run(p_seed: int = 0) -> void:
	var character_profile: Dictionary = get_selected_character_profile()
	max_health = int(character_profile.get("max_health", 5))
	current_health = max_health
	current_sector = 1
	current_room_index = 0
	current_wave = 1
	waves_in_room = 1
	score = 0
	bits = 0
	bits_updated.emit(bits)
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
	current_biome = progression.current_biome
	current_sector = progression.sector_index
	current_room_index = progression.room_index
	current_wave = progression.current_wave
	waves_in_room = progression.waves_in_room

	move_speed_mult = float(character_profile.get("move_speed_mult", 1.0))
	fire_interval_mult = float(character_profile.get("fire_interval_mult", 1.0))
	damage_bonus = 0
	projectile_count = 1
	dash_cooldown_mult = 1.0
	dash_damage = false
	siphon_chance = 0.0
	has_cryo_rounds = false
	has_acid_plasma = false
	has_arc_discharge = false
	has_tactical_reload = false
	max_ammo_bonus = 0
	reload_speed_mult = 1.0
	has_reactive_plating = false
	has_piercing_beam = false
	has_overdrive_protocol = false
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
	# Only unspent run currency is banked. Shop purchases cannot also fund unlocks.
	archive_bits += bits
	archive_bits_updated.emit(archive_bits)
	save_persistent_data()


func get_character_catalog() -> Dictionary:
	return CHARACTER_CATALOG.duplicate(true)


func get_selected_character_profile() -> Dictionary:
	return CHARACTER_CATALOG.get(selected_character_id, CHARACTER_CATALOG["OPERATIVE"]).duplicate(true)


func is_character_unlocked(character_id: String) -> bool:
	return character_id in unlocked_character_ids


func purchase_character(character_id: String) -> bool:
	if not CHARACTER_CATALOG.has(character_id) or is_character_unlocked(character_id):
		return false
	var price: int = int(CHARACTER_CATALOG[character_id].get("price", 0))
	if archive_bits < price:
		return false
	archive_bits -= price
	unlocked_character_ids.append(character_id)
	selected_character_id = character_id
	archive_bits_updated.emit(archive_bits)
	save_persistent_data()
	return true


func select_character(character_id: String) -> bool:
	if not is_character_unlocked(character_id):
		return false
	selected_character_id = character_id
	save_persistent_data()
	return true


func get_random_upgrade_choices(count: int = 3) -> Array[Dictionary]:
	var available: Array[Dictionary] = []
	for item in UPGRADE_CATALOG:
		if get_upgrade_stack_count(item.id) >= get_upgrade_stack_cap(item.id):
			continue
		available.append(item)

	if available.is_empty():
		return [{
			"id": "FIELD_REPAIR",
			"title": "FIELD REPAIR",
			"desc": "+1 HP",
			"flavor": "Restore one integrity point when every subroutine is fully stacked."
		}]
	var rng := RandomNumberGenerator.new()
	var depth: int = progression.run_depth if progression else current_room_index + 1
	rng.seed = int((current_seed ^ (depth * 104729) ^ (active_upgrade_ids.size() * 8191)) & 0x7FFFFFFF)
	var choices: Array[Dictionary] = []
	while choices.size() < mini(count, available.size()):
		var rarity_roll := rng.randi_range(1, 100)
		var wanted_rarity := "COMMON"
		if rarity_roll > UPGRADE_RARITY_CHANCES.COMMON + UPGRADE_RARITY_CHANCES.UNCOMMON:
			wanted_rarity = "RARE"
		elif rarity_roll > UPGRADE_RARITY_CHANCES.COMMON:
			wanted_rarity = "UNCOMMON"
		var tier_items: Array[Dictionary] = []
		for item in available:
			if item.get("rarity", "COMMON") == wanted_rarity:
				tier_items.append(item)
		if tier_items.is_empty():
			tier_items = available.duplicate()
		var selected: Dictionary = tier_items[rng.randi_range(0, tier_items.size() - 1)]
		choices.append(selected)
		available.erase(selected)
	return choices


func get_upgrade_rarity(upgrade_id: String) -> String:
	for item in UPGRADE_CATALOG:
		if item.id == upgrade_id:
			return item.get("rarity", "COMMON")
	return "COMMON"


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
		"CRYO_ROUNDS":
			has_cryo_rounds = true
		"ACID_PLASMA":
			has_acid_plasma = true
		"ARC_DISCHARGE":
			has_arc_discharge = true
		"TACTICAL_RELOAD":
			has_tactical_reload = true
		"EXPANDED_BATTERY":
			max_ammo_bonus += 8
			reload_speed_mult = maxf(0.45, reload_speed_mult * 0.65)
		"REACTIVE_PLATING":
			has_reactive_plating = true
		"PIERCING_BEAM":
			has_piercing_beam = true
		"OVERDRIVE_PROTOCOL":
			has_overdrive_protocol = true

	upgrade_applied.emit(upgrade_id)
	return true


func on_enemy_eliminated(bits_reward: int = 1) -> bool:
	score += 1
	add_bits(bits_reward)
	if siphon_chance > 0.0 and randf() < siphon_chance:
		if current_health < max_health:
			current_health = mini(max_health, current_health + 1)
			health_updated.emit(current_health, max_health)
			return true
	return false


func add_score(amount: int) -> void:
	score = maxi(0, score + amount)


func add_bits(amount: int) -> void:
	if amount <= 0:
		return
	bits += amount
	bits_updated.emit(bits)


func spend_bits(amount: int) -> bool:
	if amount < 0 or bits < amount:
		return false
	bits -= amount
	bits_updated.emit(bits)
	return true


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
	current_biome = progression.current_biome if progression else current_biome
	current_wave = 1
	waves_in_room = progression.waves_in_room if progression else 1
	room_advanced.emit(current_room_index, progression.rooms_per_sector if progression else TOTAL_ROOMS)
	return result


func advance_floor() -> Dictionary:
	if progression:
		progression.seed_play_time = run_time
		var res: Dictionary = progression.advance_floor()
		current_sector = progression.sector_index
		current_biome = progression.current_biome
		current_room_index = 0
		current_wave = 1
		waves_in_room = progression.waves_in_room
		room_advanced.emit(current_room_index, progression.rooms_per_sector)
		return res
	return advance_room()
