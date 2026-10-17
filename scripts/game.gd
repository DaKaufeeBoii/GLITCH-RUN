extends Node3D
## Top-Down 3D Dungeon Roguelite Game Manager using KayKit 3D Dungeon assets.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const CHASER_SCENE := preload("res://scenes/enemies/chaser.tscn")
const SHOOTER_SCENE := preload("res://scenes/enemies/shooter.tscn")
const DASHER_SCENE := preload("res://scenes/enemies/dasher.tscn")
const BOSS_SCENE := preload("res://scenes/enemies/boss.tscn")
const TOUCH_CONTROLS := preload("res://scripts/mobile_controls.gd")

# KayKit 3D Dungeon Models
var MODEL_FLOOR: PackedScene
var MODEL_WALL: PackedScene
var MODEL_PILLAR: PackedScene
var MODEL_CRATES: PackedScene
var MODEL_BARREL: PackedScene
var MODEL_CHEST: PackedScene

var camera: Camera3D
var sun: DirectionalLight3D
var player: CharacterBody3D
var active_enemies: Array[Node3D] = []
var active_obstacles: Array[Node3D] = []

var room_cleared := false
var run_over := false
var boss_active := false
var boss_ref: Node3D = null

# UI Elements
var ui_layer: CanvasLayer
var status_label: Label
var hint_label: Label
var sector_label: Label
var boss_bar_bg: ColorRect
var boss_bar_fill: ColorRect
var boss_label: Label

var upgrade_container: Control
var upgrade_cards_box: HBoxContainer

var end_panel: Control
var end_title: Label
var end_stats: Label
var end_button: Button
var touch_controls: Control = null


func _ready() -> void:
	if not Engine.has_singleton("RunState") and get_node_or_null("/root/RunState") == null:
		push_error("RunState singleton not found!")
	var rs = get_node("/root/RunState")
	rs.start_new_run()

	MODEL_FLOOR = load("res://assets/dungeon/floor_tile_large.gltf")
	MODEL_WALL = load("res://assets/dungeon/wall.gltf")
	MODEL_PILLAR = load("res://assets/dungeon/pillar.gltf")
	MODEL_CRATES = load("res://assets/dungeon/crates_stacked.gltf")
	MODEL_BARREL = load("res://assets/dungeon/barrel_large.gltf")
	MODEL_CHEST = load("res://assets/dungeon/chest.gltf")

	_setup_3d_environment()
	_create_dungeon_room()
	_create_ui()
	_create_player()
	_load_room(rs.current_room_index)


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


func _setup_3d_environment() -> void:
	# Camera3D with high-angle top-down perspective
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 22.0, 14.5)
	camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	camera.fov = 52.0
	camera.current = true
	add_child(camera)

	# Directional Sunlight with soft shadows
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, 35, 0)
	sun.light_color = Color("fff1d6")
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)

	# Ambient World Environment
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("090d16")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("232b3e")
	environment.ambient_light_energy = 0.85
	environment.glow_enabled = true
	environment.glow_intensity = 0.8
	environment.glow_strength = 1.1
	env.environment = environment
	add_child(env)


func _create_dungeon_room() -> void:
	# 7 x 5 KayKit floor tiles (each tile is 4m x 4m -> 28m x 20m arena)
	var floor_parent := Node3D.new()
	floor_parent.name = "DungeonFloor"
	add_child(floor_parent)

	for col in range(-3, 4):
		for row in range(-2, 3):
			var tile: Node3D = MODEL_FLOOR.instantiate()
			tile.position = Vector3(col * 4.0, 0.0, row * 4.0)
			floor_parent.add_child(tile)

	# Perimeter Walls
	var walls_parent := Node3D.new()
	walls_parent.name = "DungeonWalls"
	add_child(walls_parent)

	# North Wall (Z = -10.0) & South Wall (Z = 10.0)
	for col in range(-3, 4):
		var wall_n: Node3D = MODEL_WALL.instantiate()
		wall_n.position = Vector3(col * 4.0, 0.0, -10.0)
		walls_parent.add_child(wall_n)

		var wall_s: Node3D = MODEL_WALL.instantiate()
		wall_s.position = Vector3(col * 4.0, 0.0, 10.0)
		wall_s.rotation.y = PI
		walls_parent.add_child(wall_s)

	# West Wall (X = -14.0) & East Wall (X = 14.0)
	for row in range(-2, 3):
		var wall_w: Node3D = MODEL_WALL.instantiate()
		wall_w.position = Vector3(-14.0, 0.0, row * 4.0)
		wall_w.rotation.y = PI * 0.5
		walls_parent.add_child(wall_w)

		var wall_e: Node3D = MODEL_WALL.instantiate()
		wall_e.position = Vector3(14.0, 0.0, row * 4.0)
		wall_e.rotation.y = -PI * 0.5
		walls_parent.add_child(wall_e)

	# 3D Wall Colliders (StaticBody3D)
	_add_wall_collider(Vector3(0.0, 2.0, -10.5), Vector3(28.0, 4.0, 1.5))
	_add_wall_collider(Vector3(0.0, 2.0, 10.5), Vector3(28.0, 4.0, 1.5))
	_add_wall_collider(Vector3(-14.5, 2.0, 0.0), Vector3(1.5, 4.0, 20.0))
	_add_wall_collider(Vector3(14.5, 2.0, 0.0), Vector3(1.5, 4.0, 20.0))


func _add_wall_collider(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	add_child(body)


func _add_obstacle_prop(model_scene: PackedScene, pos: Vector3, rot_y: float, collider_size: Vector3) -> void:
	var prop: Node3D = model_scene.instantiate()
	prop.position = pos
	prop.rotation.y = rot_y
	add_child(prop)
	active_obstacles.append(prop)

	# StaticBody3D collision box
	var body := StaticBody3D.new()
	body.position = pos + Vector3(0.0, collider_size.y * 0.5, 0.0)
	body.collision_layer = 1
	body.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = collider_size
	shape_node.shape = shape
	body.add_child(shape_node)
	add_child(body)
	active_obstacles.append(body)


func _create_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.position = Vector3(-8.0, 0.0, 0.0)
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
	ui_layer.move_child(touch_controls, 0)


func _load_room(index: int) -> void:
	room_cleared = false
	boss_active = false
	boss_ref = null
	boss_bar_bg.visible = false

	# Clear previous obstacles and temporary objects
	for obs in active_obstacles:
		if is_instance_valid(obs):
			obs.queue_free()
	active_obstacles.clear()

	# Clear lingering projectiles
	for child in get_children():
		if child.has_method("_on_body_entered"):
			child.queue_free()

	# Reset player position
	if is_instance_valid(player):
		player.position = Vector3(-8.0, 0.0, 0.0)
		player.velocity = Vector3.ZERO

	active_enemies.clear()

	match index:
		0:
			# Sector 1: Calibration (Open Hall, 3 Chasers)
			_spawn_enemy(CHASER_SCENE, Vector3(5.0, 0.0, -3.5))
			_spawn_enemy(CHASER_SCENE, Vector3(8.0, 0.0, 0.0))
			_spawn_enemy(CHASER_SCENE, Vector3(5.0, 0.0, 3.5))

		1:
			# Sector 2: Firing Line (2 Stone pillars with crates for cover, 2 Chasers, 1 Shooter)
			_add_obstacle_prop(MODEL_PILLAR, Vector3(-3.0, 0.0, 0.0), 0.0, Vector3(1.5, 4.0, 1.5))
			_add_obstacle_prop(MODEL_PILLAR, Vector3(3.0, 0.0, 0.0), 0.0, Vector3(1.5, 4.0, 1.5))
			_add_obstacle_prop(MODEL_CRATES, Vector3(-3.0, 0.0, -1.8), 0.3, Vector3(1.8, 1.5, 1.8))
			_add_obstacle_prop(MODEL_CRATES, Vector3(3.0, 0.0, 1.8), -0.4, Vector3(1.8, 1.5, 1.8))
			_spawn_enemy(SHOOTER_SCENE, Vector3(8.0, 0.0, 0.0))
			_spawn_enemy(CHASER_SCENE, Vector3(4.0, 0.0, -4.0))
			_spawn_enemy(CHASER_SCENE, Vector3(4.0, 0.0, 4.0))

		2:
			# Sector 3: Vector Ambush (4-pillar cross grid, 2 Dashers, 2 Chasers)
			_add_obstacle_prop(MODEL_PILLAR, Vector3(-4.0, 0.0, -4.0), 0.0, Vector3(1.5, 4.0, 1.5))
			_add_obstacle_prop(MODEL_PILLAR, Vector3(4.0, 0.0, -4.0), 0.0, Vector3(1.5, 4.0, 1.5))
			_add_obstacle_prop(MODEL_PILLAR, Vector3(-4.0, 0.0, 4.0), 0.0, Vector3(1.5, 4.0, 1.5))
			_add_obstacle_prop(MODEL_PILLAR, Vector3(4.0, 0.0, 4.0), 0.0, Vector3(1.5, 4.0, 1.5))
			_spawn_enemy(DASHER_SCENE, Vector3(7.0, 0.0, -3.0))
			_spawn_enemy(DASHER_SCENE, Vector3(7.0, 0.0, 3.0))
			_spawn_enemy(CHASER_SCENE, Vector3(3.0, 0.0, 0.0))
			_spawn_enemy(CHASER_SCENE, Vector3(8.5, 0.0, 0.0))

		3:
			# Sector 4: Chokepoint (Central wall divider creating top/bottom lanes, 2 Shooters, 2 Dashers)
			_add_obstacle_prop(MODEL_WALL, Vector3(-2.0, 0.0, 0.0), 0.0, Vector3(4.0, 4.0, 1.2))
			_add_obstacle_prop(MODEL_WALL, Vector3(2.0, 0.0, 0.0), 0.0, Vector3(4.0, 4.0, 1.2))
			_spawn_enemy(SHOOTER_SCENE, Vector3(8.0, 0.0, -4.5))
			_spawn_enemy(SHOOTER_SCENE, Vector3(8.0, 0.0, 4.5))
			_spawn_enemy(DASHER_SCENE, Vector3(1.0, 0.0, -5.0))
			_spawn_enemy(DASHER_SCENE, Vector3(1.0, 0.0, 5.0))

		4:
			# Sector 5: Overload Horde (Fortress barricades, mixed horde)
			_add_obstacle_prop(MODEL_PILLAR, Vector3(-4.0, 0.0, -2.5), 0.0, Vector3(1.5, 4.0, 1.5))
			_add_obstacle_prop(MODEL_BARREL, Vector3(-3.0, 0.0, -2.5), 0.0, Vector3(1.2, 1.4, 1.2))
			_add_obstacle_prop(MODEL_PILLAR, Vector3(4.0, 0.0, 2.5), 0.0, Vector3(1.5, 4.0, 1.5))
			_add_obstacle_prop(MODEL_CRATES, Vector3(3.0, 0.0, 2.5), 0.2, Vector3(1.6, 1.4, 1.6))
			_spawn_enemy(CHASER_SCENE, Vector3(8.0, 0.0, 0.0))
			_spawn_enemy(CHASER_SCENE, Vector3(5.0, 0.0, 0.0))
			_spawn_enemy(SHOOTER_SCENE, Vector3(9.0, 0.0, -5.0))
			_spawn_enemy(SHOOTER_SCENE, Vector3(9.0, 0.0, 5.0))
			_spawn_enemy(DASHER_SCENE, Vector3(3.0, 0.0, 0.0))

		5:
			# Sector 6: Core Chamber (Boss Room with 4 corner pillars for cover, NEXUS OVERLORD)
			_add_obstacle_prop(MODEL_PILLAR, Vector3(-9.0, 0.0, -6.0), 0.0, Vector3(1.5, 4.0, 1.5))
			_add_obstacle_prop(MODEL_PILLAR, Vector3(9.0, 0.0, -6.0), 0.0, Vector3(1.5, 4.0, 1.5))
			_add_obstacle_prop(MODEL_PILLAR, Vector3(-9.0, 0.0, 6.0), 0.0, Vector3(1.5, 4.0, 1.5))
			_add_obstacle_prop(MODEL_PILLAR, Vector3(9.0, 0.0, 6.0), 0.0, Vector3(1.5, 4.0, 1.5))
			_add_obstacle_prop(MODEL_CHEST, Vector3(11.0, 0.0, 0.0), -PI * 0.5, Vector3(1.2, 1.0, 1.2))

			var boss: Node3D = BOSS_SCENE.instantiate()
			boss.position = Vector3(6.5, 0.0, 0.0)
			boss.target = player
			boss.connect("defeated", Callable(self, "_on_enemy_defeated").bind(boss))
			add_child(boss)
			active_enemies.append(boss)
			boss_ref = boss
			boss_active = true
			boss_bar_bg.visible = true


func _spawn_enemy(packed_scene: PackedScene, pos: Vector3) -> void:
	if not is_instance_valid(player):
		return
	var enemy = packed_scene.instantiate()
	enemy.position = pos
	enemy.target = player
	enemy.connect("defeated", Callable(self, "_on_enemy_defeated").bind(enemy))
	add_child(enemy)
	active_enemies.append(enemy)


func _on_enemy_defeated(enemy_node: Node3D) -> void:
	if run_over:
		return
	active_enemies.erase(enemy_node)

	var rs = get_node_or_null("/root/RunState")
	if rs:
		rs.on_enemy_eliminated()

	if active_enemies.is_empty() and not room_cleared:
		room_cleared = true
		_on_room_cleared()


func _on_room_cleared() -> void:
	var rs = get_node("/root/RunState")
	if rs.current_room_index >= rs.TOTAL_ROOMS - 1:
		_show_end_screen(true)
	else:
		_show_upgrade_draft()


func _show_upgrade_draft() -> void:
	if touch_controls:
		touch_controls.enabled = false
	get_tree().paused = true
	var rs = get_node("/root/RunState")
	var choices: Array = rs.get_random_upgrade_choices(3)

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
	get_tree().paused = false
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
	get_tree().paused = true
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
	get_tree().paused = false
	var rs = get_node_or_null("/root/RunState")
	if rs:
		rs.start_new_run()
	get_tree().reload_current_scene()


func _create_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
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
	upgrade_container = Control.new()
	upgrade_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	upgrade_container.visible = false
	ui_layer.add_child(upgrade_container)

	var draft_bg := ColorRect.new()
	draft_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	draft_bg.color = Color(0.02, 0.04, 0.09, 0.88)
	upgrade_container.add_child(draft_bg)

	var draft_center := CenterContainer.new()
	draft_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	upgrade_container.add_child(draft_center)

	var draft_vbox := VBoxContainer.new()
	draft_vbox.add_theme_constant_override("separation", 20)
	draft_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	draft_center.add_child(draft_vbox)

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

	var end_center := CenterContainer.new()
	end_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_panel.add_child(end_center)

	var end_vbox := VBoxContainer.new()
	end_vbox.add_theme_constant_override("separation", 16)
	end_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	end_center.add_child(end_vbox)

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
