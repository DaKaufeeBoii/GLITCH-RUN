extends CharacterBody2D
## Ranged hovering turret sentry with dual accelerator rails, telegraph laser, and recoil fire.

signal defeated

const PROJECTILE_SCENE := preload("res://scenes/weapons/enemy_projectile.tscn")
const ASSET_LOADER := preload("res://scripts/asset_loader.gd")

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
var damage_flash := 0.0

var anim_sprite: AnimatedSprite2D


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	fire_timer = randf_range(1.5, 2.5)
	_setup_visuals()


func _setup_visuals() -> void:
	var tex := ASSET_LOADER.load_texture("res://assets/enemies/shooter_sheet.png")
	var frames := SpriteFrames.new()

	# Hover animation (Frames 0 and 1)
	frames.add_animation("hover")
	frames.set_animation_speed("hover", 4.0)
	frames.set_animation_loop("hover", true)

	if tex:
		for i in range(2):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * 32, 0, 32, 32)
			frames.add_frame("hover", at)

		# Charge animation (Frame 2)
		frames.add_animation("charge")
		frames.set_animation_speed("charge", 8.0)
		var at_c := AtlasTexture.new()
		at_c.atlas = tex
		at_c.region = Rect2(2 * 32, 0, 32, 32)
		frames.add_frame("charge", at_c)

		# Fire animation (Frame 3)
		frames.add_animation("fire")
		frames.set_animation_speed("fire", 6.0)
		var at_f := AtlasTexture.new()
		at_f.atlas = tex
		at_f.region = Rect2(3 * 32, 0, 32, 32)
		frames.add_frame("fire", at_f)

	anim_sprite = AnimatedSprite2D.new()
	anim_sprite.sprite_frames = frames
	anim_sprite.play("hover")
	add_child(anim_sprite)


func _physics_process(delta: float) -> void:
	damage_flash = maxf(0.0, damage_flash - delta)
	if is_instance_valid(anim_sprite):
		if damage_flash > 0.0:
			anim_sprite.modulate = Color(2.0, 2.0, 2.0, 1.0)
		else:
			anim_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)

	if not is_instance_valid(target):
		return

	var to_target := target.global_position - global_position
	var dist := to_target.length()
	rotation = to_target.angle()

	if telegraph_time > 0.0:
		telegraph_time -= delta
		velocity = Vector2.ZERO
		aimed_direction = to_target.normalized()
		if is_instance_valid(anim_sprite) and anim_sprite.animation != "charge":
			anim_sprite.play("charge")
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
			velocity = -to_target.normalized() * (move_speed * 1.1)
		elif dist > ideal_distance + 40.0:
			velocity = to_target.normalized() * move_speed
		else:
			var strafe := to_target.orthogonal().normalized()
			velocity = strafe * (move_speed * 0.75)

		if is_instance_valid(anim_sprite) and anim_sprite.animation != "hover":
			anim_sprite.play("hover")

	move_and_slide()


func _fire_shot() -> void:
	if is_instance_valid(anim_sprite):
		anim_sprite.play("fire")
	var proj = PROJECTILE_SCENE.instantiate()
	proj.global_position = global_position + aimed_direction * 20.0
	proj.direction = aimed_direction
	get_parent().add_child(proj)
	queue_redraw()


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
	# Warning laser line when charging attack
	if telegraph_time > 0.0:
		var pulse := 0.5 + sin(telegraph_time * 25.0) * 0.4
		var line_color := Color(1.0, 0.6, 0.1, pulse)
		draw_line(Vector2.ZERO, to_local(global_position + aimed_direction * 380.0), line_color, 2.0)
		draw_line(Vector2.ZERO, to_local(global_position + aimed_direction * 380.0), Color(1.0, 0.9, 0.6, pulse * 0.6), 1.0)

	# Health bar
	if health < max_health:
		var hit_points := float(health) / float(max_health)
		draw_rect(Rect2(-14, -20, 28, 4), Color("181a26"))
		draw_rect(Rect2(-13, -19, 26.0 * hit_points, 2), Color("f59e0b"))
