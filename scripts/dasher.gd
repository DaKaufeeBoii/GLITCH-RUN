extends CharacterBody2D
## Fast razor interceptor drone with afterburner flare telegraph, supersonic lunge, and recovery.

signal defeated

const ASSET_LOADER := preload("res://scripts/asset_loader.gd")

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
var damage_flash := 0.0

var anim_sprite: AnimatedSprite2D


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	state_timer = randf_range(1.0, 2.0)
	_setup_visuals()


func _setup_visuals() -> void:
	var tex := ASSET_LOADER.load_texture("res://assets/enemies/dasher_sheet.png")
	var frames := SpriteFrames.new()

	# Stalk cruise (Frames 0 and 1)
	frames.add_animation("cruise")
	frames.set_animation_speed("cruise", 6.0)
	frames.set_animation_loop("cruise", true)

	if tex:
		for i in range(2):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * 32, 0, 32, 32)
			frames.add_frame("cruise", at)

		# Telegraph overclock (Frame 2)
		frames.add_animation("overclock")
		frames.set_animation_speed("overclock", 10.0)
		var at_oc := AtlasTexture.new()
		at_oc.atlas = tex
		at_oc.region = Rect2(2 * 32, 0, 32, 32)
		frames.add_frame("overclock", at_oc)

		# Lunge dive (Frame 3)
		frames.add_animation("lunge")
		frames.set_animation_speed("lunge", 12.0)
		var at_l := AtlasTexture.new()
		at_l.atlas = tex
		at_l.region = Rect2(3 * 32, 0, 32, 32)
		frames.add_frame("lunge", at_l)

	anim_sprite = AnimatedSprite2D.new()
	anim_sprite.sprite_frames = frames
	anim_sprite.play("cruise")
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
	state_timer -= delta

	match state:
		State.STALK:
			rotation = to_target.angle()
			velocity = to_target.normalized() * patrol_speed
			if is_instance_valid(anim_sprite) and anim_sprite.animation != "cruise":
				anim_sprite.play("cruise")
			if state_timer <= 0.0 and to_target.length() < 300.0:
				state = State.TELEGRAPH
				state_timer = 0.55
				lunge_direction = to_target.normalized()
				velocity = Vector2.ZERO
				if is_instance_valid(anim_sprite):
					anim_sprite.play("overclock")
				queue_redraw()

		State.TELEGRAPH:
			velocity = Vector2.ZERO
			queue_redraw()
			if state_timer <= 0.0:
				state = State.LUNGE
				state_timer = 0.28
				contact_dealt = false
				if is_instance_valid(anim_sprite):
					anim_sprite.play("lunge")

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
				if is_instance_valid(anim_sprite):
					anim_sprite.play("cruise")

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
	damage_flash = 0.12
	queue_redraw()
	if health == 0:
		defeated_already = true
		defeated.emit()
		queue_free()


func _draw() -> void:
	# Warning trajectory during telegraph
	if state == State.TELEGRAPH:
		var pulse := 0.5 + sin(state_timer * 28.0) * 0.45
		draw_line(Vector2.ZERO, to_local(global_position + lunge_direction * 240.0), Color(1.0, 0.2, 0.8, pulse), 3.0)
		draw_line(Vector2.ZERO, to_local(global_position + lunge_direction * 240.0), Color(1.0, 0.9, 1.0, pulse * 0.7), 1.0)

	# Health bar
	if health < max_health:
		var hit_points := float(health) / float(max_health)
		draw_rect(Rect2(-12, -18, 24, 3), Color("181a26"))
		draw_rect(Rect2(-11, -17, 22.0 * hit_points, 2), Color("d946ef"))
