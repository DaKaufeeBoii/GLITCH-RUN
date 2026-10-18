extends Area2D
## Lingering electric ion hazard dropped by evolved Dashers.

var lifetime := 1.75
var max_lifetime := 1.75
var damage := 1


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	body_entered.connect(_on_body_entered)
	queue_redraw()


func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("take_damage"):
		if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
			get_node("/root/AudioSynth").play("hazard_shock", 0.05, -1.0)
		body.take_damage(damage)


func _draw() -> void:
	var alpha := clampf(lifetime / max_lifetime, 0.0, 1.0)
	var pulse := 0.75 + sin((max_lifetime - lifetime) * 18.0) * 0.25

	# Outer ion glow
	draw_circle(Vector2.ZERO, 13.0 * pulse, Color(0.93, 0.29, 0.60, 0.22 * alpha))
	# Concentric energetic spark ring
	draw_circle(Vector2.ZERO, 7.5, Color(0.93, 0.29, 0.60, 0.75 * alpha))
	draw_circle(Vector2.ZERO, 3.0, Color(1.0, 1.0, 1.0, 0.9 * alpha))

	# Electric crackle arcs
	for i in range(2):
		var a := randf() * TAU
		var p1 := Vector2(cos(a), sin(a)) * 3.0
		var p2 := Vector2(cos(a + 0.5), sin(a + 0.5)) * 12.0
		draw_line(p1, p2, Color("f472b6", alpha * 0.8), 1.5)
