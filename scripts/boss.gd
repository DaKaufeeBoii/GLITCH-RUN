extends CharacterBody3D
## Milestone 1 3D Boss (NEXUS // OVERLORD) with radial projectile bursts and surge charge slams.

signal defeated
signal health_changed(curr: int, max_h: int)

const PROJECTILE_SCENE := preload("res://scenes/weapons/enemy_projectile.tscn")

@export var max_health := 35
var health := 35
var target: Node3D
var defeated_already := false

enum AttackPhase { IDLE, CHARGING_BURST, CHARGING_DASH, DASHING, RECOVER }
var current_phase := AttackPhase.IDLE
var phase_timer := 2.0
var orbital_angle := 0.0
var dash_target_dir := Vector3.FORWARD

@onready var node_orbit: Node3D = $OrbitNodes
@onready var charge_ray: MeshInstance3D = $ChargeRay


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	add_to_group("boss")
	phase_timer = 2.0
	if charge_ray:
		charge_ray.visible = false


func _physics_process(delta: float) -> void:
	orbital_angle += delta * 2.5
	if node_orbit:
		node_orbit.rotation.y = orbital_angle

	phase_timer -= delta

	if not is_instance_valid(target):
		return

	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()

	match current_phase:
		AttackPhase.IDLE:
			if charge_ray:
				charge_ray.visible = false
			if dist > 6.0:
				velocity = to_target.normalized() * 3.0
			else:
				velocity = Vector3.ZERO
			move_and_slide()

			if phase_timer <= 0.0:
				var pick := randi() % 2
				if pick == 0:
					current_phase = AttackPhase.CHARGING_BURST
					phase_timer = 0.85
				else:
					current_phase = AttackPhase.CHARGING_DASH
					phase_timer = 0.75
					dash_target_dir = to_target.normalized()
					if charge_ray:
						charge_ray.visible = true

		AttackPhase.CHARGING_BURST:
			velocity = Vector3.ZERO
			if phase_timer <= 0.0:
				_execute_burst()
				current_phase = AttackPhase.RECOVER
				phase_timer = 1.0

		AttackPhase.CHARGING_DASH:
			velocity = Vector3.ZERO
			dash_target_dir = to_target.normalized()
			if not dash_target_dir.is_zero_approx():
				var look_target := global_position + dash_target_dir
				look_target.y = global_position.y
				look_at(look_target, Vector3.UP)
			if charge_ray:
				charge_ray.visible = true
			if phase_timer <= 0.0:
				current_phase = AttackPhase.DASHING
				phase_timer = 0.48
				if charge_ray:
					charge_ray.visible = false

		AttackPhase.DASHING:
			velocity = dash_target_dir * 20.0
			move_and_slide()
			if to_target.length() < 2.0 and target.has_method("take_damage"):
				target.take_damage(2)
			if phase_timer <= 0.0:
				current_phase = AttackPhase.RECOVER
				phase_timer = 0.9

		AttackPhase.RECOVER:
			velocity = Vector3.ZERO
			if charge_ray:
				charge_ray.visible = false
			if phase_timer <= 0.0:
				current_phase = AttackPhase.IDLE
				phase_timer = randf_range(1.5, 2.4)


func _execute_burst() -> void:
	var count := 8
	var angle_step := TAU / float(count)
	var base_angle := orbital_angle
	for i in range(count):
		var angle := base_angle + i * angle_step
		var dir := Vector3(cos(angle), 0.0, sin(angle)).normalized()
		var proj = PROJECTILE_SCENE.instantiate()
		proj.global_position = global_position + Vector3(0.0, 1.0, 0.0) + dir * 1.8
		proj.direction = dir
		proj.speed = 15.0
		get_parent().add_child(proj)


func take_damage(amount: int) -> void:
	if defeated_already:
		return
	health = maxi(0, health - amount)
	health_changed.emit(health, max_health)
	if health == 0:
		defeated_already = true
		defeated.emit()
		queue_free()
