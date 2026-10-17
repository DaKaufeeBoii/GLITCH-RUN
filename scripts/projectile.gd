extends Area2D
## Short-lived player shot; only enemy bodies are in its collision mask.

@export var speed := 620.0
@export var damage := 1
var direction := Vector2.RIGHT
var lifetime := 1.5


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 5.0, Color("ffc95c"))
	draw_circle(Vector2.ZERO, 2.0, Color("fff5d1"))

