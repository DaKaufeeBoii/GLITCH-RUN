extends CharacterBody2D
## Geometric pursuer drone shaped as a ruby diamond with pincer flanking subroutines.
## Evolves through same-species combat experience:
##   Tier 0: Contact pursuit only.
##   Tier 1: High-speed pursuit (+35% speed), 2x health.
##   Tier 2: Telegraphed laser projectile attack (+committed aim window), 4x health.

signal defeated

const PROJECTILE_SCENE := preload("res://scenes/weapons/enemy_projectile.tscn")

@export var max_health := 3
@export var move_speed := 92.0
@export var flank_angle := 0.0
@export var is_flanker := false
@export var has_ranged_attack := false

var health := 3
var target: Node2D
var contact_cooldown := 0.0
var defeated_already := false
var damage_flash := 0.0
var evolution_tier: int = 0

# Ranged attack state (Tier 2 learned evolution)
const TELEGRAPH_TIME := 0.65
const AIM_LOCK_TIME := 0.25 # Aim freezes during final 0.25s so player has a readable dodge window
var ranged_cooldown := 2.0
var is_charging_shot := false
var charge_timer := 0.0
var locked_aim_dir := Vector2.RIGHT
var recovery_timer := 0.0

var genome: RefCounted = null
var spatial_index: RefCounted = null
var nav_grid: RefCounted = null
var obstacle_rects: Array[Rect2] = []
var damage_multipliers: Dictionary = {
	"plasma": 1.0,
	"dash": 1.0,
	"hazard": 1.0
}

# Debuff status
var debuff_slow_timer := 0.0
var debuff_burn_timer := 0.0
var debuff_burn_tick := 0.0
var debuff_shock_timer := 0.0


func apply_debuff(type: String, duration: float, _intensity: float = 1.0) -> void:
	match type:
		"CRYO", "SLOW":
			debuff_slow_timer = maxf(debuff_slow_timer, duration)
		"ACID", "BURN":
			debuff_burn_timer = maxf(debuff_burn_timer, duration)
			debuff_burn_tick = 0.5
		"SHOCK":
			debuff_shock_timer = maxf(debuff_shock_timer, duration)
			is_charging_shot = false
	queue_redraw()


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	ranged_cooldown = randf_range(1.5, 2.5)
	queue_redraw()


func _physics_process(delta: float) -> void:
	contact_cooldown = maxf(0.0, contact_cooldown - delta)
	damage_flash = maxf(0.0, damage_flash - delta)
	ranged_cooldown = maxf(0.0, ranged_cooldown - delta)
	recovery_timer = maxf(0.0, recovery_timer - delta)

	# Debuff updates
	if debuff_slow_timer > 0.0:
		debuff_slow_timer = maxf(0.0, debuff_slow_timer - delta)

	if debuff_burn_timer > 0.0:
		debuff_burn_timer = maxf(0.0, debuff_burn_timer - delta)
		debuff_burn_tick -= delta
		if debuff_burn_tick <= 0.0:
			debuff_burn_tick = 1.0
			take_damage(1, "hazard")

	if debuff_shock_timer > 0.0:
		debuff_shock_timer = maxf(0.0, debuff_shock_timer - delta)
		velocity = Vector2.ZERO
		queue_redraw()
		return

	if not is_instance_valid(target):
		return

	var to_target := target.global_position - global_position
	var dist := to_target.length()

	# Handle active ranged charging state
	if is_charging_shot:
		velocity = Vector2.ZERO
		charge_timer -= delta
		if charge_timer > AIM_LOCK_TIME:
			# Track player before aim lock
			locked_aim_dir = to_target.normalized()
		rotation = locked_aim_dir.angle()
		queue_redraw()
		if charge_timer <= 0.0:
			is_charging_shot = false
			recovery_timer = 0.20
			ranged_cooldown = randf_range(2.5, 3.5)
			_fire_ranged_shot()
		return

	if recovery_timer > 0.0:
		velocity = Vector2.ZERO
		queue_redraw()
		return

	# Check ranged shot initiation (Tier 2 learned ability)
	if has_ranged_attack and ranged_cooldown <= 0.0 and dist >= 85.0 and dist <= 380.0:
		var los_blocked: bool = EnemySteering.is_line_blocked(global_position, target.global_position, obstacle_rects)
		if not los_blocked:
			is_charging_shot = true
			charge_timer = TELEGRAPH_TIME
			locked_aim_dir = to_target.normalized()
			velocity = Vector2.ZERO
			if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
				get_node("/root/AudioSynth").play("enemy_laser_charge", 0.05, -3.0)
			queue_redraw()
			return

	if dist > 36.0:
		# Intelligent pathfinding around obstacles with topological A* fallback
		var approach_dir := Vector2.ZERO
		if nav_grid != null:
			approach_dir = nav_grid.get_nav_direction(global_position, target.global_position)
			var los_blocked: bool = EnemySteering.is_line_blocked(global_position, target.global_position, obstacle_rects) if not obstacle_rects.is_empty() else false
			if not los_blocked and (is_flanker or absf(flank_angle) > 0.01) and dist > 85.0:
				approach_dir = approach_dir.rotated(flank_angle).normalized()
		else:
			var los_blocked: bool = EnemySteering.is_line_blocked(global_position, target.global_position, obstacle_rects) if not obstacle_rects.is_empty() else false
			if not los_blocked:
				approach_dir = to_target.normalized()
				if (is_flanker or absf(flank_angle) > 0.01) and dist > 85.0:
					approach_dir = to_target.rotated(flank_angle).normalized()
				if not obstacle_rects.is_empty():
					approach_dir = EnemySteering.avoid_obstacles(global_position, approach_dir, obstacle_rects, 45.0)
			else:
				approach_dir = EnemySteering.avoid_obstacles(global_position, to_target.normalized(), obstacle_rects, 45.0)

		# Swarm neighbor separation using shared SpatialIndex
		var separation := Vector2.ZERO
		if spatial_index != null:
			separation = spatial_index.get_separation_for_agent(self, 30.0, 4)
		elif is_inside_tree() and get_tree() != null:
			var n_positions: Array[Vector2] = []
			for node in get_tree().get_nodes_in_group("enemies"):
				if node != self and is_instance_valid(node):
					n_positions.append(node.global_position)
			separation = EnemySteering.get_separation_vector(global_position, n_positions, 30.0, 4)

		var eff_speed: float = move_speed * (0.50 if debuff_slow_timer > 0.0 else 1.0)
		velocity = (approach_dir + separation * 0.45).normalized() * eff_speed
	else:
		velocity = Vector2.ZERO
		if contact_cooldown <= 0.0 and target.has_method("take_damage"):
			target.take_damage(1)
			var timing_mult: float = float(genome.attack_timing_mult) if (genome and "attack_timing_mult" in genome) else 1.0
			contact_cooldown = 0.9 * timing_mult
			if genome and "damage_dealt_to_player" in genome:
				genome.damage_dealt_to_player += 1

	rotation = to_target.angle()
	if is_inside_tree():
		move_and_slide()
		var col_count := get_slide_collision_count()
		for i in range(col_count):
			var col := get_slide_collision(i)
			if col:
				var n := col.get_normal()
				if velocity.dot(n) < 0.0:
					velocity = velocity.slide(n)
	queue_redraw()


func _fire_ranged_shot() -> void:
	if not get_parent():
		return
	var proj = PROJECTILE_SCENE.instantiate()
	proj.global_position = global_position + locked_aim_dir * 18.0
	proj.direction = locked_aim_dir
	if "shooter_enemy" in proj:
		proj.shooter_enemy = self
	get_parent().add_child(proj)
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("player_blaster", 0.08, 4.0)
	queue_redraw()


func take_damage(amount: int, source: String = "plasma") -> void:
	if defeated_already:
		return
	var mult: float = damage_multipliers.get(source, 1.0)
	var final_amount: int = maxi(1, int(roundf(float(amount) * mult)))
	health = maxi(0, health - final_amount)
	if genome and "damage_received" in genome:
		genome.damage_received += final_amount
	damage_flash = 0.12
	queue_redraw()
	if health == 0:
		defeated_already = true
		defeated.emit()
		queue_free()


func _draw() -> void:
	# Warning laser line during ranged attack telegraph (Tier 2)
	if is_charging_shot:
		if charge_timer <= AIM_LOCK_TIME:
			# Solid committed laser line (Aim locked! Player dodge window active!)
			draw_line(Vector2.ZERO, to_local(global_position + locked_aim_dir * 360.0), Color("f43f5e"), 2.5)
			draw_line(Vector2.ZERO, to_local(global_position + locked_aim_dir * 360.0), Color("ffffff"), 1.0)
		else:
			# Pulsing tracking warning line
			var pulse := 0.4 + sin(charge_timer * 22.0) * 0.35
			draw_line(Vector2.ZERO, to_local(global_position + locked_aim_dir * 360.0), Color(0.96, 0.25, 0.37, pulse), 1.5)

	# Primary body color with damage flash
	var body_color := Color("f43f5e") if damage_flash <= 0.0 else Color("ffffff")
	var inner_color := Color("9f1239") if damage_flash <= 0.0 else Color("fecdd3")

	# Outer diamond polygon
	var outer_pts := PackedVector2Array([
		Vector2(16, 0),
		Vector2(0, -15),
		Vector2(-16, 0),
		Vector2(0, 15)
	])
	draw_colored_polygon(outer_pts, body_color)
	draw_polyline(PackedVector2Array([Vector2(16, 0), Vector2(0, -15), Vector2(-16, 0), Vector2(0, 15), Vector2(16, 0)]), body_color.lightened(0.3), 1.5)

	# Evolved pincer flanking winglets
	if is_flanker or absf(flank_angle) > 0.01:
		draw_line(Vector2(-2, -12), Vector2(-10, -20), body_color, 2.0)
		draw_line(Vector2(-2, 12), Vector2(-10, 20), body_color, 2.0)
		draw_circle(Vector2(-10, -20), 2.0, Color("38bdf8"))
		draw_circle(Vector2(-10, 20), 2.0, Color("38bdf8"))

	# Evolved Tier 2 crimson laser cannon prongs
	if has_ranged_attack:
		draw_line(Vector2(14, -5), Vector2(21, -5), Color("be123c"), 2.0)
		draw_line(Vector2(14, 5), Vector2(21, 5), Color("be123c"), 2.0)
		draw_circle(Vector2(21, -5), 1.8, Color("f43f5e"))
		draw_circle(Vector2(21, 5), 1.8, Color("f43f5e"))

	# Inner facet diamond
	var inner_pts := PackedVector2Array([
		Vector2(8, 0),
		Vector2(0, -8),
		Vector2(-8, 0),
		Vector2(0, 8)
	])
	draw_colored_polygon(inner_pts, inner_color)

	# Center optical sensor circle
	draw_circle(Vector2(3, 0), 2.5, Color("ffffff"))

	# Health bar & Evolution Tier indicator
	if evolution_tier > 0 or max_health > 3:
		var tier_pips := evolution_tier if evolution_tier > 0 else (1 if max_health <= 6 else 2)
		for p in range(tier_pips):
			draw_circle(Vector2(-4.0 + float(p) * 8.0, -27), 2.2, Color("38bdf8"))
		draw_rect(Rect2(-16, -22, 32, 4), Color("181a26"))
		var hp_ratio := float(health) / float(max_health)
		draw_rect(Rect2(-15, -21, 30.0 * hp_ratio, 2), Color("f43f5e"))
	elif health < max_health:
		var hit_points := float(health) / float(max_health)
		draw_rect(Rect2(-14, -22, 28, 4), Color("181a26"))
		draw_rect(Rect2(-13, -21, 26.0 * hit_points, 2), Color("f43f5e"))

	# Debuff Visual Overlays
	if debuff_slow_timer > 0.0:
		draw_circle(Vector2.ZERO, 19.0, Color(0.2, 0.8, 1.0, 0.25))
	if debuff_burn_timer > 0.0:
		draw_circle(Vector2.ZERO, 16.0, Color(0.5, 1.0, 0.2, 0.25))
	if debuff_shock_timer > 0.0:
		for s in range(3):
			var a := randf() * TAU
			draw_line(Vector2.ZERO, Vector2(cos(a), sin(a)) * 20.0, Color("c084fc"), 1.8)
