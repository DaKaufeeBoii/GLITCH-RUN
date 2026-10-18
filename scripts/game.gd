extends Node2D
## Owns the roguelite game loop: procedural rooms, tech dungeon tile rendering,
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
const DUNGEON_GEN_SCRIPT := preload("res://scripts/dungeon_generator.gd")
const ENCOUNTER_DIR_SCRIPT := preload("res://scripts/encounter_director.gd")
const ENEMY_GENOME_SCRIPT := preload("res://scripts/enemy_genome.gd")
const DIRECTOR_TESTS_SCRIPT := preload("res://scripts/test_director.gd")
const DEBRIS_EMITTER_SCRIPT := preload("res://scripts/debris_emitter.gd")
const PAUSE_MENU_SCRIPT := preload("res://scripts/pause_menu.gd")
const DEBRIEF_TERMINAL_SCRIPT := preload("res://scripts/debrief_terminal.gd")
const SPATIAL_INDEX_SCRIPT := preload("res://scripts/spatial_index.gd")
const SQUAD_COORDINATOR_SCRIPT := preload("res://scripts/squad_coordinator.gd")
const BOSS_DIRECTOR_SCRIPT := preload("res://scripts/boss_director.gd")
const BOSS_DEFINITION_SCRIPT := preload("res://scripts/boss_definition.gd")

const ROOM_RECT := Rect2(42.0, 64.0, 1600.0, 900.0)

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
var boss_director: RefCounted = null
var current_boss_def: RefCounted = null
var current_boss_mutations: Array[Dictionary] = []

# Screen Trauma & Glitch Post-Processing
var camera: Camera2D
var trauma := 0.0
const TRAUMA_DECAY := 1.4
const MAX_OFFSET := Vector2(16.0, 10.0)
const MAX_ROLL := 0.04

var glitch_layer: CanvasLayer
var glitch_rect: ColorRect
var glitch_material: ShaderMaterial
var glitch_pulse := 0.0

# UI Elements
var ui_layer: CanvasLayer
var hearts_box: HBoxContainer
var full_heart_tex: AtlasTexture
var empty_heart_tex: AtlasTexture
var elims_label: Label
var hint_label: Label
var sector_label: Label
var ammo_label: Label

var boss_bar_container: PanelContainer
var boss_bar_bg: ColorRect
var boss_bar_ghost: ColorRect
var boss_bar_fill: ColorRect
var boss_label: Label
var boss_hp_label: Label

var upgrade_container: Control
var upgrade_cards_box: HBoxContainer

var doors_unlocked := false

var pause_menu: Control
var debrief_terminal: Control

# Priority 1 & 2: Procedural Generator, Evolved AI & Encounter Director
var tracker: RefCounted
var director: RefCounted
var dungeon_generator: RefCounted
var dungeon_layout: RefCounted
var encounter_director: RefCounted
var spatial_index: RefCounted
var squad_coordinator: RefCounted
var current_room_data: RefCounted
var current_sector_tactic := "DEFAULT"
var damage_taken_this_sector := 0
var sector_combat_time := 0.0

var debug_overlay: PanelContainer
var debug_content: Label
var debug_visible := false

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
	dungeon_generator = DUNGEON_GEN_SCRIPT.new()
	encounter_director = ENCOUNTER_DIR_SCRIPT.new()
	spatial_index = SPATIAL_INDEX_SCRIPT.new()
	squad_coordinator = SQUAD_COORDINATOR_SCRIPT.new()
	boss_director = BOSS_DIRECTOR_SCRIPT.new()

	if OS.get_cmdline_user_args().has("--run-tests") or OS.get_cmdline_args().has("--run-tests"):
		DIRECTOR_TESTS_SCRIPT.run_all_tests()

	if not Engine.has_singleton("RunState") and get_node_or_null("/root/RunState") == null:
		push_error("RunState singleton not found!")
	var rs = get_node("/root/RunState")
	rs.start_new_run()
	get_tree().paused = false
	run_over = false
	room_cleared = false

	# Generate deterministic procedural dungeon layout from run seed
	dungeon_layout = dungeon_generator.generate_dungeon(rs.current_seed, rs.TOTAL_ROOMS, rs.progression.sector_total_waves)
	rs.dungeon_layout_summary.clear()
	for r in dungeon_layout.rooms:
		rs.record_room_summary(r.to_dict())

	# Initialize Camera2D for trauma screen shake
	camera = Camera2D.new()
	camera.position = Vector2(480, 270)
	add_child(camera)
	camera.make_current()

	# Initialize Glitch Post-Processing Layer
	_init_glitch_layer()

	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play_music("theme_loop")

	_create_ui()
	_create_walls()
	_create_player()
	_load_room(rs.current_room_index)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if not run_over and is_instance_valid(pause_menu) and not pause_menu.visible:
			if is_instance_valid(upgrade_container) and not upgrade_container.visible:
				pause_menu.open_pause()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if not run_over and is_instance_valid(upgrade_container) and not upgrade_container.visible:
			if is_instance_valid(pause_menu):
				if pause_menu.visible:
					pause_menu._handle_back_request()
				else:
					pause_menu.open_pause()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		toggle_debug_overlay()
		return

	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or event.keycode == KEY_P or event.keycode == KEY_BACK)):
		if not run_over and is_instance_valid(upgrade_container) and not upgrade_container.visible:
			if is_instance_valid(pause_menu):
				if pause_menu.visible:
					pause_menu._handle_back_request()
				else:
					pause_menu.open_pause()


func add_trauma(amount: float) -> void:
	var sm = get_node_or_null("/root/Settings")
	if sm and not sm.screen_shake_enabled:
		trauma = 0.0
		return
	var intensity: float = sm.screen_shake_intensity if sm else 1.0
	trauma = clampf(trauma + amount * intensity, 0.0, 1.0)


func trigger_glitch(intensity: float = 0.75) -> void:
	glitch_pulse = intensity
	if is_instance_valid(glitch_material):
		glitch_material.set_shader_parameter("glitch_intensity", glitch_pulse)


func _init_glitch_layer() -> void:
	glitch_layer = CanvasLayer.new()
	glitch_layer.layer = 1
	glitch_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(glitch_layer)

	glitch_rect = ColorRect.new()
	glitch_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glitch_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader = load("res://shaders/glitch.gdshader")
	if shader:
		glitch_material = ShaderMaterial.new()
		glitch_material.shader = shader
		glitch_rect.material = glitch_material
	glitch_layer.add_child(glitch_rect)


func _process(delta: float) -> void:
	var rs = get_node_or_null("/root/RunState")
	if not rs or run_over:
		return

	rs.run_time += delta
	if not get_tree().paused and not active_enemies.is_empty():
		sector_combat_time += delta

	# Screen Trauma Shake Update
	if trauma > 0.0 and is_instance_valid(camera):
		trauma = maxf(0.0, trauma - TRAUMA_DECAY * delta)
		var shake := trauma * trauma
		camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * MAX_OFFSET * shake
		camera.rotation = randf_range(-1.0, 1.0) * MAX_ROLL * shake
	elif is_instance_valid(camera):
		camera.offset = Vector2.ZERO
		camera.rotation = 0.0

	# Glitch Post-Processing Decay
	if glitch_pulse > 0.0:
		glitch_pulse = maxf(0.0, glitch_pulse - delta * 2.8)
		if is_instance_valid(glitch_material):
			glitch_material.set_shader_parameter("glitch_intensity", glitch_pulse)

	# Manage Director Banner timer
	if banner_timer > 0.0:
		banner_timer -= delta
		if banner_timer <= 0.0:
			director_banner.visible = false

	# Track player combat behavior for adaptive director
	if not get_tree().paused and is_instance_valid(player) and tracker:
		tracker.update(delta, player.global_position, player.velocity, active_enemies, player.is_firing, rs.run_time)
	if is_instance_valid(camera) and is_instance_valid(player):
		camera.position = player.position

	# Update spatial index and squad coordinator
	if spatial_index:
		spatial_index.update_cache()
	if squad_coordinator and rs:
		var cur_depth: int = rs.progression.run_depth if rs.progression else 1
		var cur_hp: int = player.health if is_instance_valid(player) else 5
		squad_coordinator.configure_for_depth(cur_depth, cur_hp)

	# Update Top HUD Hearts & Badges
	if is_instance_valid(player):
		_update_hud_hearts()
		elims_label.text = "ELIMS  %02d" % rs.score
		var sec_w: int = rs.progression.sector_waves_completed if (rs and rs.progression) else 0
		var sec_tw: int = rs.progression.sector_total_waves if (rs and rs.progression) else 3
		var total_r: int = rs.progression.rooms_per_sector if (rs and rs.progression) else rs.TOTAL_ROOMS
		var active_wave: int = mini(sec_w + 1, sec_tw)
		sector_label.text = "SEC %d  •  RM %d/%d  •  WAVE %d/%d" % [rs.current_sector, rs.current_room_index + 1, total_r, active_wave, sec_tw]

	# Update Boss Bar if in Boss room
	if boss_active and is_instance_valid(boss_ref):
		var pct: float = clampf(float(boss_ref.health) / float(maxi(1, boss_ref.max_health)), 0.0, 1.0)
		boss_bar_fill.size.x = 420.0 * pct
		if is_instance_valid(boss_bar_ghost):
			boss_bar_ghost.size.x = move_toward(boss_bar_ghost.size.x, boss_bar_fill.size.x, delta * 140.0)
		if is_instance_valid(boss_hp_label):
			boss_hp_label.text = "%d / %d HP" % [boss_ref.health, boss_ref.max_health]
	elif boss_active and not is_instance_valid(boss_ref):
		if is_instance_valid(boss_bar_container):
			boss_bar_container.visible = false
		boss_bar_bg.visible = false

	# Check Player Proximity to Unlocked Exit Doors
	if doors_unlocked and not run_over and is_instance_valid(player) and current_room_data:
		for door in current_room_data.exit_doors:
			if player.position.distance_to(door.pos) < 55.0:
				_enter_door(door)
				break

	# Redraw arena for animated obstacle lights and effects
	queue_redraw()


func _update_hud_hearts() -> void:
	if not is_instance_valid(hearts_box) or not is_instance_valid(player):
		return

	while hearts_box.get_child_count() < player.max_health:
		var heart_rect := TextureRect.new()
		heart_rect.custom_minimum_size = Vector2(28, 28)
		heart_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		heart_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hearts_box.add_child(heart_rect)

	while hearts_box.get_child_count() > player.max_health:
		var ch = hearts_box.get_child(hearts_box.get_child_count() - 1)
		hearts_box.remove_child(ch)
		ch.queue_free()

	for i in range(hearts_box.get_child_count()):
		var heart_rect: TextureRect = hearts_box.get_child(i)
		if full_heart_tex and empty_heart_tex:
			heart_rect.texture = full_heart_tex if i < player.health else empty_heart_tex


func _draw() -> void:
	var rs = get_node_or_null("/root/RunState")
	var sec_idx: int = rs.current_room_index if rs else 0
	var tint: Color = sector_tints[clampi(sec_idx, 0, sector_tints.size() - 1)]

	# 1. Sleek Cyberpunk Floor & Geometric Grid
	draw_rect(ROOM_RECT, Color("080c16"), true)
	var grid_color := Color(0.12, 0.18, 0.28, 0.45) * tint
	grid_color.a = 0.35
	for x in range(int(ROOM_RECT.position.x), int(ROOM_RECT.end.x), 64):
		draw_line(Vector2(x, ROOM_RECT.position.y), Vector2(x, ROOM_RECT.end.y), grid_color, 1.0)
	for y in range(int(ROOM_RECT.position.y), int(ROOM_RECT.end.y), 64):
		draw_line(Vector2(ROOM_RECT.position.x, y), Vector2(ROOM_RECT.end.x, y), grid_color, 1.0)

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

	# 3. Hand-authored obstacles with slate body, cyan top trim, and telemetry LEDs
	var ticks := Time.get_ticks_msec()
	for r in obstacle_rects:
		draw_rect(Rect2(r.position.x + 3.0, r.position.y + 4.0, r.size.x, r.size.y), Color(0.0, 0.0, 0.0, 0.55), true)
		draw_rect(r, Color("1e293b"), true)
		draw_rect(r, Color("334155"), false, 1.5)
		draw_line(r.position, Vector2(r.end.x, r.position.y), Color("38bdf8"), 2.0)

		# Blinking telemetry status LEDs on terminal
		var blink_g := int(ticks / 350.0) % 2 == 0
		var blink_r := int(ticks / 550.0) % 2 == 0
		draw_circle(r.position + Vector2(6, 6), 2.0, Color("22c55e") if blink_g else Color("14532d"))
		draw_circle(r.position + Vector2(13, 6), 2.0, Color("ef4444") if blink_r else Color("7f1d1d"))

	# 4. Exit Doors & Holographic Route Signs
	if current_room_data and not current_room_data.exit_doors.is_empty():
		for door in current_room_data.exit_doors:
			var d_pos: Vector2 = door.pos
			var door_rect := Rect2(d_pos.x - 14.0, d_pos.y - 36.0, 28.0, 72.0)
			var ttype: String = door.get("target_type", "COMBAT")

			if not doors_unlocked:
				# Locked laser barrier with diagonal hazard warning stripes
				draw_rect(door_rect, Color(0.12, 0.04, 0.04, 0.85), true)
				draw_rect(door_rect, Color("ef4444"), false, 2.0)
				draw_line(door_rect.position, door_rect.end, Color(0.9, 0.2, 0.2, 0.6), 1.5)
				draw_line(Vector2(door_rect.end.x, door_rect.position.y), Vector2(door_rect.position.x, door_rect.end.y), Color(0.9, 0.2, 0.2, 0.6), 1.5)
				draw_circle(d_pos, 3.5, Color("ef4444"))
			else:
				# Unlocked pulsating cyber portal with route color cues
				var pulse := 0.75 + 0.25 * sin(float(ticks) * 0.006)
				var d_col := Color("38bdf8")
				if ttype == "RECOVERY":
					d_col = Color("22c55e")
				elif ttype == "ELITE":
					d_col = Color("f59e0b")
				elif ttype == "BOSS" or ttype == "NEXT_SECTOR":
					d_col = Color("ec4899")

				draw_rect(door_rect, Color(d_col.r * 0.15, d_col.g * 0.15, d_col.b * 0.15, 0.9), true)
				draw_rect(door_rect, Color(d_col.r, d_col.g, d_col.b, pulse), false, 2.5)
				draw_circle(d_pos, 10.0 * pulse, Color(d_col.r, d_col.g, d_col.b, 0.4 * pulse))
				draw_circle(d_pos, 4.0, Color("ffffff"))

				# Forward directional chevron
				draw_line(Vector2(d_pos.x - 6, d_pos.y - 10), Vector2(d_pos.x + 4, d_pos.y), Color(d_col.r, d_col.g, d_col.b, pulse), 2.0)
				draw_line(Vector2(d_pos.x + 4, d_pos.y), Vector2(d_pos.x - 6, d_pos.y + 10), Color(d_col.r, d_col.g, d_col.b, pulse), 2.0)

				# Holographic route badge on floor to left of door
				var tag_rect := Rect2(d_pos.x - 170.0, d_pos.y - 12.0, 150.0, 24.0)
				draw_rect(tag_rect, Color(0.02, 0.03, 0.06, 0.85), true)
				draw_rect(tag_rect, Color(d_col.r, d_col.g, d_col.b, 0.7), false, 1.0)
				var font := ThemeDB.fallback_font
				if font:
					var lbl_text: String = door.get("label", "FORWARD")
					draw_string(font, tag_rect.position + Vector2(6, 16), lbl_text, HORIZONTAL_ALIGNMENT_LEFT, 140, 10, Color(d_col.r, d_col.g, d_col.b, 1.0))


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
	player.connect("shot_fired", Callable(self, "_on_player_shot_fired"))
	player.connect("shot_hit", Callable(self, "_on_player_shot_hit"))
	player.connect("ammo_changed", Callable(self, "_on_player_ammo_changed"))
	add_child(player)
	if player.has_method("get_max_ammo"):
		_on_player_ammo_changed(player.current_ammo, player.get_max_ammo(), player.is_reloading)

	touch_controls = Control.new()
	touch_controls.set_script(TOUCH_CONTROLS)
	touch_controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	touch_controls.connect("move_changed", Callable(player, "set_touch_move"))
	touch_controls.connect("aim_changed", Callable(player, "set_touch_aim"))
	touch_controls.connect("fire_changed", Callable(player, "set_touch_fire"))
	touch_controls.connect("dash_pressed", Callable(player, "try_dash"))
	touch_controls.connect("reload_pressed", Callable(player, "start_reload"))
	ui_layer.add_child(touch_controls)
	ui_layer.move_child(touch_controls, 0)


func _on_player_ammo_changed(current: int, maximum: int, is_reloading: bool) -> void:
	if not is_instance_valid(ammo_label):
		return
	if is_reloading:
		ammo_label.text = "RELOAD..."
		ammo_label.add_theme_color_override("font_color", Color("f59e0b"))
	else:
		ammo_label.text = "CELLS %02d/%02d" % [current, maximum]
		if current <= 3:
			ammo_label.add_theme_color_override("font_color", Color("ef4444"))
		else:
			ammo_label.add_theme_color_override("font_color", Color("38bdf8"))


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


func _on_player_shot_fired() -> void:
	if tracker:
		tracker.record_shot_fired()


func _on_player_shot_hit(_enemy: Node2D) -> void:
	if tracker:
		tracker.record_shot_hit()


func _load_room(index: int) -> void:
	room_cleared = false
	doors_unlocked = false
	boss_active = false
	boss_ref = null
	if is_instance_valid(boss_bar_container):
		boss_bar_container.visible = false
	if is_instance_valid(boss_bar_bg):
		boss_bar_bg.visible = false
	sector_combat_time = 0.0

	for obs in active_obstacles:
		if is_instance_valid(obs):
			obs.queue_free()
	active_obstacles.clear()
	obstacle_rects.clear()

	for child in get_children():
		if child.is_in_group("projectiles") or child.has_method("_on_body_entered"):
			child.queue_free()

	active_enemies.clear()
	if spatial_index:
		spatial_index.clear()
	if squad_coordinator:
		squad_coordinator.reset()

	var rs_node = get_node_or_null("/root/RunState")
	var sec_seed: int = rs_node.progression.get_current_sector_seed() if (rs_node and rs_node.progression) else (rs_node.current_seed if rs_node else 1337)
	var room_count: int = rs_node.progression.rooms_per_sector if (rs_node and rs_node.progression) else 12

	if not dungeon_layout or dungeon_layout.rooms.is_empty():
		var wave_count: int = rs_node.progression.sector_total_waves if (rs_node and rs_node.progression) else 3
		dungeon_layout = dungeon_generator.generate_dungeon(sec_seed, room_count, wave_count)
		if rs_node:
			rs_node.dungeon_layout_summary.clear()
			for r in dungeon_layout.rooms:
				rs_node.record_room_summary(r.to_dict())

	current_room_data = dungeon_layout.get_room(index)
	if not current_room_data:
		var is_boss: bool = rs_node.progression.is_boss_chamber() if (rs_node and rs_node.progression) else false
		current_room_data = dungeon_generator._build_fallback_room(index, "BOSS" if is_boss else "COMBAT")

	if current_room_data.exit_doors.is_empty():
		var door_pos := Vector2(ROOM_RECT.end.x - 60.0, ROOM_RECT.get_center().y)
		current_room_data.exit_doors.append({ "pos": door_pos, "target_room": index + 1, "target_type": "COMBAT", "label": "FORWARD CORRIDOR" })
		current_room_data.exit_door = door_pos

	# Position player at designated reachable spawn
	if is_instance_valid(player):
		player.position = current_room_data.player_spawn
		if is_instance_valid(camera):
			camera.position = player.position
			camera.reset_smoothing()

	# Place procedural obstacle geometry
	for r in current_room_data.obstacles:
		_add_obstacle(r.get_center(), r.size)

	# Services and caches are safe rooms, not combat encounters.
	if current_room_data.room_type in ["START", "RECOVERY", "SHOP", "GIFT"]:
		_handle_non_wave_room(current_room_data.room_type)
		queue_redraw()
		_update_debug_overlay()
		return

	# One combat encounter is one wave; required wave rooms are selected per sector.
	if rs_node and rs_node.progression:
		rs_node.progression.calculate_waves_for_current_room(current_room_data.room_type)
		rs_node.current_wave = rs_node.progression.current_wave
		rs_node.waves_in_room = rs_node.progression.waves_in_room

	damage_taken_this_sector = 0
	room_cleared = false
	_spawn_wave_enemies(1)

	queue_redraw()
	_update_debug_overlay()


func _handle_non_wave_room(room_type: String) -> void:
	doors_unlocked = true
	var rs_node = get_node_or_null("/root/RunState")
	match room_type:
		"START":
			_show_director_banner("CALIBRATION DOCK // EXPEDITION COMMENCED", "Chamber secure. Select forward route corridor.")
			_unlock_exit_doors()
		"RECOVERY":
			if rs_node:
				rs_node.heal(2)
			if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
				get_node("/root/AudioSynth").play("powerup_pickup", 0.0, 0.0)
			_show_director_banner("RECOVERY MEDBAY // +2 HP RESTORED", "Nanite biocircuits repaired. Route doors open.")
			_unlock_exit_doors()
		"SHOP":
			_show_shop_interface()
		"GIFT":
			_show_gift_interface()
		_:
			_unlock_exit_doors()


func _show_shop_interface() -> void:
	glitch_pulse = 0.0
	if is_instance_valid(glitch_material):
		glitch_material.set_shader_parameter("glitch_intensity", 0.0)
	if touch_controls:
		touch_controls.enabled = false
	get_tree().paused = true
	var rs = get_node_or_null("/root/RunState")
	var stock: Array = current_room_data.shop_stock if current_room_data else []
	if stock.is_empty():
		stock = dungeon_generator._generate_shop_stock(RandomNumberGenerator.new())

	for child in upgrade_cards_box.get_children():
		child.queue_free()

	for item in stock:
		var card := Button.new()
		card.custom_minimum_size = Vector2(230, 210)
		var item_id: String = item.get("id", "OVERCLOCK")
		var cost: int = int(item.get("cost", 5))
		var title: String = item.get("title", item_id)
		var desc: String = item.get("desc", "+Upgrade")
		var can_afford: bool = rs != null and rs.score >= cost
		var is_capped: bool = rs != null and rs.get_upgrade_stack_count(item_id) >= rs.get_upgrade_stack_cap(item_id)

		var status_text := "COST: %d BITS" % cost
		if is_capped:
			status_text = "[ FULLY STACKED ]"
		elif not can_afford:
			status_text = "COST: %d BITS (HAVE %d)" % [cost, (rs.score if rs else 0)]

		card.text = "\n[ SHOP // %s ]\n%s\n\n%s\n\n%s" % [
			title,
			status_text,
			desc,
			"Tap to purchase" if (can_afford and not is_capped) else "Unavailable"
		]
		card.disabled = not can_afford or is_capped
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.pressed.connect(func():
			if rs and rs.score >= cost and not is_capped:
				rs.score -= cost
				rs.apply_upgrade(item_id)
				if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
					get_node("/root/AudioSynth").play("powerup_pickup", 0.0, 0.0)
				_close_shop_or_gift()
		)
		upgrade_cards_box.add_child(card)

	var bypass_btn := Button.new()
	bypass_btn.custom_minimum_size = Vector2(230, 210)
	bypass_btn.text = "\n[ BYPASS TERMINAL ]\n\nSave bits for later.\n\nProceed to exit doors."
	bypass_btn.pressed.connect(_close_shop_or_gift)
	upgrade_cards_box.add_child(bypass_btn)

	upgrade_container.visible = true


func _show_gift_interface() -> void:
	glitch_pulse = 0.0
	if is_instance_valid(glitch_material):
		glitch_material.set_shader_parameter("glitch_intensity", 0.0)
	if touch_controls:
		touch_controls.enabled = false
	get_tree().paused = true
	var rs = get_node_or_null("/root/RunState")
	var gifts: Array = current_room_data.gift_choices if current_room_data else []
	if gifts.is_empty():
		gifts = ["PHANTOM_DRIVE", "NANO_INFUSION"]

	for child in upgrade_cards_box.get_children():
		child.queue_free()

	for item_id in gifts:
		var card := Button.new()
		card.custom_minimum_size = Vector2(230, 210)
		var stack_count: int = (rs.get_upgrade_stack_count(item_id) + 1) if rs else 1
		var stack_cap: int = rs.get_upgrade_stack_cap(item_id) if rs else 2
		card.text = "\n[ CACHE // %s ]\nFREE UPGRADE\n(STACK %d/%d)\n\nTap to extract subroutine." % [item_id, stack_count, stack_cap]
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.pressed.connect(func():
			if rs:
				rs.apply_upgrade(item_id)
			if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
				get_node("/root/AudioSynth").play("powerup_pickup", 0.0, 0.0)
			_close_shop_or_gift()
		)
		upgrade_cards_box.add_child(card)

	upgrade_container.visible = true


func _close_shop_or_gift() -> void:
	upgrade_container.visible = false
	get_tree().paused = false
	if touch_controls:
		touch_controls.enabled = true
	_unlock_exit_doors()



func _spawn_wave_enemies(wave_num: int) -> void:
	var rs_node = get_node_or_null("/root/RunState")
	var profile: Dictionary = tracker.get_profile() if tracker else {}
	var p_hp: int = player.health if is_instance_valid(player) else 5
	var p_max: int = player.max_health if is_instance_valid(player) else 5
	var spawn_budget: int = rs_node.progression.calculate_spawn_budget(wave_num) if (rs_node and rs_node.progression) else current_room_data.enemy_spawns.size()
	var sector_seed: int = rs_node.progression.get_current_sector_seed() if (rs_node and rs_node.progression) else 1337
	current_room_data.enemy_spawns = dungeon_generator.generate_wave_spawns(current_room_data, sector_seed, wave_num, spawn_budget)

	var encounter: Dictionary = encounter_director.prepare_encounter(
		current_room_data,
		profile,
		p_hp,
		p_max
	)

	current_sector_tactic = encounter.tactic
	if wave_num == 1:
		_show_director_banner(encounter.banner_title, encounter.banner_sub)
	else:
		var total_w: int = rs_node.waves_in_room if rs_node else 3
		_show_director_banner("WAVE %d / %d // REINFORCEMENTS" % [wave_num, total_w], "Hostile wave engaged.")

	if rs_node and wave_num == 1:
		var active_muts: Array[String] = encounter_director.evolution_manager.get_active_mutations_summary()
		var mut_desc := ", ".join(active_muts) if not active_muts.is_empty() else "Standard swarm baseline"
		rs_node.record_tactic(rs_node.current_room_index + 1, encounter.tactic, encounter.banner_sub, mut_desc)

	# Spawn budgeted enemies for this wave
	var spawns_to_create: Array = encounter.spawn_list.slice(0, mini(spawn_budget, encounter.spawn_list.size()))
	if spawns_to_create.is_empty() and not encounter.spawn_list.is_empty():
		spawns_to_create = encounter.spawn_list
	# Boss rooms must never silently become ordinary empty/regular encounters if
	# encounter composition or budget filtering changes later.
	if current_room_data.room_type == "BOSS":
		var contains_boss := false
		for spawn in spawns_to_create:
			if spawn.type == "BOSS":
				contains_boss = true
				break
		if not contains_boss:
			spawns_to_create.push_front({
				"type": "BOSS",
				"pos": Vector2(current_room_data.bounds.position.x + current_room_data.bounds.size.x * 0.70, current_room_data.bounds.get_center().y),
				"flank_angle": 0.0,
				"genome": null
			})

	for espawn in spawns_to_create:
		var stype: String = espawn.type
		var pos: Vector2 = espawn.pos
		var flank: float = espawn.flank_angle
		var genome: RefCounted = espawn.genome

		if stype == "BOSS":
			_spawn_boss(pos)
		else:
			var scene: PackedScene = CHASER_SCENE
			if stype == "SHOOTER":
				scene = SHOOTER_SCENE
			elif stype == "DASHER":
				scene = DASHER_SCENE

			var enemy = _spawn_enemy(
				scene,
				pos,
				encounter.enemy_speed_mult,
				encounter.enemy_telegraph_mult,
				flank,
				encounter.shooter_lead,
				false # Dasher trails are granted by the learned species genome only.
			)
			if genome and enemy:
				genome.apply_to_enemy(enemy)
				encounter_director.evolution_manager.register_spawned_combatant(genome)


func _spawn_boss(pos: Vector2) -> void:
	var rs_node = get_node_or_null("/root/RunState")
	var cur_sector: int = rs_node.progression.sector_index if (rs_node and rs_node.progression) else 1
	var cur_seed: int = rs_node.current_seed if rs_node else 1337
	var last_id: String = boss_director.last_scheduled_boss_id if boss_director else ""

	current_boss_def = boss_director.select_boss_for_sector(cur_sector, cur_seed, last_id) if boss_director else null
	var scene_path: String = current_boss_def.scene_path if current_boss_def else "res://scenes/enemies/boss.tscn"
	var boss_packed: PackedScene = load(scene_path)
	var boss: Node2D = boss_packed.instantiate()

	boss.position = pos
	boss.target = player
	if "squad_coordinator" in boss:
		boss.squad_coordinator = squad_coordinator
	if spatial_index:
		spatial_index.register_agent(boss)

	# Assign returning mutations with trade-offs
	current_boss_mutations = boss_director.get_mutations_for_encounter(current_boss_def.boss_id) if (boss_director and current_boss_def) else []
	if boss.has_method("apply_mutations") and not current_boss_mutations.is_empty():
		boss.apply_mutations(current_boss_mutations)

	boss.connect("defeated", Callable(self, "_on_enemy_defeated").bind(boss))
	add_child(boss)
	active_enemies.append(boss)
	boss_ref = boss
	boss_active = true

	# Update Boss Bar appearance
	if current_boss_def:
		boss_label.text = "[ BOSS // %s ]" % current_boss_def.display_name.to_upper()
		boss_bar_fill.color = current_boss_def.accent_color
	else:
		boss_label.text = "[ BOSS // NEXUS OVERLORD ]"
		boss_bar_fill.color = Color("f43f5e")

	if is_instance_valid(boss_hp_label):
		boss_hp_label.text = "%d / %d HP" % [boss.health, boss.max_health]
	if is_instance_valid(boss_bar_ghost):
		boss_bar_ghost.size.x = 420.0
	boss_bar_fill.size.x = 420.0

	if is_instance_valid(boss_bar_container):
		boss_bar_container.visible = true
	boss_bar_bg.visible = true
	trigger_glitch(0.85)
	add_trauma(0.4)
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("boss_alarm", 0.0, 0.0)

	# Arrival holographic card / banner
	if current_boss_def:
		if current_boss_mutations.is_empty():
			_show_director_banner("ALERT // " + current_boss_def.display_name, current_boss_def.subtitle)
		else:
			var m_dict: Dictionary = current_boss_mutations[0]
			_show_director_banner(
				"EVOLVED OVERLORD // " + current_boss_def.display_name,
				"MUTATION: %s [%s]" % [m_dict.get("name", "OVERCLOCK"), m_dict.get("desc", "ADAPTATION ACTIVE")]
			)


func _spawn_enemy(
	packed_scene: PackedScene,
	pos: Vector2,
	speed_mult: float = 1.0,
	telegraph_mult: float = 1.0,
	flank_angle: float = 0.0,
	lead_prediction: float = 0.0,
	has_hazard_trail: bool = false
) -> Node2D:
	if not is_instance_valid(player):
		return null
	var enemy: Node2D = packed_scene.instantiate()
	enemy.position = pos
	if "target" in enemy:
		enemy.target = player
	if "spatial_index" in enemy:
		enemy.spatial_index = spatial_index
	if "squad_coordinator" in enemy:
		enemy.squad_coordinator = squad_coordinator
	if "obstacle_rects" in enemy:
		enemy.obstacle_rects = obstacle_rects
	if spatial_index:
		spatial_index.register_agent(enemy)
	if "move_speed" in enemy:
		enemy.move_speed *= speed_mult
	if "patrol_speed" in enemy:
		enemy.patrol_speed *= speed_mult
	if "lunge_speed" in enemy:
		enemy.lunge_speed *= speed_mult
	if "state_timer" in enemy:
		enemy.state_timer *= telegraph_mult
	if "flank_angle" in enemy:
		enemy.flank_angle = flank_angle
		if flank_angle != 0.0 and "is_flanker" in enemy:
			enemy.is_flanker = true
	if "lead_prediction" in enemy:
		enemy.lead_prediction = lead_prediction
	if "has_hazard_trail" in enemy:
		enemy.has_hazard_trail = has_hazard_trail
	enemy.connect("defeated", Callable(self, "_on_enemy_defeated").bind(enemy))
	add_child(enemy)
	active_enemies.append(enemy)
	return enemy


func _on_enemy_defeated(enemy_node: Node2D) -> void:
	if run_over:
		return
	active_enemies.erase(enemy_node)
	if spatial_index:
		spatial_index.unregister_agent(enemy_node)
	if squad_coordinator:
		squad_coordinator.release_attack_token(enemy_node)

	# Spawn geometric debris shards and screen shake based on hostile type
	var shard_type := "diamond"
	var shard_color := Color("ef4444")
	if enemy_node.get_script() and "shooter" in enemy_node.get_script().resource_path.to_lower():
		shard_type = "hexagon"
		shard_color = Color("f59e0b")
	elif enemy_node.get_script() and "dasher" in enemy_node.get_script().resource_path.to_lower():
		shard_type = "chevron"
		shard_color = Color("d946ef")
	elif enemy_node.get_script() and "boss" in enemy_node.get_script().resource_path.to_lower():
		shard_type = "hexagon"
		shard_color = current_boss_def.accent_color if current_boss_def else Color("f43f5e")
		var rs_node = get_node_or_null("/root/RunState")
		if current_boss_def and rs_node:
			var cur_sec: int = rs_node.progression.sector_index if rs_node.progression else rs_node.current_sector
			var cur_dep: int = rs_node.progression.run_depth if rs_node.progression else (rs_node.current_room_index + 1)
			if boss_director:
				boss_director.record_encounter(current_boss_def.boss_id, cur_sec, cur_dep, "VICTORY", current_boss_mutations)
			rs_node.record_boss_encounter(current_boss_def.boss_id, cur_sec, cur_dep, "VICTORY", current_boss_mutations)
			rs_node.heal(3)
			_show_director_banner("NEXUS CORE PURGED // " + current_boss_def.display_name, "+3 REPAIR CELLS HARVESTED // HYPERGRID GATEWAY UNLOCKED")

	DEBRIS_EMITTER_SCRIPT.spawn_shards(self, enemy_node.global_position, shard_color, shard_type, 9)
	add_trauma(0.18)
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("hit_impact", 0.12, -2.0)

	var rs = get_node_or_null("/root/RunState")
	if rs:
		rs.on_enemy_eliminated()

	if active_enemies.is_empty() and not room_cleared:
		if rs and rs.progression and rs.progression.advance_wave():
			rs.current_wave = rs.progression.current_wave
			_trigger_next_wave()
		else:
			room_cleared = true
			if rs and rs.progression:
				rs.progression.complete_current_wave(current_room_data.is_sector_wave)
			_on_room_cleared()


func _trigger_next_wave() -> void:
	var rs = get_node_or_null("/root/RunState")
	if not rs or not rs.progression:
		return
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("mutation_alert", 0.05, 0.0)
	_show_director_banner("WAVE %d / %d // ENGAGING" % [rs.current_wave, rs.waves_in_room], "Hostile host detected on grid.")
	# Brief inter-wave breathing window
	await get_tree().create_timer(1.2).timeout
	if run_over or not is_inside_tree():
		return
	_spawn_wave_enemies(rs.current_wave)


func _on_room_cleared() -> void:
	add_trauma(0.2)
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("wave_clear", 0.0, 0.0)
	var rs = get_node("/root/RunState")

	# Report combat outcome to EncounterDirector & EvolutionManager
	var new_adaptations: Array[Dictionary] = []
	if encounter_director and tracker and rs:
		new_adaptations = encounter_director.record_encounter_result(
			maxi(0, rs.progression.sector_index - 1) if rs.progression else maxi(0, rs.current_sector - 1),
			damage_taken_this_sector,
			sector_combat_time,
			tracker.get_profile(),
			current_sector_tactic
		)
		rs.set_evolution_log(encounter_director.evolution_manager.evolution_history)

	# If hostiles evolved, flash alert banner and play mutation audio
	if not new_adaptations.is_empty():
		var first_adap: Dictionary = new_adaptations[0]
		var f_name: String = first_adap.get("family", "HOSTILE")
		var t_num: int = first_adap.get("tier", 1)
		var m_name: String = first_adap.get("mutation", "OVERCLOCK")
		var h_mult: String = first_adap.get("health_mult", "2x HP")
		trigger_glitch(0.70)
		add_trauma(0.35)
		if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
			get_node("/root/AudioSynth").play("mutation_alert", 0.0, 0.0)
		_show_director_banner(
			"HOSTILE SPECIES EVOLVED // %s [TIER %d]" % [f_name, t_num],
			"%s (%s) • %s" % [m_name.replace("_", " "), h_mult, first_adap.get("tradeoff", "Hostiles learned from previous battles.")]
		)

	# Handle reward presentation based on room type
	var r_type: String = current_room_data.room_type if current_room_data else "COMBAT"
	match r_type:
		"RECOVERY":
			if rs:
				rs.heal(2)
			if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
				get_node("/root/AudioSynth").play("powerup_pickup", 0.0, 0.0)
			_show_upgrade_draft()
		"SHOP":
			_show_shop_interface()
		"GIFT":
			_show_gift_interface()
		_:
			_show_upgrade_draft()


func _show_upgrade_draft() -> void:
	glitch_pulse = 0.0
	if is_instance_valid(glitch_material):
		glitch_material.set_shader_parameter("glitch_intensity", 0.0)
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
		if item.id == "FIELD_REPAIR":
			card.text = "\n[ %s ]\n\n%s\n\n\"%s\"" % [item.title, item.desc, item.flavor]
		else:
			var stack_count: int = rs.get_upgrade_stack_count(item.id) + 1
			var stack_cap: int = rs.get_upgrade_stack_cap(item.id)
			card.text = "\n[ %s ]\nSTACK %d / %d\n\n%s\n\n\"%s\"" % [item.title, stack_count, stack_cap, item.desc, item.flavor]
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.pressed.connect(_on_upgrade_selected.bind(item.id))
		upgrade_cards_box.add_child(card)

	upgrade_container.visible = true


func _on_upgrade_selected(upgrade_id: String) -> void:
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("ui_click", 0.0, 0.0)
	upgrade_container.visible = false
	get_tree().paused = false
	if touch_controls:
		touch_controls.enabled = true
	var rs = get_node("/root/RunState")
	rs.apply_upgrade(upgrade_id)

	# Unlock exit doors and display route choices for touch and walk navigation
	_unlock_exit_doors()


func _unlock_exit_doors() -> void:
	doors_unlocked = true
	queue_redraw()
	_show_director_banner("CHAMBER SECURED // ROUTE DOORS UNLOCKED", "Proceed to forward gate to continue expedition.")


func _enter_door(door: Dictionary) -> void:
	if not doors_unlocked or run_over:
		return
	doors_unlocked = false

	var rs = get_node_or_null("/root/RunState")
	if not rs:
		return

	var ttype: String = door.get("target_type", "COMBAT")
	if ttype == "RECOVERY":
		rs.heal(2)
		if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
			get_node("/root/AudioSynth").play("powerup_pickup", 0.0, 0.0)
		_show_director_banner("RECOVERY NODE REACHED // +2 HP RESTORED", "Nanite biocircuits patched.")
	elif ttype == "SHOP":
		if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
			get_node("/root/AudioSynth").play("ui_click", 0.0, 0.0)
		_show_director_banner("BLACK MARKET DATA TERMINAL", "Spend collected bits for tactical upgrades.")
	elif ttype == "GIFT":
		if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
			get_node("/root/AudioSynth").play("powerup_pickup", 0.0, 0.0)
		_show_director_banner("DATA CACHE RECOVERED // UNCLAIMED TECH", "Extract 1 complimentary subroutine.")
	elif ttype == "ELITE":
		trigger_glitch(0.8)
		if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
			get_node("/root/AudioSynth").play("boss_alarm", 0.0, 0.0)
		_show_director_banner("WARNING: ELITE CHAMBER // ENGAGING HIGH THREAT", "Hostile signatures intensified.")

	var target_room: int = door.get("target_room", rs.current_room_index + 1)
	var nav: Dictionary = rs.advance_room(target_room)
	if nav.get("is_new_sector", false):
		dungeon_layout = null
		_load_room(0)
	else:
		_load_room(rs.current_room_index)


func _on_player_died() -> void:
	run_over = true
	for enemy in active_enemies:
		if is_instance_valid(enemy):
			enemy.set_physics_process(false)

	var rs = get_node_or_null("/root/RunState")
	if encounter_director and tracker and rs:
		encounter_director.record_encounter_result(
			maxi(0, rs.progression.sector_index - 1) if rs.progression else maxi(0, rs.current_sector - 1),
			damage_taken_this_sector,
			sector_combat_time,
			tracker.get_profile(),
			current_sector_tactic
		)
		rs.set_evolution_log(encounter_director.evolution_manager.evolution_history)

	_show_end_screen(false)


func _show_end_screen(won: bool) -> void:
	run_over = true
	get_tree().paused = true
	if touch_controls:
		touch_controls.enabled = false
	var rs = get_node("/root/RunState")
	rs.finalize_run_stats(won)

	var metrics: Dictionary = tracker.get_combat_metrics() if tracker else {}
	debrief_terminal.setup_debrief(won, metrics, rs.tactics_log, rs.evolution_log, rs.current_seed)


func _restart_run() -> void:
	get_tree().paused = false
	var rs = get_node_or_null("/root/RunState")
	if rs:
		rs.current_seed = 0
	get_tree().reload_current_scene()


func _return_to_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _create_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	ui_layer.layer = 20
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
	# Top HUD - Left Column: Health / Hearts
	var hearts_container := HBoxContainer.new()
	hearts_container.position = Vector2(24, 16)
	hearts_container.add_theme_constant_override("separation", 8)
	ui_layer.add_child(hearts_container)

	hearts_box = HBoxContainer.new()
	hearts_box.add_theme_constant_override("separation", 4)
	hearts_container.add_child(hearts_box)

	# Top HUD - Center Column: Cyber Telemetry Pill (Elims + Energy Cells)
	var telemetry_pill := PanelContainer.new()
	telemetry_pill.position = Vector2(270, 12)
	telemetry_pill.custom_minimum_size = Vector2(300, 36)
	var pill_style := StyleBoxFlat.new()
	pill_style.bg_color = Color(0.03, 0.06, 0.12, 0.88)
	pill_style.border_color = Color("1e293b")
	pill_style.set_border_width_all(1)
	pill_style.set_corner_radius_all(18)
	pill_style.content_margin_left = 18
	pill_style.content_margin_right = 18
	pill_style.content_margin_top = 4
	pill_style.content_margin_bottom = 4
	telemetry_pill.add_theme_stylebox_override("panel", pill_style)
	ui_layer.add_child(telemetry_pill)

	var telemetry_hbox := HBoxContainer.new()
	telemetry_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	telemetry_hbox.add_theme_constant_override("separation", 24)
	telemetry_pill.add_child(telemetry_hbox)

	elims_label = Label.new()
	elims_label.text = "ELIMS  00"
	elims_label.add_theme_color_override("font_color", Color("38bdf8"))
	elims_label.add_theme_font_size_override("font_size", 14)
	telemetry_hbox.add_child(elims_label)

	ammo_label = Label.new()
	ammo_label.text = "CELLS 16/16"
	ammo_label.add_theme_color_override("font_color", Color("38bdf8"))
	ammo_label.add_theme_font_size_override("font_size", 14)
	telemetry_hbox.add_child(ammo_label)

	# Top HUD - Right Column: Sector & Room Badge
	sector_label = Label.new()
	sector_label.position = Vector2(600, 20)
	sector_label.text = "SEC 1  •  RM 1/6"
	sector_label.add_theme_color_override("font_color", Color("38bdf8"))
	sector_label.add_theme_font_size_override("font_size", 14)
	ui_layer.add_child(sector_label)

	# HUD Touch Pause Button (Top Right corner, 48dp+ touch target, inset from edge)
	var pause_btn := Button.new()
	pause_btn.position = Vector2(888, 12)
	pause_btn.custom_minimum_size = Vector2(48, 48)
	pause_btn.text = "||"
	var pause_btn_style := StyleBoxFlat.new()
	pause_btn_style.bg_color = Color(0.06, 0.10, 0.20, 0.85)
	pause_btn_style.border_color = Color("38bdf8")
	pause_btn_style.set_border_width_all(1)
	pause_btn_style.set_corner_radius_all(6)
	pause_btn.add_theme_stylebox_override("normal", pause_btn_style)
	pause_btn.add_theme_stylebox_override("hover", pause_btn_style)
	pause_btn.add_theme_stylebox_override("pressed", pause_btn_style)
	pause_btn.add_theme_color_override("font_color", Color("38bdf8"))
	pause_btn.pressed.connect(func():
		if not run_over and is_instance_valid(pause_menu):
			pause_menu.open_pause()
	)
	ui_layer.add_child(pause_btn)

	# HUD Debug Overlay Toggle Button (48dp+ touch target)
	var dbg_btn := Button.new()
	dbg_btn.position = Vector2(830, 12)
	dbg_btn.custom_minimum_size = Vector2(48, 48)
	dbg_btn.text = "DBG"
	var dbg_btn_style := StyleBoxFlat.new()
	dbg_btn_style.bg_color = Color(0.06, 0.08, 0.18, 0.85)
	dbg_btn_style.border_color = Color("c084fc")
	dbg_btn_style.set_border_width_all(1)
	dbg_btn_style.set_corner_radius_all(6)
	dbg_btn.add_theme_stylebox_override("normal", dbg_btn_style)
	dbg_btn.add_theme_stylebox_override("hover", dbg_btn_style)
	dbg_btn.add_theme_stylebox_override("pressed", dbg_btn_style)
	dbg_btn.add_theme_color_override("font_color", Color("c084fc"))
	dbg_btn.pressed.connect(toggle_debug_overlay)
	ui_layer.add_child(dbg_btn)

	# Telemetry & Evolution Debug Inspector Panel
	debug_overlay = PanelContainer.new()
	debug_overlay.position = Vector2(42, 54)
	debug_overlay.custom_minimum_size = Vector2(440, 380)
	var dbg_panel_style := StyleBoxFlat.new()
	dbg_panel_style.bg_color = Color(0.02, 0.035, 0.08, 0.94)
	dbg_panel_style.border_color = Color("c084fc")
	dbg_panel_style.set_border_width_all(1)
	dbg_panel_style.set_corner_radius_all(4)
	dbg_panel_style.content_margin_left = 14
	dbg_panel_style.content_margin_top = 10
	dbg_panel_style.content_margin_right = 14
	dbg_panel_style.content_margin_bottom = 10
	debug_overlay.add_theme_stylebox_override("panel", dbg_panel_style)
	debug_overlay.visible = false
	ui_layer.add_child(debug_overlay)

	var dbg_vbox := VBoxContainer.new()
	dbg_vbox.add_theme_constant_override("separation", 6)
	debug_overlay.add_child(dbg_vbox)

	var dbg_header := Label.new()
	dbg_header.text = "SYSTEM TELEMETRY & ADAPTIVE EVOLUTION INSPECTOR"
	dbg_header.add_theme_font_size_override("font_size", 12)
	dbg_header.add_theme_color_override("font_color", Color("c084fc"))
	dbg_vbox.add_child(dbg_header)

	debug_content = Label.new()
	debug_content.add_theme_font_size_override("font_size", 11)
	debug_content.add_theme_color_override("font_color", Color("cbd5e1"))
	debug_content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dbg_vbox.add_child(debug_content)

	var dbg_btns_hbox := HBoxContainer.new()
	dbg_btns_hbox.add_theme_constant_override("separation", 10)
	dbg_vbox.add_child(dbg_btns_hbox)

	var replay_seed_btn := Button.new()
	replay_seed_btn.text = "Replay Seed"
	replay_seed_btn.pressed.connect(func():
		var rs_node = get_node_or_null("/root/RunState")
		var s_val: int = rs_node.current_seed if rs_node else 1337
		_restart_run_with_seed(s_val)
	)
	dbg_btns_hbox.add_child(replay_seed_btn)

	var next_seed_btn := Button.new()
	next_seed_btn.text = "New Seed"
	next_seed_btn.pressed.connect(func():
		_restart_run_with_seed(0)
	)
	dbg_btns_hbox.add_child(next_seed_btn)

	var close_dbg_btn := Button.new()
	close_dbg_btn.text = "Close (F1)"
	close_dbg_btn.pressed.connect(toggle_debug_overlay)
	dbg_btns_hbox.add_child(close_dbg_btn)

	hint_label = Label.new()
	hint_label.position = Vector2(24, 46)
	hint_label.text = "WASD/Move   •   Aim + Fire   •   Shift/Space Dash (I-Frames)   •   ESC/P/|| Pause"
	hint_label.add_theme_color_override("font_color", Color("64748b"))
	hint_label.add_theme_font_size_override("font_size", 11)
	if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available():
		hint_label.visible = false
	ui_layer.add_child(hint_label)

	# Boss Health Bar (Bottom Center - Zero HUD Collisions)
	boss_bar_container = PanelContainer.new()
	boss_bar_container.position = Vector2(250, 480)
	boss_bar_container.custom_minimum_size = Vector2(460, 48)
	var boss_panel_style := StyleBoxFlat.new()
	boss_panel_style.bg_color = Color(0.04, 0.015, 0.04, 0.90)
	boss_panel_style.border_color = Color("ec4899")
	boss_panel_style.set_border_width_all(1)
	boss_panel_style.set_corner_radius_all(6)
	boss_panel_style.content_margin_left = 14
	boss_panel_style.content_margin_right = 14
	boss_panel_style.content_margin_top = 4
	boss_panel_style.content_margin_bottom = 6
	boss_bar_container.add_theme_stylebox_override("panel", boss_panel_style)
	boss_bar_container.visible = false
	ui_layer.add_child(boss_bar_container)

	var boss_vbox := VBoxContainer.new()
	boss_vbox.add_theme_constant_override("separation", 3)
	boss_bar_container.add_child(boss_vbox)

	boss_label = Label.new()
	boss_label.text = "[ BOSS // NEXUS OVERLORD ]"
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_label.add_theme_font_size_override("font_size", 11)
	boss_label.add_theme_color_override("font_color", Color("fda4af"))
	boss_vbox.add_child(boss_label)

	boss_bar_bg = ColorRect.new()
	boss_bar_bg.custom_minimum_size = Vector2(420, 16)
	boss_bar_bg.color = Color("1a0612")
	boss_vbox.add_child(boss_bar_bg)

	boss_bar_ghost = ColorRect.new()
	boss_bar_ghost.position = Vector2.ZERO
	boss_bar_ghost.size = Vector2(420, 16)
	boss_bar_ghost.color = Color(0.9, 0.65, 0.25, 0.45)
	boss_bar_bg.add_child(boss_bar_ghost)

	boss_bar_fill = ColorRect.new()
	boss_bar_fill.position = Vector2.ZERO
	boss_bar_fill.size = Vector2(420, 16)
	boss_bar_fill.color = Color("f43f5e")
	boss_bar_bg.add_child(boss_bar_fill)

	boss_hp_label = Label.new()
	boss_hp_label.text = "35 / 35 HP"
	boss_hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	boss_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	boss_hp_label.add_theme_font_size_override("font_size", 10)
	boss_hp_label.add_theme_color_override("font_color", Color("ffffff"))
	boss_bar_bg.add_child(boss_hp_label)

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
	draft_header.text = "CHAMBER SECURED // SELECT RECONFIGURATION"
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

	# In-Game Tactical Pause Menu
	pause_menu = PAUSE_MENU_SCRIPT.new()
	pause_menu.restart_requested.connect(_restart_run)
	pause_menu.menu_requested.connect(_return_to_main_menu)
	ui_layer.add_child(pause_menu)

	# End of Run Director Telemetry Debrief Terminal
	debrief_terminal = DEBRIEF_TERMINAL_SCRIPT.new()
	debrief_terminal.visible = false
	debrief_terminal.restart_requested.connect(_restart_run)
	debrief_terminal.replay_seed_requested.connect(_restart_run_with_seed)
	debrief_terminal.menu_requested.connect(_return_to_main_menu)
	ui_layer.add_child(debrief_terminal)
	debrief_terminal.visible = false


func _show_director_banner(title: String, sub: String) -> void:
	if not is_instance_valid(director_banner):
		return
	banner_title.text = title
	banner_sub.text = sub
	director_banner.visible = true
	banner_timer = 4.0
	trigger_glitch(0.7)
	add_trauma(0.28)
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("mutation_alert", 0.05, 0.0)


func toggle_debug_overlay() -> void:
	debug_visible = not debug_visible
	if is_instance_valid(debug_overlay):
		debug_overlay.visible = debug_visible
	if debug_visible:
		_update_debug_overlay()


func _restart_run_with_seed(seed_val: int) -> void:
	get_tree().paused = false
	var rs = get_node_or_null("/root/RunState")
	if rs:
		rs.current_seed = seed_val
	get_tree().reload_current_scene()


func _update_debug_overlay() -> void:
	if not is_instance_valid(debug_content):
		return
	var rs = get_node_or_null("/root/RunState")
	var profile: Dictionary = tracker.get_profile() if tracker else {}
	var cur_seed: int = rs.current_seed if rs else 1337
	var sec_idx: int = (rs.current_room_index + 1) if rs else 1
	var t_name: String = current_room_data.template_name if current_room_data else "UNKNOWN"
	var r_type: String = current_room_data.room_type if current_room_data else "COMBAT"

	var active_muts: Array[String] = encounter_director.evolution_manager.get_active_mutations_summary() if encounter_director else []
	var mut_str: String = "\n    • ".join(active_muts) if not active_muts.is_empty() else "None (Baseline)"

	debug_content.text = """SEED: #%d  |  SECTOR: %d / %d  |  GEN: %d
ROOM TEMPLATE: %s (%s)
TACTICAL ACTION: %s

PLAYER COMBAT PROFILE:
  • Mobility (Dashes/min): %.2f (%.1f/m)
  • Ranged Positioning: %.2f
  • Stationary Turret: %.2f
  • Aggression: %.2f
  • Blaster Accuracy: %.1f%% (%d/%d)
  • Movement Consistency: %.2f

ACTIVE ENEMY GENOME MUTATIONS:
	• %s""" % [
		cur_seed,
		sec_idx,
		rs.TOTAL_ROOMS if rs else 12,
		encounter_director.evolution_manager.generation if encounter_director else 1,
		t_name,
		r_type,
		current_sector_tactic,
		profile.get("mobility", 0.5),
		profile.get("dashes_per_min", 0.0),
		profile.get("ranged", 0.5),
		profile.get("turret", 0.5),
		profile.get("aggression", 0.5),
		profile.get("accuracy", 0.5) * 100.0,
		profile.get("shots_hit", 0),
		profile.get("shots_fired", 0),
		profile.get("movement_consistency", 0.5),
		mut_str
	]
