extends CharacterBody2D
## Fast, aggressive enemy that charges with a telegraphed lunge and stalls on recovery.

signal defeated

@export var max_health := 2
@export var patrol_speed := 95.0
@export var lunge_speed := 560.0

var health := 2
var target: Node2D
var defeated_already := false

enum State { STALK, TELEGRAPH, LUNGE, RECOVER }
var state := State.STALK

var state_timer := 1.2
var lunge_direction := Vector2.RIGHT
var contact_dealt := false


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	state_timer = randf_range(1.0, 2.0)


func _physics_process(delta: float) -> void:
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

		State.LUNGE:
			velocity = lunge_direction * lunge_speed
			rotation = lunge_direction.angle()
			if not contact_dealt and to_target.length() < 32.0:
				if target.has_method("take_damage"):
					target.take_damage(1)
					contact_dealt = true
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

	move_and_slide()


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
	# Warning trajectory during telegraph
	if state == State.TELEGRAPH:
		var pulse := 0.4 + sin(state_timer * 25.0) * 0.3
		draw_line(Vector2.ZERO, to_local(global_position + lunge_direction * 220.0), Color(1.0, 0.1, 0.4, pulse), 3.0)

	# Body shape: aggressive magenta chevron
	var body_color := Color("f368e0")
	if state == State.TELEGRAPH:
		body_color = Color("ff9ff3")
	elif state == State.LUNGE:
		body_color = Color("ff3838")
	elif state == State.RECOVER:
		body_color = Color("833471")

	var pts := PackedVector2Array([
		Vector2(16, 0),
		Vector2(-12, -13),
		Vector2(-4, 0),
		Vector2(-12, 13)
	])
	draw_colored_polygon(pts, body_color)

	# Health bar
	var hit_points := float(health) / float(max_health)
	draw_rect(Rect2(-12, -18, 24, 3), Color("331c38"))
	draw_rect(Rect2(-12, -18, 24.0 * hit_points, 3), Color("ff6b81"))
