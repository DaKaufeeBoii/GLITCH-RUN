extends Control
class_name MinimapHUD
## Real-time in-game HUD Minimap for GLITCH//RUN.
## Placed on the top-right corner of the HUD, renders authentic multi-room
## chamber blueprints, connecting corridors, player real-time location, and room archetypes.

signal minimap_tapped

var room_summaries: Array[Dictionary] = []
var active_room_index: int = 0
var player_ref: Node2D = null

const MAP_SIZE := Vector2(142.0, 96.0)
const CHAMBER_SIZE := Vector2(16.0, 13.0)
const BOSS_CHAMBER_SIZE := Vector2(22.0, 18.0)


func _ready() -> void:
	custom_minimum_size = MAP_SIZE
	size = MAP_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)


func _on_gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		minimap_tapped.emit()
		accept_event()


func update_map(summaries: Array, current_index: int, player: Node2D = null) -> void:
	room_summaries.clear()
	for entry in summaries:
		if entry is Dictionary:
			room_summaries.append(entry)
	active_room_index = current_index
	player_ref = player
	queue_redraw()


func _room_position(index: int, total: int) -> Vector2:
	if index < room_summaries.size():
		var summary: Dictionary = room_summaries[index]
		if summary.has("grid_x") and summary.has("grid_y"):
			var min_x := 9999
			var max_x := -9999
			var min_y := 9999
			var max_y := -9999
			for s in room_summaries:
				var gx: int = s.get("grid_x", 0)
				var gy: int = s.get("grid_y", 0)
				min_x = mini(min_x, gx)
				max_x = maxi(max_x, gx)
				min_y = mini(min_y, gy)
				max_y = maxi(max_y, gy)
			var span_x: float = maxf(1.0, float(max_x - min_x))
			var span_y: float = maxf(1.0, float(max_y - min_y))
			var cur_gx: float = float(summary.get("grid_x", 0) - min_x)
			var cur_gy: float = float(summary.get("grid_y", 0) - min_y)
			var pad_x := 18.0
			var pad_y := 22.0
			var px := pad_x + (cur_gx / span_x) * (size.x - pad_x * 2.0)
			var py := pad_y + (cur_gy / span_y) * (size.y - pad_y - 12.0)
			return Vector2(px, py)

	var pad := 16.0
	var spacing: float = (size.x - pad * 2.0) / float(maxi(1, total - 1))
	return Vector2(pad + float(index) * spacing, size.y * 0.58)


func _draw() -> void:
	# 1. Dark holographic panel with neon border
	var bg_rect := Rect2(Vector2.ZERO, size)
	draw_rect(bg_rect, Color(0.015, 0.03, 0.07, 0.88), true)
	draw_rect(bg_rect, Color(0.0, 0.85, 1.0, 0.65), false, 1.0)

	# Corner accents
	var c_len := 6.0
	var corner_col := Color("00f0ff")
	draw_line(Vector2(0, 0), Vector2(c_len, 0), corner_col, 1.5)
	draw_line(Vector2(0, 0), Vector2(0, c_len), corner_col, 1.5)
	draw_line(Vector2(size.x, 0), Vector2(size.x - c_len, 0), corner_col, 1.5)
	draw_line(Vector2(size.x, 0), Vector2(size.x, c_len), corner_col, 1.5)
	draw_line(Vector2(0, size.y), Vector2(c_len, size.y), corner_col, 1.5)
	draw_line(Vector2(0, size.y), Vector2(0, size.y - c_len), corner_col, 1.5)
	draw_line(Vector2(size.x, size.y), Vector2(size.x - c_len, size.y), corner_col, 1.5)
	draw_line(Vector2(size.x, size.y), Vector2(size.x, size.y - c_len), corner_col, 1.5)

	# Header label
	var font := ThemeDB.fallback_font
	if font:
		draw_string(font, Vector2(8, 13), "MINIMAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("38bdf8"))
		draw_string(font, Vector2(size.x - 36, 13), "TAP", HORIZONTAL_ALIGNMENT_RIGHT, -1, 8, Color("64748b"))

	if room_summaries.is_empty():
		return

	var total := room_summaries.size()
	var positions: Array[Vector2] = []
	for i in range(total):
		positions.append(_room_position(i, total))

	# 2. Corridors
	for i in range(total):
		var s_from: Dictionary = room_summaries[i]
		if s_from.get("is_secret", false) and not s_from.get("is_revealed", false):
			continue
		var conns: Array = s_from.get("connections", [])
		for target in conns:
			var target_index := int(target)
			if target_index <= i or target_index >= total:
				continue
			var s_to: Dictionary = room_summaries[target_index]
			if s_to.get("is_secret", false) and not s_to.get("is_revealed", false):
				continue
			var traversed := (i <= active_room_index and target_index <= active_room_index)
			var line_col := Color(0.0, 0.94, 1.0, 0.75) if traversed else Color(0.18, 0.28, 0.42, 0.50)
			draw_line(positions[i], positions[target_index], line_col, 1.5)

	# 3. Room Chambers
	var ticks := Time.get_ticks_msec()
	var pulse := 0.7 + 0.3 * sin(float(ticks) * 0.008)

	for i in range(total):
		var summary: Dictionary = room_summaries[i]
		var is_secret: bool = summary.get("is_secret", false)
		var is_revealed: bool = summary.get("is_revealed", false)
		if is_secret and not is_revealed:
			continue

		var r_type: String = summary.get("room_type", "COMBAT")
		var pos: Vector2 = positions[i]
		var is_current := (i == active_room_index)
		var is_cleared := (i < active_room_index)

		var c_sz := BOSS_CHAMBER_SIZE if r_type == "BOSS" else CHAMBER_SIZE
		var rect := Rect2(pos - c_sz * 0.5, c_sz)

		# Chamber box fill & border
		var fill := Color(0.03, 0.07, 0.15, 0.95)
		var border := Color(0.20, 0.30, 0.45, 0.70)
		if is_current:
			fill = Color(0.05, 0.20, 0.35, 0.98)
			border = Color("00f0ff")
			draw_rect(Rect2(rect.position - Vector2(2, 2), rect.size + Vector2(4, 4)), Color(0.0, 0.94, 1.0, 0.25 * pulse), false, 1.0)
		elif is_cleared:
			fill = Color(0.03, 0.12, 0.08, 0.90)
			border = Color("22c55e") if r_type == "RECOVERY" else Color("38bdf8")

		if is_secret:
			border = Color("c084fc")
			fill = Color(0.14, 0.05, 0.24, 0.95)

		draw_rect(rect, fill, true)
		draw_rect(rect, border, false, 1.5 if is_current else 1.0)

		# Chamber Emblem
		match r_type:
			"START":
				draw_circle(pos, 2.0, Color("38bdf8"))
			"RECOVERY":
				var g_col := Color("22c55e")
				draw_line(pos + Vector2(-3, 0), pos + Vector2(3, 0), g_col, 1.5)
				draw_line(pos + Vector2(0, -3), pos + Vector2(0, 3), g_col, 1.5)
			"SHOP":
				var s_col := Color("00f0ff")
				draw_circle(pos, 2.5, s_col)
				draw_circle(pos, 1.0, Color.WHITE)
			"GIFT", "CACHE":
				var a_col := Color("f59e0b") if r_type == "CACHE" else Color("c084fc")
				draw_rect(Rect2(pos - Vector2(2, 2), Vector2(4, 4)), a_col, true)
			"SHRINE":
				draw_circle(pos, 2.2, Color("818cf8"))
			"TRANSIT":
				var t_col := Color("38bdf8")
				draw_line(pos + Vector2(-3, -2), pos + Vector2(0, 0), t_col, 1.2)
				draw_line(pos + Vector2(0, 0), pos + Vector2(-3, 2), t_col, 1.2)
				draw_line(pos + Vector2(0, -2), pos + Vector2(3, 0), Color.WHITE, 1.2)
				draw_line(pos + Vector2(3, 0), pos + Vector2(0, 2), Color.WHITE, 1.2)
			"SECRET":
				draw_rect(Rect2(pos - Vector2(2.5, 2.5), Vector2(5, 5)), Color("c084fc"), false, 1.2)
				draw_circle(pos, 1.5 * pulse, Color.WHITE)
			"BOSS":
				draw_arc(pos, 3.5, 0.0, TAU, 12, Color("ef4444"), 1.2)
				draw_circle(pos, 1.5 * pulse, Color("ef4444"))
			_: # COMBAT, ELITE
				var c_col := Color("f97316") if r_type == "ELITE" else Color("38bdf8")
				draw_circle(pos, 1.8, c_col if not is_cleared else Color("64748b"))

		# Player Position Pip inside current room
		if is_current:
			draw_circle(pos, 2.5 * pulse, Color.WHITE)
