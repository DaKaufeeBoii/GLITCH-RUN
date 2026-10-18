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


func generate_dungeon(seed_val: int, room_count: int = 12, regular_wave_count: int = 5) -> DungeonLayout:
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

	# 1. Generate Topology Graph with Route Branches and Loops
	_build_topology_graph(layout, room_count, graph_rng)

	# 2. Determine Room Types
	var room_types: Array[String] = []
	for i in range(room_count):
		if i == 0:
			room_types.append("START")
		elif i == room_count - 1:
			room_types.append("BOSS")
		elif i == 1:
			room_types.append("COMBAT")
		elif i == 2 or i == 6:
			room_types.append("SHOP")
		elif i == 4 or i == 8:
			room_types.append("GIFT")
		elif i == 10:
			room_types.append("ELITE" if graph_rng.randf() < 0.50 else "RECOVERY")
		elif i % 2 == 1 and i <= regular_wave_count * 2 - 1:
			room_types.append("ELITE" if i >= 5 and graph_rng.randf() < 0.25 else "COMBAT")
		else:
			room_types.append("RECOVERY")

	# 3. Generate and Validate each Room in the Graph
	for i in range(room_count):
		var room := _generate_valid_room(i, room_types[i], layout, room_types, geom_rng, spawn_rng)
		room.is_sector_wave = i % 2 == 1 and i <= regular_wave_count * 2 - 1
		room.connections.assign(layout.adjacency.get(i, []))
		layout.rooms.append(room)

	return layout


func _build_topology_graph(layout: DungeonLayout, count: int, _rng: RandomNumberGenerator) -> void:
	for i in range(count):
		layout.adjacency[i] = []

	# Main forward progression spine
	for i in range(count - 1):
		layout.adjacency[i].append(i + 1)
		layout.adjacency[i + 1].append(i)

	# Optional even-numbered rooms branch off the mandatory combat spine. Seeded
	# skip edges never bypass a scheduled wave room, and the first route choice is
	# guaranteed so every sector has at least one meaningful decision.
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
	spawn_rng: RandomNumberGenerator
) -> RoomData:
	for _attempt in range(MAX_VALIDATION_RETRIES):
		var room := RoomData.new()
		room.index = index
		room.room_type = room_type
		room.bounds = ROOM_RECT
		room.player_spawn = Vector2(ROOM_RECT.position.x + 120.0, ROOM_RECT.get_center().y)

		# Build forward exit doors based on graph topology
		room.exit_doors.clear()
		var forward_connections: Array[int] = []
		for target_idx in layout.adjacency.get(index, []):
			if target_idx > index:
				forward_connections.append(target_idx)

		var center := room.bounds.get_center()
		if forward_connections.size() <= 1:
			var target_idx: int = forward_connections[0] if not forward_connections.is_empty() else index + 1
			var door_pos := Vector2(room.bounds.end.x - 60.0, center.y)
			var target_type := _get_provisional_room_type(target_idx, layout.total_rooms, room_types)
			var label := _get_door_label(target_idx, target_type)
			room.exit_doors.append({ "pos": door_pos, "target_room": target_idx, "target_type": target_type, "label": label })
			room.exit_door = door_pos
		else:
			# Branching choices: Upper and Lower Exit Doors
			var offsets := [-90.0, 90.0]
			for c_idx in range(mini(2, forward_connections.size())):
				var target_idx: int = forward_connections[c_idx]
				var door_pos := Vector2(room.bounds.end.x - 60.0, center.y + offsets[c_idx])
				var target_type := _get_provisional_room_type(target_idx, layout.total_rooms, room_types)
				var label := _get_door_label(target_idx, target_type)
				room.exit_doors.append({ "pos": door_pos, "target_room": target_idx, "target_type": target_type, "label": label })
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
	var catalog := [
		{ "id": "OVERCLOCK", "title": "OVERCLOCK", "cost": 4, "desc": "+35% Fire Rate" },
		{ "id": "PHANTOM_DRIVE", "title": "PHANTOM DRIVE", "cost": 5, "desc": "+25% Speed, -25% Dash CD" },
		{ "id": "HIGH_VOLTAGE", "title": "HIGH VOLTAGE", "cost": 6, "desc": "+1 Shot Damage" },
		{ "id": "NANO_INFUSION", "title": "NANO INFUSION", "cost": 7, "desc": "+2 Max HP & Heal 2" },
		{ "id": "STATIC_BLINK", "title": "STATIC BLINK", "cost": 6, "desc": "Dash Deals 2 DMG" },
		{ "id": "ENERGY_SIPHON", "title": "ENERGY SIPHON", "cost": 5, "desc": "+25% Siphon Chance" }
	]
	# Deterministically shuffle with rng
	for i in range(catalog.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = catalog[i]
		catalog[i] = catalog[j]
		catalog[j] = tmp
	var chosen: Array[Dictionary] = []
	for i in range(mini(3, catalog.size())):
		chosen.append(catalog[i])
	return chosen


func _generate_gift_choices(rng: RandomNumberGenerator) -> Array[String]:
	var pool := ["PHANTOM_DRIVE", "NANO_INFUSION", "STATIC_BLINK", "OVERCLOCK", "HIGH_VOLTAGE"]
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	return [pool[0], pool[1]]


func _generate_enemy_spawns(room: RoomData, index: int, room_type: String, rng: RandomNumberGenerator) -> void:
	room.enemy_spawns.clear()

	if room_type == "START":
		room.enemy_spawns.append({ "type": "CHASER", "pos": Vector2(620, 200), "flank_angle": 0.50 })
		room.enemy_spawns.append({ "type": "CHASER", "pos": Vector2(740, 276), "flank_angle": 0.0 })
		room.enemy_spawns.append({ "type": "CHASER", "pos": Vector2(620, 360), "flank_angle": -0.50 })
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
	if room.room_type in ["START", "RECOVERY", "SHOP", "GIFT", "BOSS"]:
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
		["CHASER", "SHOOTER", "DASHER", "DASHER"]
	]
	var max_count := mini(8, maxi(3, 3 + int(room.index * 0.45)))
	var count_offset := posmod(wave_number - 1, 3) - 1
	var count := clampi(mini(spawn_budget, max_count) + count_offset, 2, mini(spawn_budget, max_count))
	var key := str(sector_seed)
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
		if signature != str(last_wave_compositions.get(key, "")):
			break
		recipe_index = (recipe_index + 1) % recipes.size()
	last_wave_compositions[key] = signature
	if last_wave_compositions.size() > 3:
		last_wave_compositions.erase(last_wave_compositions.keys()[0])

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
	
	var result: Array[Dictionary] = []
	for index in range(mini(roster.size(), positions.size())):
		var family: String = roster[index]
		result.append({
			"type": family,
			"pos": positions[index],
			"flank_angle": (0.55 if index % 2 == 0 else -0.55) if family == "CHASER" else 0.0
		})
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
	room.bounds = ROOM_RECT
	room.player_spawn = Vector2(ROOM_RECT.position.x + 120.0, ROOM_RECT.get_center().y)
	var door_pos := Vector2(ROOM_RECT.end.x - 60.0, ROOM_RECT.get_center().y)
	room.exit_door = door_pos
	room.exit_doors.append({ "pos": door_pos, "target_room": index + 1, "target_type": "COMBAT", "label": "FORWARD CORRIDOR" })
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
