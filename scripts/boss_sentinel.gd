extends CharacterBody2D
## Boss 2: VECTOR SENTINEL. Orbital ring sentry with sweeping cardinal beam arrays,
## perimeter shard defense drones, and rapid spiral pulse salvos.

signal defeated
signal health_changed(curr: int, max_h: int)
signal phase_two_entered

const PROJECTILE_SCENE := preload("res://scenes/weapons/enemy_projectile.tscn")

@export var max_health := 30
var health := 30
var target: Node2D
var defeated_already := false

enum AttackPhase { IDLE, CHARGING_SWEEP, SWEEPING, CHARGING_SALVO, FIRING_SALVO, RECOVER }
var current_phase := AttackPhase.IDLE
var phase_timer := 2.0
var orbital_angle := 0.0
var sweep_rotation_speed := 1.2
var sweep_duration := 2.2
var damage_flash := 0.0
var phase_two_triggered := false
var is_phase_two := false
var is_mid_boss := false
var laser_hit_player := false
var laser_hit_cooldown := 0.0

var squad_coordinator: RefCounted = null
var active_mutations: Array[Dictionary] = []

# Visual parameters
const CORE_COLOR := Color("06b6d4") # Cyan
const RING_COLOR := Color("0891b2") # Deep cyan
const ACCENT_COLOR := Color("67e8f9") # Light cyan
const BEAM_COLOR := Color("22d3ee") # Bright beam


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
		if m_id == "ORBITAL_ACCELERATION":
			# Sweeping lasers rotate 25% faster, but sweep duration is reduced by 0.6s
			sweep_rotation_speed *= 1.25
			sweep_duration = maxf(1.4, sweep_duration - 0.6)
		elif m_id == "SHARD_SYNCHRONY":
			# Max health slightly lowered to compensate for drone defense
			max_health = maxi(20, int(max_health * 0.85))
			health = max_health


func _physics_process(delta: float) -> void:
	orbital_angle += delta * (sweep_rotation_speed if current_phase == AttackPhase.SWEEPING else 1.5)
	phase_timer -= delta
	laser_hit_cooldown = maxf(0.0, laser_hit_cooldown - delta)
	damage_flash = maxf(0.0, damage_flash - delta)

	if not is_instance_valid(target):
		return

	var to_target := target.global_position - global_position
	var dist := to_target.length()

	match current_phase:
		AttackPhase.IDLE:
			# Orbit around player maintaining 180px distance
			if dist > 210.0:
				velocity = to_target.normalized() * 65.0
			elif dist < 150.0:
				velocity = -to_target.normalized() * 65.0
			else:
				# Sweet spot: lateral strafe
				velocity = to_target.orthogonal().normalized() * 55.0
			if is_inside_tree():
				move_and_slide()

			if phase_timer <= 0.0:
				var cur_time: float = Time.get_ticks_msec() / 1000.0
				var token_granted: bool = (squad_coordinator == null or squad_coordinator.request_attack_token(self, cur_time))
				if token_granted:
					var pick := randi() % 2
					if pick == 0:
						current_phase = AttackPhase.CHARGING_SWEEP
						phase_timer = 0.9
						if is_inside_tree():
							var synth = get_node_or_null("/root/AudioSynth")
							if synth:
								synth.play("enemy_laser_charge", 0.05, -2.0)
					else:
						current_phase = AttackPhase.CHARGING_SALVO
						phase_timer = 0.75
				else:
					phase_timer = 0.35

		AttackPhase.CHARGING_SWEEP:
			velocity = Vector2.ZERO
			if phase_timer <= 0.0:
				current_phase = AttackPhase.SWEEPING
				phase_timer = sweep_duration
				laser_hit_player = false

		AttackPhase.SWEEPING:
			velocity = Vector2.ZERO
			# Check beam intersection with player: 4 cardinal beams at angles orbital_angle + k * PI/2
			if laser_hit_cooldown <= 0.0 and is_instance_valid(target) and target.has_method("take_damage"):
				var hit := _check_laser_hit(target.global_position)
				if hit:
					target.take_damage(1)
					laser_hit_cooldown = 0.75 # Fairness: prevent tick damage

			if phase_timer <= 0.0:
				current_phase = AttackPhase.RECOVER
				phase_timer = 1.3 # Generous recovery window for player counterplay

		AttackPhase.CHARGING_SALVO:
			velocity = Vector2.ZERO
			if phase_timer <= 0.0:
				current_phase = AttackPhase.FIRING_SALVO
				phase_timer = 0.6
				_execute_salvo()

		AttackPhase.FIRING_SALVO:
			velocity = Vector2.ZERO
			if phase_timer <= 0.0:
				current_phase = AttackPhase.RECOVER
				phase_timer = 1.0

		AttackPhase.RECOVER:
			velocity = Vector2.ZERO
			if squad_coordinator:
				squad_coordinator.release_attack_token(self)
			if phase_timer <= 0.0:
				current_phase = AttackPhase.IDLE
				phase_timer = randf_range(1.5, 2.4)

	queue_redraw()


func _check_laser_hit(player_pos: Vector2) -> bool:
	var to_player := player_pos - global_position
	var player_dist := to_player.length()
	if player_dist > 400.0 or player_dist < 10.0:
		return false

	var player_angle := to_player.angle()
	for i in range(4):
		var beam_angle := orbital_angle + i * (PI / 2.0)
		var diff := absf(wrapf(player_angle - beam_angle, -PI, PI))
		if diff < 0.12: # Beam width hit cone
			return true
	return false


func _execute_salvo() -> void:
	if not is_instance_valid(target):
		return
	var base_dir := (target.global_position - global_position).normalized()
	# Fire 5-bullet fan spread with clear gaps
	for i in range(-2, 3):
		var angle := i * 0.22
		var dir := base_dir.rotated(angle)
		var proj = PROJECTILE_SCENE.instantiate()
		proj.global_position = global_position + dir * 32.0
		proj.direction = dir
		proj.speed = 340.0
		get_parent().add_child(proj)


func enter_phase_two() -> void:
	is_phase_two = true
	health = max_health
	damage_flash = 0.35
	sweep_rotation_speed *= 1.35
	phase_timer = 0.40
	current_phase = AttackPhase.IDLE

	if is_inside_tree():
		var synth = get_node_or_null("/root/AudioSynth")
		if synth:
			synth.play("mutation_alert", 0.15, 2.0)
			synth.play("boss_alarm", 0.10, 3.0)

	health_changed.emit(health, max_health)
	phase_two_entered.emit()
	queue_redraw()


func take_damage(amount: int, _source: String = "plasma") -> void:
	if defeated_already:
		return
	health = maxi(0, health - amount)
	damage_flash = 0.12

	if health == 0:
		if not is_mid_boss and not is_phase_two:
			enter_phase_two()
			return
		else:
			defeated_already = true
			if squad_coordinator:
				squad_coordinator.release_attack_token(self)
			defeated.emit()
			queue_free()
	else:
		health_changed.emit(health, max_health)
		queue_redraw()


func _draw() -> void:
	var main_color := CORE_COLOR if damage_flash <= 0.0 else Color.WHITE

	# Draw outer rotating ring
	draw_arc(Vector2.ZERO, 36.0, 0.0, TAU, 32, RING_COLOR, 2.5, false)

	# Draw 4 orbital emitters
	for i in range(4):
		var a := orbital_angle + i * (PI / 2.0)
		var p := Vector2(cos(a), sin(a)) * 36.0
		draw_circle(p, 5.0, ACCENT_COLOR)

		# Telegraph guide lines during CHARGING_SWEEP
		if current_phase == AttackPhase.CHARGING_SWEEP:
			var beam_end := Vector2(cos(a), sin(a)) * 380.0
			draw_line(p, beam_end, Color(0.1, 0.9, 1.0, 0.4), 1.0)

		# Active sweeping laser beams during SWEEPING
		elif current_phase == AttackPhase.SWEEPING:
			var beam_end := Vector2(cos(a), sin(a)) * 380.0
			draw_line(p, beam_end, BEAM_COLOR, 3.5)
			draw_line(p, beam_end, Color.WHITE, 1.2) # Hot laser center

	# Central core diamond/octahedron
	var pts := PackedVector2Array([
		Vector2(0, -22),
		Vector2(20, 0),
		Vector2(0, 22),
		Vector2(-20, 0)
	])
	draw_colored_polygon(pts, main_color)
	draw_polyline(pts, Color.WHITE if damage_flash > 0.0 else ACCENT_COLOR, 2.0)

	# Inner glowing glyph
	draw_circle(Vector2.ZERO, 6.0, Color.WHITE if current_phase != AttackPhase.RECOVER else Color(0.2, 0.4, 0.5))
