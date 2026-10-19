extends CharacterBody2D
## Geometric cyberpunk operative with twin-stick movement, dynamic dash, and precision aiming.

signal health_changed(current: int, maximum: int)
signal died
signal dashed
signal damaged(amount: int)
signal shot_fired
signal ammo_changed(current: int, maximum: int, is_reloading: bool)
@warning_ignore("unused_signal")
signal shot_hit(enemy: Node2D)

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

# Player Ammo Battery System
@export var base_max_ammo := 16
var current_ammo := 16
var is_reloading := false
var reload_timer := 0.0
var base_reload_duration := 1.1

# Status Effect Debuffs
var debuff_slow_timer := 0.0
var debuff_burn_timer := 0.0
var debuff_burn_tick := 0.0

var ghost_spawn_timer := 0.0
var visual_clock := 0.0
var muzzle_flash_timer := 0.0
var has_aegis_shield := false
var has_speed_overdrive := false


func _ready() -> void:
	add_to_group("player")
	if Engine.has_singleton("RunState") or get_node_or_null("/root/RunState") != null:
		var rs = get_node("/root/RunState")
		max_health = rs.max_health
		health = rs.current_health
		rs.health_updated.connect(_on_runstate_health_updated)
	else:
		health = max_health
	current_ammo = get_max_ammo()
	ammo_changed.emit(current_ammo, get_max_ammo(), false)
	queue_redraw()


func get_max_ammo() -> int:
	var bonus := 0
	var rs = get_node_or_null("/root/RunState")
	if rs and "max_ammo_bonus" in rs:
		bonus = rs.max_ammo_bonus
	return base_max_ammo + bonus


func get_reload_time() -> float:
	var mult := 1.0
	var rs = get_node_or_null("/root/RunState")
	if rs and "reload_speed_mult" in rs:
		mult = rs.reload_speed_mult
	return maxf(0.35, base_reload_duration * mult)


func start_reload() -> void:
	if dead or is_reloading:
		return
	if current_ammo >= get_max_ammo():
		return
	is_reloading = true
	reload_timer = get_reload_time()
	ammo_changed.emit(current_ammo, get_max_ammo(), true)
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("player_hurt", 0.03, 8.0)
	queue_redraw()


func apply_debuff(type: String, duration: float, _intensity: float = 1.0) -> void:
	match type:
		"CRYO", "SLOW":
			debuff_slow_timer = maxf(debuff_slow_timer, duration)
		"ACID", "BURN":
			debuff_burn_timer = maxf(debuff_burn_timer, duration)
			debuff_burn_tick = 0.5
		"SHOCK":
			debuff_slow_timer = maxf(debuff_slow_timer, duration * 0.5)
	queue_redraw()


func _on_runstate_health_updated(curr: int, max_h: int) -> void:
	health = curr
	max_health = max_h
	health_changed.emit(health, max_health)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if dead:
		return
	visual_clock += delta
	muzzle_flash_timer = maxf(0.0, muzzle_flash_timer - delta)

	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	damage_cooldown = maxf(0.0, damage_cooldown - delta)
	fire_cooldown = maxf(0.0, fire_cooldown - delta)

	# Debuff status tracking
	if debuff_slow_timer > 0.0:
		debuff_slow_timer = maxf(0.0, debuff_slow_timer - delta)

	if debuff_burn_timer > 0.0:
		debuff_burn_timer = maxf(0.0, debuff_burn_timer - delta)
		debuff_burn_tick -= delta
		if debuff_burn_tick <= 0.0:
			debuff_burn_tick = 1.0
			take_damage(1)

	# Ammo Reload Management
	if is_reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			is_reloading = false
			current_ammo = get_max_ammo()
			ammo_changed.emit(current_ammo, get_max_ammo(), false)
			if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
				get_node("/root/AudioSynth").play("powerup_pickup", 0.05, 5.0)

	var move_mult := 1.0
	var rs = get_node_or_null("/root/RunState")
	if rs:
		move_mult = rs.move_speed_mult
	if debuff_slow_timer > 0.0:
		move_mult *= 0.55

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
	if dash_time > 0.0:
		for i in range(get_slide_collision_count()):
			var col := get_slide_collision(i)
			var collider := col.get_collider()
			if collider and collider.is_in_group("secret_walls") and collider.has_method("take_damage"):
				collider.take_damage(1, "dash")
	queue_redraw()

	if (Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_SPACE)) and dash_cooldown <= 0.0:
		try_dash()

	# Manual reload input (R key)
	if Input.is_key_pressed(KEY_R) and not is_reloading and current_ammo < get_max_ammo():
		start_reload()

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
		# Tactical Reload upgrade perk: instant full reload on dash
		if bool(rs.get("has_tactical_reload")):
			current_ammo = get_max_ammo()
			is_reloading = false
			ammo_changed.emit(current_ammo, get_max_ammo(), false)

	dash_cooldown = DASH_COOLDOWN * cd_mult
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("dash", 0.05, -2.0)
	var sm: Node = get_node_or_null("/root/Settings") if is_inside_tree() else null
	if sm and sm.has_method("trigger_haptic"):
		sm.trigger_haptic(35)
	dashed.emit()


func _apply_dash_damage() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and global_position.distance_to(enemy.global_position) < 42.0:
			if enemy.has_method("take_damage"):
				enemy.take_damage(2)
				var game_node = get_parent()
				if game_node and game_node.has_method("spawn_damage_number"):
					game_node.spawn_damage_number(enemy.global_position, "2", Color("c084fc"))


func take_damage(amount: int) -> void:
	if dead or damage_cooldown > 0.0 or dash_time > 0.0:
		return
	if has_aegis_shield:
		has_aegis_shield = false
		damage_cooldown = 0.65
		_trigger_emp_shockwave()
		var game_node = get_parent()
		if game_node and game_node.has_method("spawn_damage_number"):
			game_node.spawn_damage_number(global_position, "AEGIS DEFLECTED!", Color("818cf8"))
		if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
			get_node("/root/AudioSynth").play("bullet_hit", 0.05, 3.0)
		queue_redraw()
		return
	health = maxi(0, health - amount)
	if is_inside_tree():
		if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
			get_node("/root/AudioSynth").play("player_hurt", 0.05, 0.0)
		var sm_hurt: Node = get_node_or_null("/root/Settings")
		if sm_hurt and sm_hurt.has_method("trigger_haptic"):
			sm_hurt.trigger_haptic(75)
	damaged.emit(amount)
	health_changed.emit(health, max_health)
	var rs = get_node_or_null("/root/RunState") if is_inside_tree() else null
	if rs:
		rs.current_health = health
		# Reactive Plating Perk: Trigger EMP shockwave
		if bool(rs.get("has_reactive_plating")):
			_trigger_emp_shockwave()

	queue_redraw()

	if health == 0:
		dead = true
		set_physics_process(false)
		died.emit()


func _trigger_emp_shockwave() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			var dist := global_position.distance_to(enemy.global_position)
			if dist < 140.0:
				var push_dir: Vector2 = (enemy.global_position - global_position).normalized()
				if "velocity" in enemy:
					enemy.velocity += push_dir * 380.0
				if enemy.has_method("apply_debuff"):
					enemy.apply_debuff("SHOCK", 1.0)
				if enemy.has_method("take_damage"):
					enemy.take_damage(1)


func _fire() -> void:
	if is_reloading:
		return
	if current_ammo <= 0:
		if is_inside_tree() and (Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth")):
			get_node("/root/AudioSynth").play("empty_ammo", 0.05, -3.0)
		start_reload()
		return

	var interval_mult := 1.0
	var extra_dmg := 0
	var count := 1
	var rs = get_node_or_null("/root/RunState")
	if rs:
		interval_mult = rs.fire_interval_mult
		extra_dmg = rs.damage_bonus
		count = rs.projectile_count
		# Overdrive Protocol perk: +50% dmg & +25% fire rate if at or below 2 HP
		if bool(rs.get("has_overdrive_protocol")) and health <= 2:
			extra_dmg += 1
			interval_mult *= 0.75

	fire_cooldown = FIRE_INTERVAL * interval_mult
	current_ammo -= 1
	ammo_changed.emit(current_ammo, get_max_ammo(), false)
	if current_ammo <= 0:
		start_reload()

	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("blaster", 0.08, -3.0)
	muzzle_flash_timer = 0.075

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
	projectile.set("player_source", self)

	# Pass elemental debuffs and piercing traits from active upgrades
	var rs = get_node_or_null("/root/RunState")
	if rs:
		if bool(rs.get("has_cryo_rounds")):
			projectile.set("debuff_type", "CRYO")
		elif bool(rs.get("has_acid_plasma")):
			projectile.set("debuff_type", "ACID")
		elif bool(rs.get("has_arc_discharge")):
			projectile.set("debuff_type", "SHOCK")
		if bool(rs.get("has_piercing_beam")):
			projectile.set("is_piercing", true)

	get_parent().add_child(projectile)
	shot_fired.emit()


func _draw() -> void:
	# Subtle engine glow and idle core pulse make the operative feel powered-on.
	var engine_pulse := 0.65 + (sin(visual_clock * 8.0) + 1.0) * 0.16
	draw_circle(Vector2(-11, 0), 5.0 + engine_pulse, Color(0.05, 0.82, 1.0, 0.10 + engine_pulse * 0.07))
	draw_circle(Vector2(-11, 0), 2.0 + engine_pulse * 0.45, Color(0.18, 0.88, 1.0, 0.5))
	if muzzle_flash_timer > 0.0:
		var flash_alpha := muzzle_flash_timer / 0.075
		draw_circle(Vector2(19, 0), 5.0 + 5.0 * flash_alpha, Color(0.55, 0.92, 1.0, 0.3 * flash_alpha))
		draw_line(Vector2(15, 0), Vector2(25 + 5 * flash_alpha, 0), Color(1, 1, 1, flash_alpha), 2.0)

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

	# Reload Progress Arc
	if is_reloading:
		var total_t := get_reload_time()
		var pct := 1.0 - (reload_timer / total_t)
		draw_arc(Vector2(0, -20), 8.0, -PI * 0.5, -PI * 0.5 + pct * TAU, 16, Color("f59e0b"), 2.2)
		draw_circle(Vector2(0, -20), 2.0, Color("fffbeb"))

	# Debuff Shimmer Rings
	if debuff_slow_timer > 0.0:
		draw_circle(Vector2.ZERO, 19.0, Color(0.2, 0.8, 1.0, 0.22))
	if debuff_burn_timer > 0.0:
		draw_circle(Vector2.ZERO, 17.0, Color(0.5, 1.0, 0.2, 0.22))

	# Neural Aegis Shield: Rotating energetic hex-barrier and orbital sparks
	if has_aegis_shield:
		var ticks := Time.get_ticks_msec()
		var rot_ang := float(ticks) * 0.003
		var shield_col := Color("818cf8")
		var s_pts := PackedVector2Array()
		for i in range(6):
			var a := rot_ang + float(i) * TAU / 6.0
			s_pts.append(Vector2(cos(a), sin(a)) * 26.0)
		var s_closed := PackedVector2Array(s_pts)
		s_closed.append(s_pts[0])
		draw_polyline(s_closed, shield_col, 2.0)
		draw_colored_polygon(s_pts, Color(shield_col.r, shield_col.g, shield_col.b, 0.15))
		for i in range(3):
			var a := -rot_ang * 1.6 + float(i) * TAU / 3.0
			draw_circle(Vector2(cos(a), sin(a)) * 30.0, 2.5, Color.WHITE)

	# Thruster Overdrive: Dynamic jet streams when moving
	if has_speed_overdrive and not velocity.is_zero_approx():
		var back_dir := -velocity.normalized()
		draw_line(Vector2(-11, -7), Vector2(-11, -7) + back_dir * 18.0, Color("00f0ff"), 2.2)
		draw_line(Vector2(-11, 7), Vector2(-11, 7) + back_dir * 18.0, Color("00f0ff"), 2.2)
		draw_circle(Vector2(-11, -7) + back_dir * 8.0, 2.0, Color.WHITE)
		draw_circle(Vector2(-11, 7) + back_dir * 8.0, 2.0, Color.WHITE)
