extends CharacterBody2D
## Ranged hovering turret sentry shaped as an amber faceted hexagon with predictive lead aiming.

signal defeated

const PROJECTILE_SCENE := preload("res://scenes/weapons/enemy_projectile.tscn")
const EnemySteering := preload("res://scripts/enemy_steering.gd")

@export var max_health := 3
@export var move_speed := 82.0
@export var ideal_distance := 210.0
@export var lead_prediction := 0.0
@export var burst_count := 1

var health := 3
var target: Node2D
var defeated_already := false

var fire_timer := 2.0
var telegraph_time := 0.0
const TELEGRAPH_DURATION := 0.65
var aimed_direction := Vector2.RIGHT
var damage_flash := 0.0
var recovery_time := 0.0

var genome: RefCounted = null
var spatial_index: RefCounted = null
var squad_coordinator: RefCounted = null
var obstacle_rects: Array[Rect2] = []

var damage_multipliers: Dictionary = {
	"plasma": 1.0,
	"dash": 1.0,
	"hazard": 1.0
}


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	fire_timer = randf_range(1.5, 2.5)
	queue_redraw()


func _physics_process(delta: float) -> void:
	damage_flash = maxf(0.0, damage_flash - delta)
	recovery_time = maxf(0.0, recovery_time - delta)

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
		var kite_vel: Vector2 = EnemySteering.calculate_range_velocity(global_position, target.global_position, ideal_distance, move_speed)
		var separation: Vector2 = Vector2.ZERO
		if spatial_index:
			separation = spatial_index.get_separation_for_agent(self, 35.0, 3)

		var move_dir: Vector2 = (kite_vel.normalized() + separation * 0.4).normalized()
		if not obstacle_rects.is_empty():
			move_dir = EnemySteering.avoid_obstacles(global_position, move_dir, obstacle_rects, 35.0)

		velocity = move_dir * move_speed

	if is_inside_tree():
		move_and_slide()
	queue_redraw()


func _fire_shot() -> void:
	if not get_parent():
		return
	var proj = PROJECTILE_SCENE.instantiate()
	proj.global_position = global_position + aimed_direction * 24.0
	proj.direction = aimed_direction
	if "shooter_enemy" in proj:
		proj.shooter_enemy = self
	get_parent().add_child(proj)
	queue_redraw()

	if burst_count >= 2 and is_inside_tree():
		await get_tree().create_timer(0.14).timeout
		if is_instance_valid(self) and not defeated_already and is_inside_tree() and get_parent():
			var proj2 = PROJECTILE_SCENE.instantiate()
			proj2.global_position = global_position + aimed_direction * 24.0
			proj2.direction = aimed_direction
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
	# Warning laser line when charging attack (shows exact predicted interception vector)
	if telegraph_time > 0.0:
		var pulse := 0.5 + sin(telegraph_time * 25.0) * 0.4
		var line_color := Color(1.0, 0.6, 0.1, pulse)
		if lead_prediction > 0.0:
			line_color = Color(0.22, 0.74, 0.97, pulse + 0.15) # Cyber cyan predictive laser
		draw_line(Vector2.ZERO, to_local(global_position + aimed_direction * 380.0), line_color, 2.0)
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

	# Health bar
	if health < max_health:
		var hit_points := float(health) / float(max_health)
		draw_rect(Rect2(-14, -22, 28, 4), Color("181a26"))
		draw_rect(Rect2(-13, -21, 26.0 * hit_points, 2), Color("f59e0b"))
