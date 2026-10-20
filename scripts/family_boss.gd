extends "res://scripts/boss.gd"
## Strong, arena-safe bosses derived from the three standard enemy families.

const HAZARD_SCENE := preload("res://scenes/weapons/hazard_node.tscn")
const MAX_TRAIL_HAZARDS := 4

@export_enum("CHASER", "DASHER", "SHOOTER") var family_archetype := "CHASER"

var aim_locked_direction := Vector2.RIGHT
var aim_lock_active := false
var trail_last_position := Vector2.ZERO
var trail_hazards_placed := 0
var family_stats_initialized := false


func _ready() -> void:
	max_health = maxi(50, max_health)
	_initialize_family_baseline()
	super._ready()
	_apply_family_mutations()


func _initialize_family_baseline() -> void:
	if family_stats_initialized:
		return
	match family_archetype:
		"CHASER":
			approach_speed = 78.0
			dash_speed = 470.0
			burst_projectile_count = 6
		"DASHER":
			approach_speed = 58.0
			dash_speed = 560.0
			post_burst_recovery = 1.15
		"SHOOTER":
			approach_speed = 48.0
			dash_speed = 360.0
			burst_projectile_count = 3
	family_stats_initialized = true


func apply_mutations(mutations: Array[Dictionary]) -> void:
	super.apply_mutations(mutations)
	if family_stats_initialized:
		_apply_family_mutations()


func _apply_family_mutations() -> void:
	for mutation in active_mutations:
		match str(mutation.get("id", "")):
			"PREDATORY_LOCK":
				approach_speed *= 1.18
				dash_speed *= 1.12
				post_burst_recovery += 0.15
			"REDLINE_OVERRUN":
				dash_speed *= 1.22
				post_burst_recovery += 0.3
			"ION_WAKE":
				# Keep the four-hazard cap; the trade-off is a more dangerous
				# trail with additional recovery time after each dash.
				post_burst_recovery += 0.35
			"AFTERIMAGE_CHAIN":
				dash_speed *= 1.16
				post_burst_recovery += 0.2
			"SIGHTLINE_CALIBRATION":
				post_burst_recovery += 0.15 # Longer lock cycle gives the player more dodge time.
			"CROSSHAIR_GRID":
				post_burst_recovery += 0.35
				burst_projectile_count = maxi(2, burst_projectile_count - 1)


func _physics_process(delta: float) -> void:
	var phase_before := current_phase
	super._physics_process(delta)
	if family_archetype == "SHOOTER":
		if current_phase == AttackPhase.CHARGING_BURST and phase_before != AttackPhase.CHARGING_BURST and is_instance_valid(target):
			aim_locked_direction = (target.global_position - global_position).normalized()
			aim_lock_active = true
		elif current_phase != AttackPhase.CHARGING_BURST and current_phase != AttackPhase.RECOVER:
			aim_lock_active = false
	if family_archetype == "DASHER":
		_update_dash_trail(phase_before)
	queue_redraw()


func _execute_burst() -> void:
	if family_archetype != "SHOOTER":
		super._execute_burst()
		return
	var direction := aim_locked_direction
	if not aim_lock_active and is_instance_valid(target):
		direction = (target.global_position - global_position).normalized()
	var shot_count := burst_projectile_count if not is_phase_two else burst_projectile_count + 2
	var spread := 0.13 if not is_phase_two else 0.20
	for i in range(shot_count):
		var centered_index := float(i) - float(shot_count - 1) * 0.5
		var shot_dir := direction.rotated(centered_index * spread).normalized()
		var proj: Node2D = PROJECTILE_SCENE.instantiate()
		proj.global_position = global_position + shot_dir * 48.0
		proj.direction = shot_dir
		proj.speed = 370.0 if not is_phase_two else 410.0
		get_parent().add_child(proj)
	aim_lock_active = false


func _update_dash_trail(phase_before: int) -> void:
	if current_phase != AttackPhase.DASHING:
		if phase_before == AttackPhase.DASHING:
			trail_hazards_placed = 0
		return
	if phase_before != AttackPhase.DASHING:
		trail_last_position = global_position
		return
	if trail_last_position.distance_to(global_position) < 68.0:
		return
	trail_last_position = global_position
	if trail_hazards_placed >= MAX_TRAIL_HAZARDS or _inside_obstacle(global_position):
		return
	var active_count := 0
	for hazard in get_tree().get_nodes_in_group("family_boss_hazard"):
		if is_instance_valid(hazard):
			active_count += 1
	if active_count >= MAX_TRAIL_HAZARDS:
		return
	var hazard: Area2D = HAZARD_SCENE.instantiate()
	hazard.global_position = global_position
	hazard.lifetime = 1.25
	hazard.max_lifetime = 1.25
	hazard.add_to_group("family_boss_hazard")
	get_parent().add_child(hazard)
	trail_hazards_placed += 1


func _inside_obstacle(point: Vector2) -> bool:
	for rect in obstacle_rects:
		if rect.grow(18.0).has_point(point):
			return true
	return false


func _draw() -> void:
	super._draw()
	match family_archetype:
		"CHASER":
			var accent := Color("fb3d55")
			for i in range(4):
				var angle := orbital_angle * 0.25 + float(i) * TAU / 4.0
				var tip := Vector2(cos(angle), sin(angle)) * 52.0
				var left := Vector2(cos(angle - 0.16), sin(angle - 0.16)) * 36.0
				var right := Vector2(cos(angle + 0.16), sin(angle + 0.16)) * 36.0
				draw_colored_polygon(PackedVector2Array([tip, left, right]), accent)
		"DASHER":
			draw_arc(Vector2.ZERO, 49.0, orbital_angle, orbital_angle + PI * 1.35, 24, Color("e879f9"), 4.0)
			draw_line(Vector2(-24, 0), Vector2(0, -23), Color.WHITE, 2.0)
			draw_line(Vector2(0, -23), Vector2(24, 0), Color.WHITE, 2.0)
		"SHOOTER":
			draw_arc(Vector2.ZERO, 48.0, 0.0, TAU, 32, Color("fbbf24"), 3.0)
			if current_phase == AttackPhase.CHARGING_BURST and aim_lock_active:
				var telegraph := Color(1.0, 0.72, 0.18, 0.72)
				draw_line(Vector2.ZERO, aim_locked_direction * 480.0, telegraph, 3.0)
				draw_line(Vector2(0.0, -5.0), Vector2(0.0, 5.0), telegraph, 2.0)
				draw_line(Vector2(-5.0, 0.0), Vector2(5.0, 0.0), telegraph, 2.0)
