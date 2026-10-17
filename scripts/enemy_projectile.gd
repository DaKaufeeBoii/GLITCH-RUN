extends Area3D
## Hostile 3D energy projectile that damages the player on contact and dissolves on walls.

@export var speed := 18.0
@export var damage := 1
var direction := Vector3.FORWARD
var lifetime := 3.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("enemies"):
		return
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()
