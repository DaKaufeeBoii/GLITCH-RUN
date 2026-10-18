extends CharacterBody2D
## Ranged hovering turret sentry shaped as an amber faceted hexagon with predictive lead aiming.

signal defeated

const PROJECTILE_SCENE := preload("res://scenes/weapons/enemy_projectile.tscn")

@export var max_health := 3
@export var move_speed := 82.0
@export var ideal_distance := 210.0
@export var lead_prediction := 0.0
@export var burst_count := 1
@export var has_beam_attack := false

var health := 3
var target: Node2D
var defeated_already := false

var fire_timer := 2.0
var telegraph_time := 0.0
const TELEGRAPH_DURATION := 0.65
var aimed_direction := Vector2.RIGHT
var damage_flash := 0.0
var recovery_time := 0.0

# Tier 3 Charged Beam Attack
var is_firing_beam := false
var beam_duration := 0.0

# Debuff status
var debuff_slow_timer := 0.0
var debuff_burn_timer := 0.0
var debuff_burn_tick := 0.0
var debuff_shock_timer := 0.0

var genome: RefCounted = null
var spatial_index: RefCounted = null
var squad_coordinator: RefCounted = null
var nav_grid: RefCounted = null
var obstacle_rects: Array[Rect2] = []

var damage_multipliers: Dictionary = {
	"plasma": 1.0,
	"dash": 1.0,
	"hazard": 1.0
}


func apply_debuff(type: String, duration: float, _intensity: float = 1.0) -> void:
	match type:
		"CRYO", "SLOW":
			debuff_slow_timer = maxf(debuff_slow_timer, duration)
		"ACID", "BURN":
			debuff_burn_timer = maxf(debuff_burn_timer, duration)
			debuff_burn_tick = 0.5
		"SHOCK":
			debuff_shock_timer = maxf(debuff_shock_timer, duration)
			telegraph_time = 0.0
			is_firing_beam = false
	queue_redraw()


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	fire_timer = randf_range(1.5, 2.5)
	queue_redraw()


func _physics_process(delta: float) -> void:
	damage_flash = maxf(0.0, damage_flash - delta)
	recovery_time = maxf(0.0, recovery_time - delta)

	# Debuff updates
	if debuff_slow_timer > 0.0:
		debuff_slow_timer = maxf(0.0, debuff_slow_timer - delta)

	if debuff_burn_timer > 0.0:
		debuff_burn_timer = maxf(0.0, debuff_burn_timer - delta)
		debuff_burn_tick -= delta
		if debuff_burn_tick <= 0.0:
			debuff_burn_tick = 1.0
			take_damage(1, "hazard")

	if debuff_shock_timer > 0.0:
		debuff_shock_timer = maxf(0.0, debuff_shock_timer - delta)
		velocity = Vector2.ZERO
		queue_redraw()
		return

	if is_firing_beam:
		beam_duration -= delta
		velocity = Vector2.ZERO
		if beam_duration <= 0.0:
			is_firing_beam = false
		queue_redraw()
		return

	if not is_instance_valid(target):
		return

	var to_target := target.global_position - global_position
	var dist := to_target.length()
	rotation = to_target.angle()

	if telegraph_time > 0.0:
		telegraph_time -= delta
		velocity = Vector2.ZERO
		# Aim is locked during telegraph so player has a readable dodge window
		queue_redraw()
		if telegraph_time <= 0.0:
			_fire_shot()
			recovery_time = 0.35 # Recovery window after shot
			if squad_coordinator:
				squad_coordinator.release_attack_token(self)
	elif recovery_time > 0.0:
		velocity = Vector2.ZERO
	else:
		# Bounded lead interception: prediction angle clamped to 45 deg max
		var target_vel: Vector2 = target.velocity if ("velocity" in target) else Vector2.ZERO
		var aim_pos: Vector2 = EnemySteering.predict_target_position(
			global_position,
			target.global_position,
			target_vel,
			390.0,
			lead_prediction
		)
		var predicted_dir: Vector2 = (aim_pos - global_position).normalized()
		aimed_direction = predicted_dir

		fire_timer -= delta
		if fire_timer <= 0.0 and dist < 450.0:
			# Check line of sight: do not shoot through blocking obstacle pillars
			var los_blocked: bool = EnemySteering.is_line_blocked(global_position, target.global_position, obstacle_rects)
			var cur_time: float = Time.get_ticks_msec() / 1000.0
			var token_granted: bool = (squad_coordinator == null or squad_coordinator.request_attack_token(self, cur_time))

			if not los_blocked and token_granted:
				var timing_mult: float = float(genome.attack_timing_mult) if (genome and "attack_timing_mult" in genome) else 1.0
				telegraph_time = TELEGRAPH_DURATION * timing_mult
				aimed_direction = predicted_dir
				fire_timer = randf_range(2.0, 3.0) * timing_mult
				if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
					get_node("/root/AudioSynth").play("enemy_laser_charge", 0.05, -4.0)
			else:
				# Reposition before re-evaluating attack
				fire_timer = 0.4

		# Kiting movement: maintain ideal distance & avoid obstacles
		var los_blocked: bool = EnemySteering.is_line_blocked(global_position, target.global_position, obstacle_rects) if not obstacle_rects.is_empty() else false
		var move_dir := Vector2.ZERO

		if not los_blocked:
			var kite_vel: Vector2 = EnemySteering.calculate_range_velocity(global_position, target.global_position, ideal_distance, move_speed)
			var separation: Vector2 = Vector2.ZERO
			if spatial_index:
				separation = spatial_index.get_separation_for_agent(self, 35.0, 3)

			move_dir = (kite_vel.normalized() + separation * 0.4).normalized()
			if not obstacle_rects.is_empty():
				move_dir = EnemySteering.avoid_obstacles(global_position, move_dir, obstacle_rects, 35.0)
		else:
			# If obstructed by obstacles, maneuver around obstacle to regain firing line
			if nav_grid != null:
				move_dir = nav_grid.get_nav_direction(global_position, target.global_position)
			else:
				move_dir = EnemySteering.avoid_obstacles(global_position, to_target.normalized(), obstacle_rects, 35.0)

		var eff_speed: float = move_speed * (0.50 if debuff_slow_timer > 0.0 else 1.0)
		velocity = move_dir * eff_speed

	if is_inside_tree():
		move_and_slide()
	queue_redraw()


func _fire_shot() -> void:
	if not get_parent():
		return

	if has_beam_attack:
		is_firing_beam = true
		beam_duration = 0.35
		if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
			get_node("/root/AudioSynth").play("laser_heavy", 0.08, -2.0)
		# Heavy beam strike deals 2 damage if player is within beam line
		if is_instance_valid(target) and target.has_method("take_damage"):
			var p_pos: Vector2 = target.global_position
			var b_start: Vector2 = global_position
			var b_end: Vector2 = global_position + aimed_direction * 650.0
			var closest_pt: Vector2 = Geometry2D.get_closest_point_to_segment(p_pos, b_start, b_end)
			if p_pos.distance_to(closest_pt) <= 24.0:
				target.take_damage(2)
		queue_redraw()
		return

	# Normal shot: if lead_prediction is 0.0, apply bad aim spread
	var shoot_dir := aimed_direction
	if lead_prediction <= 0.01:
		shoot_dir = aimed_direction.rotated(randf_range(-0.32, 0.32)) # ~18 deg bad aim spread

	var proj = PROJECTILE_SCENE.instantiate()
	proj.global_position = global_position + shoot_dir * 24.0
	proj.direction = shoot_dir
	if "shooter_enemy" in proj:
		proj.shooter_enemy = self
	get_parent().add_child(proj)
	queue_redraw()

	if burst_count >= 2 and is_inside_tree():
		await get_tree().create_timer(0.14).timeout
		if is_instance_valid(self) and not defeated_already and is_inside_tree() and get_parent():
			var proj2 = PROJECTILE_SCENE.instantiate()
			proj2.global_position = global_position + shoot_dir * 24.0
			proj2.direction = shoot_dir
			if "shooter_enemy" in proj2:
				proj2.shooter_enemy = self
			get_parent().add_child(proj2)
			queue_redraw()



func take_damage(amount: int, source: String = "plasma") -> void:
	if defeated_already:
		return
	var mult: float = damage_multipliers.get(source, 1.0)
	var final_amount: int = maxi(1, int(roundf(float(amount) * mult)))
	health = maxi(0, health - final_amount)
	damage_flash = 0.12
	queue_redraw()
	if health == 0:
		defeated_already = true
		if squad_coordinator:
			squad_coordinator.release_attack_token(self)
		defeated.emit()
		queue_free()


func _draw() -> void:
	# Active Heavy Particle Beam (Tier 3)
	if is_firing_beam:
		var beam_end := to_local(global_position + aimed_direction * 650.0)
		draw_line(Vector2.ZERO, beam_end, Color(1.0, 0.65, 0.1, 0.95), 8.0)
		draw_line(Vector2.ZERO, beam_end, Color(1.0, 0.98, 0.8, 1.0), 3.0)
		draw_circle(beam_end, 7.0, Color("f59e0b"))
		draw_circle(Vector2.ZERO, 9.0, Color("fffbeb"))

	# Warning laser line when charging attack (shows exact predicted interception vector)
	if telegraph_time > 0.0:
		var pulse := 0.5 + sin(telegraph_time * 25.0) * 0.4
		var line_color := Color(1.0, 0.6, 0.1, pulse)
		if has_beam_attack:
			line_color = Color(0.96, 0.25, 0.37, pulse + 0.2) # High-energy beam warning red/amber
		elif lead_prediction > 0.0:
			line_color = Color(0.22, 0.74, 0.97, pulse + 0.15) # Cyber cyan predictive laser
		draw_line(Vector2.ZERO, to_local(global_position + aimed_direction * 380.0), line_color, 2.5 if has_beam_attack else 2.0)
		draw_line(Vector2.ZERO, to_local(global_position + aimed_direction * 380.0), Color(1.0, 0.95, 0.7, pulse * 0.6), 1.0)

	# Enemy body: Faceted amber hexagon polygon
	var body_color := Color("f59e0b") if damage_flash <= 0.0 else Color("ffffff")
	var pts := PackedVector2Array([
		Vector2(16, 0),
		Vector2(6, -13),
		Vector2(-12, -11),
		Vector2(-16, 0),
		Vector2(-12, 11),
		Vector2(6, 13)
	])
	draw_colored_polygon(pts, body_color)
	draw_polyline(PackedVector2Array([
		Vector2(16, 0),
		Vector2(6, -13),
		Vector2(-12, -11),
		Vector2(-16, 0),
		Vector2(-12, 11),
		Vector2(6, 13),
		Vector2(16, 0)
	]), body_color.lightened(0.35), 1.5)

	# Evolved predictive targeting prongs
	if lead_prediction > 0.0:
		draw_line(Vector2(10, -9), Vector2(20, -14), body_color, 2.0)
		draw_line(Vector2(10, 9), Vector2(20, 14), body_color, 2.0)
		draw_circle(Vector2(20, -14), 2.0, Color("38bdf8"))
		draw_circle(Vector2(20, 14), 2.0, Color("38bdf8"))

	# Inner optic sensor
	draw_circle(Vector2(5, 0), 4.0, Color("fffbeb"))
	draw_circle(Vector2(5, 0), 2.0, Color("f59e0b"))

	# Tier 3 Heavy Beam Emitter Focal Lens
	if has_beam_attack:
		draw_circle(Vector2(16, 0), 4.5, Color("f43f5e"))
		draw_circle(Vector2(16, 0), 2.5, Color("fffbeb"))
		draw_line(Vector2(6, -13), Vector2(16, 0), Color("be123c"), 2.0)
		draw_line(Vector2(6, 13), Vector2(16, 0), Color("be123c"), 2.0)

	# Evolved Armored Reinforcements (Tier 2 and Tier 3)
	if max_health > 3:
		# Draw top and bottom armored chassis plating
		draw_line(Vector2(-12, -13), Vector2(6, -15), Color("38bdf8"), 2.0)
		draw_line(Vector2(-12, 13), Vector2(6, 15), Color("38bdf8"), 2.0)

	# Health bar & Evolution Tier indicator
	if max_health > 3:
		var tier_pips := 1
		if max_health >= 12:
			tier_pips = 3
		elif max_health >= 6:
			tier_pips = 2
		for p in range(tier_pips):
			draw_circle(Vector2(-6.0 + float(p) * 6.0, -27), 2.0, Color("38bdf8"))
		draw_rect(Rect2(-16, -22, 32, 4), Color("181a26"))
		var hp_ratio := float(health) / float(max_health)
		draw_rect(Rect2(-15, -21, 30.0 * hp_ratio, 2), Color("f59e0b"))
	elif health < max_health:
		var hit_points := float(health) / float(max_health)
		draw_rect(Rect2(-14, -22, 28, 4), Color("181a26"))
		draw_rect(Rect2(-13, -21, 26.0 * hit_points, 2), Color("f59e0b"))

	# Debuff Visual Overlays
	if debuff_slow_timer > 0.0:
		draw_circle(Vector2.ZERO, 19.0, Color(0.2, 0.8, 1.0, 0.25))
	if debuff_burn_timer > 0.0:
		draw_circle(Vector2.ZERO, 16.0, Color(0.5, 1.0, 0.2, 0.25))
	if debuff_shock_timer > 0.0:
		for s in range(3):
			var a := randf() * TAU
			draw_line(Vector2.ZERO, Vector2(cos(a), sin(a)) * 20.0, Color("c084fc"), 1.8)
