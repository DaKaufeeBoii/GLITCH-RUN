extends CharacterBody2D
## Production-grade cyberpunk pixel-art player with multi-animation state machine,
## aiming blaster weapon pivot, dash ghost trails, and mobile/desktop controls.

signal health_changed(current: int, maximum: int)
signal died
signal dashed
signal damaged(amount: int)

const PROJECTILE_SCENE := preload("res://scenes/weapons/projectile.tscn")
const ASSET_LOADER := preload("res://scripts/asset_loader.gd")

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

# Visual nodes
var anim_sprite: AnimatedSprite2D
var gun_sprite: Sprite2D
var ghost_spawn_timer := 0.0


func _ready() -> void:
	if Engine.has_singleton("RunState") or get_node_or_null("/root/RunState") != null:
		var rs = get_node("/root/RunState")
		max_health = rs.max_health
		health = rs.current_health
		rs.health_updated.connect(_on_runstate_health_updated)
	else:
		health = max_health

	_setup_visual_components()


func _setup_visual_components() -> void:
	var sheet_tex := ASSET_LOADER.load_texture("res://assets/player/player_sheet.png")
	var blaster_tex := ASSET_LOADER.load_texture("res://assets/player/blaster.png")

	var frames := SpriteFrames.new()

	if sheet_tex:
		# 1. Idle (Row 0, 4 frames)
		frames.add_animation("idle")
		frames.set_animation_speed("idle", 6.0)
		frames.set_animation_loop("idle", true)
		for c in range(4):
			frames.add_frame("idle", _make_atlas(sheet_tex, c, 0))

		# 2. Run (Row 1, 6 frames)
		frames.add_animation("run")
		frames.set_animation_speed("run", 10.0)
		frames.set_animation_loop("run", true)
		for c in range(6):
			frames.add_frame("run", _make_atlas(sheet_tex, c, 1))

		# 3. Dash (Row 2, 4 frames)
		frames.add_animation("dash")
		frames.set_animation_speed("dash", 14.0)
		frames.set_animation_loop("dash", false)
		for c in range(4):
			frames.add_frame("dash", _make_atlas(sheet_tex, c, 2))

		# 4. Hurt (Row 3, 4 frames)
		frames.add_animation("hurt")
		frames.set_animation_speed("hurt", 12.0)
		frames.set_animation_loop("hurt", false)
		for c in range(4):
			frames.add_frame("hurt", _make_atlas(sheet_tex, c, 3))

		# 5. Death (Row 4, 6 frames)
		frames.add_animation("death")
		frames.set_animation_speed("death", 8.0)
		frames.set_animation_loop("death", false)
		for c in range(6):
			frames.add_frame("death", _make_atlas(sheet_tex, c, 4))

	anim_sprite = AnimatedSprite2D.new()
	anim_sprite.name = "PlayerSprite"
	anim_sprite.sprite_frames = frames
	anim_sprite.play("idle")
	add_child(anim_sprite)

	# Dedicated Blaster Weapon Sprite
	gun_sprite = Sprite2D.new()
	gun_sprite.name = "Blaster"
	gun_sprite.texture = blaster_tex
	gun_sprite.offset = Vector2(0, 0)
	add_child(gun_sprite)


func _make_atlas(tex: Texture2D, col: int, row: int) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(col * 32, row * 32, 32, 32)
	return at


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

		# Spawn cyber ghost afterimages during dash
		ghost_spawn_timer -= delta
		if ghost_spawn_timer <= 0.0:
			ghost_spawn_timer = 0.035
			_spawn_dash_ghost(rs and rs.dash_damage)

		if rs and rs.dash_damage:
			_apply_dash_damage()
			queue_redraw()
	else:
		velocity = move_input * (MOVE_SPEED * move_mult)
		if not touch_aim.is_zero_approx():
			aim_direction = touch_aim.normalized()
		else:
			var mouse_direction := get_global_mouse_position() - global_position
			if not mouse_direction.is_zero_approx():
				aim_direction = mouse_direction.normalized()

	move_and_slide()

	# Update visual orientation and animation states
	_update_animation_and_weapon(move_input)

	# Input actions
	if (Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_SPACE)) and dash_cooldown <= 0.0:
		try_dash()

	var firing := touch_fire or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_J)
	is_firing = firing
	if firing and fire_cooldown <= 0.0:
		_fire()


func _update_animation_and_weapon(move_input: Vector2) -> void:
	if not is_instance_valid(anim_sprite):
		return

	# Horizontal flip matches aiming direction
	var is_facing_left := aim_direction.x < -0.05
	anim_sprite.flip_h = is_facing_left

	# Position and angle weapon towards aim direction
	if is_instance_valid(gun_sprite):
		var gun_offset := Vector2(-4.0 if is_facing_left else 4.0, 2.0)
		gun_sprite.position = gun_offset + aim_direction * 8.0
		gun_sprite.rotation = aim_direction.angle()
		gun_sprite.flip_v = is_facing_left

	# Damage flash effect
	if damage_cooldown > 0.0:
		var blink := int(damage_cooldown * 18.0) % 2 == 0
		anim_sprite.modulate = Color(1.0, 1.0, 1.0, 0.4) if blink else Color(1.0, 1.0, 1.0, 1.0)
	else:
		anim_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)

	# State-driven animation playback
	if dash_time > 0.0:
		if anim_sprite.animation != "dash":
			anim_sprite.play("dash")
	elif damage_cooldown > 0.5:
		if anim_sprite.animation != "hurt":
			anim_sprite.play("hurt")
	elif move_input.length() > 0.1:
		if anim_sprite.animation != "run":
			anim_sprite.play("run")
	else:
		if anim_sprite.animation != "idle":
			anim_sprite.play("idle")


func _spawn_dash_ghost(has_static_blink: bool) -> void:
	var ghost := Sprite2D.new()
	if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation(anim_sprite.animation):
		var frame_count := anim_sprite.sprite_frames.get_frame_count(anim_sprite.animation)
		if anim_sprite.frame < frame_count:
			ghost.texture = anim_sprite.sprite_frames.get_frame_texture(anim_sprite.animation, anim_sprite.frame)
	ghost.global_position = global_position
	ghost.flip_h = anim_sprite.flip_h
	ghost.z_index = z_index - 1

	var ghost_color := Color("c084fc") if has_static_blink else Color("38bdf8")
	ghost_color.a = 0.55
	ghost.modulate = ghost_color

	get_parent().add_child(ghost)

	var tween := ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, 0.22)
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
	damaged.emit(amount)
	health_changed.emit(health, max_health)
	var rs = get_node_or_null("/root/RunState")
	if rs:
		rs.current_health = health

	if health == 0:
		dead = true
		set_physics_process(false)
		if is_instance_valid(gun_sprite):
			gun_sprite.visible = false
		if is_instance_valid(anim_sprite):
			anim_sprite.play("death")
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
		_spawn_bullet(aim_direction.rotated(-0.08), extra_dmg)
		_spawn_bullet(aim_direction.rotated(0.08), extra_dmg)


func _spawn_bullet(dir: Vector2, extra_dmg: int) -> void:
	var projectile = PROJECTILE_SCENE.instantiate()
	projectile.position = global_position + dir * 18.0
	projectile.direction = dir
	projectile.damage = 1 + extra_dmg
	get_parent().add_child(projectile)


func _draw() -> void:
	var rs = get_node_or_null("/root/RunState")
	if dash_time > 0.0 and rs and rs.dash_damage:
		for i in range(4):
			var a := randf() * TAU
			var p1 := Vector2(cos(a), sin(a)) * 12.0
			var p2 := Vector2(cos(a + 0.3), sin(a + 0.3)) * 32.0
			draw_line(p1, p2, Color("c084fc"), 2.0)
