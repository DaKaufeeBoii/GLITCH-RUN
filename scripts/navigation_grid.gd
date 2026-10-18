extends RefCounted
class_name NavigationGrid
## High-performance topological A* 2D navigation grid for procedural chambers.
## Solves local minima and obstacle trapping by computing optimal routes around
## pillars and walls, with string-pulling line-of-sight shortcut smoothing.

const ENEMY_STEERING_SCRIPT := preload("res://scripts/enemy_steering.gd")

var cell_size: float = 40.0
var bounds: Rect2 = Rect2(0, 0, 1600, 900)
var obstacles: Array[Rect2] = []
var astar: AStar2D = null
var cols: int = 0
var rows: int = 0


func _init(p_cell_size: float = 40.0) -> void:
	cell_size = p_cell_size
	astar = AStar2D.new()


func build_grid(room_bounds: Rect2, obstacle_list: Array[Rect2], agent_radius: float = 24.0) -> void:
	## Discretizes chamber into an 8-way connected A* graph, masking out obstacle geometry.
	bounds = room_bounds
	obstacles = obstacle_list
	astar.clear()

	cols = maxi(1, int(ceil(bounds.size.x / cell_size)))
	rows = maxi(1, int(ceil(bounds.size.y / cell_size)))

	# 1. Register passable grid nodes
	for y in range(rows):
		for x in range(cols):
			var world_pos := _grid_to_world(x, y)
			if _is_position_blocked(world_pos, agent_radius):
				continue
			var pt_id := _get_point_id(x, y)
			astar.add_point(pt_id, world_pos, 1.0)

	# 2. Connect neighbors (Orthogonal weight = 1.0, Diagonal weight = 1.414)
	# Diagonal edges are ONLY connected if BOTH adjacent orthogonal cells are clear,
	# guaranteeing agents never clip or cut through obstacle corners.
	for y in range(rows):
		for x in range(cols):
			var cur_id := _get_point_id(x, y)
			if not astar.has_point(cur_id):
				continue

			# East neighbor (x + 1, y)
			if x + 1 < cols:
				var east_id := _get_point_id(x + 1, y)
				if astar.has_point(east_id):
					astar.connect_points(cur_id, east_id, true)

			# South neighbor (x, y + 1)
			if y + 1 < rows:
				var south_id := _get_point_id(x, y + 1)
				if astar.has_point(south_id):
					astar.connect_points(cur_id, south_id, true)

			# South-East diagonal (x + 1, y + 1)
			if x + 1 < cols and y + 1 < rows:
				var se_id := _get_point_id(x + 1, y + 1)
				var east_id := _get_point_id(x + 1, y)
				var south_id := _get_point_id(x, y + 1)
				if astar.has_point(se_id) and astar.has_point(east_id) and astar.has_point(south_id):
					astar.connect_points(cur_id, se_id, true)

			# South-West diagonal (x - 1, y + 1)
			if x - 1 >= 0 and y + 1 < rows:
				var sw_id := _get_point_id(x - 1, y + 1)
				var west_id := _get_point_id(x - 1, y)
				var south_id := _get_point_id(x, y + 1)
				if astar.has_point(sw_id) and astar.has_point(west_id) and astar.has_point(south_id):
					astar.connect_points(cur_id, sw_id, true)


func _get_point_id(x: int, y: int) -> int:
	return y * cols + x


func _grid_to_world(x: int, y: int) -> Vector2:
	return bounds.position + Vector2(float(x) + 0.5, float(y) + 0.5) * cell_size


func _world_to_grid(world_pos: Vector2) -> Vector2i:
	var local := world_pos - bounds.position
	var gx := clampi(int(local.x / cell_size), 0, cols - 1)
	var gy := clampi(int(local.y / cell_size), 0, rows - 1)
	return Vector2i(gx, gy)


func _is_position_blocked(world_pos: Vector2, agent_radius: float) -> bool:
	# Check outer perimeter boundary buffer
	if world_pos.x < bounds.position.x + agent_radius or world_pos.x > bounds.end.x - agent_radius:
		return true
	if world_pos.y < bounds.position.y + agent_radius or world_pos.y > bounds.end.y - agent_radius:
		return true

	# Check against all room obstacle rectangles with inflation
	for obs in obstacles:
		if obs.grow(agent_radius).has_point(world_pos):
			return true
	return false


func get_path_points(from_pos: Vector2, to_pos: Vector2) -> PackedVector2Array:
	## Retrieves full A* waypoint path between two world positions.
	if astar.get_point_count() == 0:
		return PackedVector2Array()

	var start_id := astar.get_closest_point(from_pos)
	var end_id := astar.get_closest_point(to_pos)
	if start_id == -1 or end_id == -1:
		return PackedVector2Array()

	return astar.get_point_path(start_id, end_id)


func get_next_waypoint(from_pos: Vector2, to_pos: Vector2) -> Vector2:
	## Computes next navigation target using string-pulling shortcut optimization.
	## If line of sight directly to target is clear, returns target immediately.
	if not ENEMY_STEERING_SCRIPT.is_line_blocked(from_pos, to_pos, obstacles):
		return to_pos

	var path := get_path_points(from_pos, to_pos)
	if path.is_empty():
		return to_pos

	# String-pulling: find the furthest waypoint along the path that has clear line of sight
	for i in range(path.size() - 1, -1, -1):
		var wp := path[i]
		if not ENEMY_STEERING_SCRIPT.is_line_blocked(from_pos, wp, obstacles):
			# If the agent is already at or very close to this waypoint, advance to next
			if from_pos.distance_to(wp) > 16.0 or i == path.size() - 1:
				return wp

	# If even path[0] has no line of sight (e.g. agent inside corner radius), return closest waypoint
	return path[0]


func get_nav_direction(from_pos: Vector2, to_pos: Vector2) -> Vector2:
	## High-level tactical direction generator.
	## Returns normalized velocity vector navigating around obstacles smoothly.
	var to_target := to_pos - from_pos
	if to_target.is_zero_approx():
		return Vector2.ZERO

	# 1. Unobstructed line of sight: direct pursuit
	if not ENEMY_STEERING_SCRIPT.is_line_blocked(from_pos, to_pos, obstacles):
		return to_target.normalized()

	# 2. Obstructed line of sight: navigate toward furthest visible A* waypoint
	var next_wp := get_next_waypoint(from_pos, to_pos)
	var to_wp := next_wp - from_pos
	if not to_wp.is_zero_approx():
		var dir := to_wp.normalized()
		# Local whisker clearance to maintain smooth distance from obstacle corners
		if not obstacles.is_empty():
			dir = ENEMY_STEERING_SCRIPT.avoid_obstacles(from_pos, dir, obstacles, 35.0)
		return dir

	return to_target.normalized()
