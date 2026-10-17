extends CharacterBody2D
## Keyboard/mouse player controls with matching virtual touch controls.

signal health_changed(current: int, maximum: int)
signal died

const PROJECTILE_SCENE := preload("res://scenes/weapons/projectile.tscn")
const MOVE_SPEED := 245.0
const DASH_SPEED := 720.0
const DASH_DURATION := 0.14
const DASH_COOLDOWN := 0.8
const FIRE_INTERVAL := 0.22

@export var max_health := 5
var health := 5
var aim_direction := Vector2.RIGHT
var current_move_direction := Vector2.ZERO
var touch_move := Vector2.ZERO
var touch_aim := Vector2.ZERO
var touch_fire := false
var dash_time := 0.0
var dash_cooldown := 0.0
var fire_cooldown := 0.0
var damage_cooldown := 0.0
var dead := false


func _ready() -> void:
	health = max_health
	queue_redraw()


func _physics_process(delta: float) -> void:
	if dead:
		return
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	damage_cooldown = maxf(0.0, damage_cooldown - delta)
	fire_cooldown = maxf(0.0, fire_cooldown - delta)

	var keyboard_move := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	keyboard_move += Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	keyboard_move = keyboard_move.limit_length(1.0)
	var move_input := (keyboard_move + touch_move).limit_length(1.0)
	current_move_direction = move_input
	if dash_time > 0.0:
		dash_time -= delta
		velocity = aim_direction * DASH_SPEED
	else:
		velocity = move_input * MOVE_SPEED
		if not touch_aim.is_zero_approx():
			aim_direction = touch_aim.normalized()
		else:
			var mouse_direction := get_global_mouse_position() - global_position
			if not mouse_direction.is_zero_approx():
				aim_direction = mouse_direction.normalized()
	rotation = aim_direction.angle()
	move_and_slide()

	if (Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_SPACE)) and dash_cooldown <= 0.0:
		try_dash()
	var firing := touch_fire or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_J)
	if firing and fire_cooldown <= 0.0:
		_fire()


func set_touch_move(value: Vector2) -> void:
	touch_move = value.limit_length(1.0)


func set_touch_aim(value: Vector2) -> void:
	if not value.is_zero_approx():
		touch_aim = value.normalized()
		if dash_time <= 0.0:
			aim_direction = touch_aim


func set_touch_fire(value: bool) -> void:
	touch_fire = value
	if not value:
		touch_aim = Vector2.ZERO


func try_dash() -> void:
	if dead or dash_cooldown > 0.0:
		return
	if not current_move_direction.is_zero_approx():
		aim_direction = current_move_direction.normalized()
	dash_time = DASH_DURATION
	dash_cooldown = DASH_COOLDOWN


func take_damage(amount: int) -> void:
	if dead or damage_cooldown > 0.0:
		return
	health = maxi(0, health - amount)
	damage_cooldown = 0.75
	health_changed.emit(health, max_health)
	queue_redraw()
	if health == 0:
		dead = true
		set_physics_process(false)
		died.emit()


func _fire() -> void:
	fire_cooldown = FIRE_INTERVAL
	var projectile = PROJECTILE_SCENE.instantiate()
	projectile.position = global_position + aim_direction * 20.0
	projectile.direction = aim_direction
	get_parent().add_child(projectile)


func _draw() -> void:
	var body_color := Color("42d9ec") if damage_cooldown <= 0.0 or int(damage_cooldown * 14.0) % 2 == 0 else Color("f4fbff")
	draw_colored_polygon(PackedVector2Array([Vector2(17, 0), Vector2(-11, -11), Vector2(-7, 0), Vector2(-11, 11)]), body_color)
	draw_circle(Vector2.ZERO, 3.0, Color("f4fbff"))

