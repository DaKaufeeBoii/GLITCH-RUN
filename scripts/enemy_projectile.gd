extends Area2D
## Hostile tachyon projectile with geometric crimson orb and safe collision handling.

@export var speed := 390.0
@export var damage := 1
var direction := Vector2.RIGHT
var lifetime := 2.8


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	rotation = direction.angle()
	queue_redraw()


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	# Ignore allied enemy bodies
	if body.is_in_group("enemies"):
		return

	if body.is_in_group("player") or body.has_method("take_damage"):
		body.take_damage(damage)
		queue_free()
		return

	# Hits arena walls or obstacles
	queue_free()


func _draw() -> void:
	# Concentric geometric tachyon hazard orb
	draw_circle(Vector2.ZERO, 6.5, Color(0.96, 0.25, 0.37, 0.4))
	draw_circle(Vector2.ZERO, 5.0, Color(0.96, 0.25, 0.37, 1.0))
	draw_circle(Vector2.ZERO, 2.5, Color(1.0, 0.95, 0.96, 1.0))
