extends CharacterBody3D
## Ranged 3D enemy that maintains distance and fires telegraphed energy shots.

signal defeated

const PROJECTILE_SCENE := preload("res://scenes/weapons/enemy_projectile.tscn")

@export var max_health := 3
@export var move_speed := 4.2
@export var ideal_distance := 9.5

var health := 3
var target: Node3D
var defeated_already := false

var fire_timer := 2.0
var telegraph_time := 0.0
const TELEGRAPH_DURATION := 0.65
var aimed_direction := Vector3.FORWARD

@onready var laser_sight: MeshInstance3D = $LaserSight


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	fire_timer = randf_range(1.5, 2.5)
	if laser_sight:
		laser_sight.visible = false


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return

	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()

	if not to_target.is_zero_approx():
		var look_target := global_position + to_target
		look_target.y = global_position.y
		look_at(look_target, Vector3.UP)

	if telegraph_time > 0.0:
		telegraph_time -= delta
		velocity = Vector3.ZERO
		aimed_direction = to_target.normalized()
		if laser_sight:
			laser_sight.visible = true
		if telegraph_time <= 0.0:
			_fire_shot()
	else:
		if laser_sight:
			laser_sight.visible = false
		fire_timer -= delta
		if fire_timer <= 0.0 and dist < 18.0:
			telegraph_time = TELEGRAPH_DURATION
			aimed_direction = to_target.normalized()
			fire_timer = randf_range(2.2, 3.2)

		# Kiting movement
		if dist < ideal_distance - 2.0:
			velocity = -to_target.normalized() * (move_speed * 1.1)
		elif dist > ideal_distance + 2.0:
			velocity = to_target.normalized() * move_speed
		else:
			var strafe := Vector3(-to_target.z, 0, to_target.x).normalized()
			velocity = strafe * (move_speed * 0.75)

	move_and_slide()


func _fire_shot() -> void:
	if laser_sight:
		laser_sight.visible = false
	var proj = PROJECTILE_SCENE.instantiate()
	proj.global_position = global_position + Vector3(0.0, 0.7, 0.0) + aimed_direction * 0.8
	proj.direction = aimed_direction
	get_parent().add_child(proj)


func take_damage(amount: int) -> void:
	if defeated_already:
		return
	health = maxi(0, health - amount)
	if health == 0:
		defeated_already = true
		defeated.emit()
		queue_free()
