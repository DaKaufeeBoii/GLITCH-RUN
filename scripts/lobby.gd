extends Control
## Character selection and permanent Bits sink between the title menu and a run.

var balance_label: Label
var status_label: Label
var selection_label: Label
var loadout_panel: PanelContainer
var card_list: VBoxContainer
var deploy_button: Button
var transition_busy := false

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const GAME_SCENE := "res://scenes/main.tscn"
const MENU_BACKDROP_SCRIPT := preload("res://scripts/menu_backdrop.gd")
const MENU_SKIN := preload("res://scripts/menu_ui_skin.gd")
const MENU_GLITCH_SCRIPT := preload("res://scripts/menu_glitch_overlay.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	var menu_glitch: CanvasLayer = MENU_GLITCH_SCRIPT.new()
	add_child(menu_glitch)
	var rs = get_node_or_null("/root/RunState")
	if rs and not rs.archive_bits_updated.is_connected(_on_archive_bits_updated):
		rs.archive_bits_updated.connect(_on_archive_bits_updated)
	_refresh()


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := MENU_BACKDROP_SCRIPT.new()
	bg.accent = Color("c084fc")
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 18.0
	root.offset_top = 12.0
	root.offset_right = -18.0
	root.offset_bottom = -12.0
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "OPERATIVE BAY  //  PERSONNEL"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("38bdf8"))
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	balance_label = Label.new()
	balance_label.add_theme_font_size_override("font_size", 16)
	balance_label.add_theme_color_override("font_color", Color("fbbf24"))
	header.add_child(balance_label)

	var sub := Label.new()
	sub.text = "Spend archived Bits on permanent operatives. Run upgrades remain separate."
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color("94a3b8"))
	root.add_child(sub)

	card_list = VBoxContainer.new()
	card_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_list.custom_minimum_size.y = 282
	card_list.size_flags_vertical = Control.SIZE_FILL
	card_list.add_theme_constant_override("separation", 8)
	root.add_child(card_list)

	loadout_panel = PanelContainer.new()
	MENU_SKIN.style_panel(loadout_panel, Color("c084fc"), Color("0b1021"))
	root.add_child(loadout_panel)
	var loadout_info := VBoxContainer.new()
	loadout_info.add_theme_constant_override("separation", 3)
	loadout_panel.add_child(loadout_info)
	selection_label = Label.new()
	selection_label.text = "ACTIVE LOADOUT"
	selection_label.add_theme_font_size_override("font_size", 13)
	selection_label.add_theme_color_override("font_color", Color("e9d5ff"))
	loadout_info.add_child(selection_label)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 10)
	status_label.add_theme_color_override("font_color", Color("fca5a5"))
	loadout_info.add_child(status_label)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	root.add_child(footer)
	var back := Button.new()
	back.text = "BACK TO TITLE"
	back.custom_minimum_size = Vector2(0, 42)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(_return_to_menu)
	MENU_SKIN.style_button(back, Color("64748b"))
	footer.add_child(back)
	deploy_button = Button.new()
	deploy_button.text = "DEPLOY"
	deploy_button.custom_minimum_size = Vector2(0, 42)
	deploy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deploy_button.pressed.connect(_deploy)
	MENU_SKIN.style_button(deploy_button, Color("38bdf8"))
	footer.add_child(deploy_button)


func _refresh() -> void:
	var rs = get_node_or_null("/root/RunState")
	if not rs:
		return
	balance_label.text = "ARCHIVE BITS  %d" % rs.archive_bits
	selection_label.text = "SELECTED LOADOUT  //  %s" % rs.get_selected_character_profile().get("title", "OPERATIVE")
	deploy_button.text = "DEPLOY  //  %s" % rs.get_selected_character_profile().get("title", "OPERATIVE")
	for child in card_list.get_children():
		card_list.remove_child(child)
		child.queue_free()
	var catalog: Dictionary = rs.get_character_catalog()
	for character_id in ["OPERATIVE", "BREACHER", "LONGSHOT"]:
		var profile: Dictionary = catalog[character_id]
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(0, 88)
		var character_accent := Color("c084fc") if character_id == "LONGSHOT" else Color("fb7185") if character_id == "BREACHER" else Color("38bdf8")
		var selected: bool = str(rs.selected_character_id) == character_id
		MENU_SKIN.style_panel(card, character_accent if selected else Color("164e63"), Color("091323") if selected else Color("071426"))
		card_list.add_child(card)
		card.modulate.a = 0.0
		var card_tween := create_tween()
		card_tween.tween_interval(float(card_list.get_child_count() - 1) * 0.045)
		card_tween.tween_property(card, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var stripe := ColorRect.new()
		stripe.color = character_accent
		stripe.custom_minimum_size.x = 4
		stripe.size_flags_vertical = Control.SIZE_EXPAND_FILL
		row.add_child(stripe)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(info)
		var character_title := Label.new()
		character_title.text = "%s  //  %s" % [profile.title, profile.role]
		character_title.add_theme_font_size_override("font_size", 15)
		character_title.add_theme_color_override("font_color", Color("38bdf8"))
		info.add_child(character_title)
		var desc := Label.new()
		desc.text = profile.desc
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 10)
		desc.add_theme_color_override("font_color", Color("cbd5e1"))
		info.add_child(desc)
		var action := Button.new()
		action.custom_minimum_size = Vector2(150, 42)
		MENU_SKIN.style_button(action, character_accent)
		row.add_child(action)
		if rs.is_character_unlocked(character_id):
			if rs.selected_character_id == character_id:
				action.text = "EQUIPPED"
				action.disabled = true
			else:
				action.text = "SELECT"
				action.pressed.connect(_select_character.bind(character_id))
		else:
			var price: int = int(profile.price)
			action.text = "BUY  //  %d BITS" % price
			action.disabled = rs.archive_bits < price
			action.pressed.connect(_purchase_character.bind(character_id))


func _on_archive_bits_updated(_amount: int) -> void:
	_refresh()


func _select_character(character_id: String) -> void:
	var rs = get_node_or_null("/root/RunState")
	if rs and rs.select_character(character_id):
		status_label.text = ""
		_refresh()


func _purchase_character(character_id: String) -> void:
	var rs = get_node_or_null("/root/RunState")
	if rs and rs.purchase_character(character_id):
		_refresh()
		status_label.add_theme_color_override("font_color", Color("86efac"))
		status_label.text = "%s UNLOCKED // LOADOUT EQUIPPED" % rs.get_selected_character_profile().title
	else:
		status_label.text = "NOT ENOUGH ARCHIVE BITS"


func _deploy() -> void:
	if transition_busy:
		return
	transition_busy = true
	await _transition_to(GAME_SCENE)


func _return_to_menu() -> void:
	if transition_busy:
		return
	transition_busy = true
	await _transition_to(MENU_SCENE)


func _transition_to(scene_path: String) -> void:
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
	tween.tween_property(cover, "modulate:a", 1.0, 0.22)
	await tween.finished
	get_tree().change_scene_to_file(scene_path)
