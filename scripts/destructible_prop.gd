extends StaticBody2D
class_name DestructibleProp
## Soul Knight-inspired tactical environmental prop for GLITCH//RUN.
## Supports reactive destructibility, explosive area-of-effect damage,
## cryo freezing blasts, toxic acid puddles, and heavy blast cover.

signal prop_detonated(prop_node: DestructibleProp)

var prop_type: String = "EXPLOSIVE_BARREL"
var health: int = 2
var max_health: int = 2
var is_destructible: bool = true
var is_destroyed: bool = false
var prop_size: Vector2 = Vector2(40.0, 40.0)
var game_ref: Node2D = null
var accent_color: Color = Color("ef4444")
var prop_rect: Rect2 = Rect2()
var hit_flash_timer: float = 0.0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("obstacles")
	add_to_group("props")

	# Configure durability & destructibility based on prop archetype
	match prop_type:
		"EXPLOSIVE_BARREL":
			max_health = 2
			health = 2
			is_destructible = true
			accent_color = Color("ef4444")
		"CRYO_CANISTER":
			max_health = 2
			health = 2
			is_destructible = true
			accent_color = Color("38bdf8")
		"TOXIC_VAT":
			max_health = 2
			health = 2
			is_destructible = true
			accent_color = Color("22c55e")
		"DATA_PYLON":
			max_health = 3
			health = 3
			is_destructible = true
			accent_color = Color("00f0ff")
		"SERVER_RACK":
			max_health = 9999
			health = 9999
			is_destructible = false
			accent_color = Color("64748b")
		"HEAVY_BARRIER":
			max_health = 9999
			health = 9999
			is_destructible = false
			accent_color = Color("475569")
		_:
			max_health = 9999
			health = 9999
			is_destructible = false
			accent_color = Color("475569")

	prop_rect = Rect2(position - prop_size * 0.5, prop_size)

	var col_shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = prop_size
	col_shape.shape = box
	add_child(col_shape)
	queue_redraw()


func _process(delta: float) -> void:
	if hit_flash_timer > 0.0:
		hit_flash_timer -= delta
		queue_redraw()


func take_damage(amount: int) -> void:
	if not is_destructible or is_destroyed:
		# Clink ricochet effect for solid heavy cover
		hit_flash_timer = 0.08
		queue_redraw()
		return

	health -= amount
	hit_flash_timer = 0.12
	queue_redraw()

	if health <= 0:
		detonate()


func detonate() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	prop_detonated.emit(self)

	if is_instance_valid(game_ref) and game_ref.has_method("on_prop_destroyed"):
		game_ref.on_prop_destroyed(self)

	queue_free()


func _draw() -> void:
	var r := Rect2(-prop_size * 0.5, prop_size)
	var flash: bool = hit_flash_timer > 0.0

	# 1. Cast shadow
	var shadow_rect := Rect2(r.position.x + 3.0, r.position.y + 4.0, r.size.x, r.size.y)
	draw_rect(shadow_rect, Color(0.0, 0.0, 0.0, 0.55), true)

	if flash:
		draw_rect(r, Color.WHITE, true)
		return

	match prop_type:
		"EXPLOSIVE_BARREL":
			_draw_explosive_barrel(r)
		"CRYO_CANISTER":
			_draw_cryo_canister(r)
		"TOXIC_VAT":
			_draw_toxic_vat(r)
		"SERVER_RACK":
			_draw_server_rack(r)
		"HEAVY_BARRIER":
			_draw_heavy_barrier(r)
		"DATA_PYLON":
			_draw_data_pylon(r)
		_:
			_draw_heavy_barrier(r)


func _draw_explosive_barrel(r: Rect2) -> void:
	# Cylindrical red volatile barrel
	draw_rect(r, Color("991b1b"), true)
	draw_rect(r, Color("ef4444"), false, 1.5)

	# Metallic dark end-caps
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 6.0), Color("1e293b"), true)
	draw_rect(Rect2(r.position.x, r.end.y - 6.0, r.size.x, 6.0), Color("1e293b"), true)

	# Hazard chevrons across middle
	var mid_y: float = r.get_center().y
	draw_line(Vector2(r.position.x + 4.0, mid_y - 4.0), Vector2(r.position.x + 12.0, mid_y + 4.0), Color("eab308"), 2.0)
	draw_line(Vector2(r.position.x + 14.0, mid_y - 4.0), Vector2(r.position.x + 22.0, mid_y + 4.0), Color("eab308"), 2.0)
	draw_line(Vector2(r.position.x + 24.0, mid_y - 4.0), Vector2(r.position.x + 32.0, mid_y + 4.0), Color("eab308"), 2.0)

	# Glowing core flame dot
	var pulse: float = 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.008)
	draw_circle(r.get_center(), 4.5, Color(1.0, 0.4, 0.1, 0.45 * pulse))
	draw_circle(r.get_center(), 2.5, Color("f97316"))
	draw_circle(r.get_center(), 1.0, Color.WHITE)



func _draw_cryo_canister(r: Rect2) -> void:
	# Frost cryogenic pod
	draw_rect(r, Color("0369a1"), true)
	draw_rect(r, Color("38bdf8"), false, 1.5)

	# Thermal cooling rib plates
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 5.0), Color("0f172a"), true)
	draw_rect(Rect2(r.position.x, r.end.y - 5.0, r.size.x, 5.0), Color("0f172a"), true)

	# Translucent cryogenic liquid core
	var pulse: float = 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.006)
	var core_rect := Rect2(r.position.x + 6.0, r.position.y + 8.0, r.size.x - 12.0, r.size.y - 16.0)
	draw_rect(core_rect, Color(0.2, 0.8, 1.0, 0.35 * pulse), true)

	# Frost crystal emblem lines
	var c := r.get_center()
	draw_line(Vector2(c.x - 7.0, c.y), Vector2(c.x + 7.0, c.y), Color("e0f2fe"), 1.5)
	draw_line(Vector2(c.x, c.y - 7.0), Vector2(c.x, c.y + 7.0), Color("e0f2fe"), 1.5)
	draw_circle(c, 2.0, Color.WHITE)



func _draw_toxic_vat(r: Rect2) -> void:
	# Caustic biohazard vat
	draw_rect(r, Color("14532d"), true)
	draw_rect(r, Color("22c55e"), false, 1.5)

	# Steel container banding
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 5.0), Color("0f172a"), true)
	draw_rect(Rect2(r.position.x, r.end.y - 5.0, r.size.x, 5.0), Color("0f172a"), true)

	# Toxic liquid gauge window
	var pulse: float = 0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.007)
	var win_rect := Rect2(r.position.x + 8.0, r.position.y + 8.0, r.size.x - 16.0, r.size.y - 16.0)
	draw_rect(win_rect, Color(0.1, 0.9, 0.3, 0.40 * pulse), true)

	# Biohazard tri-dots
	var c := r.get_center()
	draw_circle(Vector2(c.x - 4.0, c.y - 2.0), 2.2, Color("86efac"))
	draw_circle(Vector2(c.x + 4.0, c.y - 2.0), 2.2, Color("86efac"))
	draw_circle(Vector2(c.x, c.y + 4.0), 2.2, Color("86efac"))



func _draw_server_rack(r: Rect2) -> void:
	# Heavy data mainframe
	draw_rect(r, Color("0f172a"), true)
	draw_rect(r, Color("334155"), false, 1.5)
	draw_line(r.position, Vector2(r.end.x, r.position.y), Color("38bdf8"), 2.0)

	# Server blade bay slats
	for y in range(int(r.position.y + 8.0), int(r.end.y - 6.0), 8):
		draw_line(Vector2(r.position.x + 5.0, y), Vector2(r.end.x - 5.0, y), Color("1e293b"), 1.0)

	# Diagnostic status LEDs
	var ticks := Time.get_ticks_msec()
	var g_on := int(ticks / 320.0) % 2 == 0
	var a_on := int(ticks / 480.0) % 2 == 0
	var c_on := int(ticks / 600.0) % 2 == 0
	draw_circle(r.position + Vector2(6.0, 6.0), 1.8, Color("22c55e") if g_on else Color("14532d"))
	draw_circle(r.position + Vector2(12.0, 6.0), 1.8, Color("eab308") if a_on else Color("713f12"))
	draw_circle(r.position + Vector2(18.0, 6.0), 1.8, Color("06b6d4") if c_on else Color("164e63"))



func _draw_heavy_barrier(r: Rect2) -> void:
	# Heavy reinforced composite blast barrier
	draw_rect(r, Color("1e293b"), true)
	draw_rect(r, Color("475569"), false, 1.5)

	# Hardlight defense trim
	draw_line(r.position, Vector2(r.end.x, r.position.y), accent_color, 2.5)

	# Heavy corner reinforcement bolts
	draw_circle(r.position + Vector2(4.0, 4.0), 1.5, Color("94a3b8"))
	draw_circle(Vector2(r.end.x - 4.0, r.position.y + 4.0), 1.5, Color("94a3b8"))
	draw_circle(Vector2(r.position.x + 4.0, r.end.y - 4.0), 1.5, Color("94a3b8"))
	draw_circle(Vector2(r.end.x - 4.0, r.end.y - 4.0), 1.5, Color("94a3b8"))

	# Center armored crest
	draw_line(Vector2(r.position.x + 8.0, r.get_center().y), Vector2(r.end.x - 8.0, r.get_center().y), Color("334155"), 2.0)


func _draw_data_pylon(r: Rect2) -> void:
	# High-tech obelisk with glowing crystal center
	var c := r.get_center()
	var pts := PackedVector2Array([
		Vector2(c.x, r.position.y + 2.0),
		Vector2(r.end.x - 4.0, c.y),
		Vector2(c.x, r.end.y - 2.0),
		Vector2(r.position.x + 4.0, c.y)
	])
	draw_colored_polygon(pts, Color("0f172a"))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color("00f0ff"), 1.5)

	var pulse: float = 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.009)
	draw_circle(c, 5.0, Color(0.0, 0.94, 1.0, 0.40 * pulse))
	draw_circle(c, 2.5, Color("00f0ff"))
	draw_circle(c, 1.0, Color.WHITE)
