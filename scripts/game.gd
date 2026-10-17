extends Node2D
## Owns the roguelite game loop: hand-authored rooms, tech dungeon tile rendering,
## enemy waves, upgrade drafting, and run completion.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const CHASER_SCENE := preload("res://scenes/enemies/chaser.tscn")
const SHOOTER_SCENE := preload("res://scenes/enemies/shooter.tscn")
const DASHER_SCENE := preload("res://scenes/enemies/dasher.tscn")
const BOSS_SCENE := preload("res://scenes/enemies/boss.tscn")
const TOUCH_CONTROLS := preload("res://scripts/mobile_controls.gd")
const ASSET_LOADER := preload("res://scripts/asset_loader.gd")

const BEHAVIOR_TRACKER_SCRIPT := preload("res://scripts/behavior_tracker.gd")
const ADAPTIVE_DIRECTOR_SCRIPT := preload("res://scripts/adaptive_director.gd")
const DIRECTOR_TESTS_SCRIPT := preload("res://scripts/test_director.gd")

const ROOM_RECT := Rect2(42.0, 64.0, 876.0, 424.0)

# Custom tileset coordinates (32x32 tiles in assets/environment/tileset.png)
const FLOOR_TILE_BASE := Rect2(0, 0, 32, 32)
const FLOOR_TILE_CIRCUIT := Rect2(32, 0, 32, 32)
const FLOOR_TILE_VENT := Rect2(64, 0, 32, 32)
const FLOOR_TILE_HATCH := Rect2(96, 0, 32, 32)
const OBSTACLE_SERVER := Rect2(0, 64, 32, 32)
const OBSTACLE_GENERATOR := Rect2(32, 64, 32, 32)

var tileset_tex: Texture2D
var hearts_tex: Texture2D

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
var hearts_box: HBoxContainer
var full_heart_tex: AtlasTexture
var empty_heart_tex: AtlasTexture
var elims_label: Label
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

# Milestone 2: Adaptive Director & Behavior Tracker
var tracker: RefCounted
var director: RefCounted
var current_sector_tactic := "DEFAULT"
var damage_taken_this_sector := 0

var director_banner: PanelContainer
var banner_title: Label
var banner_sub: Label
var banner_timer := 0.0

var sector_tints: Array[Color] = [
	Color(0.88, 0.95, 1.0), # Sector 1: Cyan Calibration
	Color(1.0, 0.92, 0.82), # Sector 2: Industrial Amber
	Color(0.85, 1.0, 0.90), # Sector 3: Toxic Emerald
	Color(0.92, 0.85, 1.0), # Sector 4: Hyper Violet
	Color(1.0, 0.86, 0.78), # Sector 5: Overload Horde
	Color(1.0, 0.78, 0.82), # Sector 6: Nexus Core
]


func _ready() -> void:
	tileset_tex = ASSET_LOADER.load_texture("res://assets/environment/tileset.png")
	hearts_tex = ASSET_LOADER.load_texture("res://assets/ui/hearts.png")

	tracker = BEHAVIOR_TRACKER_SCRIPT.new()
	director = ADAPTIVE_DIRECTOR_SCRIPT.new()

	if OS.is_debug_build():
		DIRECTOR_TESTS_SCRIPT.run_all_tests()

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

	# Manage Director Banner timer
	if banner_timer > 0.0:
		banner_timer -= delta
		if banner_timer <= 0.0:
			director_banner.visible = false

	# Track player combat behavior for adaptive director
	if not get_tree().paused and is_instance_valid(player) and tracker:
		tracker.update(delta, player.global_position, player.velocity, active_enemies, player.is_firing, rs.run_time)

	# Update Top HUD Hearts & Badges
	if is_instance_valid(player):
		_update_hud_hearts()
		elims_label.text = "ELIMS  %02d" % rs.score
		sector_label.text = "SECTOR  %d / %d" % [rs.current_room_index + 1, rs.TOTAL_ROOMS]

	# Update Boss Bar if in Boss room
	if boss_active and is_instance_valid(boss_ref):
		var pct: float = float(boss_ref.health) / float(boss_ref.max_health)
		boss_bar_fill.size.x = 340.0 * pct
	elif boss_active and not is_instance_valid(boss_ref):
		boss_bar_bg.visible = false

	# Redraw arena for animated obstacle lights and effects
	queue_redraw()


func _update_hud_hearts() -> void:
	if not is_instance_valid(hearts_box) or not is_instance_valid(player):
		return

	while hearts_box.get_child_count() < player.max_health:
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(28, 28)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hearts_box.add_child(tr)

	while hearts_box.get_child_count() > player.max_health:
		var ch = hearts_box.get_child(hearts_box.get_child_count() - 1)
		hearts_box.remove_child(ch)
		ch.queue_free()

	for i in range(hearts_box.get_child_count()):
		var tr: TextureRect = hearts_box.get_child(i)
		tr.texture = full_heart_tex if i < player.health else empty_heart_tex


func _draw() -> void:
	var rs = get_node_or_null("/root/RunState")
	var sec_idx: int = rs.current_room_index if rs else 0
	var tint: Color = sector_tints[clampi(sec_idx, 0, sector_tints.size() - 1)]

	# 1. Custom Modular Floor Panels
	if tileset_tex:
		for x in range(int(ROOM_RECT.position.x), int(ROOM_RECT.end.x), 32):
			for y in range(int(ROOM_RECT.position.y), int(ROOM_RECT.end.y), 32):
				var w := minf(32.0, ROOM_RECT.end.x - float(x))
				var h := minf(32.0, ROOM_RECT.end.y - float(y))
				var dest := Rect2(float(x), float(y), w, h)

				var hash_val := ((x * 73856093) ^ (y * 19349663) ^ (sec_idx * 83492791)) % 100
				var src := FLOOR_TILE_BASE
				if hash_val < 10:
					src = FLOOR_TILE_VENT
				elif hash_val < 22:
					src = FLOOR_TILE_CIRCUIT
				elif hash_val < 30:
					src = FLOOR_TILE_HATCH

				draw_texture_rect_region(tileset_tex, dest, Rect2(src.position.x, src.position.y, w, h), tint)
	else:
		draw_rect(ROOM_RECT, Color("0b0f19"), true)

	# 2. Outer arena perimeter & neon hazard rails
	draw_rect(ROOM_RECT.grow(4.0), Color(0.01, 0.02, 0.04, 0.95), false, 4.0)
	draw_rect(ROOM_RECT, Color("38bdf8"), false, 2.5)
	draw_rect(ROOM_RECT.grow(-3.0), Color(0.05, 0.5, 0.9, 0.35), false, 1.5)

	# Corner indicator brackets
	var corners := [
		ROOM_RECT.position,
		Vector2(ROOM_RECT.end.x, ROOM_RECT.position.y),
		Vector2(ROOM_RECT.position.x, ROOM_RECT.end.y),
		ROOM_RECT.end
	]
	for c_pos in corners:
		draw_circle(c_pos, 4.0, Color("38bdf8"))
		draw_circle(c_pos, 2.0, Color("e0f2fe"))

	# 3. Hand-authored obstacles with server/terminal textures and telemetry LEDs
	var ticks := Time.get_ticks_msec()
	for r in obstacle_rects:
		draw_rect(Rect2(r.position.x + 3.0, r.position.y + 4.0, r.size.x, r.size.y), Color(0.0, 0.0, 0.0, 0.55), true)

		if tileset_tex:
			for ox in range(int(r.position.x), int(r.end.x), 32):
				for oy in range(int(r.position.y), int(r.end.y), 32):
					var ow := minf(32.0, r.end.x - float(ox))
					var oh := minf(32.0, r.end.y - float(oy))
					var obs_src := OBSTACLE_SERVER if (ox + oy) % 64 == 0 else OBSTACLE_GENERATOR
					draw_texture_rect_region(tileset_tex, Rect2(float(ox), float(oy), ow, oh), Rect2(obs_src.position.x, obs_src.position.y, ow, oh), Color(0.9, 0.95, 1.0))
		else:
			draw_rect(r, Color("1e293b"), true)

		draw_rect(r, Color("1e293b"), false, 2.0)
		draw_line(r.position, Vector2(r.end.x, r.position.y), Color("38bdf8"), 2.0)

		# Blinking telemetry status LEDs on terminal
		var blink_g := (ticks / 350) % 2 == 0
		var blink_r := (ticks / 550) % 2 == 0
		draw_circle(r.position + Vector2(6, 6), 2.0, Color("22c55e") if blink_g else Color("14532d"))
		draw_circle(r.position + Vector2(13, 6), 2.0, Color("ef4444") if blink_r else Color("7f1d1d"))


func _create_walls() -> void:
	var center_x := ROOM_RECT.position.x + ROOM_RECT.size.x * 0.5
	var center_y := ROOM_RECT.position.y + ROOM_RECT.size.y * 0.5

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
	player.connect("dashed", Callable(self, "_on_player_dashed"))
	player.connect("damaged", Callable(self, "_on_player_damaged"))
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


func _on_player_dashed() -> void:
	if tracker:
		var rs = get_node_or_null("/root/RunState")
		var t: float = rs.run_time if rs else 0.0
		tracker.record_dash(t)


func _on_player_damaged(amount: int) -> void:
	damage_taken_this_sector += amount
	if tracker:
		var rs = get_node_or_null("/root/RunState")
		var t: float = rs.run_time if rs else 0.0
		tracker.record_damage_taken(amount, t)


func _load_room(index: int) -> void:
	room_cleared = false
	boss_active = false
	boss_ref = null
	boss_bar_bg.visible = false

	for obs in active_obstacles:
		if is_instance_valid(obs):
			obs.queue_free()
	active_obstacles.clear()
	obstacle_rects.clear()

	for child in get_children():
		if child.is_in_group("projectiles") or child.has_method("_on_body_entered"):
			child.queue_free()

	if is_instance_valid(player):
		player.position = Vector2(ROOM_RECT.position.x + 120.0, ROOM_RECT.get_center().y)

	active_enemies.clear()

	var speed_mult := 1.0
	var telegraph_mult := 1.0

	if index > 0 and tracker and director:
		director.record_tactic_result(current_sector_tactic, damage_taken_this_sector)
		var decision: Dictionary = director.evaluate_sector_tactics(
			tracker.get_profile(),
			index,
			player.health,
			player.max_health
		)
		current_sector_tactic = decision.tactic
		speed_mult = decision.enemy_speed_mult
		telegraph_mult = decision.enemy_telegraph_mult
		_show_director_banner(decision.banner_title, decision.banner_sub)

		if decision.extra_dashers > 0:
			_spawn_enemy(DASHER_SCENE, Vector2(620, 150), speed_mult, telegraph_mult)
		if decision.extra_shooters > 0:
			_spawn_enemy(SHOOTER_SCENE, Vector2(760, 276), speed_mult, telegraph_mult)
		if decision.extra_chasers > 0:
			_spawn_enemy(CHASER_SCENE, Vector2(480, 276), speed_mult, telegraph_mult)

	damage_taken_this_sector = 0

	match index:
		0:
			# Room 1: Calibration (Open room, 3 Chasers)
			_spawn_enemy(CHASER_SCENE, Vector2(620, 200), speed_mult, telegraph_mult)
			_spawn_enemy(CHASER_SCENE, Vector2(740, 276), speed_mult, telegraph_mult)
			_spawn_enemy(CHASER_SCENE, Vector2(620, 360), speed_mult, telegraph_mult)

		1:
			# Room 2: Firing Line (2 Cover barriers, 2 Chasers, 1 Shooter)
			_add_obstacle(Vector2(380, 276), Vector2(24, 150))
			_add_obstacle(Vector2(620, 276), Vector2(24, 150))
			_spawn_enemy(SHOOTER_SCENE, Vector2(740, 276), speed_mult, telegraph_mult)
			_spawn_enemy(CHASER_SCENE, Vector2(520, 180), speed_mult, telegraph_mult)
			_spawn_enemy(CHASER_SCENE, Vector2(520, 370), speed_mult, telegraph_mult)

		2:
			# Room 3: Vector Ambush (4 Pillar obstacles, 2 Dashers, 2 Chasers)
			_add_obstacle(Vector2(320, 180), Vector2(40, 40))
			_add_obstacle(Vector2(640, 180), Vector2(40, 40))
			_add_obstacle(Vector2(320, 370), Vector2(40, 40))
			_add_obstacle(Vector2(640, 370), Vector2(40, 40))
			_spawn_enemy(DASHER_SCENE, Vector2(680, 200), speed_mult, telegraph_mult)
			_spawn_enemy(DASHER_SCENE, Vector2(680, 350), speed_mult, telegraph_mult)
			_spawn_enemy(CHASER_SCENE, Vector2(520, 276), speed_mult, telegraph_mult)
			_spawn_enemy(CHASER_SCENE, Vector2(760, 276), speed_mult, telegraph_mult)

		3:
			# Room 4: Chokepoint (Central divider, 2 Shooters, 2 Dashers)
			_add_obstacle(Vector2(480, 276), Vector2(280, 26))
			_spawn_enemy(SHOOTER_SCENE, Vector2(680, 180), speed_mult, telegraph_mult)
			_spawn_enemy(SHOOTER_SCENE, Vector2(680, 370), speed_mult, telegraph_mult)
			_spawn_enemy(DASHER_SCENE, Vector2(480, 140), speed_mult, telegraph_mult)
			_spawn_enemy(DASHER_SCENE, Vector2(480, 410), speed_mult, telegraph_mult)

		4:
			# Room 5: Overload Horde (Fortress blocks, mixed wave)
			_add_obstacle(Vector2(350, 190), Vector2(64, 28))
			_add_obstacle(Vector2(610, 190), Vector2(64, 28))
			_add_obstacle(Vector2(350, 360), Vector2(64, 28))
			_add_obstacle(Vector2(610, 360), Vector2(64, 28))
			_spawn_enemy(CHASER_SCENE, Vector2(740, 276), speed_mult, telegraph_mult)
			_spawn_enemy(CHASER_SCENE, Vector2(600, 276), speed_mult, telegraph_mult)
			_spawn_enemy(SHOOTER_SCENE, Vector2(760, 160), speed_mult, telegraph_mult)
			_spawn_enemy(SHOOTER_SCENE, Vector2(760, 390), speed_mult, telegraph_mult)
			_spawn_enemy(DASHER_SCENE, Vector2(480, 276), speed_mult, telegraph_mult)

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


func _spawn_enemy(packed_scene: PackedScene, pos: Vector2, speed_mult: float = 1.0, telegraph_mult: float = 1.0) -> Node2D:
	if not is_instance_valid(player):
		return null
	var enemy: Node2D = packed_scene.instantiate()
	enemy.position = pos
	if "target" in enemy:
		enemy.target = player
	if "move_speed" in enemy:
		enemy.move_speed *= speed_mult
	if "patrol_speed" in enemy:
		enemy.patrol_speed *= speed_mult
	if "lunge_speed" in enemy:
		enemy.lunge_speed *= speed_mult
	if "state_timer" in enemy:
		enemy.state_timer *= telegraph_mult
	enemy.connect("defeated", Callable(self, "_on_enemy_defeated").bind(enemy))
	add_child(enemy)
	active_enemies.append(enemy)
	return enemy


func _on_enemy_defeated(enemy_node: Node2D) -> void:
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

	# Full and Empty Heart textures from assets/ui/hearts.png
	if hearts_tex:
		full_heart_tex = AtlasTexture.new()
		full_heart_tex.atlas = hearts_tex
		full_heart_tex.region = Rect2(0, 0, 32, 32)

		empty_heart_tex = AtlasTexture.new()
		empty_heart_tex.atlas = hearts_tex
		empty_heart_tex.region = Rect2(32, 0, 32, 32)

	# Top Status Bar Container
	var top_bar := HBoxContainer.new()
	top_bar.position = Vector2(44, 16)
	top_bar.add_theme_constant_override("separation", 24)
	ui_layer.add_child(top_bar)

	# Heart Icons Container
	hearts_box = HBoxContainer.new()
	hearts_box.add_theme_constant_override("separation", 4)
	top_bar.add_child(hearts_box)

	# Elims Counter Badge
	elims_label = Label.new()
	elims_label.text = "ELIMS  00"
	elims_label.add_theme_color_override("font_color", Color("38bdf8"))
	elims_label.add_theme_font_size_override("font_size", 16)
	top_bar.add_child(elims_label)

	# Sector Badge (Top Right)
	sector_label = Label.new()
	sector_label.position = Vector2(760, 16)
	sector_label.text = "SECTOR  1 / 6"
	sector_label.add_theme_color_override("font_color", Color("38bdf8"))
	sector_label.add_theme_font_size_override("font_size", 16)
	ui_layer.add_child(sector_label)

	hint_label = Label.new()
	hint_label.position = Vector2(44, 44)
	hint_label.text = "WASD/Move   •   Aim + Fire   •   Shift/Space Dash (I-Frames)"
	hint_label.add_theme_color_override("font_color", Color("64748b"))
	hint_label.add_theme_font_size_override("font_size", 12)
	ui_layer.add_child(hint_label)

	# Boss Health Bar
	boss_bar_bg = ColorRect.new()
	boss_bar_bg.position = Vector2(310, 18)
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

	# Adaptive Director Notification Banner
	director_banner = PanelContainer.new()
	director_banner.position = Vector2(180, 68)
	director_banner.custom_minimum_size = Vector2(600, 44)
	director_banner.visible = false
	ui_layer.add_child(director_banner)

	var banner_box := VBoxContainer.new()
	banner_box.alignment = BoxContainer.ALIGNMENT_CENTER
	director_banner.add_child(banner_box)

	banner_title = Label.new()
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_title.add_theme_color_override("font_color", Color("38bdf8"))
	banner_title.add_theme_font_size_override("font_size", 13)
	banner_box.add_child(banner_title)

	banner_sub = Label.new()
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_sub.add_theme_color_override("font_color", Color("94a3b8"))
	banner_sub.add_theme_font_size_override("font_size", 11)
	banner_box.add_child(banner_sub)

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


func _show_director_banner(title: String, sub: String) -> void:
	if not is_instance_valid(director_banner):
		return
	banner_title.text = title
	banner_sub.text = sub
	director_banner.visible = true
	banner_timer = 4.0
