extends RefCounted
class_name SpatialIndex
## Shared, bounded spatial neighbor service for GLITCH//RUN combatants.
## Replaces per-agent full-tree group scans with a centralized neighbor cache,
## using squared distances and neighbor count capping to maintain high frame rates on mobile.

const ENEMY_STEERING_SCRIPT := preload("res://scripts/enemy_steering.gd")

var registered_agents: Array[Node2D] = []
var cached_positions: Array[Vector2] = []
var dirty := true


func register_agent(agent: Node2D) -> void:
	if not agent in registered_agents:
		registered_agents.append(agent)
		dirty = true


func unregister_agent(agent: Node2D) -> void:
	registered_agents.erase(agent)
	dirty = true


func clear() -> void:
	registered_agents.clear()
	cached_positions.clear()
	dirty = false


func update_cache() -> void:
	## Synchronizes cached positions for all active, valid combatants.
	cached_positions.clear()
	var valid_agents: Array[Node2D] = []
	for a in registered_agents:
		if is_instance_valid(a) and not a.is_queued_for_deletion():
			valid_agents.append(a)
			cached_positions.append(a.global_position)
	registered_agents = valid_agents
	dirty = false


func get_neighbor_positions(
	origin: Vector2,
	radius: float = 32.0,
	max_count: int = 4,
	exclude_pos: Vector2 = Vector2.INF
) -> Array[Vector2]:
	## Returns up to max_count neighbor positions within radius using squared distances.
	if dirty or cached_positions.size() != registered_agents.size():
		update_cache()

	var result: Array[Vector2] = []
	var rad_sq := radius * radius

	for pos in cached_positions:
		if result.size() >= max_count:
			break
		if pos == exclude_pos or pos.is_equal_approx(exclude_pos):
			continue
		if origin.distance_squared_to(pos) <= rad_sq:
			result.append(pos)

	return result


func get_separation_for_agent(
	agent: Node2D,
	radius: float = 28.0,
	max_neighbors: int = 4
) -> Vector2:
	## Convenience method computing separation vector directly for an agent.
	if not is_instance_valid(agent):
		return Vector2.ZERO
	var origin := agent.global_position
	var neighbors := get_neighbor_positions(origin, radius, max_neighbors, origin)
	return ENEMY_STEERING_SCRIPT.get_separation_vector(origin, neighbors, radius, max_neighbors)
