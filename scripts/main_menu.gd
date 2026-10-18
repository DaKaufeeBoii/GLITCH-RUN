extends Control
## Cyberpunk Main Menu for GLITCH//RUN.
## Touch-first title screen with neon aesthetics, difficulty selection,
## persistent settings modal, tactical manual (How to Play), threat archive, and exit handling.

const DIRECTOR_TESTS_SCRIPT := preload("res://scripts/test_director.gd")

var archive_panel: Control
var settings_panel: Control
var how_to_play_panel: Control
var records_label: Label
var difficulty_btn: Button

const DIFFICULTIES := ["NORMAL", "HARD", "HYPERGRID"]
var difficulty_index := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_cmdline_user_args().has("--run-tests") or OS.get_cmdline_args().has("--run-tests"):
		DIRECTOR_TESTS_SCRIPT.run_all_tests()

	# Start synthwave theme loop
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play_music("theme_loop")

	_sync_difficulty_from_state()
	_build_ui()


func _sync_difficulty_from_state() -> void:
	var rs = get_node_or_null("/root/RunState")
	if rs:
		var cur_diff: String = rs.difficulty.to_upper()
		var idx := DIFFICULTIES.find(cur_diff)
		if idx >= 0:
			difficulty_index = idx
		else:
			difficulty_index = 0


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back_request()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK)):
		_handle_back_request()
		if is_inside_tree():
			get_viewport().set_input_as_handled()


func _handle_back_request() -> void:
	if settings_panel and settings_panel.visible:
		settings_panel.visible = false
	elif how_to_play_panel and how_to_play_panel.visible:
		how_to_play_panel.visible = false
	elif archive_panel and archive_panel.visible:
		archive_panel.visible = false
	else:
		_on_quit_pressed()


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

	var main_row := HBoxContainer.new()
	main_row.custom_minimum_size = Vector2(800, 0)
	main_row.add_theme_constant_override("separation", 56)
	center.add_child(main_row)

	var identity_column := VBoxContainer.new()
	identity_column.custom_minimum_size = Vector2(400, 0)
	identity_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_column.add_theme_constant_override("separation", 18)
	identity_column.alignment = BoxContainer.ALIGNMENT_CENTER
	main_row.add_child(identity_column)

	# Glowing Title Banner
	var title_vbox := VBoxContainer.new()
	title_vbox.add_theme_constant_override("separation", 2)
	identity_column.add_child(title_vbox)

	var title_lbl := Label.new()
	title_lbl.text = "GLITCH // RUN"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_lbl.add_theme_font_size_override("font_size", 38)
	title_lbl.add_theme_color_override("font_color", Color("38bdf8"))
	title_vbox.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "AN ADAPTIVE ROGUELITE SIMULATION"
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sub_lbl.add_theme_font_size_override("font_size", 13)
	sub_lbl.add_theme_color_override("font_color", Color("f43f5e"))
	title_vbox.add_child(sub_lbl)

	# Records Badge
	records_label = Label.new()
	records_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	records_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	records_label.add_theme_font_size_override("font_size", 12)
	records_label.add_theme_color_override("font_color", Color("94a3b8"))
	_update_records_display()
	identity_column.add_child(records_label)

	# Action Buttons (Touch-friendly 48dp+ sizing)
	var btn_vbox := VBoxContainer.new()
	btn_vbox.custom_minimum_size = Vector2(300, 0)
	btn_vbox.add_theme_constant_override("separation", 8)
	btn_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_row.add_child(btn_vbox)

	var play_btn := Button.new()
	play_btn.text = "INITIALIZE SIMULATION"
	play_btn.custom_minimum_size = Vector2(280, 48)
	play_btn.pressed.connect(_on_play_pressed)
	btn_vbox.add_child(play_btn)

	difficulty_btn = Button.new()
	difficulty_btn.text = "DIFFICULTY: %s" % DIFFICULTIES[difficulty_index]
	difficulty_btn.custom_minimum_size = Vector2(280, 48)
	difficulty_btn.pressed.connect(_on_difficulty_pressed)
	btn_vbox.add_child(difficulty_btn)

	var htp_btn := Button.new()
	htp_btn.text = "HOW TO PLAY"
	htp_btn.custom_minimum_size = Vector2(280, 48)
	htp_btn.pressed.connect(func():
		_play_click()
		how_to_play_panel.visible = true
	)
	btn_vbox.add_child(htp_btn)

	var settings_btn := Button.new()
	settings_btn.text = "SETTINGS"
	settings_btn.custom_minimum_size = Vector2(280, 48)
	settings_btn.pressed.connect(func():
		_play_click()
		settings_panel.visible = true
	)
	btn_vbox.add_child(settings_btn)

	var archive_btn := Button.new()
	archive_btn.text = "DIRECTOR ARCHIVE"
	archive_btn.custom_minimum_size = Vector2(280, 48)
	archive_btn.pressed.connect(func():
		_play_click()
		archive_panel.visible = true
	)
	btn_vbox.add_child(archive_btn)

	var quit_btn := Button.new()
	quit_btn.text = "TERMINATE SESSION"
	quit_btn.custom_minimum_size = Vector2(280, 48)
	quit_btn.pressed.connect(_on_quit_pressed)
	btn_vbox.add_child(quit_btn)

	# Build Modals
	_build_archive_modal()
	_build_settings_modal()
	_build_how_to_play_modal()


func _update_records_display() -> void:
	var rs: Node = get_node_or_null("/root/RunState") if is_inside_tree() else null
	if rs and rs.best_score > 0:
		var mins := int(rs.best_time / 60.0)
		var secs := int(rs.best_time) % 60
		records_label.text = "RECORD ARCHIVE: DEPTH %d (SEC %d)  •  PURGED: %d  •  TIME: %02d:%02d" % [
			rs.best_depth,
			rs.best_sector,
			rs.best_score,
			mins,
			secs
		]
	else:
		records_label.text = "PERSISTENT ARCHIVE: READY FOR CALIBRATION RUN"


func _on_difficulty_pressed() -> void:
	_play_click()
	difficulty_index = (difficulty_index + 1) % DIFFICULTIES.size()
	var new_diff: String = DIFFICULTIES[difficulty_index]
	difficulty_btn.text = "DIFFICULTY: %s" % new_diff
	var rs: Node = get_node_or_null("/root/RunState") if is_inside_tree() else null
	if rs:
		rs.difficulty = new_diff
		rs.save_persistent_data()


func _on_play_pressed() -> void:
	_play_click()
	var rs: Node = get_node_or_null("/root/RunState") if is_inside_tree() else null
	if rs:
		rs.start_new_run()
	if is_inside_tree():
		get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_quit_pressed() -> void:
	_play_click()
	if is_inside_tree():
		get_tree().quit()


func _play_click() -> void:
	if not is_inside_tree():
		return
	var audio: Node = get_node_or_null("/root/AudioSynth")
	if audio:
		audio.play("ui_click", 0.0, 0.0)


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
	vbox.custom_minimum_size = Vector2(580, 0)
	vbox.add_theme_constant_override("separation", 12)
	panel_box.add_child(vbox)

	var hdr := Label.new()
	hdr.text = "TACTICAL MANUAL // HOW TO PLAY"
	hdr.add_theme_font_size_override("font_size", 20)
	hdr.add_theme_color_override("font_color", Color("38bdf8"))
	vbox.add_child(hdr)

	var guides := [
		["MOVEMENT & EVASION", "Left virtual stick or WASD to navigate. Tap DASH button or Spacebar to trigger an invulnerable phase dash through incoming fire."],
		["AIM & WEAPONS", "Right virtual stick or Mouse cursor aims and automatically discharges twin plasma bolts."],
		["ADAPTIVE ENEMY AI", "Hostiles track your movement, range, and fire rate. If you kite, Chasers flank. If you dash rapidly, Shooters lead aim. If you camp, Dashers drop hazards."],
		["TELEGRAPH DODGING", "Lethal attacks project glowing telegraph guide lines that lock direction before firing. Watch the lock window and cut back to dodge."],
		["SUBROUTINES & ROUTE DOORS", "Clear waves to draft passive upgrades. Approach glowing holographic sector portals to select your destination chamber."]
	]

	for g in guides:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		vbox.add_child(row)

		var t := Label.new()
		t.text = "• %s" % g[0]
		t.add_theme_font_size_override("font_size", 13)
		t.add_theme_color_override("font_color", Color("f43f5e"))
		row.add_child(t)

		var d := Label.new()
		d.text = g[1]
		d.add_theme_font_size_override("font_size", 11)
		d.add_theme_color_override("font_color", Color("cbd5e1"))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(d)

	var close_btn := Button.new()
	close_btn.text = "RETURN"
	close_btn.custom_minimum_size = Vector2(160, 44)
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
	style.content_margin_left = 28
	style.content_margin_top = 20
	style.content_margin_right = 28
	style.content_margin_bottom = 20
	panel_box.add_theme_stylebox_override("panel", style)
	center.add_child(panel_box)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(520, 0)
	vbox.add_theme_constant_override("separation", 14)
	panel_box.add_child(vbox)

	var hdr := Label.new()
	hdr.text = "SYSTEM CONFIGURATION // SETTINGS"
	hdr.add_theme_font_size_override("font_size", 20)
	hdr.add_theme_color_override("font_color", Color("38bdf8"))
	vbox.add_child(hdr)

	var sm: Node = get_node_or_null("/root/Settings") if is_inside_tree() else null

	# Master Volume Slider
	var master_hbox := HBoxContainer.new()
	vbox.add_child(master_hbox)
	var m_lbl := Label.new()
	m_lbl.text = "MASTER VOLUME:"
	m_lbl.custom_minimum_size = Vector2(160, 0)
	master_hbox.add_child(m_lbl)
	var m_slider := HSlider.new()
	m_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m_slider.min_value = 0.0
	m_slider.max_value = 1.0
	m_slider.step = 0.05
	m_slider.value = sm.master_volume if sm else 1.0
	master_hbox.add_child(m_slider)
	var m_val_lbl := Label.new()
	m_val_lbl.text = "%d%%" % int(m_slider.value * 100.0)
	m_val_lbl.custom_minimum_size = Vector2(50, 0)
	master_hbox.add_child(m_val_lbl)
	m_slider.value_changed.connect(func(val: float):
		m_val_lbl.text = "%d%%" % int(val * 100.0)
		if sm:
			sm.master_volume = val
			sm.set_bus_volume("Master", val)
	)

	# Music Volume Slider
	var music_hbox := HBoxContainer.new()
	vbox.add_child(music_hbox)
	var mus_lbl := Label.new()
	mus_lbl.text = "MUSIC VOLUME:"
	mus_lbl.custom_minimum_size = Vector2(160, 0)
	music_hbox.add_child(mus_lbl)
	var mus_slider := HSlider.new()
	mus_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mus_slider.min_value = 0.0
	mus_slider.max_value = 1.0
	mus_slider.step = 0.05
	mus_slider.value = sm.music_volume if sm else 0.75
	music_hbox.add_child(mus_slider)
	var mus_val_lbl := Label.new()
	mus_val_lbl.text = "%d%%" % int(mus_slider.value * 100.0)
	mus_val_lbl.custom_minimum_size = Vector2(50, 0)
	music_hbox.add_child(mus_val_lbl)
	mus_slider.value_changed.connect(func(val: float):
		mus_val_lbl.text = "%d%%" % int(val * 100.0)
		if sm:
			sm.music_volume = val
			sm.set_bus_volume("Music", val)
	)

	# SFX Volume Slider
	var sfx_hbox := HBoxContainer.new()
	vbox.add_child(sfx_hbox)
	var sfx_lbl := Label.new()
	sfx_lbl.text = "SFX VOLUME:"
	sfx_lbl.custom_minimum_size = Vector2(160, 0)
	sfx_hbox.add_child(sfx_lbl)
	var sfx_slider := HSlider.new()
	sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.05
	sfx_slider.value = sm.sfx_volume if sm else 0.9
	sfx_hbox.add_child(sfx_slider)
	var sfx_val_lbl := Label.new()
	sfx_val_lbl.text = "%d%%" % int(sfx_slider.value * 100.0)
	sfx_val_lbl.custom_minimum_size = Vector2(50, 0)
	sfx_hbox.add_child(sfx_val_lbl)
	sfx_slider.value_changed.connect(func(val: float):
		sfx_val_lbl.text = "%d%%" % int(val * 100.0)
		if sm:
			sm.sfx_volume = val
			sm.set_bus_volume("SFX", val)
	)

	# Screen Shake CheckButton
	var shake_btn := CheckButton.new()
	shake_btn.text = "SCREEN SHAKE (TRAUMA FX)"
	shake_btn.button_pressed = sm.screen_shake_enabled if sm else true
	shake_btn.toggled.connect(func(pressed: bool):
		if sm:
			sm.screen_shake_enabled = pressed
	)
	vbox.add_child(shake_btn)

	# Haptics CheckButton
	var haptics_btn := CheckButton.new()
	haptics_btn.text = "HAPTIC FEEDBACK (VIBRATION)"
	haptics_btn.button_pressed = sm.haptics_enabled if sm else true
	haptics_btn.toggled.connect(func(pressed: bool):
		if sm:
			sm.haptics_enabled = pressed
	)
	vbox.add_child(haptics_btn)

	# Save & Close
	var close_btn := Button.new()
	close_btn.text = "SAVE & CLOSE"
	close_btn.custom_minimum_size = Vector2(160, 44)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_btn.pressed.connect(func():
		_play_click()
		if sm:
			sm.save_settings()
		settings_panel.visible = false
	)
	vbox.add_child(close_btn)


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
	style.content_margin_top = 18
	style.content_margin_right = 24
	style.content_margin_bottom = 18
	panel_box.add_theme_stylebox_override("panel", style)
	center.add_child(panel_box)

	var modal_vbox := VBoxContainer.new()
	modal_vbox.custom_minimum_size = Vector2(580, 0)
	modal_vbox.add_theme_constant_override("separation", 10)
	panel_box.add_child(modal_vbox)

	var hdr := Label.new()
	hdr.text = "DIRECTOR ARCHIVE // THREAT TAXONOMY"
	hdr.add_theme_font_size_override("font_size", 20)
	hdr.add_theme_color_override("font_color", Color("38bdf8"))
	modal_vbox.add_child(hdr)

	var desc := Label.new()
	desc.text = "The Adaptive Director analyzes player mobility, distance, and firing telemetry, deploying evolutionary mutations to counter your dominant tactics:"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color("cbd5e1"))
	modal_vbox.add_child(desc)

	# Hostiles breakdown including the 3 bosses
	var enemies_info := [
		["CHASER (Ruby Diamond)", "Evolves Pincer Flanking angles (+/-38 deg) to envelope long-range kiters."],
		["SHOOTER (Amber Hexagon)", "Evolves Intercept Lead Aiming (clamped to 45 deg max) with predictive lasers."],
		["DASHER (Magenta Chevron)", "Evolves Lingering Electric Hazard Trails that punish stationary camping."],
		["NEXUS OVERLORD (Singularity Boss)", "Radial tachyon bursts and high-speed directional crush dashes."],
		["VECTOR SENTINEL (Orbital Boss)", "Quad sweeping laser beams and perimeter shard drone defense matrix."],
		["NULL ARCHITECT (Containment Boss)", "Arena quadrant warping and high-voltage grid partition lasers."]
	]

	for item in enemies_info:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		modal_vbox.add_child(row)

		var title := Label.new()
		title.text = "• %s" % item[0]
		title.add_theme_font_size_override("font_size", 12)
		title.add_theme_color_override("font_color", Color("f43f5e"))
		row.add_child(title)

		var text := Label.new()
		text.text = item[1]
		text.add_theme_font_size_override("font_size", 10)
		text.add_theme_color_override("font_color", Color("94a3b8"))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(text)

	var close_btn := Button.new()
	close_btn.text = "CLOSE ARCHIVE"
	close_btn.custom_minimum_size = Vector2(160, 42)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_btn.pressed.connect(func():
		_play_click()
		archive_panel.visible = false
	)
	modal_vbox.add_child(close_btn)
