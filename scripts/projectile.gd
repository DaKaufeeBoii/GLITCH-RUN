extends Area2D
## Player plasma bolt with geometric cyan glow, trail drawing, and reliable collision handling.

@export var speed := 640.0
@export var damage := 1
var direction := Vector2.RIGHT
var lifetime := 1.6
var visual_clock := 0.0
var player_source: Node2D = null

var debuff_type := "" # "CRYO", "ACID", "SHOCK"
var debuff_duration := 3.0
var is_piercing := false
var pierced_bodies: Array[Node2D] = []


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	rotation = direction.angle()
	queue_redraw()


func _physics_process(delta: float) -> void:
	visual_clock += delta
	global_position += direction * speed * delta
	lifetime -= delta
	queue_redraw()
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	# Never collide with the firing player or already pierced targets
	if body.is_in_group("player") or body == self or body in pierced_bodies:
		return

	if body.is_in_group("enemies"):
		pierced_bodies.append(body)
		if is_instance_valid(player_source) and player_source.has_signal("shot_hit"):
			player_source.shot_hit.emit(body)
		if body.has_method("take_damage"):
			body.take_damage(damage)

		# Apply Debuff
		if debuff_type != "" and body.has_method("apply_debuff"):
			body.apply_debuff(debuff_type, debuff_duration)

		# Arc Discharge (Chain Lightning)
		if debuff_type == "SHOCK":
			_trigger_chain_lightning(body)

		if is_piercing and pierced_bodies.size() <= 1:
			return # Continue travelling through first enemy
		queue_free()
		return

	# Collided with static arena walls or obstacles
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()


func _trigger_chain_lightning(primary_target: Node2D) -> void:
	if not get_parent():
		return
	var nearest_enemy: Node2D = null
	var min_d := 160.0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy != primary_target and not enemy in pierced_bodies:
			var d := primary_target.global_position.distance_to(enemy.global_position)
			if d < min_d:
				min_d = d
				nearest_enemy = enemy

	if is_instance_valid(nearest_enemy):
		if nearest_enemy.has_method("take_damage"):
			nearest_enemy.take_damage(1, "hazard")
		if nearest_enemy.has_method("apply_debuff"):
			nearest_enemy.apply_debuff("SHOCK", 0.65)
		# Spawn visual arc
		var arc_line := Line2D.new()
		arc_line.width = 2.5
		arc_line.default_color = Color("c084fc")
		var p1: Vector2 = primary_target.global_position
		var p2: Vector2 = nearest_enemy.global_position
		var mid: Vector2 = (p1 + p2) * 0.5 + Vector2(randf_range(-16, 16), randf_range(-16, 16))
		arc_line.add_point(p1)
		arc_line.add_point(mid)
		arc_line.add_point(p2)
		get_parent().add_child(arc_line)
		var t := arc_line.create_tween()
		t.tween_property(arc_line, "modulate:a", 0.0, 0.15)
		t.tween_callback(Callable(arc_line, "queue_free"))


func _draw() -> void:
	# Primary color scheme according to elemental debuff
	var glow_color := Color(0.22, 0.74, 0.97, 1.0) # Cyber cyan default
	if debuff_type == "CRYO":
		glow_color = Color("a5f3fc") # Chilled cryogenic frost
	elif debuff_type == "ACID":
		glow_color = Color("84cc16") # Corrosive nanite lime
	elif debuff_type == "SHOCK":
		glow_color = Color("c084fc") # High-voltage ion purple

	# Trailing ion energy line
	var pulse := 0.8 + (sin(visual_clock * 18.0) + 1.0) * 0.18
	draw_line(Vector2(-10.0 * pulse, 0), Vector2(2, 0), glow_color * Color(1, 1, 1, 0.55), 3.5 * pulse)
	# Glowing outer sphere
	draw_circle(Vector2(2, 0), 4.0 + pulse * 0.6, glow_color)
	# White-hot energetic core
	draw_circle(Vector2(2, 0), 2.2, Color(1.0, 1.0, 1.0, 1.0))
