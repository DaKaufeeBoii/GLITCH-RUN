extends RefCounted
class_name EnemySteering
## Reusable tactical steering, predictive interception, obstacle avoidance,
## and spatial separation helper for enemy combatants.

const MAX_LEAD_ANGLE := 0.7854 # 45 degrees maximum prediction deflection


static func get_separation_vector(
	agent_pos: Vector2,
	neighbor_positions: Array[Vector2],
	radius: float = 32.0,
	max_neighbors: int = 4
) -> Vector2:
	## Calculates soft repulsive separation vector using squared distances and neighbor capping.
	var separation := Vector2.ZERO
	var rad_sq := radius * radius
	var counted := 0

	for n_pos in neighbor_positions:
		if counted >= max_neighbors:
			break
		var dist_sq := agent_pos.distance_squared_to(n_pos)
		if dist_sq < rad_sq and dist_sq > 0.001:
			var d := sqrt(dist_sq)
			var push := (agent_pos - n_pos) / d # Normalized direction away
			var strength := (radius - d) / radius # Falloff [0, 1]
			separation += push * strength
			counted += 1

	if counted > 0:
		separation = separation / float(counted)
	return separation


static func predict_target_position(
	origin: Vector2,
	target_pos: Vector2,
	target_velocity: Vector2,
	bullet_speed: float,
	lead_prediction: float,
	max_angle: float = MAX_LEAD_ANGLE
) -> Vector2:
	## Predicts interception point with bounded lead deflection to guarantee dodgability.
	var to_target := target_pos - origin
	var dist := to_target.length()
	if dist <= 0.001 or bullet_speed <= 0.0 or lead_prediction <= 0.0:
		return target_pos

	var time_to_hit := dist / bullet_speed
	var raw_predicted := target_pos + target_velocity * time_to_hit * lead_prediction
	var predicted_dir := (raw_predicted - origin).normalized()
	var direct_dir := to_target.normalized()

	# Clamp angle deviation between direct direction and predicted direction
	var angle_diff := direct_dir.angle_to(predicted_dir)
	if absf(angle_diff) > max_angle:
		var clamped_angle := direct_dir.angle() + signf(angle_diff) * max_angle
		var clamped_dir := Vector2(cos(clamped_angle), sin(clamped_angle))
		return origin + clamped_dir * dist

	return raw_predicted


static func get_nav_direction(
	agent_pos: Vector2,
	target_pos: Vector2,
	nav_grid: RefCounted,
	obstacles: Array[Rect2]
) -> Vector2:
	## Computes intelligent movement direction using topological A* grid if available,
	## falling back to ray deflection if nav_grid is null.
	if nav_grid != null and nav_grid.has_method("get_nav_direction"):
		return nav_grid.get_nav_direction(agent_pos, target_pos)
	elif not is_line_blocked(agent_pos, target_pos, obstacles):
		var to_t := target_pos - agent_pos
		return to_t.normalized() if not to_t.is_zero_approx() else Vector2.ZERO
	else:
		var to_t := target_pos - agent_pos
		var dir := to_t.normalized() if not to_t.is_zero_approx() else Vector2.ZERO
		return avoid_obstacles(agent_pos, dir, obstacles, 45.0)


static func segment_intersects_rect(p0: Vector2, p1: Vector2, rect: Rect2) -> bool:
	## Exact slab intersection test between line segment and an axis-aligned bounding box.
	if rect.has_point(p0) or rect.has_point(p1):
		return true

	var min_x := rect.position.x
	var max_x := rect.end.x
	var min_y := rect.position.y
	var max_y := rect.end.y

	var tmin := 0.0
	var tmax := 1.0
	var d := p1 - p0

	# X slab
	if absf(d.x) < 0.00001:
		if p0.x < min_x or p0.x > max_x:
			return false
	else:
		var t1 := (min_x - p0.x) / d.x
		var t2 := (max_x - p0.x) / d.x
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return false

	# Y slab
	if absf(d.y) < 0.00001:
		if p0.y < min_y or p0.y > max_y:
			return false
	else:
		var t1 := (min_y - p0.y) / d.y
		var t2 := (max_y - p0.y) / d.y
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return false

	return tmin <= tmax and tmax >= 0.0 and tmin <= 1.0


static func avoid_obstacles(
	agent_pos: Vector2,
	desired_dir: Vector2,
	obstacles: Array[Rect2],
	lookahead: float = 45.0
) -> Vector2:
	## Deflects movement direction tangentially around obstacle geometry with zero inward push.
	if desired_dir.is_zero_approx() or obstacles.is_empty():
		return desired_dir

	var probe_end := agent_pos + desired_dir * lookahead
	var best_deflection := desired_dir
	var closest_hit_dist := INF

	for obs in obstacles:
		var inflated := obs.grow(16.0)
		var is_inside := inflated.has_point(agent_pos)
		var hits_path := segment_intersects_rect(agent_pos, probe_end, inflated)

		if is_inside or hits_path:
			var obs_center := obs.get_center()
			# Surface projection on obstacle boundary
			var clamped_x := clampf(agent_pos.x, obs.position.x, obs.end.x)
			var clamped_y := clampf(agent_pos.y, obs.position.y, obs.end.y)
			var closest_point := Vector2(clamped_x, clamped_y)
			var away := agent_pos - closest_point
			var dist := away.length()

			var normal: Vector2
			if dist > 0.001:
				normal = away / dist
			else:
				var from_center := agent_pos - obs_center
				normal = from_center.normalized() if not from_center.is_zero_approx() else -desired_dir

			# When heading toward obstacle or touching boundary
			var dot_prod := desired_dir.dot(normal)
			if dot_prod < 0.2:
				var tangent := desired_dir.slide(normal)
				if tangent.length_squared() < 0.01:
					tangent = normal.orthogonal()
					if tangent.dot(desired_dir) < 0.0:
						tangent = -tangent
				else:
					tangent = tangent.normalized()

				# Strongly deflect along tangent while nudging along normal away from obstacle
				var deflected := (tangent * 0.85 + normal * 0.35).normalized()
				if dist < closest_hit_dist:
					closest_hit_dist = dist
					best_deflection = deflected

	return best_deflection


static func calculate_range_velocity(
	agent_pos: Vector2,
	target_pos: Vector2,
	ideal_dist: float,
	speed: float,
	deadzone: float = 35.0
) -> Vector2:
	## Smooth kiting velocity to maintain optimal engagement range.
	var to_target := target_pos - agent_pos
	var dist := to_target.length()
	if dist < 0.001:
		return Vector2.ZERO

	var dir := to_target.normalized()
	if dist < ideal_dist - deadzone:
		# Too close: backpedal
		return -dir * (speed * 1.05)
	elif dist > ideal_dist + deadzone:
		# Too far: advance
		return dir * speed
	else:
		# Sweet spot: strafe laterally
		var strafe_dir := dir.orthogonal()
		return strafe_dir * (speed * 0.7)


static func is_line_blocked(from: Vector2, to: Vector2, obstacles: Array[Rect2], padding: float = 8.0) -> bool:
	## Checks whether line of sight between two points penetrates any obstacle geometry using exact slab intersection.
	if obstacles.is_empty():
		return false
	for obs in obstacles:
		var test_rect := obs if padding <= 0.0 else obs.grow(padding)
		if segment_intersects_rect(from, to, test_rect):
			return true
	return false
