extends Control
## In-Game Tactical Pause Menu for GLITCH//RUN.
## Freezes game tree, displays drafted subroutines and run statistics,
## sector mini-map, settings modal, tactical manual, and confirmation modals for restart/menu.

signal resume_requested
signal restart_requested
signal menu_requested
signal quit_requested

const SECTOR_MAP_SCRIPT := preload("res://scripts/sector_map.gd")
const MENU_BACKDROP_SCRIPT := preload("res://scripts/menu_backdrop.gd")
const MENU_SKIN := preload("res://scripts/menu_ui_skin.gd")
const MENU_GLITCH_SCRIPT := preload("res://scripts/menu_glitch_overlay.gd")

var title_label: Label
var stats_label: Label
var minimap_box: PanelContainer
var minimap_nodes_hbox: Control
var minimap_branch_label: Label
var upgrades_vbox: HFlowContainer

var settings_panel: Control
var how_to_play_panel: Control
var confirm_panel: Control
var confirm_msg_label: Label
var confirm_callback: Callable
var quit_btn: Button
var menu_glitch: CanvasLayer
var action_buttons: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()


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
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Animated blueprint treatment sits below all menu content.
	var bg := MENU_BACKDROP_SCRIPT.new()
	bg.accent = Color("38bdf8")
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(root_vbox)

	# Top Bar: Title & Stats
	var top_bar := HBoxContainer.new()
	top_bar.alignment = BoxContainer.ALIGNMENT_BEGIN
	top_bar.custom_minimum_size.y = 34
	root_vbox.add_child(top_bar)

	title_label = Label.new()
	title_label.text = "TACTICAL OVERVIEW // PAUSED"
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color("38bdf8"))
	top_bar.add_child(title_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)

	stats_label = Label.new()
	stats_label.text = "SECTOR 1/6  •  ELIMS: 0  •  BITS: 0  •  TIME: 00:00"
	stats_label.add_theme_font_size_override("font_size", 12)
	stats_label.add_theme_color_override("font_color", Color("94a3b8"))
	top_bar.add_child(stats_label)

	# Main Body: Split into Left Column (Map & Subroutines) and Right Column (Action Buttons)
	var body_hbox := HBoxContainer.new()
	body_hbox.add_theme_constant_override("separation", 16)
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(body_hbox)

	# LEFT COLUMN: Map & Subroutines
	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 8)
	body_hbox.add_child(left_vbox)

	# Sector Topology & Mini-Map Panel
	minimap_box = PanelContainer.new()
	var map_style := StyleBoxFlat.new()
	map_style.bg_color = Color(0.03, 0.055, 0.11, 0.9)
	map_style.border_color = Color("38bdf8")
	map_style.set_border_width_all(1)
	map_style.set_corner_radius_all(4)
	map_style.content_margin_left = 10
	map_style.content_margin_top = 6
	map_style.content_margin_right = 10
	map_style.content_margin_bottom = 6
	minimap_box.add_theme_stylebox_override("panel", map_style)
	minimap_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(minimap_box)

	var map_vbox := VBoxContainer.new()
	map_vbox.add_theme_constant_override("separation", 4)
	minimap_box.add_child(map_vbox)

	var map_hdr := Label.new()
	map_hdr.text = "SECTOR TOPOLOGY & ROUTE MAP:"
	map_hdr.add_theme_font_size_override("font_size", 11)
	map_hdr.add_theme_color_override("font_color", Color("38bdf8"))
	map_vbox.add_child(map_hdr)

	minimap_nodes_hbox = Control.new()
	minimap_nodes_hbox.set_script(SECTOR_MAP_SCRIPT)
	minimap_nodes_hbox.custom_minimum_size = Vector2(500, 150)
	minimap_nodes_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_vbox.add_child(minimap_nodes_hbox)

	minimap_branch_label = Label.new()
	minimap_branch_label.text = "Start [o]  •  Combat [•]  •  Recovery [+]  •  Shop [🛒]  •  Tech Cache [◆]  •  Shrine [▲]  •  Overlord [Ω]"
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
	style.content_margin_left = 10
	style.content_margin_top = 6
	style.content_margin_right = 10
	style.content_margin_bottom = 6
	upg_box.add_theme_stylebox_override("panel", style)
	# Keep the footer panel compact so its theme padding cannot push the final
	# pixels below the viewport on the 960x540 game canvas.
	upg_box.custom_minimum_size = Vector2(0, 94)
	left_vbox.add_child(upg_box)

	var upg_inner := VBoxContainer.new()
	upg_inner.add_theme_constant_override("separation", 3)
	upg_box.add_child(upg_inner)

	var upg_header := Label.new()
	upg_header.text = "ACTIVE INSTALLED SUBROUTINES:"
	upg_header.add_theme_font_size_override("font_size", 11)
	upg_header.add_theme_color_override("font_color", Color("38bdf8"))
	upg_inner.add_child(upg_header)

	upgrades_vbox = HFlowContainer.new()
	upgrades_vbox.add_theme_constant_override("h_separation", 8)
	upgrades_vbox.add_theme_constant_override("v_separation", 4)
	upgrades_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrades_vbox.size_flags_vertical = Control.SIZE_FILL
	upg_inner.add_child(upgrades_vbox)

	# RIGHT COLUMN: Action Buttons
	action_buttons = VBoxContainer.new()
	action_buttons.custom_minimum_size = Vector2(280, 0)
	action_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	action_buttons.add_theme_constant_override("separation", 8)
	body_hbox.add_child(action_buttons)

	var resume_btn := Button.new()
	resume_btn.text = "RESUME SIMULATION"
	resume_btn.custom_minimum_size = Vector2(0, 44)
	var resume_style := StyleBoxFlat.new()
	resume_style.bg_color = Color(0.06, 0.16, 0.28, 0.95)
	resume_style.border_color = Color("38bdf8")
	resume_style.set_border_width_all(1)
	resume_style.set_corner_radius_all(4)
	resume_btn.add_theme_stylebox_override("normal", resume_style)
	resume_btn.add_theme_color_override("font_color", Color("38bdf8"))
	resume_btn.pressed.connect(close_pause)
	action_buttons.add_child(resume_btn)

	var htp_btn := Button.new()
	htp_btn.text = "HOW TO PLAY"
	htp_btn.custom_minimum_size = Vector2(0, 40)
	htp_btn.pressed.connect(func():
		_play_click()
		how_to_play_panel.visible = true
	)
	action_buttons.add_child(htp_btn)

	var settings_btn := Button.new()
	settings_btn.text = "SETTINGS"
	settings_btn.custom_minimum_size = Vector2(0, 40)
	settings_btn.pressed.connect(func():
		_play_click()
		settings_panel.visible = true
	)
	action_buttons.add_child(settings_btn)

	var restart_btn := Button.new()
	restart_btn.text = "RESTART RUN"
	restart_btn.custom_minimum_size = Vector2(0, 40)
	restart_btn.pressed.connect(func():
		_show_confirmation(
			"ABANDON CURRENT RUN?",
			"Active progress and enemy mutations in this simulation will be lost.",
			Callable(self, "_confirm_restart")
		)
	)
	action_buttons.add_child(restart_btn)

	var menu_btn := Button.new()
	menu_btn.text = "ABORT TO MAIN MENU"
	menu_btn.custom_minimum_size = Vector2(0, 40)
	menu_btn.pressed.connect(func():
		_show_confirmation(
			"ABORT TO TITLE MENU?",
			"Active simulation telemetry will be terminated.",
			Callable(self, "_confirm_menu")
		)
	)
	action_buttons.add_child(menu_btn)

	quit_btn = Button.new()
	quit_btn.text = "QUIT SESSION"
	quit_btn.custom_minimum_size = Vector2(0, 48)
	var quit_style := StyleBoxFlat.new()
	quit_style.bg_color = Color(0.20, 0.05, 0.06, 0.90)
	quit_style.border_color = Color("ef4444")
	quit_style.set_border_width_all(1)
	quit_style.set_corner_radius_all(4)
	quit_btn.add_theme_stylebox_override("normal", quit_style)
	quit_btn.add_theme_color_override("font_color", Color("fca5a5"))
	quit_btn.pressed.connect(func():
		_show_confirmation(
			"TERMINATE APPLICATION // QUIT SESSION",
			"The game will close and the active run and its evolutions will be lost.",
			Callable(self, "_confirm_quit")
		)
	)
	action_buttons.add_child(quit_btn)

	# Build child modals
	_build_confirm_modal()
	_build_how_to_play_modal()
	_build_settings_modal()
	_style_menu_buttons(self)
	menu_glitch = MENU_GLITCH_SCRIPT.new()
	menu_glitch.layer = 30
	menu_glitch.visible = false
	add_child(menu_glitch)


func _style_menu_buttons(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			var danger := str(child.text).contains("ABORT") or str(child.text).contains("QUIT") or str(child.text).contains("RESTART") or str(child.text).contains("CONFIRM")
			MENU_SKIN.style_button(child, Color("fb7185") if danger else Color("38bdf8"), danger)
		_style_menu_buttons(child)


func get_quit_button() -> Button:
	return quit_btn


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
		var total_rooms: int = rs.progression.rooms_per_sector if rs.progression else rs.TOTAL_ROOMS
		stats_label.text = "SEC %d • ROOM %d/%d • ELIMS: %d • BITS: %d • TIME: %02d:%02d" % [
			rs.current_sector,
			rs.current_room_index + 1,
			total_rooms,
			rs.score,
			rs.bits,
			mins,
			secs
		]

		# Rebuild the generated route graph, including optional-room bypass links.
		total_rooms = rs.progression.rooms_per_sector if (rs and rs.progression) else rs.TOTAL_ROOMS
		var cur_room: int = rs.current_room_index
		minimap_nodes_hbox.call("configure_map", rs.dungeon_layout_summary, cur_room, total_rooms)

		# Clear previous items
		for child in upgrades_vbox.get_children():
			upgrades_vbox.remove_child(child)
			child.queue_free()

		if rs.active_upgrade_ids.is_empty():
			var empty_lbl := Label.new()
			empty_lbl.text = "None. Draft upgrades by purging room hostiles."
			empty_lbl.add_theme_font_size_override("font_size", 11)
			empty_lbl.add_theme_color_override("font_color", Color("64748b"))
			upgrades_vbox.add_child(empty_lbl)
		else:
			var upgrade_counts: Dictionary = {}
			for upg_id in rs.active_upgrade_ids:
				upgrade_counts[upg_id] = int(upgrade_counts.get(upg_id, 0)) + 1
			for upg_id in upgrade_counts:
				var lbl := Label.new()
				var count: int = int(upgrade_counts[upg_id])
				lbl.text = "%s ×%d" % [upg_id, count] if count > 1 else str(upg_id)
				lbl.add_theme_font_size_override("font_size", 10)
				lbl.add_theme_color_override("font_color", Color("cbd5e1"))
				upgrades_vbox.add_child(lbl)

	get_tree().paused = true
	visible = true
	if is_instance_valid(menu_glitch):
		menu_glitch.visible = true
	_animate_pause_controls()
	var p = get_parent()
	if p:
		var game_node = p.get_parent()
		if game_node and "touch_controls" in game_node and is_instance_valid(game_node.touch_controls):
			game_node.touch_controls.visible = false
			game_node.touch_controls.enabled = false
			if game_node.touch_controls.has_method("reset_controls"):
				game_node.touch_controls.reset_controls()
	_play_click()


func close_pause() -> void:
	if is_inside_tree():
		get_tree().paused = false
	visible = false
	if is_instance_valid(menu_glitch):
		menu_glitch.visible = false
	var p = get_parent()
	if p:
		var game_node = p.get_parent()
		if game_node and "touch_controls" in game_node and is_instance_valid(game_node.touch_controls):
			game_node.touch_controls.visible = true
			game_node.touch_controls.enabled = true
	_play_click()
	resume_requested.emit()


func _animate_pause_controls() -> void:
	if not is_instance_valid(action_buttons):
		return
	for index in range(action_buttons.get_child_count()):
		var button := action_buttons.get_child(index) as Control
		button.modulate.a = 0.0
		var tween := create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_interval(float(index) * 0.035)
		tween.tween_property(button, "modulate:a", 1.0, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _show_confirmation(title: String, message: String, callback: Callable) -> void:
	_play_click()
	confirm_callback = callback
	confirm_msg_label.text = "%s\n\n%s" % [title, message]
	confirm_panel.visible = true


func _confirm_restart() -> void:
	confirm_panel.visible = false
	if is_inside_tree():
		get_tree().paused = false
	visible = false
	if is_instance_valid(menu_glitch):
		menu_glitch.visible = false
	var p = get_parent()
	if p:
		var game_node = p.get_parent()
		if game_node and "touch_controls" in game_node and is_instance_valid(game_node.touch_controls):
			game_node.touch_controls.visible = true
			game_node.touch_controls.enabled = true
	restart_requested.emit()


func _confirm_menu() -> void:
	confirm_panel.visible = false
	if is_instance_valid(menu_glitch):
		menu_glitch.visible = false
	if is_inside_tree():
		get_tree().paused = false
	visible = false
	var p = get_parent()
	if p:
		var game_node = p.get_parent()
		if game_node and "touch_controls" in game_node and is_instance_valid(game_node.touch_controls):
			game_node.touch_controls.visible = true
			game_node.touch_controls.enabled = true
	menu_requested.emit()


func _confirm_quit() -> void:
	confirm_panel.visible = false
	if is_inside_tree():
		get_tree().paused = false
		get_tree().quit()
	quit_requested.emit()



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
		["NAVIGATION", "Drag the left virtual stick to move. Tap DASH to dodge through incoming fire."],
		["AIMING", "Drag the right virtual stick to aim and fire twin plasma bolts."],
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
