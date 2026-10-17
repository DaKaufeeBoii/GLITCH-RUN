extends CharacterBody2D
## Ranged enemy that maintains distance and fires telegraphed energy shots.

signal defeated

const PROJECTILE_SCENE := preload("res://scenes/weapons/enemy_projectile.tscn")

@export var max_health := 3
@export var move_speed := 82.0
@export var ideal_distance := 210.0

var health := 3
var target: Node2D
var defeated_already := false

var fire_timer := 2.0
var telegraph_time := 0.0
const TELEGRAPH_DURATION := 0.65
var aimed_direction := Vector2.RIGHT


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	fire_timer = randf_range(1.5, 2.5)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return

	var to_target := target.global_position - global_position
	var dist := to_target.length()
	rotation = to_target.angle()

	if telegraph_time > 0.0:
		telegraph_time -= delta
		velocity = Vector2.ZERO
		aimed_direction = to_target.normalized()
		queue_redraw()
		if telegraph_time <= 0.0:
			_fire_shot()
	else:
		fire_timer -= delta
		if fire_timer <= 0.0 and dist < 450.0:
			telegraph_time = TELEGRAPH_DURATION
			aimed_direction = to_target.normalized()
			fire_timer = randf_range(2.0, 3.0)

		# Kiting movement: maintain ideal distance
		if dist < ideal_distance - 40.0:
			# Too close, back away
			velocity = -to_target.normalized() * (move_speed * 1.1)
		elif dist > ideal_distance + 40.0:
			# Too far, advance
			velocity = to_target.normalized() * move_speed
		else:
			# Strafe perpendicular
			var strafe := to_target.orthogonal().normalized()
			velocity = strafe * (move_speed * 0.75)

	move_and_slide()


func _fire_shot() -> void:
	var proj = PROJECTILE_SCENE.instantiate()
	proj.global_position = global_position + aimed_direction * 18.0
	proj.direction = aimed_direction
	get_parent().add_child(proj)
	queue_redraw()


func take_damage(amount: int) -> void:
	if defeated_already:
		return
	health = maxi(0, health - amount)
	if health == 0:
		defeated_already = true
		defeated.emit()
		queue_free()
	else:
		queue_redraw()


func _draw() -> void:
	# Warning laser line when charging attack
	if telegraph_time > 0.0:
		var line_color := Color(1.0, 0.25, 0.2, 0.45 + (1.0 - telegraph_time / TELEGRAPH_DURATION) * 0.55)
		draw_line(Vector2.ZERO, to_local(global_position + aimed_direction * 350.0), line_color, 2.0)

	# Enemy body: Hexagonal/faceted diamond in amber & bronze
	var pts := PackedVector2Array([
		Vector2(16, 0),
		Vector2(6, -13),
		Vector2(-12, -11),
		Vector2(-16, 0),
		Vector2(-12, 11),
		Vector2(6, 13)
	])
	draw_colored_polygon(pts, Color("ff9f43"))
	draw_circle(Vector2(6, 0), 4.0, Color("fff2d6"))

	# Health bar
	var hit_points := float(health) / float(max_health)
	draw_rect(Rect2(-15, -22, 30, 4), Color("331c38"))
	draw_rect(Rect2(-15, -22, 30.0 * hit_points, 4), Color("ffc048"))
