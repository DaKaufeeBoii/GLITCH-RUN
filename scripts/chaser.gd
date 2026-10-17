extends CharacterBody3D
## Minimal 3D enemy that pursues the player and deals contact damage.

signal defeated

@export var max_health := 3
@export var move_speed := 5.2
var health := 3
var target: Node3D
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
	to_target.y = 0.0
	var dist := to_target.length()

	if dist > 1.3:
		velocity = to_target.normalized() * move_speed
		var look_target := global_position + to_target
		look_target.y = global_position.y
		look_at(look_target, Vector3.UP)
	else:
		velocity = Vector3.ZERO
		if contact_cooldown <= 0.0 and target.has_method("take_damage"):
			target.take_damage(1)
			contact_cooldown = 0.9

	move_and_slide()


func take_damage(amount: int) -> void:
	if defeated_already:
		return
	health = maxi(0, health - amount)
	if health == 0:
		defeated_already = true
		defeated.emit()
		queue_free()
