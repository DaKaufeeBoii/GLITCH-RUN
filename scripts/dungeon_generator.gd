extends RefCounted
class_name DungeonGenerator
## Dedicated Procedural Dungeon Engineering Component.
## Separates:
##   1. Topology Graph Generation
##   2. Configurable Room Template Selection
##   3. Obstacle Geometry & Symmetries
##   4. BFS Navigation & Reachability Validation
##   5. Spawn Clearances & Tactical Context Interface
##   6. Deterministic Seed Reproduction

const ROOM_RECT := Rect2(42.0, 64.0, 876.0, 424.0)
const GRID_CELL_SIZE := 32.0
const MIN_PLAYER_ENEMY_DIST := 200.0
const MAX_VALIDATION_RETRIES := 10

class RoomData extends RefCounted:
	var index: int = 0
	var room_type: String = "COMBAT" # "START", "COMBAT", "RECOVERY", "ELITE", "BOSS"
	var template_name: String = "OPEN_ARENA"
	var bounds: Rect2 = Rect2()
	var obstacles: Array[Rect2] = []
	var player_spawn: Vector2 = Vector2.ZERO
	var exit_door: Vector2 = Vector2.ZERO
	var enemy_spawns: Array[Dictionary] = []
	var connections: Array[int] = []
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

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	# 1. Generate Topology Graph
	_build_topology_graph(layout, room_count, rng)

	# 2. Generate and Validate each Room in the Graph
	for i in range(room_count):
		var room_type := "COMBAT"
		if i == 0:
			room_type = "START"
		elif i == room_count - 1:
			room_type = "BOSS"
		elif i == 2 and rng.randf() < 0.35:
			room_type = "RECOVERY"
		elif i == 4 and rng.randf() < 0.40:
			room_type = "ELITE"

		var room := _generate_valid_room(i, room_type, rng)
		room.connections.assign(layout.adjacency.get(i, []))
		layout.rooms.append(room)

	return layout


func _build_topology_graph(layout: DungeonLayout, count: int, rng: RandomNumberGenerator) -> void:
	for i in range(count):
		layout.adjacency[i] = []

	# Linear progression spine (0 -> 1 -> 2 -> ... -> Boss)
	for i in range(count - 1):
		layout.adjacency[i].append(i + 1)
		layout.adjacency[i + 1].append(i)

	# Optional branch or bypass edge between combat rooms if count >= 5
	if count >= 5 and rng.randf() < 0.50:
		# Add a bypass link (e.g. 1 connects to 3)
		if not 3 in layout.adjacency[1]:
			layout.adjacency[1].append(3)
			layout.adjacency[3].append(1)


func _generate_valid_room(index: int, room_type: String, rng: RandomNumberGenerator) -> RoomData:
	for attempt in range(MAX_VALIDATION_RETRIES):
		var room := RoomData.new()
		room.index = index
		room.room_type = room_type
		room.bounds = ROOM_RECT
		room.player_spawn = Vector2(ROOM_RECT.position.x + 120.0, ROOM_RECT.get_center().y)
		room.exit_door = Vector2(ROOM_RECT.end.x - 60.0, ROOM_RECT.get_center().y)

		# Choose Room Template
		var template_name := _pick_template_name(index, room_type, rng)
		room.template_name = template_name

		# Generate Geometry & Obstacles
		_apply_template_geometry(room, template_name, rng)

		# Generate Enemy Spawns
		_generate_enemy_spawns(room, index, room_type, rng)

		# Validate Reachability & Clearances via BFS Grid Flood-Fill
		if _validate_room_reachability(room):
			room.is_validated = true
			return room

	# Fallback to guaranteed valid calibration room if retries exhausted
	return _build_fallback_room(index, room_type)


func _pick_template_name(index: int, room_type: String, rng: RandomNumberGenerator) -> String:
	if room_type == "START":
		return "CALIBRATION_OPEN"
	if room_type == "BOSS":
		return "BOSS_NEXUS"

	var templates := [
		"QUAD_PILLARS",
		"CENTRAL_CHOKEPOINT",
		"SPLIT_LANE",
		"COVER_FORTRESS",
		"HAZARD_CORRIDOR",
		"CROSS_INTERSECTION"
	]
	return templates[rng.randi() % templates.size()]


func _apply_template_geometry(room: RoomData, template_name: String, rng: RandomNumberGenerator) -> void:
	room.obstacles.clear()
	var center := room.bounds.get_center()

	match template_name:
		"CALIBRATION_OPEN":
			room.tactical_context.has_cover = false
			room.tactical_context.chokepoint_ratio = 0.0
			room.tactical_context.flanking_lanes = 2

		"QUAD_PILLARS":
			# 4 symmetrical pillar columns providing cover and 3 distinct approach channels
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
			# Central barrier splitting upper and lower lanes
			var wall_w := 260.0
			var wall_h := 28.0
			room.obstacles.append(Rect2(Vector2(center.x - wall_w * 0.5, center.y - wall_h * 0.5), Vector2(wall_w, wall_h)))
			room.tactical_context.has_cover = true
			room.tactical_context.chokepoint_ratio = 0.65
			room.tactical_context.flanking_lanes = 2

		"SPLIT_LANE":
			# Twin vertical or horizontal barriers dividing arena into 3 lanes
			var bar_size := Vector2(26.0, 140.0)
			room.obstacles.append(Rect2(Vector2(center.x - 120.0 - 13.0, center.y - 70.0), bar_size))
			room.obstacles.append(Rect2(Vector2(center.x + 120.0 - 13.0, center.y - 70.0), bar_size))
			room.tactical_context.has_cover = true
			room.tactical_context.chokepoint_ratio = 0.45
			room.tactical_context.flanking_lanes = 3

		"COVER_FORTRESS":
			# 4 staggered terminal clusters for close-quarters firefights
			var block_size := Vector2(60.0, 28.0)
			room.obstacles.append(Rect2(Vector2(center.x - 130.0, center.y - 85.0), block_size))
			room.obstacles.append(Rect2(Vector2(center.x + 80.0, center.y - 85.0), block_size))
			room.obstacles.append(Rect2(Vector2(center.x - 130.0, center.y + 60.0), block_size))
			room.obstacles.append(Rect2(Vector2(center.x + 80.0, center.y + 60.0), block_size))
			room.tactical_context.has_cover = true
			room.tactical_context.chokepoint_ratio = 0.35
			room.tactical_context.flanking_lanes = 3

		"HAZARD_CORRIDOR":
			# Low obstacle density, but high hazard ratio
			room.obstacles.append(Rect2(Vector2(center.x - 80.0, center.y - 20.0), Vector2(160.0, 40.0)))
			room.tactical_context.has_cover = true
			room.tactical_context.chokepoint_ratio = 0.30
			room.tactical_context.flanking_lanes = 2
			room.tactical_context.hazard_density = 0.60

		"CROSS_INTERSECTION":
			# Central cross layout with 4 corner approach corridors
			room.obstacles.append(Rect2(Vector2(center.x - 20.0, center.y - 90.0), Vector2(40.0, 60.0)))
			room.obstacles.append(Rect2(Vector2(center.x - 20.0, center.y + 30.0), Vector2(40.0, 60.0)))
			room.tactical_context.has_cover = true
			room.tactical_context.chokepoint_ratio = 0.50
			room.tactical_context.flanking_lanes = 2

		"BOSS_NEXUS":
			# Corner blast barriers protecting perimeter
			var b_size := Vector2(36.0, 36.0)
			room.obstacles.append(Rect2(Vector2(180.0 - 18.0, 150.0 - 18.0), b_size))
			room.obstacles.append(Rect2(Vector2(780.0 - 18.0, 150.0 - 18.0), b_size))
			room.obstacles.append(Rect2(Vector2(180.0 - 18.0, 400.0 - 18.0), b_size))
			room.obstacles.append(Rect2(Vector2(780.0 - 18.0, 400.0 - 18.0), b_size))
			room.tactical_context.has_cover = true
			room.tactical_context.chokepoint_ratio = 0.15
			room.tactical_context.flanking_lanes = 4


func _generate_enemy_spawns(room: RoomData, index: int, room_type: String, rng: RandomNumberGenerator) -> void:
	room.enemy_spawns.clear()

	if room_type == "START":
		# 3 introductory chasers
		room.enemy_spawns.append({ "type": "CHASER", "pos": Vector2(620, 200), "flank_angle": 0.50 })
		room.enemy_spawns.append({ "type": "CHASER", "pos": Vector2(740, 276), "flank_angle": 0.0 })
		room.enemy_spawns.append({ "type": "CHASER", "pos": Vector2(620, 360), "flank_angle": -0.50 })
		return

	if room_type == "BOSS":
		room.enemy_spawns.append({ "type": "BOSS", "pos": Vector2(680, 276), "flank_angle": 0.0 })
		return

	# Progressive enemy composition
	var base_enemy_count: int = clampi(3 + int(index * 0.65), 3, 6)
	var possible_types := ["CHASER"]
	if index >= 1:
		possible_types.append("SHOOTER")
	if index >= 2:
		possible_types.append("DASHER")

	for i in range(base_enemy_count):
		var etype: String = possible_types[rng.randi() % possible_types.size()]
		# Sample position on right 60% of arena
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
	## BFS Flood-Fill reachability validator on discrete 32x32 grid.
	## Guarantees:
	##   1. Player spawn is clear and within bounds.
	##   2. Obstacles do not overlap player spawn or exits.
	##   3. Obstacles do not block all navigation (exit door is 100% reachable).
	##   4. Every enemy spawn is reachable and not embedded in an obstacle.
	##   5. Minimum distance between player spawn and enemy spawns is >= 200px.

	# 1. Check player spawn bounds and clearance
	if not room.bounds.has_point(room.player_spawn):
		return false
	for obs in room.obstacles:
		if obs.grow(20.0).has_point(room.player_spawn):
			return false
		if obs.grow(20.0).has_point(room.exit_door):
			return false

	# 2. Check enemy spawn clearance and minimum distance
	for espawn in room.enemy_spawns:
		var epos: Vector2 = espawn.pos
		if not room.bounds.has_point(epos):
			return false
		if room.player_spawn.distance_to(epos) < MIN_PLAYER_ENEMY_DIST:
			return false
		for obs in room.obstacles:
			if obs.grow(16.0).has_point(epos):
				return false

	# 3. Construct 2D Walkability Grid
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

	# Mark obstacle cells as blocked
	for obs in room.obstacles:
		var min_gx := clampi(int((obs.position.x - origin_x) / GRID_CELL_SIZE), 0, grid_w - 1)
		var max_gx := clampi(int((obs.end.x - origin_x) / GRID_CELL_SIZE), 0, grid_w - 1)
		var min_gy := clampi(int((obs.position.y - origin_y) / GRID_CELL_SIZE), 0, grid_h - 1)
		var max_gy := clampi(int((obs.end.y - origin_y) / GRID_CELL_SIZE), 0, grid_h - 1)

		for gx in range(min_gx, max_gx + 1):
			for gy in range(min_gy, max_gy + 1):
				blocked_grid[gx][gy] = true

	# 4. BFS Reachability from Player Spawn
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

	# Confirm exit door is reachable
	var exit_gx := clampi(int((room.exit_door.x - origin_x) / GRID_CELL_SIZE), 0, grid_w - 1)
	var exit_gy := clampi(int((room.exit_door.y - origin_y) / GRID_CELL_SIZE), 0, grid_h - 1)
	if not visited[exit_gx][exit_gy]:
		return false # Exit is completely blocked by obstacles!

	# Confirm all enemy spawns are reachable
	for espawn in room.enemy_spawns:
		var egx := clampi(int((espawn.pos.x - origin_x) / GRID_CELL_SIZE), 0, grid_w - 1)
		var egy := clampi(int((espawn.pos.y - origin_y) / GRID_CELL_SIZE), 0, grid_h - 1)
		if not visited[egx][egy]:
			return false # Enemy spawn trapped in unreachable chamber!

	return true


func _build_fallback_room(index: int, room_type: String) -> RoomData:
	## Guaranteed safe fallback room template if procedural generation exceeds retries.
	var room := RoomData.new()
	room.index = index
	room.room_type = room_type
	room.template_name = "SAFE_FALLBACK"
	room.bounds = ROOM_RECT
	room.player_spawn = Vector2(ROOM_RECT.position.x + 120.0, ROOM_RECT.get_center().y)
	room.exit_door = Vector2(ROOM_RECT.end.x - 60.0, ROOM_RECT.get_center().y)
	room.obstacles.clear()

	# Two safe, small pillar blocks
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
