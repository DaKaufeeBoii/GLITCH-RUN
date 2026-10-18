extends CharacterBody2D
## Ranged hovering turret sentry shaped as an amber faceted hexagon with predictive lead aiming.

signal defeated

const PROJECTILE_SCENE := preload("res://scenes/weapons/enemy_projectile.tscn")

@export var max_health := 3
@export var move_speed := 82.0
@export var ideal_distance := 210.0
@export var lead_prediction := 0.0

var health := 3
var target: Node2D
var defeated_already := false

var fire_timer := 2.0
var telegraph_time := 0.0
const TELEGRAPH_DURATION := 0.65
var aimed_direction := Vector2.RIGHT
var damage_flash := 0.0


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	fire_timer = randf_range(1.5, 2.5)
	queue_redraw()


func _physics_process(delta: float) -> void:
	damage_flash = maxf(0.0, damage_flash - delta)

	if not is_instance_valid(target):
		return

	var to_target := target.global_position - global_position
	var dist := to_target.length()

	# Compute predictive interception vector based on target velocity
	var aim_pos := target.global_position
	if lead_prediction > 0.0 and "velocity" in target:
		var bullet_speed := 390.0
		var time_to_hit := dist / bullet_speed
		aim_pos += target.velocity * time_to_hit * lead_prediction
	var predicted_dir := (aim_pos - global_position).normalized()
	aimed_direction = predicted_dir
	rotation = to_target.angle()

	if telegraph_time > 0.0:
		telegraph_time -= delta
		velocity = Vector2.ZERO
		aimed_direction = predicted_dir
		queue_redraw()
		if telegraph_time <= 0.0:
			_fire_shot()
	else:
		fire_timer -= delta
		if fire_timer <= 0.0 and dist < 450.0:
			telegraph_time = TELEGRAPH_DURATION
			aimed_direction = predicted_dir
			fire_timer = randf_range(2.0, 3.0)
			if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
				get_node("/root/AudioSynth").play("enemy_laser_charge", 0.05, -4.0)

		# Kiting movement: maintain ideal distance
		if dist < ideal_distance - 40.0:
			velocity = -to_target.normalized() * (move_speed * 1.1)
		elif dist > ideal_distance + 40.0:
			velocity = to_target.normalized() * move_speed
		else:
			var strafe := to_target.orthogonal().normalized()
			velocity = strafe * (move_speed * 0.75)

	if is_inside_tree():
		move_and_slide()
	queue_redraw()


func _fire_shot() -> void:
	var proj = PROJECTILE_SCENE.instantiate()
	proj.global_position = global_position + aimed_direction * 24.0
	proj.direction = aimed_direction
	get_parent().add_child(proj)
	queue_redraw()


func take_damage(amount: int) -> void:
	if defeated_already:
		return
	health = maxi(0, health - amount)
	damage_flash = 0.12
	queue_redraw()
	if health == 0:
		defeated_already = true
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
