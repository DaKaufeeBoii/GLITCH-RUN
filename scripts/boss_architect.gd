extends CharacterBody2D
## Boss 3: NULL ARCHITECT. Dimensional containment construct that warps across arena quadrants,
## constructs electric grid partition lasers, and fires converging dart spreads.

signal defeated
signal health_changed(curr: int, max_h: int)

const PROJECTILE_SCENE := preload("res://scenes/weapons/enemy_projectile.tscn")

@export var max_health := 40
var health := 40
var target: Node2D
var defeated_already := false

enum AttackPhase { IDLE, WARPING, CHARGING_GRID, ACTIVE_GRID, FIRING_DARTS, RECOVER }
var current_phase := AttackPhase.IDLE
var phase_timer := 2.0
var warp_timer := 0.0
var target_warp_pos := Vector2.ZERO
var damage_flash := 0.0
var phase_two_triggered := false

# Grid partition line parameters
var grid_h_y: float = -1.0 # Horizontal partition line Y coordinate
var grid_v_x: float = -1.0 # Vertical partition line X coordinate
var grid_hit_cooldown := 0.0
var grid_duration := 2.2

var squad_coordinator: RefCounted = null
var active_mutations: Array[Dictionary] = []

# Visual styling
const PRIMARY_COLOR := Color("a855f7") # Electric purple
const SECONDARY_COLOR := Color("7e22ce") # Deep violet
const GLITCH_COLOR := Color("d8b4fe") # Lavender highlight
const GRID_LASER_COLOR := Color("c084fc") # Bright laser purple


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
		if m_id == "GRID_OVERLOAD":
			# Grid partitions last +1.0s, but recovery window after grid increases by 0.5s
			grid_duration += 1.0
		elif m_id == "WARP_ECHO":
			# Leaves an aftershock, but boss health is 15% lower
			max_health = maxi(25, int(max_health * 0.85))
			health = max_health


func _physics_process(delta: float) -> void:
	phase_timer -= delta
	grid_hit_cooldown = maxf(0.0, grid_hit_cooldown - delta)
	damage_flash = maxf(0.0, damage_flash - delta)

	if not is_instance_valid(target):
		return

	var to_target := target.global_position - global_position
	var dist := to_target.length()

	match current_phase:
		AttackPhase.IDLE:
			# Slow hovering pursuit
			if dist > 180.0:
				velocity = to_target.normalized() * 45.0
			elif dist < 120.0:
				velocity = -to_target.normalized() * 45.0
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
						_prepare_warp()
					else:
						_prepare_grid()
				else:
					phase_timer = 0.35

		AttackPhase.WARPING:
			velocity = Vector2.ZERO
			if phase_timer <= 0.0:
				# Teleport to destination
				global_position = target_warp_pos
				current_phase = AttackPhase.FIRING_DARTS
				phase_timer = 0.8
				_fire_spiral_darts()

		AttackPhase.CHARGING_GRID:
			velocity = Vector2.ZERO
			if phase_timer <= 0.0:
				current_phase = AttackPhase.ACTIVE_GRID
				phase_timer = grid_duration

		AttackPhase.ACTIVE_GRID:
			velocity = Vector2.ZERO
			# Check player collision with horizontal and vertical grid partition laser lines
			if grid_hit_cooldown <= 0.0 and is_instance_valid(target) and target.has_method("take_damage"):
				var p_pos := target.global_position
				var hit_h := absf(p_pos.y - grid_h_y) < 14.0
				var hit_v := absf(p_pos.x - grid_v_x) < 14.0
				if hit_h or hit_v:
					target.take_damage(1)
					grid_hit_cooldown = 0.85 # Prevent tick damage

			if phase_timer <= 0.0:
				grid_h_y = -1.0
				grid_v_x = -1.0
				current_phase = AttackPhase.RECOVER
				phase_timer = 1.4 # Generous recovery window for player counterattack

		AttackPhase.FIRING_DARTS:
			velocity = Vector2.ZERO
			if phase_timer <= 0.0:
				current_phase = AttackPhase.RECOVER
				phase_timer = 1.1

		AttackPhase.RECOVER:
			velocity = Vector2.ZERO
			if squad_coordinator:
				squad_coordinator.release_attack_token(self)
			if phase_timer <= 0.0:
				current_phase = AttackPhase.IDLE
				phase_timer = randf_range(1.6, 2.5)

	queue_redraw()


func _prepare_warp() -> void:
	current_phase = AttackPhase.WARPING
	phase_timer = 0.65
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("player_dash", 0.04, -3.0)

	# Choose one of 4 quadrant anchor points in the arena [200..750, 150..400]
	var quadrants := [
		Vector2(220, 160),
		Vector2(740, 160),
		Vector2(220, 380),
		Vector2(740, 380)
	]
	quadrants.shuffle()
	target_warp_pos = quadrants[0]


func _prepare_grid() -> void:
	current_phase = AttackPhase.CHARGING_GRID
	phase_timer = 0.85
	# Center partition lines near player's current position to force tactical repositioning
	if is_instance_valid(target):
		grid_h_y = clampf(target.global_position.y, 140.0, 420.0)
		grid_v_x = clampf(target.global_position.x, 180.0, 780.0)
	else:
		grid_h_y = 276.0
		grid_v_x = 480.0
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("enemy_laser_charge", 0.06, -3.0)


func _fire_spiral_darts() -> void:
	var count := 8
	var angle_step := TAU / float(count)
	for i in range(count):
		var angle := i * angle_step
		var dir := Vector2(cos(angle), sin(angle))
		var proj = PROJECTILE_SCENE.instantiate()
		proj.global_position = global_position + dir * 28.0
		proj.direction = dir
		proj.speed = 290.0
		get_parent().add_child(proj)


func take_damage(amount: int) -> void:
	if defeated_already:
		return
	health = maxi(0, health - amount)
	damage_flash = 0.12

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


func _draw() -> void:
	var main_color := PRIMARY_COLOR if damage_flash <= 0.0 else Color.WHITE

	# Grid Laser Partitions (drawn in global coordinates offset to local)
	if grid_h_y > 0.0 or grid_v_x > 0.0:
		var local_h_y := grid_h_y - global_position.y
		var local_v_x := grid_v_x - global_position.x
		var alpha: float = 0.4 if current_phase == AttackPhase.CHARGING_GRID else 0.95
		var l_col := Color(GRID_LASER_COLOR.r, GRID_LASER_COLOR.g, GRID_LASER_COLOR.b, alpha)

		# Horizontal partition line
		draw_line(Vector2(-1000, local_h_y), Vector2(1000, local_h_y), l_col, 2.5 if current_phase == AttackPhase.ACTIVE_GRID else 1.0)
		# Vertical partition line
		draw_line(Vector2(local_v_x, -1000), Vector2(local_v_x, 1000), l_col, 2.5 if current_phase == AttackPhase.ACTIVE_GRID else 1.0)

	# Warp destination ghost indicator
	if current_phase == AttackPhase.WARPING:
		var to_dest := target_warp_pos - global_position
		draw_circle(to_dest, 18.0, Color(PRIMARY_COLOR.r, PRIMARY_COLOR.g, PRIMARY_COLOR.b, 0.35))
		draw_line(Vector2.ZERO, to_dest, Color(GLITCH_COLOR.r, GLITCH_COLOR.g, GLITCH_COLOR.b, 0.25), 1.0)

	# Fractured Hypercube Polygon
	var pts := PackedVector2Array([
		Vector2(-24, -24),
		Vector2(24, -24),
		Vector2(24, 24),
		Vector2(-24, 24)
	])
	draw_colored_polygon(pts, SECONDARY_COLOR)
	draw_polyline(pts, main_color, 2.0)

	# Inner dimensional cross
	draw_line(Vector2(-16, -16), Vector2(16, 16), GLITCH_COLOR, 1.5)
	draw_line(Vector2(16, -16), Vector2(-16, 16), GLITCH_COLOR, 1.5)
	draw_circle(Vector2.ZERO, 5.0, Color.WHITE if current_phase != AttackPhase.RECOVER else Color(0.3, 0.2, 0.4))
