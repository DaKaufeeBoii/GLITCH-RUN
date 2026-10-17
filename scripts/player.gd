extends CharacterBody3D
## Top-down 3D player controller with twin-stick touch/mouse aiming, dash i-frames, and RunState upgrades.

signal health_changed(current: int, maximum: int)
signal died

const PROJECTILE_SCENE := preload("res://scenes/weapons/projectile.tscn")
const MOVE_SPEED := 11.0
const DASH_SPEED := 32.0
const DASH_DURATION := 0.16
const DASH_COOLDOWN := 0.75
const FIRE_INTERVAL := 0.22

@export var max_health := 5
var health := 5
var aim_direction := Vector3.FORWARD
var current_move_direction := Vector3.ZERO
var touch_move := Vector2.ZERO
var touch_aim := Vector2.ZERO
var touch_fire := false
var dash_time := 0.0
var dash_cooldown := 0.0
var fire_cooldown := 0.0
var damage_cooldown := 0.0
var dead := false

@onready var mesh_body: MeshInstance3D = $MeshBody
@onready var mesh_visor: MeshInstance3D = $MeshBody/MeshVisor


func _ready() -> void:
	if Engine.has_singleton("RunState") or get_node_or_null("/root/RunState") != null:
		var rs = get_node("/root/RunState")
		max_health = rs.max_health
		health = rs.current_health
		rs.health_updated.connect(_on_runstate_health_updated)
	else:
		health = max_health


func _on_runstate_health_updated(curr: int, max_h: int) -> void:
	health = curr
	max_health = max_h
	health_changed.emit(health, max_health)


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

	# Keyboard move (WASD / Arrows)
	var keyboard_move := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	keyboard_move += Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	keyboard_move = keyboard_move.limit_length(1.0)
	var move_2d := (keyboard_move + touch_move).limit_length(1.0)
	var move_3d := Vector3(move_2d.x, 0.0, move_2d.y)
	current_move_direction = move_3d

	if dash_time > 0.0:
		dash_time -= delta
		velocity = aim_direction * DASH_SPEED
		if rs and rs.dash_damage:
			_apply_dash_damage()
	else:
		velocity = move_3d * (MOVE_SPEED * move_mult)
		# Aim calculation
		if not touch_aim.is_zero_approx():
			aim_direction = Vector3(touch_aim.x, 0.0, touch_aim.y).normalized()
		else:
			_update_mouse_aim()

	# Rotate body to face aim direction
	if not aim_direction.is_zero_approx():
		var look_target := global_position + aim_direction
		look_target.y = global_position.y
		look_at(look_target, Vector3.UP)

	move_and_slide()

	# Dash input
	if (Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_SPACE)) and dash_cooldown <= 0.0:
		try_dash()

	# Fire input
	var firing := touch_fire or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_J)
	if firing and fire_cooldown <= 0.0:
		_fire()


func _update_mouse_aim() -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	if abs(ray_dir.y) > 0.001:
		var t := (global_position.y - ray_origin.y) / ray_dir.y
		var hit_pos := ray_origin + ray_dir * t
		var to_hit := hit_pos - global_position
		to_hit.y = 0.0
		if to_hit.length_squared() > 0.04:
			aim_direction = to_hit.normalized()


func set_touch_move(value: Vector2) -> void:
	touch_move = value.limit_length(1.0)


func set_touch_aim(value: Vector2) -> void:
	if not value.is_zero_approx():
		touch_aim = value.normalized()
		if dash_time <= 0.0:
			aim_direction = Vector3(touch_aim.x, 0.0, touch_aim.y).normalized()


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
	var cd_mult := 1.0
	var rs = get_node_or_null("/root/RunState")
	if rs:
		cd_mult = rs.dash_cooldown_mult
	dash_cooldown = DASH_COOLDOWN * cd_mult


func _apply_dash_damage() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and global_position.distance_to(enemy.global_position) < 2.0:
			if enemy.has_method("take_damage"):
				enemy.take_damage(2)


func take_damage(amount: int) -> void:
	if dead or damage_cooldown > 0.0 or dash_time > 0.0:
		return
	health = maxi(0, health - amount)
	damage_cooldown = 0.75
	health_changed.emit(health, max_health)
	var rs = get_node_or_null("/root/RunState")
	if rs:
		rs.current_health = health
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

	if count == 1:
		_spawn_bullet(aim_direction, extra_dmg)
	else:
		_spawn_bullet(aim_direction.rotated(Vector3.UP, -0.09), extra_dmg)
		_spawn_bullet(aim_direction.rotated(Vector3.UP, 0.09), extra_dmg)


func _spawn_bullet(dir: Vector3, extra_dmg: int) -> void:
	var projectile = PROJECTILE_SCENE.instantiate()
	projectile.global_position = global_position + Vector3(0.0, 0.8, 0.0) + dir * 0.9
	projectile.direction = dir
	projectile.damage = 1 + extra_dmg
	get_parent().add_child(projectile)
