extends Control
## In-Game Tactical Pause Menu for GLITCH//RUN.
## Freezes game tree, displays drafted subroutines and run statistics,
## and offers restart / menu options.

signal resume_requested
signal restart_requested
signal menu_requested

var title_label: Label
var stats_label: Label
var minimap_box: PanelContainer
var minimap_nodes_hbox: HBoxContainer
var minimap_branch_label: Label
var upgrades_vbox: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or event.keycode == KEY_P)):
		close_pause()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Translucent backdrop
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.015, 0.025, 0.05, 0.88)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var main_vbox := VBoxContainer.new()
	main_vbox.custom_minimum_size = Vector2(460, 0)
	main_vbox.add_theme_constant_override("separation", 16)
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(main_vbox)

	title_label = Label.new()
	title_label.text = "TACTICAL OVERVIEW // PAUSED"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color("38bdf8"))
	main_vbox.add_child(title_label)

	stats_label = Label.new()
	stats_label.text = "SECTOR 1/6  •  ELIMS: 0  •  TIME: 00:00"
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_label.add_theme_font_size_override("font_size", 13)
	stats_label.add_theme_color_override("font_color", Color("94a3b8"))
	main_vbox.add_child(stats_label)

	# Sector Topology & Mini-Map Panel
	minimap_box = PanelContainer.new()
	var map_style := StyleBoxFlat.new()
	map_style.bg_color = Color(0.03, 0.055, 0.11, 0.9)
	map_style.border_color = Color("38bdf8")
	map_style.set_border_width_all(1)
	map_style.set_corner_radius_all(4)
	map_style.content_margin_left = 12
	map_style.content_margin_top = 8
	map_style.content_margin_right = 12
	map_style.content_margin_bottom = 8
	minimap_box.add_theme_stylebox_override("panel", map_style)
	main_vbox.add_child(minimap_box)

	var map_vbox := VBoxContainer.new()
	map_vbox.add_theme_constant_override("separation", 5)
	minimap_box.add_child(map_vbox)

	var map_hdr := Label.new()
	map_hdr.text = "SECTOR TOPOLOGY & ROUTE MAP:"
	map_hdr.add_theme_font_size_override("font_size", 11)
	map_hdr.add_theme_color_override("font_color", Color("38bdf8"))
	map_vbox.add_child(map_hdr)

	minimap_nodes_hbox = HBoxContainer.new()
	minimap_nodes_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	minimap_nodes_hbox.add_theme_constant_override("separation", 6)
	map_vbox.add_child(minimap_nodes_hbox)

	minimap_branch_label = Label.new()
	minimap_branch_label.text = "S: Start  •  ⚔: Combat  •  +: Recovery  •  ★: Elite Threat  •  Ω: Nexus Boss"
	minimap_branch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	minimap_branch_label.add_theme_font_size_override("font_size", 10)
	minimap_branch_label.add_theme_color_override("font_color", Color("64748b"))
	map_vbox.add_child(minimap_branch_label)

	# Drafted Upgrades Panel
	var upg_box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.14, 0.8)
	style.border_color = Color("38bdf8")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 14
	style.content_margin_top = 10
	style.content_margin_right = 14
	style.content_margin_bottom = 10
	upg_box.add_theme_stylebox_override("panel", style)
	main_vbox.add_child(upg_box)

	upgrades_vbox = VBoxContainer.new()
	upgrades_vbox.add_theme_constant_override("separation", 4)
	upg_box.add_child(upgrades_vbox)

	var upg_header := Label.new()
	upg_header.text = "ACTIVE INSTALLED SUBROUTINES:"
	upg_header.add_theme_font_size_override("font_size", 11)
	upg_header.add_theme_color_override("font_color", Color("38bdf8"))
	upgrades_vbox.add_child(upg_header)

	# Action Buttons
	var btn_vbox := VBoxContainer.new()
	btn_vbox.add_theme_constant_override("separation", 10)
	main_vbox.add_child(btn_vbox)

	var resume_btn := Button.new()
	resume_btn.text = "RESUME SIMULATION"
	resume_btn.custom_minimum_size = Vector2(0, 42)
	resume_btn.pressed.connect(_on_resume_pressed)
	btn_vbox.add_child(resume_btn)

	var restart_btn := Button.new()
	restart_btn.text = "RESTART RUN"
	restart_btn.custom_minimum_size = Vector2(0, 40)
	restart_btn.pressed.connect(_on_restart_pressed)
	btn_vbox.add_child(restart_btn)

	var menu_btn := Button.new()
	menu_btn.text = "ABORT TO MAIN MENU"
	menu_btn.custom_minimum_size = Vector2(0, 40)
	menu_btn.pressed.connect(_on_menu_pressed)
	btn_vbox.add_child(menu_btn)


func open_pause() -> void:
	var rs: Node = get_node_or_null("/root/RunState") if is_inside_tree() else null
	if rs:
		var mins := int(rs.run_time / 60.0)
		var secs := int(rs.run_time) % 60
		stats_label.text = "SEC %d • ROOM %d/%d  •  ELIMS: %d  •  TIME: %02d:%02d" % [
			rs.current_sector,
			rs.current_room_index + 1,
			rs.TOTAL_ROOMS,
			rs.score,
			mins,
			secs
		]

		# Rebuild Sector Mini-Map
		for child in minimap_nodes_hbox.get_children():
			child.queue_free()

		var total_rooms: int = rs.progression.rooms_per_sector if (rs and rs.progression) else rs.TOTAL_ROOMS
		var cur_room: int = rs.current_room_index

		for i in range(total_rooms):
			var r_type: String = "COMBAT"
			if i == 0:
				r_type = "START"
			elif i == total_rooms - 1:
				r_type = "BOSS"
			elif i < rs.dungeon_layout_summary.size():
				r_type = rs.dungeon_layout_summary[i].get("room_type", "COMBAT")
			elif i == 2:
				r_type = "RECOVERY"
			elif i == 3:
				r_type = "ELITE"

			var icon := "⚔"
			var accent_col := Color("38bdf8")
			match r_type:
				"START":
					icon = "S"
					accent_col = Color("94a3b8")
				"RECOVERY":
					icon = "+"
					accent_col = Color("22c55e")
				"ELITE":
					icon = "★"
					accent_col = Color("f59e0b")
				"BOSS":
					icon = "Ω"
					accent_col = Color("ec4899")
				_:
					icon = "⚔"
					accent_col = Color("38bdf8")

			var node_panel := PanelContainer.new()
			var n_style := StyleBoxFlat.new()
			n_style.set_corner_radius_all(4)
			n_style.content_margin_left = 6
			n_style.content_margin_right = 6
			n_style.content_margin_top = 4
			n_style.content_margin_bottom = 4

			var lbl := Label.new()
			lbl.add_theme_font_size_override("font_size", 11)

			if i < cur_room:
				# Cleared room
				n_style.bg_color = Color(0.05, 0.10, 0.08, 0.8)
				n_style.border_color = Color("22c55e")
				n_style.set_border_width_all(1)
				lbl.text = "✓ %s" % icon
				lbl.add_theme_color_override("font_color", Color("86efac"))
			elif i == cur_room:
				# Current active room
				n_style.bg_color = Color(0.08, 0.18, 0.32, 0.95)
				n_style.border_color = Color("38bdf8")
				n_style.set_border_width_all(2)
				lbl.text = "▶ %s" % icon
				lbl.add_theme_color_override("font_color", Color("38bdf8"))
			else:
				# Upcoming room
				n_style.bg_color = Color(0.03, 0.05, 0.08, 0.7)
				n_style.border_color = Color("334155")
				n_style.set_border_width_all(1)
				lbl.text = icon
				lbl.add_theme_color_override("font_color", accent_col)

			node_panel.add_theme_stylebox_override("panel", n_style)
			node_panel.add_child(lbl)
			minimap_nodes_hbox.add_child(node_panel)

			if i < total_rooms - 1:
				var arrow := Label.new()
				arrow.text = "➔"
				arrow.add_theme_font_size_override("font_size", 10)
				arrow.add_theme_color_override("font_color", Color("475569"))
				minimap_nodes_hbox.add_child(arrow)

		# Clear previous items
		for i in range(1, upgrades_vbox.get_child_count()):
			upgrades_vbox.get_child(i).queue_free()

		if rs.active_upgrade_ids.is_empty():
			var empty_lbl := Label.new()
			empty_lbl.text = "None. Draft upgrades by purging room hostiles."
			empty_lbl.add_theme_font_size_override("font_size", 11)
			empty_lbl.add_theme_color_override("font_color", Color("64748b"))
			upgrades_vbox.add_child(empty_lbl)
		else:
			for upg_id in rs.active_upgrade_ids:
				var lbl := Label.new()
				lbl.text = "• %s" % upg_id
				lbl.add_theme_font_size_override("font_size", 12)
				lbl.add_theme_color_override("font_color", Color("cbd5e1"))
				upgrades_vbox.add_child(lbl)

	get_tree().paused = true
	visible = true
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("ui_click", 0.0, 0.0)


func close_pause() -> void:
	get_tree().paused = false
	visible = false
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("ui_click", 0.0, 0.0)
	resume_requested.emit()


func _on_resume_pressed() -> void:
	close_pause()


func _on_restart_pressed() -> void:
	get_tree().paused = false
	visible = false
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("ui_click", 0.0, 0.0)
	restart_requested.emit()


func _on_menu_pressed() -> void:
	get_tree().paused = false
	visible = false
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("ui_click", 0.0, 0.0)
	menu_requested.emit()
