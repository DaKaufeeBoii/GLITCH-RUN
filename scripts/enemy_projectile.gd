extends Area2D
## Hostile tachyon projectile with unstable corona, rotation, and wall dissolution.

const ASSET_LOADER := preload("res://scripts/asset_loader.gd")

@export var speed := 390.0
@export var damage := 1
var direction := Vector2.RIGHT
var lifetime := 2.8

var sprite: Sprite2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	sprite = Sprite2D.new()
	sprite.texture = ASSET_LOADER.load_texture("res://assets/weapons/enemy_tachyon.png")
	add_child(sprite)


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	lifetime -= delta
	if is_instance_valid(sprite):
		sprite.rotation += delta * 12.0
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	# Ignore other enemy bodies
	if body.is_in_group("enemies"):
		return
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()
