extends Node
## Central manager for the active roguelite run: health, room progression, upgrades, and score.

signal health_updated(current: int, maximum: int)
signal room_advanced(new_room_index: int, total_rooms: int)
signal upgrade_applied(upgrade_id: String)
signal run_completed(won: bool)

const TOTAL_ROOMS := 6

var current_health := 5
var max_health := 5
var current_room_index := 0
var score := 0
var run_active := false
var run_won := false
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
var best_sector := 1
var best_score := 0
var best_time := 0.0
var tactics_log: Array[Dictionary] = []

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


func start_new_run() -> void:
	max_health = 5
	current_health = max_health
	current_room_index = 0
	score = 0
	run_time = 0.0
	run_active = true
	run_won = false

	move_speed_mult = 1.0
	fire_interval_mult = 1.0
	damage_bonus = 0
	projectile_count = 1
	dash_cooldown_mult = 1.0
	dash_damage = false
	siphon_chance = 0.0
	active_upgrade_ids.clear()
	tactics_log.clear()
	health_updated.emit(current_health, max_health)


func record_tactic(sector: int, tactic_name: String, trigger_reason: String, mutations_desc: String) -> void:
	tactics_log.append({
		"sector": sector,
		"tactic": tactic_name,
		"reason": trigger_reason,
		"mutations": mutations_desc
	})


func finalize_run_stats(won: bool) -> void:
	var sector_reached := current_room_index + (1 if won else 0)
	if sector_reached > best_sector:
		best_sector = sector_reached
	if score > best_score:
		best_score = score
	if won and (best_time == 0.0 or run_time < best_time):
		best_time = run_time


func get_random_upgrade_choices(count: int = 3) -> Array[Dictionary]:
	var available: Array[Dictionary] = []
	for item in UPGRADE_CATALOG:
		# Some single-purchase perks like SPLIT_PULSE or STATIC_BLINK shouldn't repeat if already owned
		if item.id in ["SPLIT_PULSE", "STATIC_BLINK"] and item.id in active_upgrade_ids:
			continue
		available.append(item)

	available.shuffle()
	return available.slice(0, mini(count, available.size()))


func apply_upgrade(upgrade_id: String) -> void:
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
			move_speed_mult *= 1.25
			dash_cooldown_mult = maxf(0.35, dash_cooldown_mult * 0.75)
		"NANO_INFUSION":
			max_health += 2
			current_health = mini(max_health, current_health + 2)
			health_updated.emit(current_health, max_health)
		"STATIC_BLINK":
			dash_damage = true
		"ENERGY_SIPHON":
			siphon_chance = minf(0.5, siphon_chance + 0.25)

	upgrade_applied.emit(upgrade_id)


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


func advance_room() -> bool:
	current_room_index += 1
	if current_room_index >= TOTAL_ROOMS:
		run_active = false
		run_won = true
		run_completed.emit(true)
		return false
	room_advanced.emit(current_room_index, TOTAL_ROOMS)
	return true
