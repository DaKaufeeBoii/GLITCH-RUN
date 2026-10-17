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


const PLAYER_SHEET := preload("res://assets/Tech Dungeon Roguelite - Asset Pack (DEMO)/Players/players blue x1.png")

var anim_sprite: AnimatedSprite2D
var gun_sprite: Sprite2D


func _ready() -> void:
	_setup_sprites()
	if Engine.has_singleton("RunState") or get_node_or_null("/root/RunState") != null:
		var rs = get_node("/root/RunState")
		max_health = rs.max_health
		health = rs.current_health
		rs.health_updated.connect(_on_runstate_health_updated)
	else:
		health = max_health


func _setup_sprites() -> void:
	var sf := SpriteFrames.new()

	# Idle animation (1 frame)
	sf.add_animation("idle")
	sf.set_animation_loop("idle", true)
	sf.set_animation_speed("idle", 4.0)
	var idle_tex := AtlasTexture.new()
	idle_tex.atlas = PLAYER_SHEET
	idle_tex.region = Rect2(0, 0, 32, 32)
	sf.add_frame("idle", idle_tex)

	# Run animation (5 frames)
	sf.add_animation("run")
	sf.set_animation_loop("run", true)
	sf.set_animation_speed("run", 10.0)
	for c in range(5):
		var run_tex := AtlasTexture.new()
		run_tex.atlas = PLAYER_SHEET
		run_tex.region = Rect2(c * 32, 2 * 32, 32, 32)
		sf.add_frame("run", run_tex)

	# Dash / Dodge roll animation (4 frames)
	sf.add_animation("dash")
	sf.set_animation_loop("dash", true)
	sf.set_animation_speed("dash", 14.0)
	for c in range(4):
		var dash_tex := AtlasTexture.new()
		dash_tex.atlas = PLAYER_SHEET
		dash_tex.region = Rect2(c * 32, 3 * 32, 32, 32)
		sf.add_frame("dash", dash_tex)

	# Hurt / Hit animation (3 frames)
	sf.add_animation("hurt")
	sf.set_animation_loop("hurt", false)
	sf.set_animation_speed("hurt", 9.0)
	for c in range(3):
		var hurt_tex := AtlasTexture.new()
		hurt_tex.atlas = PLAYER_SHEET
		hurt_tex.region = Rect2(c * 32, 4 * 32, 32, 32)
		sf.add_frame("hurt", hurt_tex)

	# Death / Dissolve animation (7 frames)
	sf.add_animation("death")
	sf.set_animation_loop("death", false)
	sf.set_animation_speed("death", 11.0)
	for c in range(7):
		var death_tex := AtlasTexture.new()
		death_tex.atlas = PLAYER_SHEET
		death_tex.region = Rect2(c * 32, 5 * 32, 32, 32)
		sf.add_frame("death", death_tex)

	anim_sprite = AnimatedSprite2D.new()
	anim_sprite.sprite_frames = sf
	anim_sprite.animation = "idle"
	anim_sprite.position = Vector2(0, -2)
	add_child(anim_sprite)
	anim_sprite.play("idle")

	# Rotating blaster weapon
	var gun_tex := AtlasTexture.new()
	gun_tex.atlas = PLAYER_SHEET
	gun_tex.region = Rect2(32, 0, 32, 32)
	gun_sprite = Sprite2D.new()
	gun_sprite.texture = gun_tex
	gun_sprite.offset = Vector2(10, 0)
	add_child(gun_sprite)


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

	move_and_slide()

	# Keep character upright and flip sprite based on aiming
	anim_sprite.flip_h = (aim_direction.x < 0)
	gun_sprite.rotation = aim_direction.angle()
	gun_sprite.flip_v = (aim_direction.x < 0)

	# Animation selection
	if dash_time > 0.0:
		if anim_sprite.animation != "dash":
			anim_sprite.play("dash")
	elif damage_cooldown > 0.45:
		if anim_sprite.animation != "hurt":
			anim_sprite.play("hurt")
	elif current_move_direction.length_squared() > 0.05:
		if anim_sprite.animation != "run":
			anim_sprite.play("run")
	else:
		if anim_sprite.animation != "idle":
			anim_sprite.play("idle")

	# Visual effects during dash / hurt
	if damage_cooldown > 0.0:
		anim_sprite.modulate = Color(1.0, 0.4, 0.4, 0.7) if int(damage_cooldown * 14.0) % 2 == 0 else Color.WHITE
	elif dash_time > 0.0:
		anim_sprite.modulate = Color(0.7, 0.9, 1.0, 0.8)
	else:
		anim_sprite.modulate = Color.WHITE

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
	var cd_mult := 1.0
	var rs = get_node_or_null("/root/RunState")
	if rs:
		cd_mult = rs.dash_cooldown_mult
	dash_cooldown = DASH_COOLDOWN * cd_mult


func _apply_dash_damage() -> void:
	# Deal contact shock damage to nearby enemies during static blink
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and global_position.distance_to(enemy.global_position) < 38.0:
			if enemy.has_method("take_damage"):
				enemy.take_damage(2)


func take_damage(amount: int) -> void:
	# i-frames during dash or invulnerability cooldown
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
		anim_sprite.play("death")
		gun_sprite.visible = false
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
		# Twin spread shot
		_spawn_bullet(aim_direction.rotated(-0.08), extra_dmg)
		_spawn_bullet(aim_direction.rotated(0.08), extra_dmg)


func _spawn_bullet(dir: Vector2, extra_dmg: int) -> void:
	var projectile = PROJECTILE_SCENE.instantiate()
	projectile.position = global_position + dir * 22.0
	projectile.direction = dir
	projectile.damage = 1 + extra_dmg
	get_parent().add_child(projectile)

