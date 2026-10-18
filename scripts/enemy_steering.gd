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


static func avoid_obstacles(
	agent_pos: Vector2,
	desired_dir: Vector2,
	obstacles: Array[Rect2],
	lookahead: float = 45.0
) -> Vector2:
	## Deflects movement direction tangentially around obstacle rectangles.
	if desired_dir.is_zero_approx():
		return Vector2.ZERO

	var probe_point := agent_pos + desired_dir * lookahead
	for obs in obstacles:
		if obs.grow(16.0).has_point(probe_point):
			# Deflect around obstacle center
			var obs_center := obs.get_center()
			var away_from_obs := (agent_pos - obs_center).normalized()
			# Tangent perpendicular to the obstacle normal
			var tangent := away_from_obs.orthogonal()
			if tangent.dot(desired_dir) < 0.0:
				tangent = -tangent
			return (desired_dir * 0.4 + tangent * 0.6).normalized()

	return desired_dir


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


static func is_line_blocked(from: Vector2, to: Vector2, obstacles: Array[Rect2]) -> bool:
	## Checks whether line of sight between two points penetrates any obstacle geometry.
	if obstacles.is_empty():
		return false
	var steps := 8
	var delta := (to - from) / float(steps)
	for i in range(1, steps):
		var pt := from + delta * float(i)
		for obs in obstacles:
			if obs.has_point(pt):
				return true
	return false
