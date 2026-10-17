extends Area2D
## Hostile projectile that damages the player on contact and dissolves on walls.

@export var speed := 390.0
@export var damage := 1
var direction := Vector2.RIGHT
var lifetime := 2.8


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	# Ignore other enemy bodies
	if body.is_in_group("enemies"):
		return
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 6.0, Color("ff3b5c"))
	draw_circle(Vector2.ZERO, 3.0, Color("fff0f3"))
