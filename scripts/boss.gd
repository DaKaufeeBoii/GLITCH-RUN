extends CharacterBody2D
## Final Boss: NEXUS OVERLORD. Multi-phase biomechanical singularity core with
## rotating orbital defense pods, radial bursts, and crushing dash attacks.

signal defeated
signal health_changed(curr: int, max_h: int)

const PROJECTILE_SCENE := preload("res://scenes/weapons/enemy_projectile.tscn")
const ASSET_LOADER := preload("res://scripts/asset_loader.gd")

@export var max_health := 35
var health := 35
var target: Node2D
var defeated_already := false

enum AttackPhase { IDLE, CHARGING_BURST, CHARGING_DASH, DASHING, RECOVER }
var current_phase := AttackPhase.IDLE
var phase_timer := 2.0
var orbital_angle := 0.0
var dash_target_dir := Vector2.ZERO
var damage_flash := 0.0

var anim_sprite: AnimatedSprite2D
var orbital_drones: Array[Sprite2D] = []


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	add_to_group("boss")
	phase_timer = 2.0
	_setup_visuals()


func _setup_visuals() -> void:
	var tex := ASSET_LOADER.load_texture("res://assets/enemies/boss_sheet.png")
	var drone_tex := ASSET_LOADER.load_texture("res://assets/enemies/boss_drone.png")
	var frames := SpriteFrames.new()

	# Idle core pulse (Frames 0 and 1)
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 4.0)
	frames.set_animation_loop("idle", true)

	if tex:
		for i in range(2):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * 64, 0, 64, 64)
			frames.add_frame("idle", at)

		# Burst power surge (Frame 2)
		frames.add_animation("surge")
		frames.set_animation_speed("surge", 6.0)
		var at_s := AtlasTexture.new()
		at_s.atlas = tex
		at_s.region = Rect2(2 * 64, 0, 64, 64)
		frames.add_frame("surge", at_s)

		# Overload dash (Frame 3)
		frames.add_animation("overload")
		frames.set_animation_speed("overload", 6.0)
		var at_o := AtlasTexture.new()
		at_o.atlas = tex
		at_o.region = Rect2(3 * 64, 0, 64, 64)
		frames.add_frame("overload", at_o)

	anim_sprite = AnimatedSprite2D.new()
	anim_sprite.sprite_frames = frames
	anim_sprite.play("idle")
	add_child(anim_sprite)

	# 3 Floating Autonomous Orbital Defense Drones
	for i in range(3):
		var drone := Sprite2D.new()
		drone.texture = drone_tex
		add_child(drone)
		orbital_drones.append(drone)


func _physics_process(delta: float) -> void:
	orbital_angle += delta * 2.2
	phase_timer -= delta
	damage_flash = maxf(0.0, damage_flash - delta)

	if is_instance_valid(anim_sprite):
		if damage_flash > 0.0:
			anim_sprite.modulate = Color(2.5, 2.5, 2.5, 1.0)
		else:
			anim_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)

	# Update orbital defense drones
	for i in range(orbital_drones.size()):
		var drone := orbital_drones[i]
		if is_instance_valid(drone):
			var a := orbital_angle + i * (TAU / 3.0)
			drone.position = Vector2(cos(a), sin(a)) * 44.0
			drone.rotation = a + PI * 0.5

	if not is_instance_valid(target):
		return

	var to_target := target.global_position - global_position
	var dist := to_target.length()

	match current_phase:
		AttackPhase.IDLE:
			if dist > 140.0:
				velocity = to_target.normalized() * 55.0
			else:
				velocity = Vector2.ZERO
			move_and_slide()

			if is_instance_valid(anim_sprite) and anim_sprite.animation != "idle":
				anim_sprite.play("idle")

			if phase_timer <= 0.0:
				var pick := randi() % 2
				if pick == 0:
					current_phase = AttackPhase.CHARGING_BURST
					phase_timer = 0.85
					if is_instance_valid(anim_sprite):
						anim_sprite.play("surge")
				else:
					current_phase = AttackPhase.CHARGING_DASH
					phase_timer = 0.75
					dash_target_dir = to_target.normalized()
					if is_instance_valid(anim_sprite):
						anim_sprite.play("overload")

		AttackPhase.CHARGING_BURST:
			velocity = Vector2.ZERO
			queue_redraw()
			if phase_timer <= 0.0:
				_execute_burst()
				current_phase = AttackPhase.RECOVER
				phase_timer = 1.0
				if is_instance_valid(anim_sprite):
					anim_sprite.play("idle")

		AttackPhase.CHARGING_DASH:
			velocity = Vector2.ZERO
			dash_target_dir = to_target.normalized()
			queue_redraw()
			if phase_timer <= 0.0:
				current_phase = AttackPhase.DASHING
				phase_timer = 0.45

		AttackPhase.DASHING:
			velocity = dash_target_dir * 420.0
			move_and_slide()
			if to_target.length() < 46.0 and target.has_method("take_damage"):
				target.take_damage(2)
			if phase_timer <= 0.0:
				current_phase = AttackPhase.RECOVER
				phase_timer = 0.9
				if is_instance_valid(anim_sprite):
					anim_sprite.play("idle")

		AttackPhase.RECOVER:
			velocity = Vector2.ZERO
			if phase_timer <= 0.0:
				current_phase = AttackPhase.IDLE
				phase_timer = randf_range(1.4, 2.2)

	queue_redraw()


func _execute_burst() -> void:
	var count := 8
	var angle_step := TAU / float(count)
	var base_angle := orbital_angle
	for i in range(count):
		var angle := base_angle + i * angle_step
		var dir := Vector2(cos(angle), sin(angle))
		var proj = PROJECTILE_SCENE.instantiate()
		proj.global_position = global_position + dir * 36.0
		proj.direction = dir
		proj.speed = 310.0
		get_parent().add_child(proj)


func take_damage(amount: int) -> void:
	if defeated_already:
		return
	health = maxi(0, health - amount)
	damage_flash = 0.12
	health_changed.emit(health, max_health)
	if health == 0:
		defeated_already = true
		defeated.emit()
		queue_free()
	else:
		queue_redraw()


func _draw() -> void:
	# Attack telegraph visuals
	if current_phase == AttackPhase.CHARGING_BURST:
		var burst_radius := 30.0 + (1.0 - phase_timer / 0.85) * 45.0
		draw_arc(Vector2.ZERO, burst_radius, 0.0, TAU, 32, Color(1.0, 0.2, 0.4, 0.8), 2.5)
		draw_circle(Vector2.ZERO, 14.0, Color(1.0, 0.3, 0.5, 0.5))
	elif current_phase == AttackPhase.CHARGING_DASH:
		var line_color := Color(1.0, 0.3, 0.1, 0.75)
		draw_line(Vector2.ZERO, to_local(global_position + dash_target_dir * 320.0), line_color, 4.0)
		draw_line(Vector2.ZERO, to_local(global_position + dash_target_dir * 320.0), Color(1.0, 0.9, 0.7, 0.5), 1.5)
