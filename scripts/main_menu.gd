extends Control
## Cyberpunk Main Menu for GLITCH//RUN.
## Title screen with glitch neon aesthetics, persistent records,
## and Director Archive threat database modal.

const DIRECTOR_TESTS_SCRIPT := preload("res://scripts/test_director.gd")

var archive_panel: Control
var records_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.is_debug_build():
		DIRECTOR_TESTS_SCRIPT.run_all_tests()
	_build_ui()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Deep Cyber Dark Background
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.012, 0.02, 0.045, 1.0)
	add_child(bg)

	# Decorative Grid Lines
	var grid_node := Control.new()
	grid_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid_node.draw.connect(func():
		for x in range(0, 960, 48):
			grid_node.draw_line(Vector2(x, 0), Vector2(x, 540), Color(0.08, 0.14, 0.25, 0.22), 1.0)
		for y in range(0, 540, 48):
			grid_node.draw_line(Vector2(0, y), Vector2(960, y), Color(0.08, 0.14, 0.25, 0.22), 1.0)
	)
	add_child(grid_node)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var main_vbox := VBoxContainer.new()
	main_vbox.custom_minimum_size = Vector2(480, 0)
	main_vbox.add_theme_constant_override("separation", 18)
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(main_vbox)

	# Glowing Title Banner
	var title_vbox := VBoxContainer.new()
	title_vbox.add_theme_constant_override("separation", 2)
	main_vbox.add_child(title_vbox)

	var title_lbl := Label.new()
	title_lbl.text = "GLITCH // RUN"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 42)
	title_lbl.add_theme_color_override("font_color", Color("38bdf8"))
	title_vbox.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "AN ADAPTIVE ROGUELITE SIMULATION"
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", 14)
	sub_lbl.add_theme_color_override("font_color", Color("f43f5e"))
	title_vbox.add_child(sub_lbl)

	# Records Badge
	records_label = Label.new()
	records_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	records_label.add_theme_font_size_override("font_size", 12)
	records_label.add_theme_color_override("font_color", Color("94a3b8"))
	_update_records_display()
	main_vbox.add_child(records_label)

	# Action Buttons
	var btn_vbox := VBoxContainer.new()
	btn_vbox.custom_minimum_size = Vector2(280, 0)
	btn_vbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn_vbox.add_theme_constant_override("separation", 12)
	main_vbox.add_child(btn_vbox)

	var play_btn := Button.new()
	play_btn.text = "INITIALIZE SIMULATION"
	play_btn.custom_minimum_size = Vector2(260, 46)
	play_btn.pressed.connect(_on_play_pressed)
	btn_vbox.add_child(play_btn)

	var archive_btn := Button.new()
	archive_btn.text = "DIRECTOR ARCHIVE"
	archive_btn.custom_minimum_size = Vector2(260, 42)
	archive_btn.pressed.connect(_on_archive_pressed)
	btn_vbox.add_child(archive_btn)

	# Build Archive Modal (Hidden initially)
	_build_archive_modal()


func _update_records_display() -> void:
	var rs = get_node_or_null("/root/RunState")
	if rs and rs.best_score > 0:
		var mins := int(rs.best_time / 60.0)
		var secs := int(rs.best_time) % 60
		records_label.text = "PERSISTENT ARCHIVE: BEST SECTOR %d  •  HIGHEST PURGE: %d  •  RECORD: %02d:%02d" % [
			rs.best_sector,
			rs.best_score,
			mins,
			secs
		]
	else:
		records_label.text = "PERSISTENT ARCHIVE: READY FOR CALIBRATION RUN"


func _on_play_pressed() -> void:
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("ui_click", 0.0, 0.0)
	var rs = get_node_or_null("/root/RunState")
	if rs:
		rs.start_new_run()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_archive_pressed() -> void:
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("ui_click", 0.0, 0.0)
	archive_panel.visible = true


func _build_archive_modal() -> void:
	archive_panel = Control.new()
	archive_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	archive_panel.visible = false
	add_child(archive_panel)

	var modal_bg := ColorRect.new()
	modal_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_bg.color = Color(0.012, 0.02, 0.045, 0.95)
	archive_panel.add_child(modal_bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	archive_panel.add_child(center)

	var panel_box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.14, 0.92)
	style.border_color = Color("38bdf8")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 24
	style.content_margin_top = 20
	style.content_margin_right = 24
	style.content_margin_bottom = 20
	panel_box.add_theme_stylebox_override("panel", style)
	center.add_child(panel_box)

	var modal_vbox := VBoxContainer.new()
	modal_vbox.custom_minimum_size = Vector2(580, 0)
	modal_vbox.add_theme_constant_override("separation", 14)
	panel_box.add_child(modal_vbox)

	var hdr := Label.new()
	hdr.text = "DIRECTOR ARCHIVE // THREAT TAXONOMY"
	hdr.add_theme_font_size_override("font_size", 20)
	hdr.add_theme_color_override("font_color", Color("38bdf8"))
	modal_vbox.add_child(hdr)

	var desc := Label.new()
	desc.text = "The Adaptive Director analyzes player mobility, distance, and firing telemetry in real time, deploying evolutionary mutations to counter your dominant tactics:"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color("cbd5e1"))
	modal_vbox.add_child(desc)

	# Hostiles breakdown
	var enemies_info := [
		["CHASER (Ruby Diamond)", "Evolves Pincer Flanking angles (+/-38 deg) to envelope long-range kiters and avoid bunching."],
		["SHOOTER (Amber Hexagon)", "Evolves Intercept Lead Aiming (lambda = 0.75 - 1.0) with predictive lasers to snipe hyper-mobile targets."],
		["DASHER (Magenta Chevron)", "Evolves Lingering Electric Hazard Trails that punish circular kite routes and stationary turrets."],
		["NEXUS OVERLORD (Boss Octagon)", "Tri-satellite orbital shield array, sweeping rotational Tachyon beams, and phase transitions."]
	]

	for item in enemies_info:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		modal_vbox.add_child(row)

		var title := Label.new()
		title.text = "• %s" % item[0]
		title.add_theme_font_size_override("font_size", 13)
		title.add_theme_color_override("font_color", Color("f43f5e"))
		row.add_child(title)

		var text := Label.new()
		text.text = item[1]
		text.add_theme_font_size_override("font_size", 11)
		text.add_theme_color_override("font_color", Color("94a3b8"))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(text)

	var close_btn := Button.new()
	close_btn.text = "CLOSE ARCHIVE"
	close_btn.custom_minimum_size = Vector2(160, 38)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_btn.pressed.connect(func():
		if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
			get_node("/root/AudioSynth").play("ui_click", 0.0, 0.0)
		archive_panel.visible = false
	)
	modal_vbox.add_child(close_btn)
