extends Area2D
## High-energy player plasma projectile with glowing pixel-art bolt and wall impact.

const ASSET_LOADER := preload("res://scripts/asset_loader.gd")

@export var speed := 620.0
@export var damage := 1
var direction := Vector2.RIGHT
var lifetime := 1.5

var sprite: Sprite2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	sprite = Sprite2D.new()
	sprite.texture = ASSET_LOADER.load_texture("res://assets/weapons/player_plasma.png")
	add_child(sprite)
	rotation = direction.angle()


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()
