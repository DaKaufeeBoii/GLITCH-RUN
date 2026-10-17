extends CharacterBody2D
## Final encounter for Milestone 1: Multi-phase boss with telegraphed attacks and orbital nodes.

signal defeated
signal health_changed(curr: int, max_h: int)

const PROJECTILE_SCENE := preload("res://scenes/weapons/enemy_projectile.tscn")
const CHASER_SCENE := preload("res://scenes/enemies/chaser.tscn")

@export var max_health := 35
var health := 35
var target: Node2D
var defeated_already := false

enum AttackPhase { IDLE, CHARGING_BURST, CHARGING_DASH, DASHING, RECOVER }
var current_phase := AttackPhase.IDLE
var phase_timer := 2.0
var orbital_angle := 0.0
var dash_target_dir := Vector2.ZERO


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	add_to_group("boss")
	phase_timer = 2.0


func _physics_process(delta: float) -> void:
	orbital_angle += delta * 2.0
	phase_timer -= delta

	if not is_instance_valid(target):
		return

	var to_target := target.global_position - global_position
	var dist := to_target.length()

	match current_phase:
		AttackPhase.IDLE:
			# Slow hovering pursuit
			if dist > 140.0:
				velocity = to_target.normalized() * 55.0
			else:
				velocity = Vector2.ZERO
			move_and_slide()

			if phase_timer <= 0.0:
				# Choose next attack
				var pick := randi() % 2
				if pick == 0:
					current_phase = AttackPhase.CHARGING_BURST
					phase_timer = 0.85
				else:
					current_phase = AttackPhase.CHARGING_DASH
					phase_timer = 0.75
					dash_target_dir = to_target.normalized()

		AttackPhase.CHARGING_BURST:
			velocity = Vector2.ZERO
			queue_redraw()
			if phase_timer <= 0.0:
				_execute_burst()
				current_phase = AttackPhase.RECOVER
				phase_timer = 1.0

		AttackPhase.CHARGING_DASH:
			velocity = Vector2.ZERO
			dash_target_dir = to_target.normalized()
			queue_redraw()
			if phase_timer <= 0.0:
				current_phase = AttackPhase.DASHING
				phase_timer = 0.45

		AttackPhase.DASHING:
			velocity = dash_target_dir * 420.0
			move_and_slide()
			# Contact damage
			if to_target.length() < 46.0 and target.has_method("take_damage"):
				target.take_damage(2)
			if phase_timer <= 0.0:
				current_phase = AttackPhase.RECOVER
				phase_timer = 0.9

		AttackPhase.RECOVER:
			velocity = Vector2.ZERO
			if phase_timer <= 0.0:
				current_phase = AttackPhase.IDLE
				phase_timer = randf_range(1.4, 2.2)

	queue_redraw()


func _execute_burst() -> void:
	# 8-direction radial burst with safe gaps
	var count := 8
	var angle_step := TAU / float(count)
	var base_angle := orbital_angle
	for i in range(count):
		var angle := base_angle + i * angle_step
		var dir := Vector2(cos(angle), sin(angle))
		var proj = PROJECTILE_SCENE.instantiate()
		proj.global_position = global_position + dir * 34.0
		proj.direction = dir
		proj.speed = 310.0
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
	else:
		queue_redraw()


func _draw() -> void:
	# Attack telegraph visuals
	if current_phase == AttackPhase.CHARGING_BURST:
		var burst_radius := 30.0 + (1.0 - phase_timer / 0.85) * 45.0
		draw_arc(Vector2.ZERO, burst_radius, 0.0, TAU, 32, Color(1.0, 0.2, 0.3, 0.8), 2.0)
	elif current_phase == AttackPhase.CHARGING_DASH:
		var line_color := Color(1.0, 0.3, 0.1, 0.7)
		draw_line(Vector2.ZERO, to_local(global_position + dash_target_dir * 300.0), line_color, 4.0)

	# Main Core Body (Octagon)
	var pts: Array[Vector2] = []
	for i in range(8):
		var a := float(i) * TAU / 8.0
		pts.append(Vector2(cos(a), sin(a)) * 28.0)
	draw_colored_polygon(pts, Color("881337"))
	draw_arc(Vector2.ZERO, 28.0, 0.0, TAU, 32, Color("fb7185"), 2.5)

	# Inner pulsing core
	draw_circle(Vector2.ZERO, 13.0, Color("f43f5e"))
	draw_circle(Vector2.ZERO, 6.0, Color("fff1f2"))

	# Rotating Orbital Shield Nodes
	for i in range(3):
		var node_a := orbital_angle + i * (TAU / 3.0)
		var node_pos := Vector2(cos(node_a), sin(node_a)) * 42.0
		draw_circle(node_pos, 5.0, Color("fda4af"))
