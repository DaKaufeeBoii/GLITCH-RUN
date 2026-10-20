extends Control
## Minimal tap-to-start splash screen. The existing menu is the second screen.

var prompt: Label
var splash_stack: VBoxContainer
var logo_visual: Control
var transitioning := false
var pulse_time := 0.0
const GLITCH_OVERLAY := preload("res://scripts/menu_glitch_overlay.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_screen()
	add_child(GLITCH_OVERLAY.new())
	var audio: Node = get_node_or_null("/root/AudioSynth")
	if audio:
		audio.play_music("theme_loop")


func _process(delta: float) -> void:
	pulse_time += delta
	if is_instance_valid(prompt):
		prompt.modulate.a = 0.65 + (sin(pulse_time * 2.4) + 1.0) * 0.17
	if is_instance_valid(splash_stack):
		splash_stack.rotation = sin(pulse_time * 0.45) * 0.010
	if is_instance_valid(logo_visual):
		logo_visual.pivot_offset = logo_visual.size * 0.5
		logo_visual.rotation = sin(pulse_time * 0.8) * 0.014
		var logo_scale := 1.0 + sin(pulse_time * 1.6) * 0.012
		logo_visual.scale = Vector2(logo_scale, logo_scale)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_open_menu()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()


func _build_screen() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("030712")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var grid := Control.new()
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.draw.connect(func():
		for x in range(0, 960, 48):
			grid.draw_line(Vector2(x, 0), Vector2(x, 540), Color(0.08, 0.14, 0.25, 0.3), 1.0)
		for y in range(0, 540, 48):
			grid.draw_line(Vector2(0, y), Vector2(960, y), Color(0.08, 0.14, 0.25, 0.3), 1.0)
	)
	add_child(grid)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	splash_stack = VBoxContainer.new()
	var stack := splash_stack
	stack.custom_minimum_size = Vector2(0, 190)
	stack.add_theme_constant_override("separation", 18)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(stack)

	var logo_tex = load("res://assets/ui/glitch_run_logo.png")
	if logo_tex:
		var logo_rect := TextureRect.new()
		logo_rect.texture = logo_tex
		logo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo_rect.custom_minimum_size = Vector2(480, 110)
		logo_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		logo_visual = logo_rect
		stack.add_child(logo_rect)
	else:
		var title := Label.new()
		title.text = "GLITCH // RUN"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.add_theme_font_size_override("font_size", 58)
		title.add_theme_color_override("font_color", Color("38bdf8"))
		logo_visual = title
		stack.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "ADAPT. SURVIVE. DESCEND."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color("f43f5e"))
	stack.add_child(subtitle)

	prompt = Label.new()
	prompt.text = "TAP TO START"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.add_theme_font_size_override("font_size", 20)
	prompt.add_theme_color_override("font_color", Color("e2e8f0"))
	prompt.custom_minimum_size = Vector2(280, 52)
	stack.add_child(prompt)


func _open_menu() -> void:
	if transitioning or not is_inside_tree():
		return
	transitioning = true
	var audio: Node = get_node_or_null("/root/AudioSynth")
	if audio:
		audio.play("ui_click")
	var cover := ColorRect.new()
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.color = Color("030712")
	cover.modulate.a = 0.0
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.process_mode = Node.PROCESS_MODE_ALWAYS
	cover.z_index = 20
	add_child(cover)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(cover, "modulate:a", 1.0, 0.24)
	await tween.finished
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
