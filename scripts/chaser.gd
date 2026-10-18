extends CharacterBody2D
## Geometric pursuer drone shaped as a ruby diamond with pincer flanking subroutines.

signal defeated

@export var max_health := 3
@export var move_speed := 92.0
@export var flank_angle := 0.0
@export var is_flanker := false

var health := 3
var target: Node2D
var contact_cooldown := 0.0
var defeated_already := false
var damage_flash := 0.0


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	queue_redraw()


func _physics_process(delta: float) -> void:
	contact_cooldown = maxf(0.0, contact_cooldown - delta)
	damage_flash = maxf(0.0, damage_flash - delta)

	if not is_instance_valid(target):
		return

	var to_target := target.global_position - global_position
	var dist := to_target.length()

	if dist > 36.0:
		# Pincer flanking trajectory when at medium/long range
		var approach_dir := to_target.normalized()
		if (is_flanker or absf(flank_angle) > 0.01) and dist > 85.0:
			approach_dir = to_target.rotated(flank_angle).normalized()

		# Swarm neighbor separation to prevent stacking
		var separation := Vector2.ZERO
		if is_inside_tree() and get_tree() != null:
			for node in get_tree().get_nodes_in_group("enemies"):
				if node != self and is_instance_valid(node):
					var d := global_position.distance_to(node.global_position)
					if d < 28.0 and d > 0.0:
						separation += (global_position - node.global_position).normalized() * ((28.0 - d) / 28.0)

		velocity = (approach_dir + separation * 0.4).normalized() * move_speed
	else:
		velocity = Vector2.ZERO
		if contact_cooldown <= 0.0 and target.has_method("take_damage"):
			target.take_damage(1)
			contact_cooldown = 0.9

	rotation = to_target.angle()
	if is_inside_tree():
		move_and_slide()
	queue_redraw()


func take_damage(amount: int) -> void:
	if defeated_already:
		return
	health = maxi(0, health - amount)
	damage_flash = 0.12
	queue_redraw()
	if health == 0:
		defeated_already = true
		defeated.emit()
		queue_free()


func _draw() -> void:
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

	# Health bar
	if health < max_health:
		var hit_points := float(health) / float(max_health)
		draw_rect(Rect2(-14, -22, 28, 4), Color("181a26"))
		draw_rect(Rect2(-13, -21, 26.0 * hit_points, 2), Color("f43f5e"))
