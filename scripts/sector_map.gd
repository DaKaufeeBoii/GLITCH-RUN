extends Control
class_name SectorMap
## Cyberpunk top-down facility blueprint route map for GLITCH//RUN.
## Renders authentic chamber geometries, connecting corridors, laser thresholds,
## and room-type emblems (Green Cross, Cyan Cart, Purple Diamond, Boss Core).

var room_summaries: Array[Dictionary] = []
var active_room_index: int = 0

const MAP_HEIGHT := 140.0
const CHAMBER_SIZE := Vector2(36.0, 32.0)
const BOSS_CHAMBER_SIZE := Vector2(46.0, 42.0)


func _ready() -> void:
	custom_minimum_size = Vector2(480.0, MAP_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func configure_map(summaries: Array, current_index: int, total_rooms: int) -> void:
	room_summaries.clear()
	for entry in summaries:
		if entry is Dictionary:
			room_summaries.append(entry)
	active_room_index = clampi(current_index, 0, maxi(0, total_rooms - 1))
	queue_redraw()


func _room_position(index: int, room_type: String, spacing: float, start_x: float) -> Vector2:
	var lane_y := MAP_HEIGHT * 0.50
	if room_type in ["RECOVERY"]:
		lane_y = MAP_HEIGHT * 0.20
	elif room_type in ["GIFT"]:
		lane_y = MAP_HEIGHT * 0.22
	elif room_type in ["SHOP"]:
		lane_y = MAP_HEIGHT * 0.80
	elif room_type in ["ELITE"]:
		lane_y = MAP_HEIGHT * 0.68
	var x := start_x + float(index) * spacing
	return Vector2(x, lane_y)


func _room_color(room_type: String) -> Color:
	match room_type:
		"START":
			return Color("38bdf8")
		"SHOP":
			return Color("00f0ff") # Neon cyan cart
		"GIFT":
			return Color("c084fc") # Purple diamond
		"RECOVERY":
			return Color("22c55e") # Medical green
		"ELITE":
			return Color("f97316") # Orange threat
		"BOSS":
			return Color("ef4444") # Crimson Overlord
		_:
			return Color("38bdf8")


func _draw_chamfered_rect(center_pos: Vector2, sz: Vector2, fill_col: Color, border_col: Color, chamfer: float = 6.0, line_w: float = 1.5) -> void:
	var hw := sz.x * 0.5
	var hh := sz.y * 0.5
	var c := minf(chamfer, minf(hw, hh) * 0.45)
	var pts := PackedVector2Array([
		center_pos + Vector2(-hw + c, -hh),
		center_pos + Vector2(hw - c, -hh),
		center_pos + Vector2(hw, -hh + c),
		center_pos + Vector2(hw, hh - c),
		center_pos + Vector2(hw - c, hh),
		center_pos + Vector2(-hw + c, hh),
		center_pos + Vector2(-hw, hh - c),
		center_pos + Vector2(-hw, -hh + c)
	])
	draw_colored_polygon(pts, fill_col)
	var border_pts := PackedVector2Array(pts)
	border_pts.append(pts[0])
	draw_polyline(border_pts, border_col, line_w, true)


func _draw_corridor(from_pos: Vector2, to_pos: Vector2, is_traversed: bool) -> void:
	var base_col := Color(0.00, 0.94, 1.0, 0.80) if is_traversed else Color(0.12, 0.24, 0.38, 0.65)
	var glow_col := Color(0.00, 0.94, 1.0, 0.25) if is_traversed else Color(0.08, 0.16, 0.26, 0.40)
	
	# Determine bend path (horizontal -> vertical -> horizontal)
	var mid_x := (from_pos.x + to_pos.x) * 0.5
	var p1 := from_pos
	var p2 := Vector2(mid_x, from_pos.y)
	var p3 := Vector2(mid_x, to_pos.y)
	var p4 := to_pos

	var path := PackedVector2Array([p1, p2, p3, p4])
	draw_polyline(path, glow_col, 5.0, true)
	draw_polyline(path, base_col, 2.0, true)

	# Doorway laser threshold marks (dotted perpendicular bar)
	var d_pos := p1.lerp(p2, 0.40)
	draw_line(d_pos + Vector2(0, -4), d_pos + Vector2(0, 4), Color("38bdf8") if is_traversed else Color("475569"), 1.5)


func _draw() -> void:
	if room_summaries.is_empty():
		return

	var total := room_summaries.size()
	var start_x := 30.0
	var spacing := (size.x - 60.0) / float(maxi(1, total - 1))
	var positions: Array[Vector2] = []
	for i in range(total):
		var r_type: String = room_summaries[i].get("room_type", "COMBAT")
		positions.append(_room_position(i, r_type, spacing, start_x))

	# 1. Background tactical facility grid
	var bg_grid_col := Color(0.08, 0.14, 0.24, 0.30)
	for x in range(0, int(size.x), 24):
		draw_line(Vector2(x, 0), Vector2(x, size.y), bg_grid_col, 1.0)
	for y in range(0, int(size.y), 24):
		draw_line(Vector2(0, y), Vector2(size.x, y), bg_grid_col, 1.0)

	# 2. Corridors connecting chambers
	for i in range(total):
		var conns: Array = room_summaries[i].get("connections", [])
		for target in conns:
			var target_index := int(target)
			if target_index <= i or target_index >= total:
				continue
			var traversed := i < active_room_index
			_draw_corridor(positions[i], positions[target_index], traversed)

	# 3. Chambers with authentic cyberpunk blueprints
	var font := ThemeDB.fallback_font
	var ticks := Time.get_ticks_msec()
	var pulse := 0.75 + 0.25 * sin(float(ticks) * 0.007)

	for i in range(total):
		var r_type: String = room_summaries[i].get("room_type", "COMBAT")
		var pos: Vector2 = positions[i]
		var is_current := (i == active_room_index)
		var is_cleared := (i < active_room_index)
		var accent := _room_color(r_type)

		var c_size := BOSS_CHAMBER_SIZE if r_type == "BOSS" else (Vector2(32.0, 26.0) if r_type == "START" else CHAMBER_SIZE)
		var fill_col := Color(0.03, 0.06, 0.12, 0.96)
		var border_col := accent if (is_current or is_cleared) else Color(0.20, 0.28, 0.38, 0.8)

		if is_current:
			fill_col = Color(0.05, 0.14, 0.24, 0.98)
			border_col = Color("00f0ff")
			# Outer pulsating neon beacon halo
			_draw_chamfered_rect(pos, c_size + Vector2(6, 6), Color(0.0, 0.94, 1.0, 0.18 * pulse), Color("00f0ff"), 7.0, 1.2)
		elif is_cleared:
			fill_col = Color(0.04, 0.10, 0.08, 0.95)

		# Draw primary chamfered room chamber
		_draw_chamfered_rect(pos, c_size, fill_col, border_col, 5.0, 1.8 if is_current else 1.2)

		# Draw internal room emblems matching the user's reference map
		match r_type:
			"START":
				# Ingress airlock concentric pod
				draw_circle(pos, 5.0, Color("38bdf8") if is_current else Color("64748b"))
				draw_circle(pos, 2.0, Color.WHITE)

			"RECOVERY":
				# Glowing Green Medical Cross
				var g_col := Color("22c55e")
				draw_rect(Rect2(pos.x - 2.5, pos.y - 7.0, 5.0, 14.0), g_col, true)
				draw_rect(Rect2(pos.x - 7.0, pos.y - 2.5, 14.0, 5.0), g_col, true)
				draw_circle(pos, 9.0, Color(0.13, 0.77, 0.36, 0.25))

			"SHOP":
				# Glowing Cyan Shopping Cart Emblem
				var s_col := Color("00f0ff")
				# Cart basket
				draw_line(pos + Vector2(-6, -4), pos + Vector2(4, -4), s_col, 1.5)
				draw_line(pos + Vector2(4, -4), pos + Vector2(2, 2), s_col, 1.5)
				draw_line(pos + Vector2(2, 2), pos + Vector2(-4, 2), s_col, 1.5)
				draw_line(pos + Vector2(-4, 2), pos + Vector2(-6, -4), s_col, 1.5)
				# Handle and wheels
				draw_line(pos + Vector2(4, -4), pos + Vector2(6, -6), s_col, 1.5)
				draw_circle(pos + Vector2(-3, 4), 1.3, s_col)
				draw_circle(pos + Vector2(2, 4), 1.3, s_col)

			"GIFT":
				# Glowing Purple Diamond Emblem
				var p_col := Color("c084fc")
				var d_pts := PackedVector2Array([
					pos + Vector2(0, -7),
					pos + Vector2(6, 0),
					pos + Vector2(0, 7),
					pos + Vector2(-6, 0)
				])
				draw_colored_polygon(d_pts, Color(0.75, 0.52, 0.98, 0.35))
				var d_border := PackedVector2Array(d_pts)
				d_border.append(d_pts[0])
				draw_polyline(d_border, p_col, 1.5)
				draw_circle(pos, 2.0, Color.WHITE)

			"BOSS":
				# 4 Corner Bastions + Central Summoning Core
				var b_col := Color("ef4444")
				var bast_offset := 13.0
				draw_rect(Rect2(pos.x - bast_offset - 3, pos.y - bast_offset - 3, 6, 6), b_col, true)
				draw_rect(Rect2(pos.x + bast_offset - 3, pos.y - bast_offset - 3, 6, 6), b_col, true)
				draw_rect(Rect2(pos.x - bast_offset - 3, pos.y + bast_offset - 3, 6, 6), b_col, true)
				draw_rect(Rect2(pos.x + bast_offset - 3, pos.y + bast_offset - 3, 6, 6), b_col, true)
				# Central pulsating core ring
				draw_arc(pos, 7.0, 0.0, TAU, 16, b_col, 1.5)
				draw_circle(pos, 3.0 * pulse, b_col)

			_: # COMBAT, ELITE
				# Tactical crosshair / corner obstacles
				var obs_col := Color("f97316") if r_type == "ELITE" else Color(0.22, 0.74, 0.97, 0.6)
				draw_line(pos + Vector2(-4, 0), pos + Vector2(4, 0), obs_col, 1.2)
				draw_line(pos + Vector2(0, -4), pos + Vector2(0, 4), obs_col, 1.2)
				if is_cleared:
					draw_circle(pos, 3.0, Color("22c55e"))

		# Status marker below room
		if font:
			var label_text := ""
			if is_current:
				label_text = "CURRENT"
			elif is_cleared:
				label_text = "CLEARED"
			else:
				label_text = "RM %d" % (i + 1)
			var font_col := Color("00f0ff") if is_current else (Color("22c55e") if is_cleared else Color("64748b"))
			var l_size := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
			draw_string(font, pos + Vector2(-l_size.x * 0.5, c_size.y * 0.5 + 13.0), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, font_col)
