extends CharacterBody3D
## Fast 3D enemy that charges with a telegraphed lunge and stalls on recovery.

signal defeated

@export var max_health := 2
@export var patrol_speed := 5.2
@export var lunge_speed := 26.0

var health := 2
var target: Node3D
var defeated_already := false

enum State { STALK, TELEGRAPH, LUNGE, RECOVER }
var state := State.STALK

var state_timer := 1.2
var lunge_direction := Vector3.FORWARD
var contact_dealt := false

@onready var warning_ray: MeshInstance3D = $WarningRay


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	state_timer = randf_range(1.0, 1.8)
	if warning_ray:
		warning_ray.visible = false


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return

	var to_target := target.global_position - global_position
	to_target.y = 0.0
	state_timer -= delta

	match state:
		State.STALK:
			if warning_ray:
				warning_ray.visible = false
			velocity = to_target.normalized() * patrol_speed
			if not to_target.is_zero_approx():
				var look_target := global_position + to_target
				look_target.y = global_position.y
				look_at(look_target, Vector3.UP)
			if state_timer <= 0.0 and to_target.length() < 13.0:
				state = State.TELEGRAPH
				state_timer = 0.55
				lunge_direction = to_target.normalized()
				velocity = Vector3.ZERO
				if warning_ray:
					warning_ray.visible = true

		State.TELEGRAPH:
			velocity = Vector3.ZERO
			if warning_ray:
				warning_ray.visible = true
			if state_timer <= 0.0:
				state = State.LUNGE
				state_timer = 0.32
				contact_dealt = false
				if warning_ray:
					warning_ray.visible = false

		State.LUNGE:
			velocity = lunge_direction * lunge_speed
			if not contact_dealt and to_target.length() < 1.4:
				if target.has_method("take_damage"):
					target.take_damage(1)
					contact_dealt = true
			if state_timer <= 0.0:
				state = State.RECOVER
				state_timer = 0.65
				velocity = Vector3.ZERO

		State.RECOVER:
			velocity = Vector3.ZERO
			if state_timer <= 0.0:
				state = State.STALK
				state_timer = randf_range(1.4, 2.2)

	move_and_slide()


func take_damage(amount: int) -> void:
	if defeated_already:
		return
	health = maxi(0, health - amount)
	if health == 0:
		defeated_already = true
		defeated.emit()
		queue_free()
