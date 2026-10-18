extends CharacterBody2D
## Geometric cyberpunk operative with twin-stick movement, dynamic dash, and precision aiming.

signal health_changed(current: int, maximum: int)
signal died
signal dashed
signal damaged(amount: int)

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
var is_firing := false

var ghost_spawn_timer := 0.0


func _ready() -> void:
	add_to_group("player")
	if Engine.has_singleton("RunState") or get_node_or_null("/root/RunState") != null:
		var rs = get_node("/root/RunState")
		max_health = rs.max_health
		health = rs.current_health
		rs.health_updated.connect(_on_runstate_health_updated)
	else:
		health = max_health
	queue_redraw()


func _on_runstate_health_updated(curr: int, max_h: int) -> void:
	health = curr
	max_health = max_h
	health_changed.emit(health, max_health)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if dead:
		return

	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	damage_cooldown = maxf(0.0, damage_cooldown - delta)
	fire_cooldown = maxf(0.0, fire_cooldown - delta)

	var move_mult := 1.0
	var rs = get_node_or_null("/root/RunState")
	if rs:
		move_mult = rs.move_speed_mult

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

		ghost_spawn_timer -= delta
		if ghost_spawn_timer <= 0.0:
			ghost_spawn_timer = 0.035
			_spawn_dash_ghost(rs and rs.dash_damage)

		if rs and rs.dash_damage:
			_apply_dash_damage()
	else:
		velocity = move_input * (MOVE_SPEED * move_mult)
		if not touch_aim.is_zero_approx():
			aim_direction = touch_aim.normalized()
		else:
			var mouse_direction := get_global_mouse_position() - global_position
			if not mouse_direction.is_zero_approx():
				aim_direction = mouse_direction.normalized()

	rotation = aim_direction.angle()
	move_and_slide()
	queue_redraw()

	if (Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_SPACE)) and dash_cooldown <= 0.0:
		try_dash()

	var firing := touch_fire or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_J) or Input.is_key_pressed(KEY_K)
	is_firing = firing
	if firing and fire_cooldown <= 0.0:
		_fire()


func _spawn_dash_ghost(has_static_blink: bool) -> void:
	var ghost := Node2D.new()
	ghost.global_position = global_position
	ghost.rotation = rotation
	ghost.z_index = z_index - 1
	var ghost_color := Color("c084fc") if has_static_blink else Color("38bdf8")
	ghost_color.a = 0.55
	ghost.modulate = ghost_color

	# Custom draw for ghost polygon
	var poly := PackedVector2Array([Vector2(17, 0), Vector2(-11, -11), Vector2(-7, 0), Vector2(-11, 11)])
	ghost.draw.connect(func(): ghost.draw_colored_polygon(poly, Color.WHITE))

	get_parent().add_child(ghost)

	var tween := ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, 0.2)
	tween.tween_callback(Callable(ghost, "queue_free"))


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
	ghost_spawn_timer = 0.0
	var cd_mult := 1.0
	var rs = get_node_or_null("/root/RunState")
	if rs:
		cd_mult = rs.dash_cooldown_mult
	dash_cooldown = DASH_COOLDOWN * cd_mult
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("dash", 0.05, -2.0)
	dashed.emit()


func _apply_dash_damage() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and global_position.distance_to(enemy.global_position) < 42.0:
			if enemy.has_method("take_damage"):
				enemy.take_damage(2)


func take_damage(amount: int) -> void:
	if dead or damage_cooldown > 0.0 or dash_time > 0.0:
		return
	health = maxi(0, health - amount)
	damage_cooldown = 0.75
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("player_hurt", 0.05, 0.0)
	damaged.emit(amount)
	health_changed.emit(health, max_health)
	var rs = get_node_or_null("/root/RunState")
	if rs:
		rs.current_health = health
	queue_redraw()

	if health == 0:
		dead = true
		set_physics_process(false)
		died.emit()


func _fire() -> void:
	var interval_mult := 1.0
	var extra_dmg := 0
	var count := 1
	var rs = get_node_or_null("/root/RunState")
	if rs:
		interval_mult = rs.fire_interval_mult
		extra_dmg = rs.damage_bonus
		count = rs.projectile_count

	fire_cooldown = FIRE_INTERVAL * interval_mult
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("blaster", 0.08, -3.0)

	if count == 1:
		_spawn_bullet(aim_direction, extra_dmg)
	else:
		_spawn_bullet(aim_direction.rotated(-0.10), extra_dmg)
		_spawn_bullet(aim_direction.rotated(0.10), extra_dmg)


func _spawn_bullet(dir: Vector2, extra_dmg: int) -> void:
	var shoot_dir := dir.normalized()
	if shoot_dir.is_zero_approx():
		shoot_dir = Vector2.RIGHT

	var projectile = PROJECTILE_SCENE.instantiate()
	# Spawn clear of player collision shape (radius 13 + bullet 5 = 18; using 24.0)
	projectile.global_position = global_position + shoot_dir * 24.0
	projectile.direction = shoot_dir
	projectile.damage = 1 + extra_dmg
	get_parent().add_child(projectile)


func _draw() -> void:
	var body_color := Color("38bdf8") # Sleek cyber cyan
	if dash_time > 0.0:
		body_color = Color("c084fc") # Dynamic purple during invulnerable dash
	elif damage_cooldown > 0.0 and int(damage_cooldown * 14.0) % 2 == 0:
		body_color = Color("ffffff") # Crisp damage flash blink

	# Primary aerodynamic geometric arrow polygon
	var pts := PackedVector2Array([
		Vector2(17, 0),
		Vector2(-11, -11),
		Vector2(-7, 0),
		Vector2(-11, 11)
	])
	draw_colored_polygon(pts, body_color)
	draw_polyline(PackedVector2Array([Vector2(17, 0), Vector2(-11, -11), Vector2(-7, 0), Vector2(-11, 11), Vector2(17, 0)]), body_color.lightened(0.35), 1.2)

	# Twin rail blaster barrels
	draw_line(Vector2(-1, -7), Vector2(13, -7), Color("1e293b"), 2.2)
	draw_line(Vector2(-1, 7), Vector2(13, 7), Color("1e293b"), 2.2)
	draw_circle(Vector2(13, -7), 1.5, body_color)
	draw_circle(Vector2(13, 7), 1.5, body_color)

	# Cockpit / visor targeting line
	draw_line(Vector2(5, 0), Vector2(16, 0), Color("ffffff"), 1.8)

	# Central glowing energy core
	draw_circle(Vector2(-2, 0), 3.5, Color("e0f2fe"))
	draw_circle(Vector2(-2, 0), 2.0, Color("ffffff"))

	# Electric discharge during static blink dash damage
	var rs = get_node_or_null("/root/RunState")
	if dash_time > 0.0 and rs and rs.dash_damage:
		for i in range(4):
			var a := randf() * TAU
			var p1 := Vector2(cos(a), sin(a)) * 12.0
			var p2 := Vector2(cos(a + 0.3), sin(a + 0.3)) * 32.0
			draw_line(p1, p2, Color("c084fc"), 2.0)
