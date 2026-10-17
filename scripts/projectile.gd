extends Area3D
## 3D player energy projectile that travels along the X/Z plane and impacts enemies/walls.

@export var speed := 28.0
@export var damage := 1
var direction := Vector3.FORWARD
var lifetime := 1.8


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()
