extends Node2D
## Owns the roguelite game loop: hand-authored rooms, enemy waves, upgrade drafting, and run completion.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const CHASER_SCENE := preload("res://scenes/enemies/chaser.tscn")
const SHOOTER_SCENE := preload("res://scenes/enemies/shooter.tscn")
const DASHER_SCENE := preload("res://scenes/enemies/dasher.tscn")
const BOSS_SCENE := preload("res://scenes/enemies/boss.tscn")
const TOUCH_CONTROLS := preload("res://scripts/mobile_controls.gd")

const ROOM_RECT := Rect2(42.0, 64.0, 876.0, 424.0)

var player: CharacterBody2D
var active_enemies: Array[Node2D] = []
var active_obstacles: Array[StaticBody2D] = []
var obstacle_rects: Array[Rect2] = []

var room_cleared := false
var run_over := false
var boss_active := false
var boss_ref: Node2D = null

# UI Elements
var ui_layer: CanvasLayer
var status_label: Label
var hint_label: Label
var sector_label: Label
var boss_bar_bg: ColorRect
var boss_bar_fill: ColorRect
var boss_label: Label

var upgrade_container: PanelContainer
var upgrade_cards_box: HBoxContainer

var end_panel: Control
var end_title: Label
var end_stats: Label
var end_button: Button


func _ready() -> void:
	if not Engine.has_singleton("RunState") and get_node_or_null("/root/RunState") == null:
		push_error("RunState singleton not found!")
	var rs = get_node("/root/RunState")
	rs.start_new_run()

	_create_ui()
	_create_walls()
	_create_player()
	_load_room(rs.current_room_index)
	queue_redraw()


func _process(delta: float) -> void:
	var rs = get_node_or_null("/root/RunState")
	if not rs or run_over:
		return

	rs.run_time += delta

	# Update Top HUD
	if is_instance_valid(player):
		status_label.text = "HP  %d / %d   |   ELIMS  %d" % [player.health, player.max_health, rs.score]
		sector_label.text = "SECTOR %d / %d" % [rs.current_room_index + 1, rs.TOTAL_ROOMS]

	# Update Boss Bar if in Boss room
	if boss_active and is_instance_valid(boss_ref):
		var pct: float = float(boss_ref.health) / float(boss_ref.max_health)
		boss_bar_fill.size.x = 340.0 * pct
	elif boss_active and not is_instance_valid(boss_ref):
		boss_bar_bg.visible = false


func _draw() -> void:
	# Subtle grid
	for x in range(int(ROOM_RECT.position.x), int(ROOM_RECT.end.x), 32):
		draw_line(Vector2(x, ROOM_RECT.position.y), Vector2(x, ROOM_RECT.end.y), Color("121b36"), 1.0)
	for y in range(int(ROOM_RECT.position.y), int(ROOM_RECT.end.y), 32):
		draw_line(Vector2(ROOM_RECT.position.x, y), Vector2(ROOM_RECT.end.x, y), Color("121b36"), 1.0)

	# Room boundary neon wireframe
	draw_rect(ROOM_RECT, Color("38bdf8"), false, 2.0)

	# Hand-authored obstacles
	for r in obstacle_rects:
		draw_rect(r, Color("1e293b"), true)
		draw_rect(r, Color("475569"), false, 1.5)


func _create_walls() -> void:
	var center_x := ROOM_RECT.position.x + ROOM_RECT.size.x * 0.5
	var center_y := ROOM_RECT.position.y + ROOM_RECT.size.y * 0.5

	# Fixed: All walls accurately positioned at segment midpoints
	_add_wall(Vector2(center_x, ROOM_RECT.position.y - 10.0), Vector2(ROOM_RECT.size.x, 20.0))
	_add_wall(Vector2(center_x, ROOM_RECT.end.y + 10.0), Vector2(ROOM_RECT.size.x, 20.0))
	_add_wall(Vector2(ROOM_RECT.position.x - 10.0, center_y), Vector2(20.0, ROOM_RECT.size.y))
	_add_wall(Vector2(ROOM_RECT.end.x + 10.0, center_y), Vector2(20.0, ROOM_RECT.size.y))


func _add_wall(center: Vector2, size: Vector2) -> void:
	var wall := StaticBody2D.new()
	wall.position = center
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	shape_node.shape = shape
	wall.add_child(shape_node)
	add_child(wall)


func _add_obstacle(pos: Vector2, size: Vector2) -> void:
	var obstacle := StaticBody2D.new()
	obstacle.position = pos
	obstacle.collision_layer = 1
	obstacle.collision_mask = 0
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	shape_node.shape = shape
	obstacle.add_child(shape_node)
	add_child(obstacle)
	active_obstacles.append(obstacle)
	obstacle_rects.append(Rect2(pos - size * 0.5, size))


var touch_controls: Control = null


func _create_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.position = ROOM_RECT.get_center()
	player.connect("died", Callable(self, "_on_player_died"))
	add_child(player)

	touch_controls = Control.new()
	touch_controls.set_script(TOUCH_CONTROLS)
	touch_controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	touch_controls.connect("move_changed", Callable(player, "set_touch_move"))
	touch_controls.connect("aim_changed", Callable(player, "set_touch_aim"))
	touch_controls.connect("fire_changed", Callable(player, "set_touch_fire"))
	touch_controls.connect("dash_pressed", Callable(player, "try_dash"))
	ui_layer.add_child(touch_controls)
	# Ensure touch controls sit beneath interactive menus
	ui_layer.move_child(touch_controls, 0)


func _load_room(index: int) -> void:
	room_cleared = false
	boss_active = false
	boss_ref = null
	boss_bar_bg.visible = false

	# Clear previous room obstacles and projectiles
	for obs in active_obstacles:
		if is_instance_valid(obs):
			obs.queue_free()
	active_obstacles.clear()
	obstacle_rects.clear()

	# Clear lingering projectiles
	for child in get_children():
		if child.is_in_group("projectiles") or child.has_method("_on_body_entered"):
			child.queue_free()

	# Reset player position to center-left
	if is_instance_valid(player):
		player.position = Vector2(ROOM_RECT.position.x + 120.0, ROOM_RECT.get_center().y)

	active_enemies.clear()

	# Hand-authored room layouts & encounters
	match index:
		0:
			# Room 1: Calibration (Open room, 3 Chasers)
			_spawn_enemy(CHASER_SCENE, Vector2(620, 200))
			_spawn_enemy(CHASER_SCENE, Vector2(740, 276))
			_spawn_enemy(CHASER_SCENE, Vector2(620, 360))

		1:
			# Room 2: Firing Line (2 Cover barriers, 2 Chasers, 1 Shooter)
			_add_obstacle(Vector2(380, 276), Vector2(24, 150))
			_add_obstacle(Vector2(620, 276), Vector2(24, 150))
			_spawn_enemy(SHOOTER_SCENE, Vector2(740, 276))
			_spawn_enemy(CHASER_SCENE, Vector2(520, 180))
			_spawn_enemy(CHASER_SCENE, Vector2(520, 370))

		2:
			# Room 3: Vector Ambush (4 Pillar obstacles, 2 Dashers, 2 Chasers)
			_add_obstacle(Vector2(320, 180), Vector2(40, 40))
			_add_obstacle(Vector2(640, 180), Vector2(40, 40))
			_add_obstacle(Vector2(320, 370), Vector2(40, 40))
			_add_obstacle(Vector2(640, 370), Vector2(40, 40))
			_spawn_enemy(DASHER_SCENE, Vector2(680, 200))
			_spawn_enemy(DASHER_SCENE, Vector2(680, 350))
			_spawn_enemy(CHASER_SCENE, Vector2(520, 276))
			_spawn_enemy(CHASER_SCENE, Vector2(760, 276))

		3:
			# Room 4: Chokepoint (Central divider, 2 Shooters, 2 Dashers)
			_add_obstacle(Vector2(480, 276), Vector2(280, 26))
			_spawn_enemy(SHOOTER_SCENE, Vector2(680, 180))
			_spawn_enemy(SHOOTER_SCENE, Vector2(680, 370))
			_spawn_enemy(DASHER_SCENE, Vector2(480, 140))
			_spawn_enemy(DASHER_SCENE, Vector2(480, 410))

		4:
			# Room 5: Overload Horde (Fortress blocks, mixed wave)
			_add_obstacle(Vector2(350, 190), Vector2(64, 28))
			_add_obstacle(Vector2(610, 190), Vector2(64, 28))
			_add_obstacle(Vector2(350, 360), Vector2(64, 28))
			_add_obstacle(Vector2(610, 360), Vector2(64, 28))
			_spawn_enemy(CHASER_SCENE, Vector2(740, 276))
			_spawn_enemy(CHASER_SCENE, Vector2(600, 276))
			_spawn_enemy(SHOOTER_SCENE, Vector2(760, 160))
			_spawn_enemy(SHOOTER_SCENE, Vector2(760, 390))
			_spawn_enemy(DASHER_SCENE, Vector2(480, 276))

		5:
			# Room 6: Boss Room (Corner cover blocks, NEXUS OVERLORD)
			_add_obstacle(Vector2(180, 150), Vector2(36, 36))
			_add_obstacle(Vector2(780, 150), Vector2(36, 36))
			_add_obstacle(Vector2(180, 400), Vector2(36, 36))
			_add_obstacle(Vector2(780, 400), Vector2(36, 36))

			var boss: Node2D = BOSS_SCENE.instantiate()
			boss.position = Vector2(680, 276)
			boss.target = player
			boss.connect("defeated", Callable(self, "_on_enemy_defeated").bind(boss))
			add_child(boss)
			active_enemies.append(boss)
			boss_ref = boss
			boss_active = true
			boss_bar_bg.visible = true

	queue_redraw()


func _spawn_enemy(packed_scene: PackedScene, pos: Vector2) -> void:
	if not is_instance_valid(player):
		return
	var enemy = packed_scene.instantiate()
	enemy.position = pos
	enemy.target = player
	enemy.connect("defeated", Callable(self, "_on_enemy_defeated").bind(enemy))
	add_child(enemy)
	active_enemies.append(enemy)


func _on_enemy_defeated(enemy_node: Node2D) -> void:
	if run_over:
		return
	active_enemies.erase(enemy_node)

	var rs = get_node_or_null("/root/RunState")
	if rs:
		rs.on_enemy_eliminated()

	# Check wave clearance
	if active_enemies.is_empty() and not room_cleared:
		room_cleared = true
		_on_room_cleared()


func _on_room_cleared() -> void:
	var rs = get_node("/root/RunState")
	# If this was the Boss room, victory!
	if rs.current_room_index >= rs.TOTAL_ROOMS - 1:
		_show_end_screen(true)
	else:
		_show_upgrade_draft()


func _show_upgrade_draft() -> void:
	if touch_controls:
		touch_controls.enabled = false
	var rs = get_node("/root/RunState")
	var choices: Array = rs.get_random_upgrade_choices(3)

	# Clean children of upgrade cards container
	for child in upgrade_cards_box.get_children():
		child.queue_free()

	for item in choices:
		var card := Button.new()
		card.custom_minimum_size = Vector2(230, 210)
		card.text = "\n[ %s ]\n\n%s\n\n\"%s\"" % [item.title, item.desc, item.flavor]
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.pressed.connect(_on_upgrade_selected.bind(item.id))
		upgrade_cards_box.add_child(card)

	upgrade_container.visible = true


func _on_upgrade_selected(upgrade_id: String) -> void:
	upgrade_container.visible = false
	if touch_controls:
		touch_controls.enabled = true
	var rs = get_node("/root/RunState")
	rs.apply_upgrade(upgrade_id)
	rs.advance_room()
	_load_room(rs.current_room_index)


func _on_player_died() -> void:
	run_over = true
	for enemy in active_enemies:
		if is_instance_valid(enemy):
			enemy.set_physics_process(false)
	_show_end_screen(false)


func _show_end_screen(won: bool) -> void:
	run_over = true
	if touch_controls:
		touch_controls.enabled = false
	var rs = get_node("/root/RunState")

	end_title.text = "CORE PURGED // RUN COMPLETE" if won else "SUBJECT TERMINATED"
	end_title.add_theme_color_override("font_color", Color("38bdf8") if won else Color("ff4d6d"))

	var minutes := int(rs.run_time / 60.0)
	var seconds := int(rs.run_time) % 60
	end_stats.text = "SECTORS CLEARED: %d / %d\nHOSTILES PURGED: %d\nSURVIVAL TIME: %02d:%02d\nUPGRADES INSTALLED: %d" % [
		rs.current_room_index + (1 if won else 0),
		rs.TOTAL_ROOMS,
		rs.score,
		minutes,
		seconds,
		rs.active_upgrade_ids.size()
	]

	end_button.text = "NEW RUN" if won else "RETRY RUN"
	end_panel.visible = true


func _restart_run() -> void:
	var rs = get_node_or_null("/root/RunState")
	if rs:
		rs.start_new_run()
	get_tree().reload_current_scene()


func _create_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)

	# Top Status Bar
	status_label = Label.new()
	status_label.position = Vector2(44, 18)
	status_label.add_theme_color_override("font_color", Color("e0f2fe"))
	status_label.add_theme_font_size_override("font_size", 20)
	ui_layer.add_child(status_label)

	sector_label = Label.new()
	sector_label.position = Vector2(770, 18)
	sector_label.add_theme_color_override("font_color", Color("38bdf8"))
	sector_label.add_theme_font_size_override("font_size", 20)
	ui_layer.add_child(sector_label)

	hint_label = Label.new()
	hint_label.position = Vector2(44, 42)
	hint_label.text = "WASD/Move   •   Aim + Fire   •   Shift/Space Dash (I-Frames)"
	hint_label.add_theme_color_override("font_color", Color("64748b"))
	hint_label.add_theme_font_size_override("font_size", 13)
	ui_layer.add_child(hint_label)

	# Boss Health Bar
	boss_bar_bg = ColorRect.new()
	boss_bar_bg.position = Vector2(310, 20)
	boss_bar_bg.size = Vector2(340, 16)
	boss_bar_bg.color = Color("271020")
	boss_bar_bg.visible = false
	ui_layer.add_child(boss_bar_bg)

	boss_bar_fill = ColorRect.new()
	boss_bar_fill.position = Vector2.ZERO
	boss_bar_fill.size = Vector2(340, 16)
	boss_bar_fill.color = Color("f43f5e")
	boss_bar_bg.add_child(boss_bar_fill)

	boss_label = Label.new()
	boss_label.text = "NEXUS // OVERLORD"
	boss_label.position = Vector2(0, -18)
	boss_label.add_theme_font_size_override("font_size", 12)
	boss_label.add_theme_color_override("font_color", Color("fda4af"))
	boss_bar_bg.add_child(boss_label)

	# Upgrade Selection Modal
	upgrade_container = PanelContainer.new()
	upgrade_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	upgrade_container.visible = false
	ui_layer.add_child(upgrade_container)

	var draft_bg := ColorRect.new()
	draft_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	draft_bg.color = Color(0.02, 0.04, 0.09, 0.88)
	upgrade_container.add_child(draft_bg)

	var draft_vbox := VBoxContainer.new()
	draft_vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	draft_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	draft_bg.add_child(draft_vbox)

	var draft_header := Label.new()
	draft_header.text = "SECTOR SECURED // SELECT RECONFIGURATION"
	draft_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	draft_header.add_theme_color_override("font_color", Color("38bdf8"))
	draft_header.add_theme_font_size_override("font_size", 22)
	draft_vbox.add_child(draft_header)

	var draft_sub := Label.new()
	draft_sub.text = "Upgrade subroutines to counter escalating threat level"
	draft_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	draft_sub.add_theme_color_override("font_color", Color("94a3b8"))
	draft_sub.add_theme_font_size_override("font_size", 14)
	draft_vbox.add_child(draft_sub)

	upgrade_cards_box = HBoxContainer.new()
	upgrade_cards_box.add_theme_constant_override("separation", 24)
	upgrade_cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	draft_vbox.add_child(upgrade_cards_box)

	# End of Run Modal (Victory / Defeat)
	end_panel = Control.new()
	end_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_panel.visible = false
	ui_layer.add_child(end_panel)

	var end_bg := ColorRect.new()
	end_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_bg.color = Color(0.01, 0.02, 0.05, 0.90)
	end_panel.add_child(end_bg)

	var end_vbox := VBoxContainer.new()
	end_vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	end_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	end_bg.add_child(end_vbox)

	end_title = Label.new()
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_title.add_theme_font_size_override("font_size", 30)
	end_vbox.add_child(end_title)

	end_stats = Label.new()
	end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_stats.add_theme_color_override("font_color", Color("cbd5e1"))
	end_stats.add_theme_font_size_override("font_size", 16)
	end_vbox.add_child(end_stats)

	end_button = Button.new()
	end_button.custom_minimum_size = Vector2(200, 48)
	end_button.pressed.connect(_restart_run)
	end_vbox.add_child(end_button)
