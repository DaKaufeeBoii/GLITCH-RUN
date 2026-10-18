extends Control
## Director Telemetry Debrief Terminal for GLITCH//RUN.
## Renders player combat metrics, archetype classification, procedural radar chart,
## and chronological AI adaptation history.

signal restart_requested
signal menu_requested
signal replay_seed_requested(seed_val: int)

var radar_node: Control
var archetype_label: Label
var archetype_desc: Label
var stats_label: Label
var title_label: Label
var tactics_vbox: VBoxContainer

var current_metrics: Dictionary = {}
var archetype_name := "CALIBRATING"
var archetype_description := ""

# Radar chart normalized values [0.0, 1.0]
# 0: Mobility, 1: Engagement Range, 2: Fire Density, 3: Evasion
var player_radar_vals: Array[float] = [0.5, 0.5, 0.5, 0.5]
var director_radar_vals: Array[float] = [0.5, 0.5, 0.5, 0.5]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

	# Dark glassmorphic cyber backdrop
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.012, 0.02, 0.045, 0.94)
	add_child(bg)

	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 12)
	main_vbox.offset_left = 36
	main_vbox.offset_top = 24
	main_vbox.offset_right = -36
	main_vbox.offset_bottom = -24
	add_child(main_vbox)

	# Header Title
	title_label = Label.new()
	title_label.text = "DIRECTOR DEBRIEF // MISSION ANALYSIS"
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color("38bdf8"))
	main_vbox.add_child(title_label)

	# Stats Subheader
	stats_label = Label.new()
	stats_label.text = "SECTORS CLEARED: 0/6  •  HOSTILES PURGED: 0  •  TIME: 00:00  •  UPGRADES: 0"
	stats_label.add_theme_font_size_override("font_size", 13)
	stats_label.add_theme_color_override("font_color", Color("94a3b8"))
	main_vbox.add_child(stats_label)

	# Middle Columns Split (Left: Radar & Archetype, Right: Director Mutation Log)
	var split_hbox := HBoxContainer.new()
	split_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_hbox.add_theme_constant_override("separation", 28)
	main_vbox.add_child(split_hbox)

	# Left Column: Archetype & Radar (Width ~420)
	var left_vbox := VBoxContainer.new()
	left_vbox.custom_minimum_size = Vector2(400, 0)
	left_vbox.add_theme_constant_override("separation", 8)
	split_hbox.add_child(left_vbox)

	var archetype_box := PanelContainer.new()
	var arch_style := StyleBoxFlat.new()
	arch_style.bg_color = Color(0.04, 0.07, 0.14, 0.85)
	arch_style.border_color = Color("38bdf8")
	arch_style.set_border_width_all(1)
	arch_style.set_corner_radius_all(4)
	arch_style.content_margin_left = 12
	arch_style.content_margin_top = 8
	arch_style.content_margin_right = 12
	arch_style.content_margin_bottom = 8
	archetype_box.add_theme_stylebox_override("panel", arch_style)
	left_vbox.add_child(archetype_box)

	var arch_inner_vbox := VBoxContainer.new()
	archetype_box.add_child(arch_inner_vbox)

	archetype_label = Label.new()
	archetype_label.text = "COMBAT ARCHETYPE: HYPER-MOBILE"
	archetype_label.add_theme_font_size_override("font_size", 14)
	archetype_label.add_theme_color_override("font_color", Color("38bdf8"))
	arch_inner_vbox.add_child(archetype_label)

	archetype_desc = Label.new()
	archetype_desc.text = "Exhibits continuous high-velocity repositioning."
	archetype_desc.add_theme_font_size_override("font_size", 11)
	archetype_desc.add_theme_color_override("font_color", Color("cbd5e1"))
	archetype_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	arch_inner_vbox.add_child(archetype_desc)

	# Procedural Radar Canvas Node
	radar_node = Control.new()
	radar_node.custom_minimum_size = Vector2(380, 240)
	radar_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	radar_node.draw.connect(_draw_radar_chart)
	left_vbox.add_child(radar_node)

	# Right Column: Director Mutation Timeline
	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 6)
	split_hbox.add_child(right_vbox)

	var right_header := Label.new()
	right_header.text = "ADAPTIVE DIRECTOR // TACTICAL LOG"
	right_header.add_theme_font_size_override("font_size", 14)
	right_header.add_theme_color_override("font_color", Color("f43f5e"))
	right_vbox.add_child(right_header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(scroll)

	tactics_vbox = VBoxContainer.new()
	tactics_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tactics_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(tactics_vbox)

	# Footer Buttons
	var footer_hbox := HBoxContainer.new()
	footer_hbox.alignment = BoxContainer.ALIGNMENT_END
	footer_hbox.add_theme_constant_override("separation", 16)
	main_vbox.add_child(footer_hbox)

	var menu_btn := Button.new()
	menu_btn.text = "MAIN MENU"
	menu_btn.custom_minimum_size = Vector2(150, 48)
	menu_btn.pressed.connect(_on_menu_pressed)
	footer_hbox.add_child(menu_btn)

	var replay_btn := Button.new()
	replay_btn.text = "REPLAY SEED"
	replay_btn.custom_minimum_size = Vector2(160, 48)
	replay_btn.pressed.connect(_on_replay_seed_pressed)
	footer_hbox.add_child(replay_btn)

	var restart_btn := Button.new()
	restart_btn.text = "NEW SIMULATION"
	restart_btn.custom_minimum_size = Vector2(180, 48)
	restart_btn.pressed.connect(_on_restart_pressed)
	footer_hbox.add_child(restart_btn)


func setup_debrief(
	won: bool,
	metrics: Dictionary,
	tactics_history: Array,
	evolution_history: Array = [],
	dungeon_seed: int = 0
) -> void:
	current_metrics = metrics
	var rs: Node = get_node_or_null("/root/RunState") if is_inside_tree() else null

	if won:
		title_label.text = "CORE PURGED // SIMULATION COMPLETE"
		title_label.add_theme_color_override("font_color", Color("38bdf8"))
	else:
		title_label.text = "SUBJECT TERMINATED // HOSTILES PREVAILED"
		title_label.add_theme_color_override("font_color", Color("f43f5e"))

	var seed_to_display: int = dungeon_seed if dungeon_seed != 0 else (rs.current_seed if rs else 1337)
	if rs:
		var mins := int(rs.run_time / 60.0)
		var secs := int(rs.run_time) % 60
		var cur_depth: int = rs.progression.run_depth if rs.progression else (rs.current_room_index + 1)
		var cur_sec: int = rs.progression.sector_index if rs.progression else rs.current_sector
		stats_label.text = "SEED: #%d  •  DEPTH: %d (SEC %d)  •  PURGED: %d  •  TIME: %02d:%02d  •  UPGRADES: %d" % [
			seed_to_display,
			cur_depth,
			cur_sec,
			rs.score,
			mins,
			secs,
			rs.active_upgrade_ids.size()
		]
	else:
		stats_label.text = "SEED: #%d  •  METRICS RECORDED DETERMINISTICALLY" % seed_to_display

	# Analyze Archetype & Radar values
	_classify_archetype(metrics)

	# Populate Director Mutation Log & Evolution Lineage
	for child in tactics_vbox.get_children():
		child.queue_free()

	if tactics_history.is_empty() and evolution_history.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "Director remained in baseline calibration state."
		empty_lbl.add_theme_color_override("font_color", Color("64748b"))
		tactics_vbox.add_child(empty_lbl)
	else:
		# 1. Tactical Decisions
		for entry in tactics_history:
			var card := PanelContainer.new()
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.08, 0.04, 0.07, 0.75)
			style.border_color = Color("f43f5e")
			style.set_border_width_all(1)
			style.set_corner_radius_all(3)
			style.content_margin_left = 10
			style.content_margin_top = 6
			style.content_margin_right = 10
			style.content_margin_bottom = 6
			card.add_theme_stylebox_override("panel", style)
			tactics_vbox.add_child(card)

			var card_vbox := VBoxContainer.new()
			card_vbox.add_theme_constant_override("separation", 2)
			card.add_child(card_vbox)

			var header := Label.new()
			header.text = "SECTOR %d: %s" % [entry.get("sector", 1), entry.get("tactic", "COUNTER")]
			header.add_theme_font_size_override("font_size", 12)
			header.add_theme_color_override("font_color", Color("fda4af"))
			card_vbox.add_child(header)

			var reason := Label.new()
			reason.text = "Trigger: %s" % entry.get("reason", "Combat telemetry shift")
			reason.add_theme_font_size_override("font_size", 10)
			reason.add_theme_color_override("font_color", Color("94a3b8"))
			card_vbox.add_child(reason)

			var muts := Label.new()
			muts.text = "Mutations: %s" % entry.get("mutations", "Evolved aggressive swarm tactics")
			muts.add_theme_font_size_override("font_size", 11)
			muts.add_theme_color_override("font_color", Color("38bdf8"))
			card_vbox.add_child(muts)

		# 2. Enemy Genome Evolution Lineage
		if not evolution_history.is_empty():
			var evo_header := Label.new()
			evo_header.text = "ENEMY EVOLUTION LINEAGE (LAYERS B & C)"
			evo_header.add_theme_font_size_override("font_size", 12)
			evo_header.add_theme_color_override("font_color", Color("a855f7"))
			tactics_vbox.add_child(evo_header)

			for evo in evolution_history:
				var evo_card := PanelContainer.new()
				var evo_style := StyleBoxFlat.new()
				evo_style.bg_color = Color(0.06, 0.03, 0.10, 0.85)
				evo_style.border_color = Color("c084fc")
				evo_style.set_border_width_all(1)
				evo_style.set_corner_radius_all(3)
				evo_style.content_margin_left = 10
				evo_style.content_margin_top = 4
				evo_style.content_margin_right = 10
				evo_style.content_margin_bottom = 4
				evo_card.add_theme_stylebox_override("panel", evo_style)
				tactics_vbox.add_child(evo_card)

				var ev_vbox := VBoxContainer.new()
				ev_vbox.add_theme_constant_override("separation", 2)
				evo_card.add_child(ev_vbox)

				var ev_title := Label.new()
				var tier_str: String = " [TIER %d | %s]" % [evo.get("tier", 1), evo.get("health_mult", "2x HP")] if evo.has("tier") else ""
				ev_title.text = "SECTOR %d: %s%s -> %s" % [evo.get("sector", 1), evo.get("family", "ENEMY"), tier_str, evo.get("mutation", "MUTATION")]
				ev_title.add_theme_font_size_override("font_size", 11)
				ev_title.add_theme_color_override("font_color", Color("e9d5ff"))
				ev_vbox.add_child(ev_title)

				var ev_reason := Label.new()
				ev_reason.text = "Evidence: %s" % evo.get("reason", "Observation")
				ev_reason.add_theme_font_size_override("font_size", 10)
				ev_reason.add_theme_color_override("font_color", Color("cbd5e1"))
				ev_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				ev_vbox.add_child(ev_reason)

				if evo.has("counter"):
					var ev_counter := Label.new()
					ev_counter.text = "Player Counter: %s" % evo.get("counter", "")
					ev_counter.add_theme_font_size_override("font_size", 10)
					ev_counter.add_theme_color_override("font_color", Color("38bdf8"))
					ev_counter.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					ev_vbox.add_child(ev_counter)


		# 3. Boss Encounters & Returning Mutations
		if rs and not rs.boss_encounter_history.is_empty():
			var boss_header := Label.new()
			boss_header.text = "BOSS ENCOUNTERS & RETURNING MUTATIONS"
			boss_header.add_theme_font_size_override("font_size", 12)
			boss_header.add_theme_color_override("font_color", Color("f43f5e"))
			tactics_vbox.add_child(boss_header)

			for b_rec in rs.boss_encounter_history:
				var b_card := PanelContainer.new()
				var b_style := StyleBoxFlat.new()
				b_style.bg_color = Color(0.12, 0.03, 0.05, 0.85)
				b_style.border_color = Color("fb7185")
				b_style.set_border_width_all(1)
				b_style.set_corner_radius_all(3)
				b_style.content_margin_left = 10
				b_style.content_margin_top = 4
				b_style.content_margin_right = 10
				b_style.content_margin_bottom = 4
				b_card.add_theme_stylebox_override("panel", b_style)
				tactics_vbox.add_child(b_card)

				var b_vbox := VBoxContainer.new()
				b_vbox.add_theme_constant_override("separation", 2)
				b_card.add_child(b_vbox)

				var b_title := Label.new()
				var muts: Array = b_rec.get("mutations", [])
				var mut_desc: String = muts[0].get("name", "BASELINE") if not muts.is_empty() else "BASELINE CALIBRATION"
				b_title.text = "SEC %d (DEPTH %d): %s // %s [%s]" % [
					b_rec.get("sector", 1),
					b_rec.get("depth", 1),
					b_rec.get("boss_id", "BOSS").to_upper().replace("_", " "),
					b_rec.get("outcome", "VICTORY"),
					mut_desc
				]
				b_title.add_theme_font_size_override("font_size", 11)
				b_title.add_theme_color_override("font_color", Color("fecdd3"))
				b_vbox.add_child(b_title)

	radar_node.queue_redraw()
	visible = true


func _classify_archetype(m: Dictionary) -> void:
	var mobility := float(m.get("moving_time_ratio", 0.5))
	var dist := float(m.get("avg_distance_to_enemy", 180.0))
	var firing := float(m.get("firing_time_ratio", 0.5))
	var dash_freq := float(m.get("dash_count", 0.0))

	# Compute player radar polygon points
	var r_mobility := clampf(mobility * 1.2, 0.15, 1.0)
	var r_range := clampf(dist / 320.0, 0.15, 1.0)
	var r_fire := clampf(firing * 1.3, 0.15, 1.0)
	var r_evasion := clampf(1.0 - (float(m.get("damage_taken", 0)) * 0.1), 0.2, 1.0)

	player_radar_vals = [r_mobility, r_range, r_fire, r_evasion]

	# Director counter-profile
	director_radar_vals = [
		clampf(1.1 - r_range, 0.2, 1.0),
		clampf(1.0 - r_mobility, 0.2, 1.0),
		clampf(r_fire * 0.9, 0.2, 1.0),
		clampf(r_mobility * 0.8, 0.2, 1.0)
	]

	if mobility < 0.35 and firing > 0.45:
		archetype_name = "STATIONARY TURRET"
		archetype_description = "High firing uptime from fixed positions. Director countered with Lingering Hazard Trails and pincer choke points."
		archetype_label.add_theme_color_override("font_color", Color("fb923c"))
	elif r_range > 0.65:
		archetype_name = "RANGED KITER"
		archetype_description = "Maintains outer perimeter standoff distance. Director countered with Chaser Pincer Flanking angles."
		archetype_label.add_theme_color_override("font_color", Color("facc15"))
	elif mobility > 0.65 or dash_freq > 6.0:
		archetype_name = "HYPER-MOBILE"
		archetype_description = "Frequent evasion and rapid repositioning. Director countered with Shooter Intercept Lead Aim."
		archetype_label.add_theme_color_override("font_color", Color("38bdf8"))
	else:
		archetype_name = "TACTICAL COMBATANT"
		archetype_description = "Balanced movement, range management, and shot timing."
		archetype_label.add_theme_color_override("font_color", Color("4ade80"))

	archetype_label.text = "COMBAT ARCHETYPE: %s" % archetype_name
	archetype_desc.text = archetype_description


func _draw_radar_chart() -> void:
	if not is_instance_valid(radar_node):
		return

	var center := radar_node.size * 0.5
	var radius := minf(center.x, center.y) * 0.72

	# 4 Axes: Top (Mobility), Right (Standoff Range), Bottom (Fire Density), Left (Evasion)
	var axis_angles: Array[float] = [-PI * 0.5, 0.0, PI * 0.5, PI]
	var axis_labels: Array[String] = ["MOBILITY", "RANGE", "FIRE RATE", "EVASION"]

	# Draw concentric grid rings
	for ring in [0.33, 0.66, 1.0]:
		var pts := PackedVector2Array()
		for a in axis_angles:
			pts.append(center + Vector2.from_angle(a) * (radius * ring))
		pts.append(pts[0])
		radar_node.draw_polyline(pts, Color(0.18, 0.25, 0.38, 0.4), 1.0)

	# Draw radial axis lines
	for i in range(4):
		var a: float = axis_angles[i]
		var tip := center + Vector2.from_angle(a) * radius
		radar_node.draw_line(center, tip, Color(0.24, 0.35, 0.52, 0.5), 1.0)
		# Draw label
		var lbl_pos := center + Vector2.from_angle(a) * (radius + 18.0) - Vector2(25, 6)
		radar_node.draw_string(ThemeDB.fallback_font, lbl_pos, axis_labels[i], HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color("94a3b8"))

	# Draw Director Counter Polygon (Magenta)
	var dir_pts := PackedVector2Array()
	for i in range(4):
		var a: float = axis_angles[i]
		var dist: float = director_radar_vals[i] * radius
		dir_pts.append(center + Vector2.from_angle(a) * dist)
	dir_pts.append(dir_pts[0])
	radar_node.draw_colored_polygon(dir_pts, Color(0.96, 0.25, 0.45, 0.25))
	radar_node.draw_polyline(dir_pts, Color("f43f5e"), 1.8)

	# Draw Player Polygon (Cyan)
	var ply_pts := PackedVector2Array()
	for i in range(4):
		var a: float = axis_angles[i]
		var dist: float = player_radar_vals[i] * radius
		ply_pts.append(center + Vector2.from_angle(a) * dist)
	ply_pts.append(ply_pts[0])
	radar_node.draw_colored_polygon(ply_pts, Color(0.22, 0.74, 0.97, 0.35))
	radar_node.draw_polyline(ply_pts, Color("38bdf8"), 2.2)

	# Small legend
	radar_node.draw_line(Vector2(14, 14), Vector2(30, 14), Color("38bdf8"), 2.0)
	radar_node.draw_string(ThemeDB.fallback_font, Vector2(36, 18), "Player Profile", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("38bdf8"))
	radar_node.draw_line(Vector2(14, 30), Vector2(30, 30), Color("f43f5e"), 2.0)
	radar_node.draw_string(ThemeDB.fallback_font, Vector2(36, 34), "Director Counter", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("f43f5e"))


func _on_restart_pressed() -> void:
	visible = false
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("ui_click", 0.0, 0.0)
	restart_requested.emit()


func _on_replay_seed_pressed() -> void:
	visible = false
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("ui_click", 0.0, 0.0)
	var rs = get_node_or_null("/root/RunState")
	var s: int = rs.current_seed if rs else 1337
	replay_seed_requested.emit(s)


func _on_menu_pressed() -> void:
	visible = false
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("ui_click", 0.0, 0.0)
	menu_requested.emit()
