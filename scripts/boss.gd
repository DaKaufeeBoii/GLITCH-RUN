extends CharacterBody2D
## Final Boss: NEXUS OVERLORD. Multi-phase biomechanical singularity core with
## rotating orbital defense nodes, radial bursts, and crushing dash attacks.

signal defeated
signal health_changed(curr: int, max_h: int)

const PROJECTILE_SCENE := preload("res://scenes/weapons/enemy_projectile.tscn")

@export var max_health := 35
var health := 35
var target: Node2D
var defeated_already := false

enum AttackPhase { IDLE, CHARGING_BURST, CHARGING_DASH, DASHING, RECOVER }
var current_phase := AttackPhase.IDLE
var phase_timer := 2.0
var orbital_angle := 0.0
var dash_target_dir := Vector2.ZERO
var dash_hit_player := false
var damage_flash := 0.0
var phase_two_triggered := false

var squad_coordinator: RefCounted = null
var active_mutations: Array[Dictionary] = []
var burst_projectile_count := 8
var dash_speed := 420.0
var post_burst_recovery := 1.0


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	add_to_group("boss")
	phase_timer = 2.0
	queue_redraw()


func apply_mutations(mutations: Array[Dictionary]) -> void:
	active_mutations = mutations
	for m in mutations:
		var m_id: String = m.get("id", "")
		if m_id == "BURST_OVERCLOCK":
			burst_projectile_count = 10
			post_burst_recovery = 1.35
		elif m_id == "TITAN_DASH":
			dash_speed = 500.0


func _physics_process(delta: float) -> void:
	orbital_angle += delta * 2.2
	phase_timer -= delta
	damage_flash = maxf(0.0, damage_flash - delta)

	if not is_instance_valid(target):
		return

	var to_target := target.global_position - global_position
	var dist := to_target.length()

	match current_phase:
		AttackPhase.IDLE:
			if dist > 140.0:
				velocity = to_target.normalized() * 55.0
			else:
				velocity = Vector2.ZERO
			if is_inside_tree():
				move_and_slide()

			if phase_timer <= 0.0:
				var cur_time: float = Time.get_ticks_msec() / 1000.0
				var token_granted: bool = (squad_coordinator == null or squad_coordinator.request_attack_token(self, cur_time))
				if token_granted:
					var pick := randi() % 2
					if pick == 0:
						current_phase = AttackPhase.CHARGING_BURST
						phase_timer = 0.85
					else:
						current_phase = AttackPhase.CHARGING_DASH
						phase_timer = 0.75
						dash_target_dir = to_target.normalized()
						dash_hit_player = false
				else:
					phase_timer = 0.35 # Stagger retry

		AttackPhase.CHARGING_BURST:
			velocity = Vector2.ZERO
			if phase_timer <= 0.0:
				_execute_burst()
				current_phase = AttackPhase.RECOVER
				phase_timer = post_burst_recovery

		AttackPhase.CHARGING_DASH:
			velocity = Vector2.ZERO
			# Lock telegraph direction during the final 0.35s to guarantee readable dodge window
			if phase_timer > 0.35:
				dash_target_dir = to_target.normalized()
			if phase_timer <= 0.0:
				current_phase = AttackPhase.DASHING
				phase_timer = 0.45
				dash_hit_player = false

		AttackPhase.DASHING:
			velocity = dash_target_dir * dash_speed
			if is_inside_tree():
				move_and_slide()
			if not dash_hit_player and to_target.length() < 46.0 and target.has_method("take_damage"):
				target.take_damage(2)
				dash_hit_player = true
			if phase_timer <= 0.0:
				current_phase = AttackPhase.RECOVER
				phase_timer = 0.9

		AttackPhase.RECOVER:
			velocity = Vector2.ZERO
			if squad_coordinator:
				squad_coordinator.release_attack_token(self)
			if phase_timer <= 0.0:
				current_phase = AttackPhase.IDLE
				phase_timer = randf_range(1.4, 2.2)

	queue_redraw()


func _execute_burst() -> void:
	var count := burst_projectile_count
	var angle_step := TAU / float(count)
	var base_angle := orbital_angle
	for i in range(count):
		var angle := base_angle + i * angle_step
		var dir := Vector2(cos(angle), sin(angle))
		var proj = PROJECTILE_SCENE.instantiate()
		proj.global_position = global_position + dir * 38.0
		proj.direction = dir
		proj.speed = 310.0
		get_parent().add_child(proj)


func take_damage(amount: int) -> void:
	if defeated_already:
		return
	health = maxi(0, health - amount)
	damage_flash = 0.12

	# Phase 2 cue when boss health drops below 50%
	if not phase_two_triggered and health <= int(max_health * 0.5):
		phase_two_triggered = true
		if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
			get_node("/root/AudioSynth").play("mutation_alert", 0.08, 0.0)

	health_changed.emit(health, max_health)
	if health == 0:
		defeated_already = true
		if squad_coordinator:
			squad_coordinator.release_attack_token(self)
		defeated.emit()
		queue_free()
	else:
		queue_redraw()


func _draw() -> void:
	# Attack telegraph visuals
	if current_phase == AttackPhase.CHARGING_BURST:
		var burst_radius := 30.0 + (1.0 - phase_timer / 0.85) * 45.0
		draw_arc(Vector2.ZERO, burst_radius, 0.0, TAU, 32, Color(1.0, 0.25, 0.4, 0.8), 2.5)
		draw_circle(Vector2.ZERO, 14.0, Color(1.0, 0.3, 0.5, 0.35))
	elif current_phase == AttackPhase.CHARGING_DASH:
		var line_color := Color(1.0, 0.35, 0.15, 0.75)
		draw_line(Vector2.ZERO, to_local(global_position + dash_target_dir * 320.0), line_color, 4.0)
		draw_line(Vector2.ZERO, to_local(global_position + dash_target_dir * 320.0), Color(1.0, 0.9, 0.7, 0.5), 1.5)

	# Main Core Body (Octagon polygon)
	var core_color := Color("881337") if damage_flash <= 0.0 else Color("ffffff")
	var pts: Array[Vector2] = []
	for i in range(8):
		var a := float(i) * TAU / 8.0
		pts.append(Vector2(cos(a), sin(a)) * 28.0)
	draw_colored_polygon(pts, core_color)
	draw_arc(Vector2.ZERO, 28.0, 0.0, TAU, 32, Color("fb7185"), 2.5)

	# Inner pulsing core
	draw_circle(Vector2.ZERO, 13.0, Color("f43f5e"))
	draw_circle(Vector2.ZERO, 6.0, Color("ffffff"))

	# Rotating Orbital Shield Nodes
	for i in range(3):
		var node_a := orbital_angle + i * (TAU / 3.0)
		var node_pos := Vector2(cos(node_a), sin(node_a)) * 44.0
		draw_circle(node_pos, 5.5, Color("fda4af"))
		draw_circle(node_pos, 2.5, Color("ffffff"))
