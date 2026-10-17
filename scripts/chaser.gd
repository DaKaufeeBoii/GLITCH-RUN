extends CharacterBody2D
## Minimal enemy that pursues the player and deals contact damage.

signal defeated

@export var max_health := 3
@export var move_speed := 92.0
var health := 3
var target: Node2D
var contact_cooldown := 0.0
var defeated_already := false


func _ready() -> void:
	health = max_health
	add_to_group("enemies")


func _physics_process(delta: float) -> void:
	contact_cooldown = maxf(0.0, contact_cooldown - delta)
	if not is_instance_valid(target):
		return
	var to_target := target.global_position - global_position
	if to_target.length() > 36.0:
		velocity = to_target.normalized() * move_speed
	else:
		velocity = Vector2.ZERO
		if contact_cooldown <= 0.0 and target.has_method("take_damage"):
			target.take_damage(1)
			contact_cooldown = 0.9
	rotation = to_target.angle()
	move_and_slide()


func take_damage(amount: int) -> void:
	if defeated_already:
		return
	health = maxi(0, health - amount)
	if health == 0:
		defeated_already = true
		defeated.emit()
		queue_free()
	else:
		queue_redraw()


func _draw() -> void:
	var hit_points := float(health) / float(max_health)
	draw_colored_polygon(PackedVector2Array([Vector2(15, 0), Vector2(0, -15), Vector2(-15, 0), Vector2(0, 15)]), Color("ff5578"))
	draw_rect(Rect2(-15, -23, 30, 4), Color("331c38"))
	draw_rect(Rect2(-15, -23, 30.0 * hit_points, 4), Color("ff8c7a"))

