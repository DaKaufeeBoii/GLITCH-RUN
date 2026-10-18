extends Area2D
## Player plasma bolt with geometric cyan glow, trail drawing, and reliable collision handling.

@export var speed := 640.0
@export var damage := 1
var direction := Vector2.RIGHT
var lifetime := 1.6


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
	# Never collide with the firing player
	if body.is_in_group("player") or body == self:
		return

	if body.is_in_group("enemies"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		queue_free()
		return

	# Collided with static arena walls or obstacles
	queue_free()


func _draw() -> void:
	# High-visibility geometric cyan plasma bolt
	# Trailing ion energy line
	draw_line(Vector2(-10, 0), Vector2(2, 0), Color(0.22, 0.74, 0.97, 0.55), 3.5)
	# Glowing outer sphere
	draw_circle(Vector2(2, 0), 4.5, Color(0.22, 0.74, 0.97, 1.0))
	# White-hot energetic core
	draw_circle(Vector2(2, 0), 2.2, Color(1.0, 1.0, 1.0, 1.0))
