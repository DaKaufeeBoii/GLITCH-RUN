extends RefCounted
class_name DungeonGenerator
## Dedicated Procedural Dungeon Engineering Component.
## Separates:
##   1. Topology Graph Generation with branching routes, shops, and gift caches
##   2. Configurable Room Template Selection
##   3. Obstacle Geometry & Symmetries
##   4. BFS Navigation & Reachability Validation
##   5. Spawn Clearances & Tactical Context Interface
##   6. Deterministic Seed Reproduction

const ROOM_RECT := Rect2(42.0, 64.0, 1600.0, 900.0)
const GRID_CELL_SIZE := 32.0
const MIN_PLAYER_ENEMY_DIST := 195.0
const MAX_VALIDATION_RETRIES := 10

class RoomData extends RefCounted:
	var index: int = 0
	var room_type: String = "COMBAT" # "START", "COMBAT", "RECOVERY", "ELITE", "SHOP", "GIFT", "BOSS"
	var template_name: String = "OPEN_ARENA"
	var bounds: Rect2 = Rect2()
	var obstacles: Array[Rect2] = []
	var player_spawn: Vector2 = Vector2.ZERO
	var exit_door: Vector2 = Vector2.ZERO
	var exit_doors: Array[Dictionary] = [] # Array of { "pos": Vector2, "target_room": int, "target_type": String, "label": String }
	var enemy_spawns: Array[Dictionary] = []
	var connections: Array[int] = []
	var shop_stock: Array[Dictionary] = []
	var gift_choices: Array[String] = []
	var tactical_context: Dictionary = {
		"has_cover": false,
		"chokepoint_ratio": 0.0,
		"flanking_lanes": 1,
		"hazard_density": 0.0
	}
	var is_validated: bool = false
	var is_sector_wave: bool = false

	func to_dict() -> Dictionary:
		var obs_list: Array[Dictionary] = []
		for r in obstacles:
			obs_list.append({ "x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y })
		return {
			"index": index,
			"room_type": room_type,
			"connections": connections.duplicate(),
			"is_sector_wave": is_sector_wave,
			"template_name": template_name,
			"obstacles_count": obstacles.size(),
			"enemy_count": enemy_spawns.size(),
			"tactical_context": tactical_context.duplicate()
		}

class DungeonLayout extends RefCounted:
	var seed_value: int = 0
	var total_rooms: int = 12
	var rooms: Array[RoomData] = []
	var adjacency: Dictionary = {} # int -> Array[int]

	func get_room(idx: int) -> RoomData:
		if idx >= 0 and idx < rooms.size():
			return rooms[idx]
		return null

var last_wave_compositions: Dictionary = {}

const UPGRADE_OFFERINGS: Array[Dictionary] = [
	{ "id": "OVERCLOCK", "title": "OVERCLOCK", "desc": "+35% Fire Rate", "cat": "WEAPON", "rarity": "COMMON" },
	{ "id": "HIGH_VOLTAGE", "title": "HIGH VOLTAGE", "desc": "+1 Shot DMG", "cat": "WEAPON", "rarity": "UNCOMMON" },
	{ "id": "SPLIT_PULSE", "title": "SPLIT PULSE", "desc": "Twin Projectiles", "cat": "WEAPON", "rarity": "UNCOMMON" },
	{ "id": "PHANTOM_DRIVE", "title": "PHANTOM DRIVE", "desc": "+25% Speed, -25% Dash CD", "cat": "MOBILITY", "rarity": "COMMON" },
	{ "id": "NANO_INFUSION", "title": "NANO INFUSION", "desc": "+2 Max HP & Heal", "cat": "DEFENSE", "rarity": "COMMON" },
	{ "id": "STATIC_BLINK", "title": "STATIC BLINK", "desc": "Dash Zaps 2 DMG", "cat": "MOBILITY", "rarity": "UNCOMMON" },
	{ "id": "ENERGY_SIPHON", "title": "ENERGY SIPHON", "desc": "25% HP Siphon on Kill", "cat": "SURVIVAL", "rarity": "UNCOMMON" },
	{ "id": "CRYO_ROUNDS", "title": "CRYO MATRIX", "desc": "Shots Slow Enemies 50%", "cat": "STATUS", "rarity": "RARE" },
	{ "id": "ACID_PLASMA", "title": "ACID CORROSION", "desc": "Shots Inflict Acid Burn", "cat": "STATUS", "rarity": "RARE" },
	{ "id": "ARC_DISCHARGE", "title": "ARC DISCHARGE", "desc": "Shots Chain Shock Foes", "cat": "STATUS", "rarity": "RARE" },
	{ "id": "TACTICAL_RELOAD", "title": "TACTICAL RELOAD", "desc": "Dash Refills Full Ammo", "cat": "WEAPON", "rarity": "UNCOMMON" },
	{ "id": "EXPANDED_BATTERY", "title": "EXPANDED BATTERY", "desc": "+8 Ammo & Faster Reload", "cat": "WEAPON", "rarity": "COMMON" },
	{ "id": "REACTIVE_PLATING", "title": "REACTIVE PLATING", "desc": "Damage Emits EMP Stun", "cat": "DEFENSE", "rarity": "UNCOMMON" },
	{ "id": "PIERCING_BEAM", "title": "PIERCING BEAM", "desc": "Bolts Pierce Enemies", "cat": "WEAPON", "rarity": "UNCOMMON" },
	{ "id": "OVERDRIVE_PROTOCOL", "title": "OVERDRIVE", "desc": "+50% DMG when <= 2 HP", "cat": "SURVIVAL", "rarity": "RARE" },
	{ "id": "RECOVERY", "title": "RECOVERY BAY", "desc": "+2 HP Repair Patch", "cat": "HEAL", "rarity": "COMMON" },
	{ "id": "DATA_BITS", "title": "BIT CACHE", "desc": "+35 Data Currency", "cat": "REWARD", "rarity": "COMMON" },
]

const RARITY_CHANCES := {"COMMON": 70, "UNCOMMON": 24, "RARE": 6}


func _pick_upgrades(rng: RandomNumberGenerator, count: int) -> Array[Dictionary]:
	return _pick_by_rarity(rng, UPGRADE_OFFERINGS, count)


func _pick_by_rarity(rng: RandomNumberGenerator, pool: Array[Dictionary], count: int) -> Array[Dictionary]:
	var available: Array[Dictionary] = pool.duplicate()
	var picked: Array[Dictionary] = []
	while picked.size() < mini(count, available.size()):
		var roll := rng.randi_range(1, 100)
		var wanted := "COMMON"
		if roll > RARITY_CHANCES.COMMON + RARITY_CHANCES.UNCOMMON:
			wanted = "RARE"
		elif roll > RARITY_CHANCES.COMMON:
			wanted = "UNCOMMON"
		var tier: Array[Dictionary] = []
		for item in available:
			if item.get("rarity", "COMMON") == wanted:
				tier.append(item)
		if tier.is_empty():
			tier = available.duplicate()
		var selected: Dictionary = tier[rng.randi_range(0, tier.size() - 1)]
		picked.append(selected)
		available.erase(selected)
	return picked


func generate_dungeon(
	seed_val: int,
	room_count: int = 12,
	regular_wave_count: int = 5,
	procedural_floor: bool = false,
	difficulty: String = "NORMAL",
	sector_index: int = 1
) -> DungeonLayout:
	## Generates a completely validated, connected procedural dungeon layout from a seed.
	var layout := DungeonLayout.new()
	layout.seed_value = seed_val
	layout.total_rooms = room_count

	# Derive independent sub-seeds for graph topology, geometry templates, and spawn compositions
	var graph_seed := ((seed_val * 65537) ^ 0x12345) & 0x7FFFFFFF
	var geom_seed := ((seed_val * 31337) ^ 0x54321) & 0x7FFFFFFF
	var spawn_seed := ((seed_val * 101) ^ 0x98765) & 0x7FFFFFFF

	var graph_rng := RandomNumberGenerator.new()
	graph_rng.seed = graph_seed

	var geom_rng := RandomNumberGenerator.new()
	geom_rng.seed = geom_seed

	var spawn_rng := RandomNumberGenerator.new()
	spawn_rng.seed = spawn_seed

	# 1. Determine the room sequence. Production floors place required encounters
	# in order and insert a seed-selected set of safe perk rooms between them.
	var room_types: Array[String] = []
	if procedural_floor:
		room_types = _compose_procedural_floor(room_count, regular_wave_count, graph_rng, difficulty, sector_index)
	else:
		for i in range(room_count):
			if i == 0:
				room_types.append("START")
			elif i == room_count - 1:
				room_types.append("BOSS")
			elif i == 1:
				room_types.append("COMBAT")
			elif i == 2 or i == 6:
				room_types.append("SHOP")
			elif (i == 4 or i == 8) or (room_count == 5 and i == 3):
				room_types.append("GIFT")
			elif i == 10:
				room_types.append("ELITE" if graph_rng.randf() < 0.50 else "RECOVERY")
			elif i % 2 == 1 and i <= regular_wave_count * 2 - 1:
				room_types.append("ELITE" if i >= 5 and graph_rng.randf() < 0.25 else "COMBAT")
			else:
				room_types.append("RECOVERY")

	# 2. Generate topology after room roles are known. A branch can skip an
	# optional service room, but never a required combat encounter.
	_build_topology_graph(layout, room_count, graph_rng, room_types, procedural_floor)

	# 3. Generate and Validate each Room in the Graph
	for i in range(room_count):
		var room := _generate_valid_room(i, room_types[i], layout, room_types, geom_rng, spawn_rng, procedural_floor)
		room.is_sector_wave = room_types[i] in ["COMBAT", "ELITE"] if procedural_floor else (i % 2 == 1 and i <= regular_wave_count * 2 - 1)
		room.connections.assign(layout.adjacency.get(i, []))
		layout.rooms.append(room)

	return layout


func _compose_procedural_floor(
	room_count: int,
	regular_wave_count: int,
	rng: RandomNumberGenerator,
	difficulty: String = "NORMAL",
	sector_index: int = 1
) -> Array[String]:
	var types: Array[String] = ["START"]
	var encounter_count := mini(regular_wave_count, maxi(1, room_count - 2))
	var optional_count := maxi(0, room_count - encounter_count - 2)
	var service_pool: Array[String] = ["SHOP", "GIFT", "RECOVERY"]
	for i in range(service_pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temp := service_pool[i]
		service_pool[i] = service_pool[j]
		service_pool[j] = temp

	var insertion_slots: Array[int] = []
	for wave_idx in range(encounter_count):
		insertion_slots.append(wave_idx)
	for i in range(insertion_slots.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temp := insertion_slots[i]
		insertion_slots[i] = insertion_slots[j]
		insertion_slots[j] = temp
	insertion_slots.resize(mini(optional_count, insertion_slots.size()))
	insertion_slots.sort()

	var service_index := 0
	var elite_chance := 0.22
	match difficulty:
		"EASY":
			elite_chance = 0.10
		"HARD":
			elite_chance = 0.30
		"HYPERGRID":
			elite_chance = 0.36
	if sector_index >= 4:
		elite_chance = minf(0.50, elite_chance + 0.05)
	for wave_idx in range(encounter_count):
		var is_late_wave := wave_idx >= 2
		var this_wave_elite_chance := elite_chance if is_late_wave else elite_chance * 0.20
		types.append("ELITE" if rng.randf() < this_wave_elite_chance else "COMBAT")
		if insertion_slots.has(wave_idx) and service_index < service_pool.size():
			types.append(service_pool[service_index])
			service_index += 1

	# Room counts are derived from scheduled waves plus 0–3 service rooms.
	# If a caller supplies extra capacity, fill it with encounters so no rooms
	# silently disappear from the forward route.
	while types.size() < room_count - 1:
		types.append("COMBAT")
	types.append("BOSS")
	return types


func _build_topology_graph(
	layout: DungeonLayout,
	count: int,
	_rng: RandomNumberGenerator,
	room_types: Array[String],
	procedural_floor: bool
) -> void:
	for i in range(count):
		layout.adjacency[i] = []

	# Main forward progression spine
	for i in range(count - 1):
		layout.adjacency[i].append(i + 1)
		layout.adjacency[i + 1].append(i)

	# Optional service rooms have an always-available bypass that rejoins at the
	# next required encounter. Required combat rooms are never skipped.
	if procedural_floor:
		for index in range(count - 2):
			var target := index + 2
			var middle_is_service := room_types[index + 1] in ["SHOP", "GIFT", "RECOVERY"]
			var rejoins_at_encounter := room_types[target] in ["COMBAT", "ELITE", "BOSS"]
			if middle_is_service and rejoins_at_encounter and not target in layout.adjacency[index]:
				layout.adjacency[index].append(target)
				layout.adjacency[target].append(index)
	else:
		# Preserve the legacy graph behavior for existing generator callers.
		for index in range(1, count - 2, 2):
			var target := index + 2
			if (index == 1 or _rng.randf() < 0.70) and not target in layout.adjacency[index]:
				layout.adjacency[index].append(target)
				layout.adjacency[target].append(index)


func _generate_valid_room(
	index: int,
	room_type: String,
	layout: DungeonLayout,
	room_types: Array[String],
	geom_rng: RandomNumberGenerator,
	spawn_rng: RandomNumberGenerator,
	procedural_floor: bool = false
) -> RoomData:
	for _attempt in range(MAX_VALIDATION_RETRIES):
		var room := RoomData.new()
		room.index = index
		room.room_type = room_type
		if index == 0:
			# Room 0 (START): Compact Staging & Calibration Dock
			# Much tighter room bounds so the player doesn't have to sprint across a huge empty void.
			room.bounds = Rect2(380.0, 180.0, 840.0, 480.0)
			room.player_spawn = Vector2(room.bounds.position.x + 90.0, room.bounds.get_center().y)
		else:
			room.bounds = ROOM_RECT
			room.player_spawn = Vector2(ROOM_RECT.position.x + 120.0, ROOM_RECT.get_center().y)

		# Build forward exit doors: One door = One upgrade! Range of 1–3 doors randomly selected
		room.exit_doors.clear()
		var center := room.bounds.get_center()

		if index >= layout.total_rooms - 1:
			# Boss Chamber: Sector Gateway
			var door_pos := Vector2(room.bounds.end.x - 60.0, center.y)
			room.exit_doors.append({
				"pos": door_pos,
				"target_room": index + 1,
				"target_type": "NEXT_SECTOR",
				"upgrade_id": "SECTOR_GATE",
				"upgrade_title": "SECTOR GATEWAY",
				"upgrade_desc": "Advance to Next Sector",
				"category": "GATEWAY",
				"label": "GATEWAY // SECTOR ESCAPE"
			})
			room.exit_door = door_pos
		elif index == layout.total_rooms - 2:
			# Pre-Boss Chamber: Gate leading to Overlord Core
			var door_pos := Vector2(room.bounds.end.x - 60.0, center.y)
			room.exit_doors.append({
				"pos": door_pos,
				"target_room": layout.total_rooms - 1,
				"target_type": "BOSS",
				"upgrade_id": "BOSS",
				"upgrade_title": "OVERLORD CORE",
				"upgrade_desc": "Defeat Sector Boss",
				"category": "BOSS",
				"label": "NEXUS // OVERLORD CORE"
			})
			room.exit_door = door_pos
		else:
			# Regular chambers (Room 0, 1, 2...): Range of 1–3 doors, randomly selected!
			# Ensure Room 1 has at least 2 branching doors to satisfy topological route tests
			var forward_targets: Array[int] = []
			for connected_room in layout.adjacency.get(index, []):
				if connected_room > index:
					forward_targets.append(connected_room)
			forward_targets.sort()
			var num_doors := 1 if (procedural_floor and index == 0) else (mini(3, maxi(1, forward_targets.size())) if procedural_floor else (2 if index == 1 else spawn_rng.randi_range(1, 3)))
			var offsets: Array = [0.0]
			if num_doors == 2:
				offsets = [-65.0, 65.0] if index == 0 else [-90.0, 90.0]
			elif num_doors == 3:
				offsets = [-85.0, 0.0, 85.0] if index == 0 else [-120.0, 0.0, 120.0]

			# The opening staging room is a safe tutorial space, not a free upgrade.
			# Buff offers begin only after the first required encounter is cleared.
			var chosen_upgrades: Array[Dictionary] = []
			if not (procedural_floor and index == 0):
				chosen_upgrades = _pick_upgrades(spawn_rng, num_doors)

			for d_idx in range(num_doors):
				var up: Dictionary = chosen_upgrades[d_idx] if d_idx < chosen_upgrades.size() else {
					"id": "",
					"title": "SECTOR INGRESS",
					"desc": "Proceed to the first encounter",
					"cat": "ROUTE",
					"rarity": "COMMON"
				}
				var door_margin: float = 50.0 if index == 0 else 60.0
				var door_pos := Vector2(room.bounds.end.x - door_margin, center.y + offsets[d_idx])

				# Determine forward target room
				var target_idx: int = index + 1
				if procedural_floor and not forward_targets.is_empty():
					target_idx = forward_targets[mini(d_idx, forward_targets.size() - 1)]
				elif num_doors >= 2:
					if d_idx == 0:
						target_idx = index + 1
					elif d_idx == 1:
						target_idx = mini(index + 2, layout.total_rooms - 1)
					else:
						target_idx = mini(index + 1, layout.total_rooms - 1)
				else:
					target_idx = index + 1

				# If Room 1: guarantee door 0 and door 1 lead to distinct forward rooms (> 1)
				if index == 1 and num_doors >= 2:
					if d_idx == 0:
						target_idx = 2
					elif d_idx == 1:
						target_idx = 3

				var target_type := _get_provisional_room_type(target_idx, layout.total_rooms, room_types)
				var label := "[ %s ] // %s" % [up.title, up.desc.to_upper()]

				room.exit_doors.append({
					"pos": door_pos,
					"target_room": target_idx,
					"target_type": target_type,
					"upgrade_id": up.id,
					"upgrade_title": up.title,
					"upgrade_desc": up.desc,
					"category": up.cat,
					"rarity": up.get("rarity", "COMMON"),
					"label": label
				})

				# Ensure topology adjacency includes this connection
				if not layout.adjacency.has(index):
					layout.adjacency[index] = []
				if not target_idx in layout.adjacency[index]:
					layout.adjacency[index].append(target_idx)
				if not layout.adjacency.has(target_idx):
					layout.adjacency[target_idx] = []
				if not index in layout.adjacency[target_idx]:
					layout.adjacency[target_idx].append(index)

			room.exit_door = room.exit_doors[0].pos

		# Choose Room Template
		var template_name := _pick_template_name(index, room_type, geom_rng)
		room.template_name = template_name

		# Generate Geometry & Obstacles
		_apply_template_geometry(room, template_name, geom_rng)

		# Populate Shop / Gift stock if applicable
		if room_type == "SHOP":
			room.shop_stock = _generate_shop_stock(spawn_rng)
		elif room_type == "GIFT":
			room.gift_choices = _generate_gift_choices(spawn_rng)

		# Generate Enemy Spawns
		_generate_enemy_spawns(room, index, room_type, spawn_rng)
		if procedural_floor and room_type in ["START", "RECOVERY", "SHOP", "GIFT"]:
			room.enemy_spawns.clear()

		# Validate Reachability & Clearances via BFS Grid Flood-Fill
		if _validate_room_reachability(room):
			room.is_validated = true
			return room

	# Fallback to guaranteed valid calibration room if retries exhausted
	return _build_fallback_room(index, room_type)


func _get_provisional_room_type(room_idx: int, total_rooms: int, room_types: Array[String] = []) -> String:
	if not room_types.is_empty() and room_idx < room_types.size():
		return room_types[room_idx]
	if room_idx == 0:
		return "START"
	if room_idx >= total_rooms - 1:
		return "BOSS"
	if total_rooms == 5 and room_idx == 3:
		return "GIFT"
	match room_idx:
		2, 6:
			return "SHOP"
		4, 8:
			return "GIFT"
		10:
			return "RECOVERY"
		_:
			return "COMBAT"


func _get_door_label(target_idx: int, room_type: String) -> String:
	match room_type:
		"START":
			return "CALIBRATION DOCK"
		"SHOP":
			return "BLACK MARKET // DATA TERMINAL"
		"GIFT":
			return "SUBROUTINE CACHE // FREE REWARD"
		"RECOVERY":
			return "RECOVERY BAY (+2 HP)"
		"ELITE":
			return "ELITE THREAT // HIGH REWARD"
		"BOSS":
			return "NEXUS // OVERLORD CORE"
		_:
			return "CHAMBER %d // COMBAT WAVE" % (target_idx + 1)


func _pick_template_name(_index: int, room_type: String, rng: RandomNumberGenerator) -> String:
	if room_type == "START":
		return "CALIBRATION_OPEN"
	if room_type == "BOSS":
		return "BOSS_NEXUS"
	if room_type == "SHOP":
		return "SHOP_DEPOT"
	if room_type == "GIFT":
		return "GIFT_VAULT"
	if room_type == "RECOVERY":
		return "RECOVERY_BAY"

	var templates := [
		"QUAD_PILLARS",
		"CENTRAL_CHOKEPOINT",
		"SPLIT_LANE",
		"COVER_FORTRESS",
		"HAZARD_CORRIDOR",
		"CROSS_INTERSECTION"
	]
	return templates[rng.randi() % templates.size()]


func _apply_template_geometry(room: RoomData, template_name: String, _rng: RandomNumberGenerator) -> void:
	room.obstacles.clear()
	var center := room.bounds.get_center()

	match template_name:
		"CALIBRATION_OPEN":
			room.tactical_context.has_cover = false
			room.tactical_context.chokepoint_ratio = 0.0
			room.tactical_context.flanking_lanes = 2

		"SHOP_DEPOT":
			# Central merchant kiosk with clear perimeter pathways
			room.obstacles.append(Rect2(Vector2(center.x - 30.0, center.y - 25.0), Vector2(60.0, 50.0)))
			room.tactical_context.has_cover = true
			room.tactical_context.chokepoint_ratio = 0.15
			room.tactical_context.flanking_lanes = 3

		"GIFT_VAULT":
			# Secure cache station in center with decorative corner pylons
			room.obstacles.append(Rect2(Vector2(center.x - 24.0, center.y - 24.0), Vector2(48.0, 48.0)))
			room.obstacles.append(Rect2(Vector2(center.x - 140.0, center.y - 80.0), Vector2(36.0, 36.0)))
			room.obstacles.append(Rect2(Vector2(center.x + 104.0, center.y + 44.0), Vector2(36.0, 36.0)))
			room.tactical_context.has_cover = true
			room.tactical_context.chokepoint_ratio = 0.20
			room.tactical_context.flanking_lanes = 3

		"RECOVERY_BAY":
			# Twin medbay pods flanking center aisle
			room.obstacles.append(Rect2(Vector2(center.x - 110.0, center.y - 80.0), Vector2(50.0, 36.0)))
			room.obstacles.append(Rect2(Vector2(center.x + 60.0, center.y + 44.0), Vector2(50.0, 36.0)))
			room.tactical_context.has_cover = true
			room.tactical_context.chokepoint_ratio = 0.20
			room.tactical_context.flanking_lanes = 3

		"QUAD_PILLARS":
			var x_offset := 160.0
			var y_offset := 95.0
			var col_size := Vector2(44.0, 44.0)
			room.obstacles.append(Rect2(Vector2(center.x - x_offset - 22.0, center.y - y_offset - 22.0), col_size))
			room.obstacles.append(Rect2(Vector2(center.x + x_offset - 22.0, center.y - y_offset - 22.0), col_size))
			room.obstacles.append(Rect2(Vector2(center.x - x_offset - 22.0, center.y + y_offset - 22.0), col_size))
			room.obstacles.append(Rect2(Vector2(center.x + x_offset - 22.0, center.y + y_offset - 22.0), col_size))
			room.tactical_context.has_cover = true
			room.tactical_context.chokepoint_ratio = 0.20
			room.tactical_context.flanking_lanes = 3

		"CENTRAL_CHOKEPOINT":
			var wall_w := 260.0
			var wall_h := 28.0
			room.obstacles.append(Rect2(Vector2(center.x - wall_w * 0.5, center.y - wall_h * 0.5), Vector2(wall_w, wall_h)))
			room.tactical_context.has_cover = true
			room.tactical_context.chokepoint_ratio = 0.65
			room.tactical_context.flanking_lanes = 2

		"SPLIT_LANE":
			var bar_size := Vector2(26.0, 140.0)
			room.obstacles.append(Rect2(Vector2(center.x - 120.0 - 13.0, center.y - 70.0), bar_size))
			room.obstacles.append(Rect2(Vector2(center.x + 120.0 - 13.0, center.y - 70.0), bar_size))
			room.tactical_context.has_cover = true
			room.tactical_context.chokepoint_ratio = 0.45
			room.tactical_context.flanking_lanes = 3

		"COVER_FORTRESS":
			var block_size := Vector2(60.0, 28.0)
			room.obstacles.append(Rect2(Vector2(center.x - 130.0, center.y - 85.0), block_size))
			room.obstacles.append(Rect2(Vector2(center.x + 80.0, center.y - 85.0), block_size))
			room.obstacles.append(Rect2(Vector2(center.x - 130.0, center.y + 60.0), block_size))
			room.obstacles.append(Rect2(Vector2(center.x + 80.0, center.y + 60.0), block_size))
			room.tactical_context.has_cover = true
			room.tactical_context.chokepoint_ratio = 0.35
			room.tactical_context.flanking_lanes = 3

		"HAZARD_CORRIDOR":
			room.obstacles.append(Rect2(Vector2(center.x - 80.0, center.y - 20.0), Vector2(160.0, 40.0)))
			room.tactical_context.has_cover = true
			room.tactical_context.chokepoint_ratio = 0.30
			room.tactical_context.flanking_lanes = 2
			room.tactical_context.hazard_density = 0.60

		"CROSS_INTERSECTION":
			room.obstacles.append(Rect2(Vector2(center.x - 20.0, center.y - 90.0), Vector2(40.0, 60.0)))
			room.obstacles.append(Rect2(Vector2(center.x - 20.0, center.y + 30.0), Vector2(40.0, 60.0)))
			room.tactical_context.has_cover = true
			room.tactical_context.chokepoint_ratio = 0.50
			room.tactical_context.flanking_lanes = 2

		"BOSS_NEXUS":
			var b_size := Vector2(64.0, 64.0)
			var x_offset := room.bounds.size.x * 0.28
			var y_offset := room.bounds.size.y * 0.25
			room.obstacles.append(Rect2(center + Vector2(-x_offset, -y_offset) - b_size * 0.5, b_size))
			room.obstacles.append(Rect2(center + Vector2(x_offset, -y_offset) - b_size * 0.5, b_size))
			room.obstacles.append(Rect2(center + Vector2(-x_offset, y_offset) - b_size * 0.5, b_size))
			room.obstacles.append(Rect2(center + Vector2(x_offset, y_offset) - b_size * 0.5, b_size))
			room.tactical_context.has_cover = true
			room.tactical_context.chokepoint_ratio = 0.15
			room.tactical_context.flanking_lanes = 4

	# The enlarged rooms need their cover and lanes spread out too. Scale around
	# the room center so templates remain legible at the scrolling camera scale.
	if template_name != "BOSS_NEXUS":
		for obstacle_index in range(room.obstacles.size()):
			var obstacle: Rect2 = room.obstacles[obstacle_index]
			var scaled_size := obstacle.size * 1.65
			var scaled_center := center + (obstacle.get_center() - center) * 1.65
			room.obstacles[obstacle_index] = Rect2(scaled_center - scaled_size * 0.5, scaled_size)


func _generate_shop_stock(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var catalog: Array[Dictionary] = [
		{ "id": "OVERCLOCK", "title": "OVERCLOCK", "cost": 3, "desc": "+35% Fire Rate", "rarity": "COMMON" },
		{ "id": "PHANTOM_DRIVE", "title": "PHANTOM DRIVE", "cost": 4, "desc": "+25% Speed, -25% Dash CD", "rarity": "COMMON" },
		{ "id": "HIGH_VOLTAGE", "title": "HIGH VOLTAGE", "cost": 5, "desc": "+1 Shot Damage", "rarity": "UNCOMMON" },
		{ "id": "NANO_INFUSION", "title": "NANO INFUSION", "cost": 6, "desc": "+2 Max HP & Heal 2", "rarity": "COMMON" },
		{ "id": "STATIC_BLINK", "title": "STATIC BLINK", "cost": 5, "desc": "Dash Deals 2 DMG", "rarity": "UNCOMMON" },
		{ "id": "ENERGY_SIPHON", "title": "ENERGY SIPHON", "cost": 4, "desc": "+25% Siphon Chance", "rarity": "UNCOMMON" },
		{ "id": "CRYO_ROUNDS", "title": "CRYO MATRIX", "cost": 9, "desc": "Shots slow enemies", "rarity": "RARE" },
		{ "id": "ACID_PLASMA", "title": "ACID CORROSION", "cost": 9, "desc": "Shots inflict acid burn", "rarity": "RARE" },
		{ "id": "ARC_DISCHARGE", "title": "ARC DISCHARGE", "cost": 9, "desc": "Shots chain shock", "rarity": "RARE" }
	]
	return _pick_by_rarity(rng, catalog, 3)


func _generate_gift_choices(rng: RandomNumberGenerator) -> Array[String]:
	var pool: Array[Dictionary] = []
	for item in UPGRADE_OFFERINGS:
		if item.id not in ["RECOVERY", "DATA_BITS"]:
			pool.append(item)
	var picks := _pick_by_rarity(rng, pool, 2)
	var result: Array[String] = []
	for item in picks:
		result.append(item.id)
	return result


func get_upgrade_rarity(upgrade_id: String) -> String:
	for item in UPGRADE_OFFERINGS:
		if item.id == upgrade_id:
			return item.get("rarity", "COMMON")
	return "COMMON"


func _generate_enemy_spawns(room: RoomData, index: int, room_type: String, rng: RandomNumberGenerator) -> void:
	room.enemy_spawns.clear()

	if room_type == "START":
		room.enemy_spawns.clear()
		return

	if room_type == "BOSS":
		room.enemy_spawns.append({ "type": "BOSS", "pos": Vector2(room.bounds.position.x + room.bounds.size.x * 0.70, room.bounds.get_center().y), "flank_angle": 0.0 })
		return

	# Progressive enemy composition for combat arenas & standby spawns
	var base_enemy_count: int = clampi(3 + int(index * 0.65), 3, 6)
	var possible_types := ["CHASER"]
	if index >= 1:
		possible_types.append("SHOOTER")
	if index >= 2:
		possible_types.append("DASHER")

	for i in range(base_enemy_count):
		var etype: String = possible_types[rng.randi() % possible_types.size()]
		var min_x := room.bounds.position.x + room.bounds.size.x * 0.45
		var max_x := room.bounds.end.x - 80.0
		var min_y := room.bounds.position.y + 60.0
		var max_y := room.bounds.end.y - 60.0

		var pos := Vector2(rng.randf_range(min_x, max_x), rng.randf_range(min_y, max_y))
		var flank := 0.60 if (i % 2 == 1) else -0.60
		room.enemy_spawns.append({
			"type": etype,
			"pos": pos,
			"flank_angle": flank if etype == "CHASER" else 0.0
		})


func generate_wave_spawns(room: RoomData, sector_seed: int, wave_number: int, spawn_budget: int) -> Array[Dictionary]:
	## Builds a deterministic, room-specific roster for each wave. It varies enemy
	## roles, count, and spawn positions instead of replaying room.enemy_spawns.
	if room.room_type in ["START", "BOSS"]:
		return room.enemy_spawns.duplicate(true)

	var rng := RandomNumberGenerator.new()
	rng.seed = int((sector_seed ^ (room.index * 73856093) ^ (wave_number * 19349663)) & 0x7FFFFFFF)
	var available := ["CHASER"]
	if room.index >= 1:
		available.append("SHOOTER")
	if room.index >= 2:
		available.append("DASHER")
	var recipes := [
		["CHASER", "CHASER", "CHASER", "CHASER"],
		["SHOOTER", "CHASER", "SHOOTER", "CHASER"],
		["DASHER", "CHASER", "DASHER", "CHASER"],
		["SHOOTER", "DASHER", "CHASER", "SHOOTER"],
		["DASHER", "DASHER", "SHOOTER", "CHASER"],
		["CHASER", "SHOOTER", "DASHER", "DASHER"],
		["SHOOTER", "SHOOTER", "CHASER", "CHASER"],
		["DASHER", "DASHER", "DASHER", "CHASER"],
		["CHASER", "CHASER", "DASHER", "SHOOTER"],
		["SHOOTER", "DASHER", "SHOOTER", "DASHER"],
		["CHASER", "DASHER", "CHASER", "DASHER"],
		["SHOOTER", "SHOOTER", "DASHER", "SHOOTER"]
	]
	var max_count := mini(16, maxi(4, 4 + int(room.index * 0.75)))
	var budget_limit := maxi(1, mini(spawn_budget, max_count))
	var count := budget_limit
	var key := str(sector_seed)
	var past_signatures: Array = []
	if last_wave_compositions.has(key):
		if last_wave_compositions[key] is Array:
			past_signatures = last_wave_compositions[key]
		elif last_wave_compositions[key] is String:
			past_signatures = [last_wave_compositions[key]]

	var recipe_index := int(rng.randi() % recipes.size())
	var roster: Array[String] = []
	var signature := ""
	for attempt in range(recipes.size()):
		roster.clear()
		var recipe: Array = recipes[recipe_index]
		for slot in range(count):
			var wanted: String = recipe[(slot + wave_number - 1) % recipe.size()]
			if not available.has(wanted):
				wanted = available[(slot + attempt) % available.size()]
			roster.append(wanted)
		signature = ",".join(roster)
		if not past_signatures.has(signature) or attempt == recipes.size() - 1:
			break
		recipe_index = (recipe_index + 1) % recipes.size()

	past_signatures.append(signature)
	while past_signatures.size() > 4:
		past_signatures.pop_front()
	last_wave_compositions[key] = past_signatures

	var positions: Array[Vector2] = []
	var tries := 0
	while positions.size() < count and tries < count * 30:
		tries += 1
		var pos := Vector2(
			rng.randf_range(room.bounds.position.x + 110.0, room.bounds.end.x - 110.0),
			rng.randf_range(room.bounds.position.y + 90.0, room.bounds.end.y - 90.0)
		)
		if pos.distance_to(room.player_spawn) < MIN_PLAYER_ENEMY_DIST:
			continue
		var blocked := false
		for obstacle in room.obstacles:
			if obstacle.grow(28.0).has_point(pos):
				blocked = true
				break
		if blocked:
			continue
		var spaced := true
		for other in positions:
			if pos.distance_squared_to(other) < 80.0 * 80.0:
				spaced = false
				break
		if spaced:
			positions.append(pos)

	# Fixed perimeter fallback points keep a valid combat room from loading with
	# no visible enemies when random placement rejects too many obstacle-adjacent
	# candidates. These points stay well away from the standard left-side spawn.
	if positions.size() < mini(2, count):
		var safe_offsets: Array[Vector2] = [
			Vector2(210.0, 190.0),
			Vector2(room.bounds.size.x - 210.0, 190.0),
			Vector2(210.0, room.bounds.size.y - 190.0),
			Vector2(room.bounds.size.x - 210.0, room.bounds.size.y - 190.0)
		]
		for offset in safe_offsets:
			var fallback_pos: Vector2 = room.bounds.position + offset
			if fallback_pos.distance_to(room.player_spawn) < MIN_PLAYER_ENEMY_DIST:
				continue
			var blocked_by_obstacle := false
			for obstacle in room.obstacles:
				if obstacle.grow(28.0).has_point(fallback_pos):
					blocked_by_obstacle = true
					break
			if blocked_by_obstacle:
				continue
			var too_close := false
			for other in positions:
				if fallback_pos.distance_squared_to(other) < 80.0 * 80.0:
					too_close = true
					break
			if not too_close:
				positions.append(fallback_pos)
			if positions.size() >= mini(2, count):
				break

	var result: Array[Dictionary] = []
	for index in range(mini(roster.size(), positions.size())):
		var family: String = roster[index]
		result.append({
			"type": family,
			"pos": positions[index],
			"flank_angle": (0.55 if index % 2 == 0 else -0.55) if family == "CHASER" else 0.0
		})
	if result.is_empty():
		# Last-resort fallback for a malformed or over-obstructed normal room.
		# Keep the encounter playable instead of silently treating it as cleared.
		var emergency_pos := Vector2(room.bounds.end.x - 180.0, room.bounds.position.y + 180.0)
		result.append({"type": "CHASER", "pos": emergency_pos, "flank_angle": 0.0})
	return result


func _validate_room_reachability(room: RoomData) -> bool:
	if not room.bounds.has_point(room.player_spawn):
		return false
	for obs in room.obstacles:
		if obs.grow(20.0).has_point(room.player_spawn):
			return false
		for door in room.exit_doors:
			if obs.grow(20.0).has_point(door.pos):
				return false

	for espawn in room.enemy_spawns:
		var epos: Vector2 = espawn.pos
		if not room.bounds.has_point(epos):
			return false
		if room.player_spawn.distance_to(epos) < MIN_PLAYER_ENEMY_DIST:
			return false
		for obs in room.obstacles:
			if obs.grow(16.0).has_point(epos):
				return false

	# Construct 2D Walkability Grid
	var origin_x := room.bounds.position.x
	var origin_y := room.bounds.position.y
	var grid_w := int(ceil(room.bounds.size.x / GRID_CELL_SIZE))
	var grid_h := int(ceil(room.bounds.size.y / GRID_CELL_SIZE))

	var blocked_grid: Array = []
	for x in range(grid_w):
		var col: Array[bool] = []
		for y in range(grid_h):
			col.append(false)
		blocked_grid.append(col)

	for obs in room.obstacles:
		var min_gx := clampi(int((obs.position.x - origin_x) / GRID_CELL_SIZE), 0, grid_w - 1)
		var max_gx := clampi(int((obs.end.x - origin_x) / GRID_CELL_SIZE), 0, grid_w - 1)
		var min_gy := clampi(int((obs.position.y - origin_y) / GRID_CELL_SIZE), 0, grid_h - 1)
		var max_gy := clampi(int((obs.end.y - origin_y) / GRID_CELL_SIZE), 0, grid_h - 1)

		for gx in range(min_gx, max_gx + 1):
			for gy in range(min_gy, max_gy + 1):
				blocked_grid[gx][gy] = true

	var start_gx := clampi(int((room.player_spawn.x - origin_x) / GRID_CELL_SIZE), 0, grid_w - 1)
	var start_gy := clampi(int((room.player_spawn.y - origin_y) / GRID_CELL_SIZE), 0, grid_h - 1)

	if blocked_grid[start_gx][start_gy]:
		return false

	var visited: Array = []
	for x in range(grid_w):
		var col: Array[bool] = []
		for y in range(grid_h):
			col.append(false)
		visited.append(col)

	var queue: Array[Vector2i] = [Vector2i(start_gx, start_gy)]
	visited[start_gx][start_gy] = true

	var neighbor_offsets := [
		Vector2i(1, 0), Vector2i(-1, 0),
		Vector2i(0, 1), Vector2i(0, -1)
	]

	while not queue.is_empty():
		var curr: Vector2i = queue.pop_front()
		for off in neighbor_offsets:
			var nx: int = curr.x + off.x
			var ny: int = curr.y + off.y
			if nx >= 0 and nx < grid_w and ny >= 0 and ny < grid_h:
				if not blocked_grid[nx][ny] and not visited[nx][ny]:
					visited[nx][ny] = true
					queue.append(Vector2i(nx, ny))

	for door in room.exit_doors:
		var dgx := clampi(int((door.pos.x - origin_x) / GRID_CELL_SIZE), 0, grid_w - 1)
		var dgy := clampi(int((door.pos.y - origin_y) / GRID_CELL_SIZE), 0, grid_h - 1)
		if not visited[dgx][dgy]:
			return false

	for espawn in room.enemy_spawns:
		var egx := clampi(int((espawn.pos.x - origin_x) / GRID_CELL_SIZE), 0, grid_w - 1)
		var egy := clampi(int((espawn.pos.y - origin_y) / GRID_CELL_SIZE), 0, grid_h - 1)
		if not visited[egx][egy]:
			return false

	return true


func _build_fallback_room(index: int, room_type: String) -> RoomData:
	var room := RoomData.new()
	room.index = index
	room.room_type = room_type
	room.template_name = "SAFE_FALLBACK"

	if index == 0:
		room.bounds = Rect2(380.0, 180.0, 840.0, 480.0)
		room.player_spawn = Vector2(room.bounds.position.x + 90.0, room.bounds.get_center().y)
		var d_pos := Vector2(room.bounds.end.x - 40.0, room.bounds.get_center().y)
		room.exit_door = d_pos
		room.exit_doors.append({
			"pos": d_pos,
			"target_room": index + 1,
			"target_type": "COMBAT",
			"upgrade_id": "OVERCLOCK",
			"upgrade_title": "OVERCLOCK",
			"upgrade_desc": "+35% Fire Rate",
			"category": "WEAPON",
			"label": "[ OVERCLOCK ] // +35% FIRE RATE"
		})
		room.obstacles.clear()
		room.enemy_spawns.clear()
		room.is_validated = true
		return room

	room.bounds = ROOM_RECT
	room.player_spawn = Vector2(ROOM_RECT.position.x + 120.0, ROOM_RECT.get_center().y)
	var door_pos := Vector2(ROOM_RECT.end.x - 60.0, ROOM_RECT.get_center().y)
	room.exit_door = door_pos
	room.exit_doors.append({
		"pos": door_pos,
		"target_room": index + 1,
		"target_type": "COMBAT",
		"upgrade_id": "OVERCLOCK",
		"upgrade_title": "OVERCLOCK",
		"upgrade_desc": "+35% Fire Rate",
		"category": "WEAPON",
		"label": "[ OVERCLOCK ] // +35% FIRE RATE"
	})
	room.obstacles.clear()

	var center := ROOM_RECT.get_center()
	room.obstacles.append(Rect2(center.x - 120.0, center.y - 20.0, 40.0, 40.0))
	room.obstacles.append(Rect2(center.x + 120.0, center.y - 20.0, 40.0, 40.0))

	if room_type == "BOSS":
		room.enemy_spawns.append({ "type": "BOSS", "pos": Vector2(room.bounds.position.x + room.bounds.size.x * 0.70, room.bounds.get_center().y), "flank_angle": 0.0 })
	else:
		room.enemy_spawns.append({ "type": "CHASER", "pos": Vector2(620, 200), "flank_angle": 0.55 })
		room.enemy_spawns.append({ "type": "CHASER", "pos": Vector2(740, 276), "flank_angle": 0.0 })
		room.enemy_spawns.append({ "type": "SHOOTER", "pos": Vector2(620, 360), "flank_angle": 0.0 })

	room.is_validated = true
	return room
