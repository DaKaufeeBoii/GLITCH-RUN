extends CharacterBody2D
## Fast interceptor drone shaped as an aggressive magenta chevron with high-speed lunge and hazard trails.

signal defeated

const HAZARD_SCENE := preload("res://scenes/weapons/hazard_node.tscn")

@export var max_health := 2
@export var patrol_speed := 95.0
@export var lunge_speed := 560.0
@export var has_hazard_trail := false

var health := 2
var target: Node2D
var defeated_already := false

enum State { STALK, TELEGRAPH, LUNGE, RECOVER }
var state := State.STALK

var state_timer := 1.2
var lunge_direction := Vector2.RIGHT
var contact_dealt := false
var contact_cooldown := 0.0
var damage_flash := 0.0
var evolution_tier: int = 1
var hazard_timer := 0.0

const MAX_ACTIVE_HAZARDS := 4
var active_hazards: Array[Node2D] = []
var last_hazard_pos := Vector2.INF

var genome: RefCounted = null
var spatial_index: RefCounted = null
var squad_coordinator: RefCounted = null
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
			if state == State.TELEGRAPH or state == State.LUNGE:
				state = State.STALK
				state_timer = 0.6
	queue_redraw()


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	state_timer = randf_range(1.0, 2.0)
	queue_redraw()


func _physics_process(delta: float) -> void:
	damage_flash = maxf(0.0, damage_flash - delta)
	contact_cooldown = maxf(0.0, contact_cooldown - delta)

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
	state_timer -= delta
	var los_blocked: bool = false

	match state:
		State.STALK:
			rotation = to_target.angle()
			los_blocked = EnemySteering.is_line_blocked(global_position, target.global_position, obstacle_rects) if not obstacle_rects.is_empty() else false
			var move_dir := Vector2.ZERO
			if nav_grid != null:
				move_dir = nav_grid.get_nav_direction(global_position, target.global_position)
			else:
				if not los_blocked:
					move_dir = to_target.normalized()
					if not obstacle_rects.is_empty():
						move_dir = EnemySteering.avoid_obstacles(global_position, move_dir, obstacle_rects, 45.0)
				else:
					move_dir = EnemySteering.avoid_obstacles(global_position, to_target.normalized(), obstacle_rects, 45.0)

			var separation: Vector2 = Vector2.ZERO
			if spatial_index:
				separation = spatial_index.get_separation_for_agent(self, 30.0, 3)
			var eff_patrol: float = patrol_speed * (0.50 if debuff_slow_timer > 0.0 else 1.0)
			velocity = (move_dir + separation * 0.4).normalized() * eff_patrol

			if state_timer <= 0.0 and to_target.length() < 300.0:
				los_blocked = EnemySteering.is_line_blocked(global_position, target.global_position, obstacle_rects)
				var cur_time: float = Time.get_ticks_msec() / 1000.0
				var token_granted: bool = (squad_coordinator == null or squad_coordinator.request_attack_token(self, cur_time))

				if not los_blocked and token_granted:
					state = State.TELEGRAPH
					var timing_mult: float = float(genome.attack_timing_mult) if (genome and "attack_timing_mult" in genome) else 1.0
					state_timer = 0.55 * timing_mult
					lunge_direction = to_target.normalized()
					velocity = Vector2.ZERO
					last_hazard_pos = Vector2.INF
					queue_redraw()
				else:
					state_timer = 0.35 # Staggered retry

		State.TELEGRAPH:
			velocity = Vector2.ZERO
			queue_redraw()
			if state_timer <= 0.0:
				state = State.LUNGE
				state_timer = 0.28
				contact_dealt = false
				hazard_timer = 0.0

		State.LUNGE:
			var eff_lunge: float = lunge_speed * (0.65 if debuff_slow_timer > 0.0 else 1.0)
			velocity = lunge_direction * eff_lunge
			rotation = lunge_direction.angle()
			if not contact_dealt and to_target.length() < 32.0:
				_deal_contact_damage()

			# Drop capped, spaced electric hazard nodes along the lunge path
			if has_hazard_trail:
				hazard_timer -= delta
				if hazard_timer <= 0.0:
					hazard_timer = 0.06
					_clean_hazards()
					if active_hazards.size() < MAX_ACTIVE_HAZARDS:
						if last_hazard_pos == Vector2.INF or global_position.distance_to(last_hazard_pos) >= 45.0:
							_drop_hazard()

			if state_timer <= 0.0:
				state = State.RECOVER
				var timing_mult: float = float(genome.attack_timing_mult) if (genome and "attack_timing_mult" in genome) else 1.0
				state_timer = 0.65 * timing_mult
				velocity = Vector2.ZERO
				if squad_coordinator:
					squad_coordinator.release_attack_token(self)

		State.RECOVER:
			velocity = Vector2.ZERO
			rotation = to_target.angle()
			if state_timer <= 0.0:
				state = State.STALK
				state_timer = randf_range(1.4, 2.2)

	if is_inside_tree():
		move_and_slide()
		var col_count := get_slide_collision_count()
		for i in range(col_count):
			var col := get_slide_collision(i)
			if col:
				if col.get_collider() == target:
					_deal_contact_damage()
				var n := col.get_normal()
				if velocity.dot(n) < 0.0:
					velocity = velocity.slide(n)
	if is_instance_valid(target) and global_position.distance_to(target.global_position) <= 32.0:
		_deal_contact_damage()
	queue_redraw()


func _deal_contact_damage() -> void:
	if contact_cooldown > 0.0 or not is_instance_valid(target) or not target.has_method("take_damage"):
		return
	target.take_damage(1)
	contact_cooldown = 0.9
	contact_dealt = true
	if genome and "damage_dealt_to_player" in genome:
		genome.damage_dealt_to_player += 1


func _clean_hazards() -> void:
	var valid: Array[Node2D] = []
	for h in active_hazards:
		if is_instance_valid(h):
			valid.append(h)
	active_hazards = valid


func _drop_hazard() -> void:
	if not get_parent():
		return
	var hz = HAZARD_SCENE.instantiate()
	hz.global_position = global_position
	last_hazard_pos = global_position
	active_hazards.append(hz)
	get_parent().add_child(hz)


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
		if squad_coordinator:
			squad_coordinator.release_attack_token(self)
		defeated.emit()
		queue_free()


func _draw() -> void:
	# Warning trajectory during telegraph
	if state == State.TELEGRAPH:
		var pulse := 0.4 + sin(state_timer * 25.0) * 0.3
		var line_color := Color(1.0, 0.1, 0.5, pulse) if not has_hazard_trail else Color(1.0, 0.2, 0.7, pulse + 0.2)
		draw_line(Vector2.ZERO, to_local(global_position + lunge_direction * 220.0), line_color, 3.0)
		draw_line(Vector2.ZERO, to_local(global_position + lunge_direction * 220.0), Color("ffffff"), 1.0)

	# Evolved ion hazard trail discharge fins
	if has_hazard_trail:
		draw_line(Vector2(-12, -14), Vector2(-22, -22), Color("c084fc"), 2.2)
		draw_line(Vector2(-12, 14), Vector2(-22, 22), Color("c084fc"), 2.2)
		draw_circle(Vector2(-22, -22), 2.5, Color("e879f9"))
		draw_circle(Vector2(-22, 22), 2.5, Color("e879f9"))

	# Aggressive magenta chevron polygon
	var body_color := Color("ec4899") if damage_flash <= 0.0 else Color("ffffff")
	var pts := PackedVector2Array([
		Vector2(16, 0),
		Vector2(-12, -14),
		Vector2(-6, 0),
		Vector2(-12, 14)
	])
	draw_colored_polygon(pts, body_color)
	draw_polyline(PackedVector2Array([
		Vector2(16, 0),
		Vector2(-12, -14),
		Vector2(-6, 0),
		Vector2(-12, 14),
		Vector2(16, 0)
	]), body_color.lightened(0.4), 1.5)

	# Evolved Armored Reinforcements (Tier 3)
	if evolution_tier > 1:
		draw_line(Vector2(-12, -14), Vector2(16, 0), Color("38bdf8"), 2.2)
		draw_line(Vector2(-12, 14), Vector2(16, 0), Color("38bdf8"), 2.2)
		draw_line(Vector2(-6, -8), Vector2(6, 0), Color("a855f7"), 1.8)
		draw_line(Vector2(-6, 8), Vector2(6, 0), Color("a855f7"), 1.8)

	# Central thruster plasma core
	draw_circle(Vector2(-4, 0), 3.0, Color("fdf2f8"))

	# Health bar & Evolution Tier indicator
	if evolution_tier > 1:
		var tier_pips := evolution_tier - 1
		for p in range(tier_pips):
			draw_circle(Vector2(-6.0 + float(p) * 6.0, -26), 2.0, Color("38bdf8"))
		draw_rect(Rect2(-16, -21, 32, 4), Color("181a26"))
		var hp_ratio := float(health) / float(max_health)
		draw_rect(Rect2(-15, -20, 30.0 * hp_ratio, 2), Color("ec4899"))
	elif health < max_health:
		var hit_points := float(health) / float(max_health)
		draw_rect(Rect2(-14, -20, 28, 4), Color("181a26"))
		draw_rect(Rect2(-13, -19, 26.0 * hit_points, 2), Color("ec4899"))

	# Debuff Visual Overlays
	if debuff_slow_timer > 0.0:
		draw_circle(Vector2.ZERO, 19.0, Color(0.2, 0.8, 1.0, 0.25))
	if debuff_burn_timer > 0.0:
		draw_circle(Vector2.ZERO, 16.0, Color(0.5, 1.0, 0.2, 0.25))
	if debuff_shock_timer > 0.0:
		for s in range(3):
			var a := randf() * TAU
			draw_line(Vector2.ZERO, Vector2(cos(a), sin(a)) * 20.0, Color("c084fc"), 1.8)
