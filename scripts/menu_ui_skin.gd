extends RefCounted
## Shared compact visual styling for non-title menu controls.

static func style_button(button: Button, accent: Color = Color("38bdf8"), danger: bool = false) -> void:
	var main := Color("190d18") if danger else Color("0a1c2d")
	var hover := Color("32101e") if danger else Color("10334b")
	var pressed := Color("4a1424") if danger else Color("16465d")
	var disabled := Color("0a101b")
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = main
		box.border_color = accent
		box.set_border_width_all(1)
		box.set_corner_radius_all(4)
		box.content_margin_left = 10
		box.content_margin_right = 10
		box.content_margin_top = 6
		box.content_margin_bottom = 6
		if state == "hover":
			box.bg_color = hover
			box.set_border_width_all(2)
		elif state == "pressed":
			box.bg_color = pressed
		elif state == "disabled":
			box.bg_color = disabled
			box.border_color = Color("334155")
		button.add_theme_stylebox_override(state, box)
	button.add_theme_color_override("font_color", Color("e2e8f0"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("64748b"))
	button.add_theme_font_size_override("font_size", 13)


static func style_panel(panel: PanelContainer, accent: Color = Color("38bdf8"), fill: Color = Color("071426")) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = accent
	box.set_border_width_all(1)
	box.set_corner_radius_all(5)
	box.content_margin_left = 10
	box.content_margin_top = 8
	box.content_margin_right = 10
	box.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", box)
