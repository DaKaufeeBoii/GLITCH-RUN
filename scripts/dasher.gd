extends CharacterBody2D
## Fast interceptor drone shaped as an aggressive magenta chevron with high-speed lunge and hazard trails.

signal defeated

const HAZARD_SCENE := preload("res://scenes/weapons/hazard_node.tscn")

@export var max_health := 2
@export var patrol_speed := 95.0
@export var lunge_speed := 560.0
@export var has_hazard_trail := false

var health := 2
var target: Node2D
var defeated_already := false

enum State { STALK, TELEGRAPH, LUNGE, RECOVER }
var state := State.STALK

var state_timer := 1.2
var lunge_direction := Vector2.RIGHT
var contact_dealt := false
var damage_flash := 0.0
var hazard_timer := 0.0


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	state_timer = randf_range(1.0, 2.0)
	queue_redraw()


func _physics_process(delta: float) -> void:
	damage_flash = maxf(0.0, damage_flash - delta)

	if not is_instance_valid(target):
		return

	var to_target := target.global_position - global_position
	state_timer -= delta

	match state:
		State.STALK:
			rotation = to_target.angle()
			velocity = to_target.normalized() * patrol_speed
			if state_timer <= 0.0 and to_target.length() < 300.0:
				state = State.TELEGRAPH
				state_timer = 0.55
				lunge_direction = to_target.normalized()
				velocity = Vector2.ZERO
				queue_redraw()

		State.TELEGRAPH:
			velocity = Vector2.ZERO
			queue_redraw()
			if state_timer <= 0.0:
				state = State.LUNGE
				state_timer = 0.28
				contact_dealt = false
				hazard_timer = 0.0

		State.LUNGE:
			velocity = lunge_direction * lunge_speed
			rotation = lunge_direction.angle()
			if not contact_dealt and to_target.length() < 32.0:
				if target.has_method("take_damage"):
					target.take_damage(1)
					contact_dealt = true

			# Drop electric hazard nodes along the lunge path
			if has_hazard_trail:
				hazard_timer -= delta
				if hazard_timer <= 0.0:
					hazard_timer = 0.05
					_drop_hazard()

			if state_timer <= 0.0:
				state = State.RECOVER
				state_timer = 0.65
				velocity = Vector2.ZERO

		State.RECOVER:
			velocity = Vector2.ZERO
			rotation = to_target.angle()
			if state_timer <= 0.0:
				state = State.STALK
				state_timer = randf_range(1.4, 2.2)

	if is_inside_tree():
		move_and_slide()
	queue_redraw()


func _drop_hazard() -> void:
	if not get_parent():
		return
	var hz = HAZARD_SCENE.instantiate()
	hz.global_position = global_position
	get_parent().add_child(hz)


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
	# Warning trajectory during telegraph
	if state == State.TELEGRAPH:
		var pulse := 0.4 + sin(state_timer * 25.0) * 0.3
		var line_color := Color(1.0, 0.1, 0.5, pulse) if not has_hazard_trail else Color(1.0, 0.2, 0.7, pulse + 0.2)
		draw_line(Vector2.ZERO, to_local(global_position + lunge_direction * 220.0), line_color, 3.0)
		if has_hazard_trail:
			draw_line(Vector2.ZERO, to_local(global_position + lunge_direction * 220.0), Color(1.0, 0.9, 1.0, pulse * 0.7), 1.0)

	# Dynamic color based on combat state
	var body_color := Color("d946ef")
	if damage_flash > 0.0:
		body_color = Color("ffffff")
	elif state == State.TELEGRAPH:
		body_color = Color("f472b6")
	elif state == State.LUNGE:
		body_color = Color("ef4444")
	elif state == State.RECOVER:
		body_color = Color("831843")

	# Aggressive geometric chevron polygon
	var pts := PackedVector2Array([
		Vector2(16, 0),
		Vector2(-12, -13),
		Vector2(-4, 0),
		Vector2(-12, 13)
	])
	draw_colored_polygon(pts, body_color)
	draw_polyline(PackedVector2Array([
		Vector2(16, 0),
		Vector2(-12, -13),
		Vector2(-4, 0),
		Vector2(-12, 13),
		Vector2(16, 0)
	]), body_color.lightened(0.35), 1.5)

	# Evolved hazard trail capacitors on wingtips
	if has_hazard_trail:
		draw_circle(Vector2(-12, -13), 2.5, Color("f472b6"))
		draw_circle(Vector2(-12, 13), 2.5, Color("f472b6"))
		draw_circle(Vector2(-12, -13), 1.2, Color("ffffff"))
		draw_circle(Vector2(-12, 13), 1.2, Color("ffffff"))

	# Thruster flare during lunge
	if state == State.LUNGE:
		var flame := PackedVector2Array([
			Vector2(-4, 0),
			Vector2(-14, -5),
			Vector2(-22, 0),
			Vector2(-14, 5)
		])
		draw_colored_polygon(flame, Color("fbcfe8"))

	# Health bar
	if health < max_health:
		var hit_points := float(health) / float(max_health)
		draw_rect(Rect2(-12, -18, 24, 3), Color("181a26"))
		draw_rect(Rect2(-11, -17, 22.0 * hit_points, 2), Color("ec4899"))
