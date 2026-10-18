extends Control
## In-Game Tactical Pause Menu for GLITCH//RUN.
## Freezes game tree, displays drafted subroutines and run statistics,
## sector mini-map, settings modal, tactical manual, and confirmation modals for restart/menu.

signal resume_requested
signal restart_requested
signal menu_requested

var title_label: Label
var stats_label: Label
var minimap_box: PanelContainer
var minimap_nodes_hbox: HBoxContainer
var minimap_branch_label: Label
var upgrades_vbox: VBoxContainer

var settings_panel: Control
var how_to_play_panel: Control
var confirm_panel: Control
var confirm_msg_label: Label
var confirm_callback: Callable


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or event.keycode == KEY_P or event.keycode == KEY_BACK)):
		_handle_back_request()
		if is_inside_tree():
			get_viewport().set_input_as_handled()


func _handle_back_request() -> void:
	if confirm_panel and confirm_panel.visible:
		confirm_panel.visible = false
	elif settings_panel and settings_panel.visible:
		settings_panel.visible = false
	elif how_to_play_panel and how_to_play_panel.visible:
		how_to_play_panel.visible = false
	else:
		close_pause()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Translucent backdrop
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.015, 0.025, 0.05, 0.92)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var main_vbox := VBoxContainer.new()
	main_vbox.custom_minimum_size = Vector2(480, 0)
	main_vbox.add_theme_constant_override("separation", 12)
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
	stats_label.add_theme_font_size_override("font_size", 12)
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
	map_style.content_margin_top = 6
	map_style.content_margin_right = 12
	map_style.content_margin_bottom = 6
	minimap_box.add_theme_stylebox_override("panel", map_style)
	main_vbox.add_child(minimap_box)

	var map_vbox := VBoxContainer.new()
	map_vbox.add_theme_constant_override("separation", 4)
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
	style.content_margin_left = 12
	style.content_margin_top = 8
	style.content_margin_right = 12
	style.content_margin_bottom = 8
	upg_box.add_theme_stylebox_override("panel", style)
	main_vbox.add_child(upg_box)

	upgrades_vbox = VBoxContainer.new()
	upgrades_vbox.add_theme_constant_override("separation", 3)
	upg_box.add_child(upgrades_vbox)

	var upg_header := Label.new()
	upg_header.text = "ACTIVE INSTALLED SUBROUTINES:"
	upg_header.add_theme_font_size_override("font_size", 11)
	upg_header.add_theme_color_override("font_color", Color("38bdf8"))
	upgrades_vbox.add_child(upg_header)

	# Action Buttons (Touch-friendly 48dp+ sizing)
	var btn_vbox := VBoxContainer.new()
	btn_vbox.add_theme_constant_override("separation", 8)
	main_vbox.add_child(btn_vbox)

	var resume_btn := Button.new()
	resume_btn.text = "RESUME SIMULATION"
	resume_btn.custom_minimum_size = Vector2(0, 46)
	resume_btn.pressed.connect(close_pause)
	btn_vbox.add_child(resume_btn)

	var htp_btn := Button.new()
	htp_btn.text = "HOW TO PLAY"
	htp_btn.custom_minimum_size = Vector2(0, 44)
	htp_btn.pressed.connect(func():
		_play_click()
		how_to_play_panel.visible = true
	)
	btn_vbox.add_child(htp_btn)

	var settings_btn := Button.new()
	settings_btn.text = "SETTINGS"
	settings_btn.custom_minimum_size = Vector2(0, 44)
	settings_btn.pressed.connect(func():
		_play_click()
		settings_panel.visible = true
	)
	btn_vbox.add_child(settings_btn)

	var restart_btn := Button.new()
	restart_btn.text = "RESTART RUN"
	restart_btn.custom_minimum_size = Vector2(0, 44)
	restart_btn.pressed.connect(func():
		_show_confirmation(
			"ABANDON CURRENT RUN?",
			"Active progress and enemy mutations in this simulation will be lost.",
			Callable(self, "_confirm_restart")
		)
	)
	btn_vbox.add_child(restart_btn)

	var menu_btn := Button.new()
	menu_btn.text = "ABORT TO MAIN MENU"
	menu_btn.custom_minimum_size = Vector2(0, 44)
	menu_btn.pressed.connect(func():
		_show_confirmation(
			"ABORT TO TITLE MENU?",
			"Active simulation telemetry will be terminated.",
			Callable(self, "_confirm_menu")
		)
	)
	btn_vbox.add_child(menu_btn)

	# Build child modals
	_build_confirm_modal()
	_build_how_to_play_modal()
	_build_settings_modal()


func _play_click() -> void:
	if not is_inside_tree():
		return
	var audio: Node = get_node_or_null("/root/AudioSynth")
	if audio:
		audio.play("ui_click", 0.0, 0.0)


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

			var node_box := PanelContainer.new()
			var n_style := StyleBoxFlat.new()
			if i < cur_room:
				n_style.bg_color = Color(0.08, 0.16, 0.08, 0.9)
				n_style.border_color = Color("22c55e")
			elif i == cur_room:
				n_style.bg_color = Color(0.12, 0.22, 0.35, 0.95)
				n_style.border_color = Color("38bdf8")
			else:
				n_style.bg_color = Color(0.04, 0.06, 0.10, 0.8)
				n_style.border_color = Color("334155")

			n_style.set_border_width_all(1)
			n_style.set_corner_radius_all(4)
			n_style.content_margin_left = 6
			n_style.content_margin_top = 4
			n_style.content_margin_right = 6
			n_style.content_margin_bottom = 4
			node_box.add_theme_stylebox_override("panel", n_style)

			var n_lbl := Label.new()
			if i < cur_room:
				n_lbl.text = "%s ✓" % icon
				n_lbl.add_theme_color_override("font_color", Color("4ade80"))
			elif i == cur_room:
				n_lbl.text = "▶ %s" % icon
				n_lbl.add_theme_color_override("font_color", Color("38bdf8"))
			else:
				n_lbl.text = icon
				n_lbl.add_theme_color_override("font_color", accent_col)

			n_lbl.add_theme_font_size_override("font_size", 11)
			node_box.add_child(n_lbl)
			minimap_nodes_hbox.add_child(node_box)

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
	_play_click()


func close_pause() -> void:
	if is_inside_tree():
		get_tree().paused = false
	visible = false
	_play_click()
	resume_requested.emit()


func _show_confirmation(title: String, message: String, callback: Callable) -> void:
	_play_click()
	confirm_callback = callback
	confirm_msg_label.text = "%s\n\n%s" % [title, message]
	confirm_panel.visible = true


func _confirm_restart() -> void:
	confirm_panel.visible = false
	get_tree().paused = false
	visible = false
	restart_requested.emit()


func _confirm_menu() -> void:
	confirm_panel.visible = false
	get_tree().paused = false
	visible = false
	menu_requested.emit()


func _build_confirm_modal() -> void:
	confirm_panel = Control.new()
	confirm_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	confirm_panel.visible = false
	add_child(confirm_panel)

	var modal_bg := ColorRect.new()
	modal_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_bg.color = Color(0.01, 0.015, 0.03, 0.95)
	confirm_panel.add_child(modal_bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	confirm_panel.add_child(center)

	var panel_box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.03, 0.06, 0.95)
	style.border_color = Color("f43f5e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 24
	style.content_margin_top = 20
	style.content_margin_right = 24
	style.content_margin_bottom = 20
	panel_box.add_theme_stylebox_override("panel", style)
	center.add_child(panel_box)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(400, 0)
	vbox.add_theme_constant_override("separation", 16)
	panel_box.add_child(vbox)

	confirm_msg_label = Label.new()
	confirm_msg_label.text = "CONFIRM ACTION?"
	confirm_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_msg_label.add_theme_font_size_override("font_size", 14)
	confirm_msg_label.add_theme_color_override("font_color", Color("fda4af"))
	vbox.add_child(confirm_msg_label)

	var btn_hbox := HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_hbox)

	var ok_btn := Button.new()
	ok_btn.text = "CONFIRM"
	ok_btn.custom_minimum_size = Vector2(140, 44)
	ok_btn.pressed.connect(func():
		_play_click()
		if confirm_callback.is_valid():
			confirm_callback.call()
	)
	btn_hbox.add_child(ok_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "CANCEL"
	cancel_btn.custom_minimum_size = Vector2(140, 44)
	cancel_btn.pressed.connect(func():
		_play_click()
		confirm_panel.visible = false
	)
	btn_hbox.add_child(cancel_btn)


func _build_how_to_play_modal() -> void:
	how_to_play_panel = Control.new()
	how_to_play_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	how_to_play_panel.visible = false
	add_child(how_to_play_panel)

	var modal_bg := ColorRect.new()
	modal_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_bg.color = Color(0.012, 0.02, 0.045, 0.95)
	how_to_play_panel.add_child(modal_bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	how_to_play_panel.add_child(center)

	var panel_box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.14, 0.95)
	style.border_color = Color("38bdf8")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 24
	style.content_margin_top = 18
	style.content_margin_right = 24
	style.content_margin_bottom = 18
	panel_box.add_theme_stylebox_override("panel", style)
	center.add_child(panel_box)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(540, 0)
	vbox.add_theme_constant_override("separation", 10)
	panel_box.add_child(vbox)

	var hdr := Label.new()
	hdr.text = "TACTICAL MANUAL // HOW TO PLAY"
	hdr.add_theme_font_size_override("font_size", 18)
	hdr.add_theme_color_override("font_color", Color("38bdf8"))
	vbox.add_child(hdr)

	var guides := [
		["NAVIGATION", "Left virtual stick or WASD to move. Tap DASH to dodge through incoming fire."],
		["AIMING", "Right virtual stick or Mouse cursor aims and fires twin plasma bolts."],
		["MUTATION COUNTERS", "Enemies adapt to your style: Chasers flank kiters; Shooters lead sprinters; Dashers drop hazard trails."],
		["TELEGRAPHS", "Hostile attacks lock direction during the telegraph window. Watch the ray and cut back!"]
	]

	for g in guides:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		vbox.add_child(row)

		var t := Label.new()
		t.text = "• %s" % g[0]
		t.add_theme_font_size_override("font_size", 12)
		t.add_theme_color_override("font_color", Color("f43f5e"))
		row.add_child(t)

		var d := Label.new()
		d.text = g[1]
		d.add_theme_font_size_override("font_size", 10)
		d.add_theme_color_override("font_color", Color("cbd5e1"))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(d)

	var close_btn := Button.new()
	close_btn.text = "RETURN"
	close_btn.custom_minimum_size = Vector2(140, 42)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_btn.pressed.connect(func():
		_play_click()
		how_to_play_panel.visible = false
	)
	vbox.add_child(close_btn)


func _build_settings_modal() -> void:
	settings_panel = Control.new()
	settings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_panel.visible = false
	add_child(settings_panel)

	var modal_bg := ColorRect.new()
	modal_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_bg.color = Color(0.012, 0.02, 0.045, 0.95)
	settings_panel.add_child(modal_bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_panel.add_child(center)

	var panel_box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.14, 0.95)
	style.border_color = Color("38bdf8")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 24
	style.content_margin_top = 18
	style.content_margin_right = 24
	style.content_margin_bottom = 18
	panel_box.add_theme_stylebox_override("panel", style)
	center.add_child(panel_box)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(480, 0)
	vbox.add_theme_constant_override("separation", 12)
	panel_box.add_child(vbox)

	var hdr := Label.new()
	hdr.text = "SYSTEM SETTINGS"
	hdr.add_theme_font_size_override("font_size", 18)
	hdr.add_theme_color_override("font_color", Color("38bdf8"))
	vbox.add_child(hdr)

	var sm: Node = get_node_or_null("/root/Settings") if is_inside_tree() else null

	# Master Volume
	var m_hbox := HBoxContainer.new()
	vbox.add_child(m_hbox)
	var m_lbl := Label.new()
	m_lbl.text = "MASTER VOLUME:"
	m_lbl.custom_minimum_size = Vector2(150, 0)
	m_hbox.add_child(m_lbl)
	var m_slider := HSlider.new()
	m_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m_slider.min_value = 0.0
	m_slider.max_value = 1.0
	m_slider.step = 0.05
	m_slider.value = sm.master_volume if sm else 1.0
	m_hbox.add_child(m_slider)
	m_slider.value_changed.connect(func(v: float):
		if sm:
			sm.master_volume = v
			sm.set_bus_volume("Master", v)
	)

	# Music Volume
	var mus_hbox := HBoxContainer.new()
	vbox.add_child(mus_hbox)
	var mus_lbl := Label.new()
	mus_lbl.text = "MUSIC VOLUME:"
	mus_lbl.custom_minimum_size = Vector2(150, 0)
	mus_hbox.add_child(mus_lbl)
	var mus_slider := HSlider.new()
	mus_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mus_slider.min_value = 0.0
	mus_slider.max_value = 1.0
	mus_slider.step = 0.05
	mus_slider.value = sm.music_volume if sm else 0.75
	mus_hbox.add_child(mus_slider)
	mus_slider.value_changed.connect(func(v: float):
		if sm:
			sm.music_volume = v
			sm.set_bus_volume("Music", v)
	)

	# SFX Volume
	var sfx_hbox := HBoxContainer.new()
	vbox.add_child(sfx_hbox)
	var sfx_lbl := Label.new()
	sfx_lbl.text = "SFX VOLUME:"
	sfx_lbl.custom_minimum_size = Vector2(150, 0)
	sfx_hbox.add_child(sfx_lbl)
	var sfx_slider := HSlider.new()
	sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.05
	sfx_slider.value = sm.sfx_volume if sm else 0.9
	sfx_hbox.add_child(sfx_slider)
	sfx_slider.value_changed.connect(func(v: float):
		if sm:
			sm.sfx_volume = v
			sm.set_bus_volume("SFX", v)
	)

	# Screen Shake CheckButton
	var shake_btn := CheckButton.new()
	shake_btn.text = "SCREEN SHAKE FX"
	shake_btn.button_pressed = sm.screen_shake_enabled if sm else true
	shake_btn.toggled.connect(func(pressed: bool):
		if sm:
			sm.screen_shake_enabled = pressed
	)
	vbox.add_child(shake_btn)

	var close_btn := Button.new()
	close_btn.text = "SAVE & CLOSE"
	close_btn.custom_minimum_size = Vector2(140, 42)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_btn.pressed.connect(func():
		_play_click()
		if sm:
			sm.save_settings()
		settings_panel.visible = false
	)
	vbox.add_child(close_btn)
