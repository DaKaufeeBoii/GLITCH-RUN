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

const ROOM_RECT := Rect2(42.0, 64.0, 876.0, 424.0)
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
	var total_rooms: int = 6
	var rooms: Array[RoomData] = []
	var adjacency: Dictionary = {} # int -> Array[int]

	func get_room(idx: int) -> RoomData:
		if idx >= 0 and idx < rooms.size():
			return rooms[idx]
		return null


func generate_dungeon(seed_val: int, room_count: int = 6) -> DungeonLayout:
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
		elif i == 2:
			# Branch node: Shop or Recovery
			room_types.append("SHOP" if graph_rng.randf() < 0.60 else "RECOVERY")
		elif i == 3:
			# Branch node: Gift or Combat
			room_types.append("GIFT" if graph_rng.randf() < 0.55 else "COMBAT")
		elif i == 4:
			# Late node: Elite or Combat
			room_types.append("ELITE" if graph_rng.randf() < 0.50 else "COMBAT")
		else:
			room_types.append("COMBAT")

	# 3. Generate and Validate each Room in the Graph
	for i in range(room_count):
		var room := _generate_valid_room(i, room_types[i], layout, room_types, geom_rng, spawn_rng)
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

	# Interconnected branch shortcuts and loops
	if count >= 6:
		# Room 0 connects forward to Room 1 (Combat) and Room 2 (Shop/Recovery)
		if not 2 in layout.adjacency[0]:
			layout.adjacency[0].append(2)
			layout.adjacency[2].append(0)

		# Room 1 connects forward to Room 3 (Gift/Combat)
		if not 3 in layout.adjacency[1]:
			layout.adjacency[1].append(3)
			layout.adjacency[3].append(1)

		# Room 2 connects forward to Room 4 (Elite/Combat)
		if not 4 in layout.adjacency[2]:
			layout.adjacency[2].append(4)
			layout.adjacency[4].append(2)

		# Room 3 connects forward to Room 5 (Boss)
		if not (count - 1) in layout.adjacency[3]:
			layout.adjacency[3].append(count - 1)
			layout.adjacency[count - 1].append(3)

	elif count >= 5:
		if not 3 in layout.adjacency[1]:
			layout.adjacency[1].append(3)
			layout.adjacency[3].append(1)


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
		1:
			return "COMBAT"
		2:
			return "SHOP"
		3:
			return "GIFT"
		4:
			return "ELITE"
		_:
			return "COMBAT"


func _get_door_label(target_idx: int, room_type: String) -> String:
	if target_idx >= 5:
		return "SECTOR GATE // NEXUS CORE"
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
			var b_size := Vector2(36.0, 36.0)
			room.obstacles.append(Rect2(Vector2(180.0 - 18.0, 150.0 - 18.0), b_size))
			room.obstacles.append(Rect2(Vector2(780.0 - 18.0, 150.0 - 18.0), b_size))
			room.obstacles.append(Rect2(Vector2(180.0 - 18.0, 400.0 - 18.0), b_size))
			room.obstacles.append(Rect2(Vector2(780.0 - 18.0, 400.0 - 18.0), b_size))
			room.tactical_context.has_cover = true
			room.tactical_context.chokepoint_ratio = 0.15
			room.tactical_context.flanking_lanes = 4


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
		room.enemy_spawns.append({ "type": "BOSS", "pos": Vector2(680, 276), "flank_angle": 0.0 })
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
		room.enemy_spawns.append({ "type": "BOSS", "pos": Vector2(680, 276), "flank_angle": 0.0 })
	else:
		room.enemy_spawns.append({ "type": "CHASER", "pos": Vector2(620, 200), "flank_angle": 0.55 })
		room.enemy_spawns.append({ "type": "CHASER", "pos": Vector2(740, 276), "flank_angle": 0.0 })
		room.enemy_spawns.append({ "type": "SHOOTER", "pos": Vector2(620, 360), "flank_angle": 0.0 })

	room.is_validated = true
	return room
