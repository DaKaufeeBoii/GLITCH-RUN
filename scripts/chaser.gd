extends CharacterBody2D
## Cyberpunk stalker arachnid drone with animated 4-frame scuttle, optical sensor, and contact damage.

signal defeated

const ASSET_LOADER := preload("res://scripts/asset_loader.gd")

@export var max_health := 3
@export var move_speed := 92.0
var health := 3
var target: Node2D
var contact_cooldown := 0.0
var defeated_already := false
var damage_flash := 0.0

var anim_sprite: AnimatedSprite2D


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	_setup_visuals()


func _setup_visuals() -> void:
	var tex := ASSET_LOADER.load_texture("res://assets/enemies/chaser_sheet.png")
	var frames := SpriteFrames.new()
	frames.add_animation("scuttle")
	frames.set_animation_speed("scuttle", 8.0)
	frames.set_animation_loop("scuttle", true)

	if tex:
		for i in range(4):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * 32, 0, 32, 32)
			frames.add_frame("scuttle", at)

	anim_sprite = AnimatedSprite2D.new()
	anim_sprite.sprite_frames = frames
	anim_sprite.play("scuttle")
	add_child(anim_sprite)


func _physics_process(delta: float) -> void:
	contact_cooldown = maxf(0.0, contact_cooldown - delta)
	damage_flash = maxf(0.0, damage_flash - delta)

	if is_instance_valid(anim_sprite):
		if damage_flash > 0.0:
			anim_sprite.modulate = Color(2.0, 2.0, 2.0, 1.0)
		else:
			anim_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)

	if not is_instance_valid(target):
		return

	var to_target := target.global_position - global_position
	if to_target.length() > 36.0:
		velocity = to_target.normalized() * move_speed
		if is_instance_valid(anim_sprite) and not anim_sprite.is_playing():
			anim_sprite.play("scuttle")
	else:
		velocity = Vector2.ZERO
		if is_instance_valid(anim_sprite):
			anim_sprite.stop()
		if contact_cooldown <= 0.0 and target.has_method("take_damage"):
			target.take_damage(1)
			contact_cooldown = 0.9

	rotation = to_target.angle()
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
	# Clean cyber health bar above unit
	if health < max_health:
		var hit_points := float(health) / float(max_health)
		draw_rect(Rect2(-14, -20, 28, 4), Color("181a26"))
		draw_rect(Rect2(-13, -19, 26.0 * hit_points, 2), Color("ff3366"))
