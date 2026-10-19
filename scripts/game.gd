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
const NAV_GRID_SCRIPT := preload("res://scripts/navigation_grid.gd")
const BIOME_DATA_SCRIPT := preload("res://scripts/biome_data.gd")

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
var active_door_barriers: Array[StaticBody2D] = []

var room_cleared := false
var run_over := false
var boss_active := false
var boss_ref: Node2D = null
var boss_director: RefCounted = null
var current_boss_def: RefCounted = null
var current_boss_mutations: Array[Dictionary] = []
var boss_vanguard_active := false
var boss_spawn_pos := Vector2.ZERO
var active_walls: Array[StaticBody2D] = []
var fountain_rect := Rect2()
var fountain_center := Vector2.ZERO
var fountain_radius := 44.0

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

var vignette_layer: CanvasLayer
var vignette_rect: ColorRect
var vignette_material: ShaderMaterial
var vignette_intensity := 0.0
var vignette_target_intensity := 0.0
var vignette_pulse_speed := 4.0
var heartbeat_timer := 0.0

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
var draft_header_label: Label
var draft_sub_label: Label
var floor_buff_awarded := false
var post_upgrade_callback: Callable = Callable()
var pending_spawn_telegraphs: Array[Dictionary] = []

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
var nav_grid: RefCounted
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
	nav_grid = NAV_GRID_SCRIPT.new()

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
	var first_floor_rooms: int = rs.progression.rooms_per_sector if rs.progression else rs.TOTAL_ROOMS
	var first_floor_waves: int = rs.progression.sector_total_waves if rs.progression else 3
	dungeon_layout = dungeon_generator.generate_dungeon(
		rs.current_seed,
		first_floor_rooms,
		first_floor_waves,
		true,
		rs.progression.difficulty if rs.progression else rs.difficulty,
		rs.progression.sector_index if rs.progression else rs.current_sector
	)
	rs.dungeon_layout_summary.clear()
	for r in dungeon_layout.rooms:
		rs.record_room_summary(r.to_dict())

	# Initialize Camera2D for trauma screen shake
	camera = Camera2D.new()
	camera.position = Vector2(480, 270)
	add_child(camera)
	camera.make_current()

	# Initialize Glitch Post-Processing & Danger Vignette Layers
	_init_glitch_layer()
	_init_vignette_layer()

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

	# Direct touch or click selection on unlocked doors
	if doors_unlocked and not run_over and current_room_data and is_instance_valid(player):
		var click_pos := Vector2.ZERO
		var is_click := false
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			is_click = true
			click_pos = event.position
		elif event is InputEventScreenTouch and event.pressed:
			is_click = true
			click_pos = event.position

		if is_click and is_instance_valid(camera):
			var world_click := camera.get_screen_center_position() - (get_viewport_rect().size * 0.5) + click_pos
			for door in current_room_data.exit_doors:
				if door.pos.distance_to(world_click) < 80.0:
					_enter_door(door)
					return


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
	glitch_layer.layer = 2
	glitch_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(glitch_layer)

	var back_buffer := BackBufferCopy.new()
	back_buffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	back_buffer.rect = Rect2(0, 0, 960, 540)
	glitch_layer.add_child(back_buffer)

	glitch_rect = ColorRect.new()
	glitch_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glitch_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader = load("res://shaders/glitch.gdshader")
	if shader:
		glitch_material = ShaderMaterial.new()
		glitch_material.shader = shader
		glitch_rect.material = glitch_material
		glitch_material.set_shader_parameter("glitch_intensity", 0.0)
	glitch_layer.add_child(glitch_rect)


func _init_vignette_layer() -> void:
	vignette_layer = CanvasLayer.new()
	vignette_layer.layer = 15 # Above world and glitch, below UI layer (20)
	vignette_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(vignette_layer)

	vignette_rect = ColorRect.new()
	vignette_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader = load("res://shaders/vignette.gdshader")
	if shader:
		vignette_material = ShaderMaterial.new()
		vignette_material.shader = shader
		vignette_rect.material = vignette_material
		vignette_material.set_shader_parameter("intensity", 0.0)
	vignette_layer.add_child(vignette_rect)


func _update_low_health_vignette(delta: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(vignette_material):
		return

	var p_health: int = player.health

	# Target intensity based on remaining player health:
	# >= 3: 0.0 (healthy, clear corners)
	# == 2: 0.38 (steady warning pulse)
	# == 1: 0.85 (intense frantic heartbeat pulse!)
	if p_health >= 3:
		vignette_target_intensity = 0.0
		vignette_pulse_speed = 3.5
	elif p_health == 2:
		vignette_target_intensity = 0.38
		vignette_pulse_speed = 3.8
	elif p_health == 1:
		vignette_target_intensity = 0.85
		vignette_pulse_speed = 6.2

	# Smooth decay / lerp toward target
	if vignette_intensity > vignette_target_intensity:
		vignette_intensity = maxf(vignette_target_intensity, vignette_intensity - delta * 2.2)
	else:
		vignette_intensity = lerpf(vignette_intensity, vignette_target_intensity, delta * 4.5)

	vignette_material.set_shader_parameter("intensity", vignette_intensity)
	vignette_material.set_shader_parameter("pulse_speed", vignette_pulse_speed)

	# Audio heartbeat rhythm when at critical 1 HP
	if p_health == 1 and not run_over and not get_tree().paused:
		heartbeat_timer += delta
		if heartbeat_timer >= 0.50: # 120 BPM heartbeat rhythm
			heartbeat_timer = 0.0
			if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
				get_node("/root/AudioSynth").play("heartbeat", 0.03, -3.0)


func _process(delta: float) -> void:
	var rs = get_node_or_null("/root/RunState")
	if not rs or run_over:
		return

	rs.run_time += delta
	if not get_tree().paused and not active_enemies.is_empty():
		sector_combat_time += delta

	# Update incoming hostile spawn telegraphs
	_update_spawn_telegraphs(delta)

	# Screen Trauma Shake Update
	if trauma > 0.0 and is_instance_valid(camera):
		trauma = maxf(0.0, trauma - TRAUMA_DECAY * delta)
		var shake := trauma * trauma
		camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * MAX_OFFSET * shake
		camera.rotation = randf_range(-1.0, 1.0) * MAX_ROLL * shake
	elif is_instance_valid(camera):
		camera.offset = Vector2.ZERO
		camera.rotation = 0.0

	# Glitch Post-Processing Decay (snappy cyber recovery)
	if glitch_pulse > 0.0:
		glitch_pulse = maxf(0.0, glitch_pulse - delta * 3.4)
		if is_instance_valid(glitch_material):
			glitch_material.set_shader_parameter("glitch_intensity", glitch_pulse)

	# Low Health Red Corner Vignette & Pulse Update
	_update_low_health_vignette(delta)

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
		elims_label.text = "ELIMS %02d  •  BITS %02d" % [rs.score, rs.bits]
		var sec_w: int = rs.progression.sector_waves_completed if (rs and rs.progression) else 0
		var sec_tw: int = rs.progression.sector_total_waves if (rs and rs.progression) else 3
		var total_r: int = rs.progression.rooms_per_sector if (rs and rs.progression) else rs.TOTAL_ROOMS
		var active_wave: int = mini(sec_w + 1, sec_tw)
		if rs and rs.waves_in_room > 1:
			sector_label.text = "SEC %d  •  RM %d/%d  •  WAVE %d/%d (SUB %d/%d)" % [rs.current_sector, rs.current_room_index + 1, total_r, active_wave, sec_tw, rs.current_wave, rs.waves_in_room]
		else:
			sector_label.text = "SEC %d  •  RM %d/%d  •  WAVE %d/%d" % [rs.current_sector, rs.current_room_index + 1, total_r, active_wave, sec_tw]

	# Update Boss Bar if in Boss room
	if boss_active and is_instance_valid(boss_ref):
		var pct: float = clampf(float(boss_ref.health) / float(maxi(1, boss_ref.max_health)), 0.0, 1.0)
		boss_bar_fill.size.x = 420.0 * pct
		if is_instance_valid(boss_bar_ghost):
			boss_bar_ghost.size.x = move_toward(boss_bar_ghost.size.x, boss_bar_fill.size.x, delta * 140.0)
		if is_instance_valid(boss_hp_label):
			boss_hp_label.text = "%d / %d HP" % [boss_ref.health, boss_ref.max_health]
	elif boss_vanguard_active:
		if is_instance_valid(boss_bar_container):
			boss_bar_container.visible = true
		boss_bar_bg.visible = true
		if is_instance_valid(boss_hp_label):
			boss_hp_label.text = "CORE SHIELDED // VANGUARD: %d HOSTILES" % active_enemies.size()
	elif boss_active and not is_instance_valid(boss_ref):
		if is_instance_valid(boss_bar_container):
			boss_bar_container.visible = false
		if is_instance_valid(boss_bar_bg):
			boss_bar_bg.visible = false

	# Contain all active combatants strictly inside the current chamber during lockdown
	if current_room_data and not active_door_barriers.is_empty():
		var rb: Rect2 = current_room_data.bounds
		var pad := 40.0
		for enemy in active_enemies:
			if is_instance_valid(enemy):
				if not rb.has_point(enemy.position):
					enemy.position.x = clampf(enemy.position.x, rb.position.x + pad, rb.end.x - pad)
					enemy.position.y = clampf(enemy.position.y, rb.position.y + pad, rb.end.y - pad)
					if "velocity" in enemy:
						enemy.velocity = Vector2.ZERO

	# Check Player Proximity to Unlocked Exit Doors / Floor Interactions
	if dungeon_layout and not dungeon_layout.corridors.is_empty():
		_check_floor_interactions(delta)
	elif doors_unlocked and not run_over and is_instance_valid(player) and current_room_data:
		for door in current_room_data.exit_doors:
			if player.position.distance_to(door.pos) < 55.0:
				_enter_door(door)
				break

	# Redraw arena for animated obstacle lights and effects
	queue_redraw()


func _check_floor_interactions(_delta: float) -> void:
	if not is_instance_valid(player) or run_over or not dungeon_layout:
		return

	var p_pos := player.position

	# 1. Exit Portal Check in final room
	if dungeon_layout.exit_portal_pos != Vector2.ZERO:
		if p_pos.distance_to(dungeon_layout.exit_portal_pos) < 55.0:
			var last_r: RefCounted = dungeon_layout.rooms.back()
			if last_r and (last_r.is_cleared or last_r.room_type != "BOSS"):
				_use_floor_exit_portal()
				return

	# 2. Identify which room the player is inside
	var inside_room: RefCounted = null
	for r in dungeon_layout.rooms:
		if r.bounds.has_point(p_pos):
			inside_room = r
			break

	if not inside_room:
		# Player is navigating a corridor
		return

	if inside_room != current_room_data:
		current_room_data = inside_room
		var rs = get_node_or_null("/root/RunState")
		if rs:
			rs.current_room_index = inside_room.index

	if not inside_room.is_cleared:
		if inside_room.room_type in ["COMBAT", "ELITE"] and active_enemies.is_empty() and active_door_barriers.is_empty():
			# Engage room combat lockdown
			_lock_room_doorways(inside_room)
			if nav_grid:
				nav_grid.build_grid(inside_room.bounds, obstacle_rects, 24.0)
			var rs = get_node_or_null("/root/RunState")
			if rs and rs.progression:
				rs.progression.calculate_waves_for_current_room(inside_room.room_type)
				rs.current_wave = rs.progression.current_wave
				rs.waves_in_room = rs.progression.waves_in_room
			damage_taken_this_sector = 0
			room_cleared = false
			_spawn_wave_enemies(1)
		elif inside_room.room_type == "BOSS" and not boss_active and not boss_vanguard_active and active_enemies.is_empty():
			_lock_room_doorways(inside_room)
			if nav_grid:
				nav_grid.build_grid(inside_room.bounds, obstacle_rects, 24.0)
			room_cleared = false
			_spawn_wave_enemies(1)
		elif inside_room.room_type == "RECOVERY":
			var f_center: Vector2 = inside_room.bounds.get_center()
			if p_pos.distance_to(f_center) < 70.0:
				inside_room.is_cleared = true
				var rs = get_node_or_null("/root/RunState")
				if rs:
					rs.heal(2)
				if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
					get_node("/root/AudioSynth").play("powerup_pickup", 0.0, 0.0)
				_show_director_banner("RECOVERY MEDBAY // +2 HP RESTORED", "Nanite biocircuits repaired.")
		elif inside_room.room_type == "SHOP":
			var s_center: Vector2 = inside_room.bounds.get_center()
			if p_pos.distance_to(s_center) < 70.0:
				inside_room.is_cleared = true
				_show_shop_interface()
		elif inside_room.room_type == "GIFT":
			var g_center: Vector2 = inside_room.bounds.get_center()
			if p_pos.distance_to(g_center) < 70.0:
				inside_room.is_cleared = true
				_show_gift_interface()


func _use_floor_exit_portal() -> void:
	if run_over:
		return
	var rs = get_node_or_null("/root/RunState")
	if not rs or not rs.progression:
		return

	# If the floor completion buff was not awarded yet, grant it before warping
	if not floor_buff_awarded:
		floor_buff_awarded = true
		_show_upgrade_draft(
			"FLOOR CLEARED // SELECT TACTICAL SUBROUTINE",
			"Install 1 passive subroutine buff before warping to next floor.",
			func(): _proceed_through_exit_portal()
		)
		return

	_proceed_through_exit_portal()


func _proceed_through_exit_portal() -> void:
	var rs = get_node_or_null("/root/RunState")
	if not rs or not rs.progression:
		return

	add_trauma(0.5)
	trigger_glitch(0.85)
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("powerup_pickup", 0.05, 3.0)

	var nav: Dictionary = rs.advance_room(dungeon_layout.rooms.size() - 1)
	if nav.get("is_new_biome", false):
		var next_b: int = rs.progression.current_biome
		var b_info: Dictionary = BIOME_DATA_SCRIPT.get_biome(next_b)
		_show_director_banner(
			"HYPERSPACE WARP // BIOME %d INGRESS" % next_b,
			"%s PROTOCOL INITIALIZED // %s" % [b_info.name.to_upper(), b_info.description.to_upper()]
		)
		dungeon_layout = null
		_load_room(0)
	elif nav.get("is_new_sector", false):
		var cur_sec: int = rs.progression.sector_index
		_show_director_banner("SECTOR ADVANCEMENT // SECTOR %d" % cur_sec, "Ingress route cleared. Staging on new sector floor.")
		dungeon_layout = null
		_load_room(0)
	else:
		dungeon_layout = null
		_load_room(0)


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
	var cur_biome_idx: int = rs.progression.current_biome if (rs and rs.progression) else (rs.current_biome if rs else 1)
	var biome: Dictionary = BIOME_DATA_SCRIPT.get_biome(cur_biome_idx)
	var tint: Color = biome.get("sector_tint", Color.CYAN)
	var ticks := Time.get_ticks_msec()
	var pulse := 0.75 + 0.25 * sin(float(ticks) * 0.005)

	if dungeon_layout and not dungeon_layout.corridors.is_empty():
		_draw_multi_room_floor(dungeon_layout, biome, ticks, pulse)
	else:
		_draw_single_room_arena(current_room_data, tint, ticks, pulse)

	# 3. Hand-authored obstacles with slate body, cyan top trim, and telemetry LEDs
	for r in obstacle_rects:
		if fountain_rect.size != Vector2.ZERO and r == fountain_rect:
			continue
		draw_rect(Rect2(r.position.x + 3.0, r.position.y + 4.0, r.size.x, r.size.y), Color(0.0, 0.0, 0.0, 0.55), true)
		draw_rect(r, Color("1e293b"), true)
		draw_rect(r, Color("334155"), false, 1.5)
		draw_line(r.position, Vector2(r.end.x, r.position.y), biome.get("accent", Color("38bdf8")), 2.0)

		# Blinking telemetry status LEDs on terminal
		var blink_g := int(ticks / 350.0) % 2 == 0
		var blink_r := int(ticks / 550.0) % 2 == 0
		draw_circle(r.position + Vector2(6, 6), 2.0, Color("22c55e") if blink_g else Color("14532d"))
		draw_circle(r.position + Vector2(13, 6), 2.0, Color("ef4444") if blink_r else Color("7f1d1d"))

	# 4. Exit Doors & Holographic Route Signs (if in single room mode)
	if (not dungeon_layout or dungeon_layout.corridors.is_empty()) and current_room_data and not current_room_data.exit_doors.is_empty():
		_draw_exit_doors(current_room_data, ticks, pulse)

	# 5. Off-screen hostile radar chevrons at viewport bounds
	_draw_radar_chevrons()

	# 6. Incoming Enemy Spawn Telegraph Reticles
	_draw_spawn_telegraphs(ticks)


func _draw_multi_room_floor(layout: RefCounted, biome: Dictionary, ticks: int, pulse: float) -> void:
	var bg_floor_col: Color = biome.get("floor_color", Color("080c16"))
	var grid_color: Color = biome.get("grid_color", Color(0.0, 0.94, 1.0, 0.22))
	var wall_glow: Color = biome.get("wall_glow", Color("00f0ff"))
	var wall_inner: Color = biome.get("wall_inner", Color(0.04, 0.10, 0.18, 0.95))

	# 1. Draw Corridors
	for c in layout.corridors:
		draw_rect(c, bg_floor_col, true)
		for gx in range(int(c.position.x), int(c.end.x), 48):
			draw_line(Vector2(gx, c.position.y), Vector2(gx, c.end.y), grid_color, 1.0)
		for gy in range(int(c.position.y), int(c.end.y), 48):
			draw_line(Vector2(c.position.x, gy), Vector2(c.end.x, gy), grid_color, 1.0)
		if c.size.x > c.size.y:
			draw_line(Vector2(c.position.x, c.position.y), Vector2(c.end.x, c.position.y), wall_inner, 5.0)
			draw_line(Vector2(c.position.x, c.position.y), Vector2(c.end.x, c.position.y), wall_glow, 2.0)
			draw_line(Vector2(c.position.x, c.end.y), Vector2(c.end.x, c.end.y), wall_inner, 5.0)
			draw_line(Vector2(c.position.x, c.end.y), Vector2(c.end.x, c.end.y), wall_glow, 2.0)
		else:
			draw_line(Vector2(c.position.x, c.position.y), Vector2(c.position.x, c.end.y), wall_inner, 5.0)
			draw_line(Vector2(c.position.x, c.position.y), Vector2(c.position.x, c.end.y), wall_glow, 2.0)
			draw_line(Vector2(c.end.x, c.position.y), Vector2(c.end.x, c.end.y), wall_inner, 5.0)
			draw_line(Vector2(c.end.x, c.position.y), Vector2(c.end.x, c.end.y), wall_glow, 2.0)

	# 2. Draw Rooms
	for r in layout.rooms:
		var b: Rect2 = r.bounds
		draw_rect(b, bg_floor_col, true)
		for gx in range(int(b.position.x), int(b.end.x), 64):
			draw_line(Vector2(gx, b.position.y), Vector2(gx, b.end.y), grid_color, 1.0)
		for gy in range(int(b.position.y), int(b.end.y), 64):
			draw_line(Vector2(b.position.x, gy), Vector2(b.end.x, gy), grid_color, 1.0)
		_draw_chamfered_room_outline(b, wall_inner, wall_glow)
		_draw_room_emblem(r.room_type, b.get_center(), pulse, b)

	# 3. Draw Doorway Thresholds & Lockdown Laser Barriers
	for d_dict in layout.doorways:
		var d_rect: Rect2 = d_dict.get("rect", Rect2())
		var r_idx: int = int(d_dict.get("room_idx", -1))
		var is_locked: bool = false
		if current_room_data and current_room_data.index == r_idx and not active_door_barriers.is_empty():
			is_locked = true
		if is_locked:
			var laser_pulse := 0.7 + 0.3 * sin(float(ticks) * 0.012)
			draw_rect(d_rect, Color(0.95, 0.2, 0.2, 0.35 * laser_pulse), true)
			if d_rect.size.x < d_rect.size.y:
				draw_line(Vector2(d_rect.get_center().x, d_rect.position.y), Vector2(d_rect.get_center().x, d_rect.end.y), Color("ef4444"), 4.0)
				draw_line(Vector2(d_rect.get_center().x, d_rect.position.y), Vector2(d_rect.get_center().x, d_rect.end.y), Color.WHITE, 1.5)
			else:
				draw_line(Vector2(d_rect.position.x, d_rect.get_center().y), Vector2(d_rect.end.x, d_rect.get_center().y), Color("ef4444"), 4.0)
				draw_line(Vector2(d_rect.position.x, d_rect.get_center().y), Vector2(d_rect.end.x, d_rect.get_center().y), Color.WHITE, 1.5)
		else:
			if d_rect.size.x < d_rect.size.y:
				for dy in range(int(d_rect.position.y), int(d_rect.end.y), 16):
					draw_circle(Vector2(d_rect.get_center().x, dy + 8), 2.5, wall_glow * 0.7)
			else:
				for dx in range(int(d_rect.position.x), int(d_rect.end.x), 16):
					draw_circle(Vector2(dx + 8, d_rect.get_center().y), 2.5, wall_glow * 0.7)

	# 4. Draw Exit Portal in Exit Room (if not boss floor)
	if layout.exit_portal_pos != Vector2.ZERO:
		var last_r: RefCounted = layout.rooms.back()
		if last_r and (last_r.is_cleared or last_r.room_type != "BOSS"):
			_draw_exit_portal(layout.exit_portal_pos, pulse, biome.get("portal_color", Color.CYAN))


func _draw_single_room_arena(room_data: RefCounted, tint: Color, _ticks: int, pulse: float) -> void:
	var active_bounds: Rect2 = room_data.bounds if room_data else ROOM_RECT
	draw_rect(active_bounds, Color("080c16"), true)
	var grid_color := Color(0.12, 0.18, 0.28, 0.45) * tint
	grid_color.a = 0.35
	for x in range(int(active_bounds.position.x), int(active_bounds.end.x), 64):
		draw_line(Vector2(x, active_bounds.position.y), Vector2(x, active_bounds.end.y), grid_color, 1.0)
	for y in range(int(active_bounds.position.y), int(active_bounds.end.y), 64):
		draw_line(Vector2(active_bounds.position.x, y), Vector2(active_bounds.end.x, y), grid_color, 1.0)
	_draw_chamfered_room_outline(active_bounds, Color(0.01, 0.02, 0.04, 0.95), Color("00f0ff"))
	if room_data:
		_draw_room_emblem(room_data.room_type, active_bounds.get_center(), pulse, active_bounds)


func _draw_chamfered_room_outline(active_bounds: Rect2, wall_inner: Color, wall_glow: Color, c_inset: float = 36.0) -> void:
	var poly_pts := PackedVector2Array([
		Vector2(active_bounds.position.x + c_inset, active_bounds.position.y),
		Vector2(active_bounds.end.x - c_inset, active_bounds.position.y),
		Vector2(active_bounds.end.x, active_bounds.position.y + c_inset),
		Vector2(active_bounds.end.x, active_bounds.end.y - c_inset),
		Vector2(active_bounds.end.x - c_inset, active_bounds.end.y),
		Vector2(active_bounds.position.x + c_inset, active_bounds.end.y),
		Vector2(active_bounds.position.x, active_bounds.end.y - c_inset),
		Vector2(active_bounds.position.x, active_bounds.position.y + c_inset)
	])
	var poly_closed := PackedVector2Array(poly_pts)
	poly_closed.append(poly_pts[0])

	draw_polyline(poly_closed, wall_inner, 6.0, true)
	draw_polyline(poly_closed, wall_glow, 2.5, true)
	draw_rect(active_bounds, wall_glow * 0.15, false, 1.0)
	for pt in poly_pts:
		draw_circle(pt, 3.5, wall_glow)
		draw_circle(pt, 1.5, Color.WHITE)


func _draw_room_emblem(r_type: String, center_pt: Vector2, pulse: float, bounds: Rect2) -> void:
	match r_type:
		"START":
			# Ingress airlock staging dock
			draw_circle(center_pt, 48.0, Color(0.0, 0.0, 0.0, 0.60))
			draw_circle(center_pt, 44.0, Color(0.04, 0.14, 0.24, 0.85))
			draw_arc(center_pt, 44.0, 0.0, TAU, 36, Color("38bdf8"), 2.5)
			draw_arc(center_pt, 30.0, 0.0, TAU, 28, Color("67e8f9"), 1.5)
			draw_circle(center_pt, 14.0 * pulse, Color("38bdf8"))
			draw_circle(center_pt, 4.0, Color.WHITE)
			for i in range(4):
				var a := float(i) * TAU / 4.0
				draw_line(center_pt + Vector2(cos(a), sin(a)) * 16.0, center_pt + Vector2(cos(a), sin(a)) * 32.0, Color("38bdf8"), 2.0)

		"RECOVERY":
			# Glowing Green Medical Cross
			draw_circle(center_pt, 56.0, Color(0.0, 0.0, 0.0, 0.60))
			draw_circle(center_pt, 52.0, Color(0.02, 0.18, 0.10, 0.90))
			draw_arc(center_pt, 52.0, 0.0, TAU, 36, Color("22c55e"), 3.0)
			draw_arc(center_pt, 38.0, 0.0, TAU, 28, Color("4ade80"), 1.5)
			var arm_w := 14.0
			var arm_len := 42.0
			draw_rect(Rect2(center_pt.x - arm_w * 0.5, center_pt.y - arm_len * 0.5, arm_w, arm_len), Color("22c55e"), true)
			draw_rect(Rect2(center_pt.x - arm_len * 0.5, center_pt.y - arm_w * 0.5, arm_len, arm_w), Color("22c55e"), true)
			draw_rect(Rect2(center_pt.x - arm_w * 0.5 + 2, center_pt.y - arm_len * 0.5 + 2, arm_w - 4, arm_len - 4), Color.WHITE, true)
			draw_rect(Rect2(center_pt.x - arm_len * 0.5 + 2, center_pt.y - arm_w * 0.5 + 2, arm_len - 4, arm_w - 4), Color.WHITE, true)

		"SHOP":
			# Glowing Cyan Shopping Cart Emblem
			draw_circle(center_pt, 52.0, Color(0.0, 0.0, 0.0, 0.60))
			draw_circle(center_pt, 48.0, Color(0.02, 0.14, 0.22, 0.90))
			draw_arc(center_pt, 48.0, 0.0, TAU, 36, Color("00f0ff"), 3.0)
			var s_col := Color("00f0ff")
			draw_line(center_pt + Vector2(-16, -10), center_pt + Vector2(10, -10), s_col, 3.0)
			draw_line(center_pt + Vector2(10, -10), center_pt + Vector2(6, 8), s_col, 3.0)
			draw_line(center_pt + Vector2(6, 8), center_pt + Vector2(-12, 8), s_col, 3.0)
			draw_line(center_pt + Vector2(-12, 8), center_pt + Vector2(-16, -10), s_col, 3.0)
			draw_line(center_pt + Vector2(10, -10), center_pt + Vector2(16, -16), s_col, 3.0)
			draw_circle(center_pt + Vector2(-8, 14), 3.5, s_col)
			draw_circle(center_pt + Vector2(6, 14), 3.5, s_col)

		"GIFT":
			# Glowing Purple Diamond Emblem
			draw_circle(center_pt, 52.0, Color(0.0, 0.0, 0.0, 0.60))
			draw_circle(center_pt, 48.0, Color(0.12, 0.05, 0.22, 0.90))
			draw_arc(center_pt, 48.0, 0.0, TAU, 36, Color("c084fc"), 3.0)
			var d_pts := PackedVector2Array([
				center_pt + Vector2(0, -22),
				center_pt + Vector2(20, 0),
				center_pt + Vector2(0, 22),
				center_pt + Vector2(-20, 0)
			])
			draw_colored_polygon(d_pts, Color(0.75, 0.52, 0.98, 0.40))
			var d_closed := PackedVector2Array(d_pts)
			d_closed.append(d_pts[0])
			draw_polyline(d_closed, Color("c084fc"), 3.0)
			draw_circle(center_pt, 6.0 * pulse, Color.WHITE)

		"COMBAT", "ELITE":
			var h_col := Color("ef4444") if r_type == "ELITE" else Color(0.85, 0.25, 0.25, 0.45)
			for h_x in range(int(bounds.position.x + 80), int(bounds.end.x - 80), 120):
				var h_rect := Rect2(h_x, bounds.position.y + 12.0, 48.0, 10.0)
				draw_rect(h_rect, Color(0.1, 0.02, 0.02, 0.8), true)
				draw_rect(h_rect, h_col, false, 1.2)
				for s in range(0, 48, 12):
					draw_line(Vector2(h_rect.position.x + s, h_rect.position.y), Vector2(h_rect.position.x + s + 8, h_rect.end.y), h_col, 1.5)
				var b_rect := Rect2(h_x, bounds.end.y - 22.0, 48.0, 10.0)
				draw_rect(b_rect, Color(0.1, 0.02, 0.02, 0.8), true)
				draw_rect(b_rect, h_col, false, 1.2)
				for s in range(0, 48, 12):
					draw_line(Vector2(b_rect.position.x + s, b_rect.position.y), Vector2(b_rect.position.x + s + 8, b_rect.end.y), h_col, 1.5)

		"BOSS":
			# Boss Overlord Dais with pulsating red concentric rings & runes
			draw_circle(center_pt, 64.0, Color(0.0, 0.0, 0.0, 0.65))
			draw_circle(center_pt, 60.0, Color(0.18, 0.04, 0.06, 0.90))
			draw_arc(center_pt, 60.0, 0.0, TAU, 48, Color("ef4444"), 3.0)
			draw_arc(center_pt, 44.0, 0.0, TAU, 36, Color("f43f5e"), 2.0)
			draw_circle(center_pt, 16.0 * pulse, Color("ef4444"))
			draw_circle(center_pt, 6.0, Color.WHITE)
			for i in range(8):
				var a := float(i) * TAU / 8.0
				draw_line(center_pt + Vector2(cos(a), sin(a)) * 24.0, center_pt + Vector2(cos(a), sin(a)) * 48.0, Color("ef4444"), 2.0)


func _draw_exit_portal(pos: Vector2, pulse: float, portal_col: Color) -> void:
	var ticks := Time.get_ticks_msec()
	var spin := float(ticks) * 0.003
	draw_circle(pos, 42.0, Color(0.0, 0.0, 0.0, 0.65))
	draw_arc(pos, 38.0, 0.0, TAU, 32, portal_col * 0.6, 2.0)
	draw_arc(pos, 28.0, spin, spin + TAU * 0.75, 24, portal_col, 3.5)
	draw_arc(pos, 18.0, -spin * 1.5, -spin * 1.5 + TAU * 0.75, 20, Color.WHITE, 2.0)
	draw_circle(pos, 12.0 * pulse, portal_col)
	draw_circle(pos, 4.0, Color.WHITE)


func _draw_exit_doors(room_data: RefCounted, ticks: int, pulse: float) -> void:

	# 3. Hand-authored obstacles with slate body, cyan top trim, and telemetry LEDs
	for r in obstacle_rects:
		if fountain_rect.size != Vector2.ZERO and r == fountain_rect:
			continue
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
	var rdata: RefCounted = room_data if room_data else current_room_data
	if rdata and not rdata.exit_doors.is_empty():
		for door in rdata.exit_doors:
			var d_pos: Vector2 = door.pos
			var door_rect := Rect2(d_pos.x - 14.0, d_pos.y - 36.0, 28.0, 72.0)
			var ttype: String = door.get("target_type", "COMBAT")
			var cat: String = door.get("category", "")
			var up_title: String = door.get("upgrade_title", "")
			var up_desc: String = door.get("upgrade_desc", "")

			if not doors_unlocked:
				# Locked laser barrier with diagonal hazard warning stripes
				draw_rect(door_rect, Color(0.12, 0.04, 0.04, 0.85), true)
				draw_rect(door_rect, Color("ef4444"), false, 2.0)
				draw_line(door_rect.position, door_rect.end, Color(0.9, 0.2, 0.2, 0.6), 1.5)
				draw_line(Vector2(door_rect.end.x, door_rect.position.y), Vector2(door_rect.position.x, door_rect.end.y), Color(0.9, 0.2, 0.2, 0.6), 1.5)
				draw_circle(d_pos, 3.5, Color("ef4444"))
			else:
				# Unlocked pulsating cyber portal with route color cues
				var d_pulse := 0.75 + 0.25 * sin(float(ticks) * 0.006)
				var d_col := Color("38bdf8")
				if cat == "WEAPON":
					d_col = Color("06b6d4")
				elif cat == "MOBILITY":
					d_col = Color("eab308")
				elif cat == "DEFENSE":
					d_col = Color("22c55e")
				elif cat == "STATUS":
					d_col = Color("c084fc")
				elif cat == "SURVIVAL" or cat == "HEAL" or ttype == "RECOVERY":
					d_col = Color("10b981")
				elif cat == "REWARD" or ttype == "SHOP":
					d_col = Color("f59e0b")
				elif cat == "BOSS" or ttype == "BOSS" or cat == "GATEWAY" or ttype == "NEXT_SECTOR":
					d_col = Color("ec4899")

				draw_rect(door_rect, Color(d_col.r * 0.15, d_col.g * 0.15, d_col.b * 0.15, 0.9), true)
				draw_rect(door_rect, Color(d_col.r, d_col.g, d_col.b, d_pulse), false, 2.5)
				draw_circle(d_pos, 10.0 * d_pulse, Color(d_col.r, d_col.g, d_col.b, 0.4 * d_pulse))
				draw_circle(d_pos, 4.0, Color("ffffff"))

				# Forward directional chevron
				draw_line(Vector2(d_pos.x - 6, d_pos.y - 10), Vector2(d_pos.x + 4, d_pos.y), Color(d_col.r, d_col.g, d_col.b, d_pulse), 2.0)
				draw_line(Vector2(d_pos.x + 4, d_pos.y), Vector2(d_pos.x - 6, d_pos.y + 10), Color(d_col.r, d_col.g, d_col.b, d_pulse), 2.0)

				# Dotted laser threshold across doorway entry (reference map style)
				for dy in range(int(door_rect.position.y), int(door_rect.end.y), 8):
					draw_line(Vector2(door_rect.position.x - 6, dy), Vector2(door_rect.position.x - 2, dy), Color(d_col.r, d_col.g, d_col.b, d_pulse), 2.0)

				# Holographic route badge on floor to left of door
				var tag_w := 210.0
				var tag_h := 32.0
				var tag_rect := Rect2(d_pos.x - tag_w - 20.0, d_pos.y - tag_h * 0.5, tag_w, tag_h)
				draw_rect(tag_rect, Color(0.02, 0.03, 0.07, 0.90), true)
				draw_rect(tag_rect, Color(d_col.r, d_col.g, d_col.b, 0.85 * pulse), false, 1.5)
				var font := ThemeDB.fallback_font
				if font:
					var display_title: String = up_title if up_title != "" else door.get("label", "GATE")
					var rarity: String = door.get("rarity", "")
					if rarity != "" and door.get("upgrade_id", "") != "":
						display_title = "%s // %s" % [rarity, display_title]
					var display_desc: String = up_desc if up_desc != "" else ""
					if display_desc != "":
						draw_string(font, tag_rect.position + Vector2(6, 13), "[ %s ]" % display_title, HORIZONTAL_ALIGNMENT_LEFT, int(tag_w - 12), 11, Color(d_col.r, d_col.g, d_col.b, 1.0))
						draw_string(font, tag_rect.position + Vector2(6, 26), display_desc, HORIZONTAL_ALIGNMENT_LEFT, int(tag_w - 12), 9, Color(0.85, 0.9, 0.95, 0.85))
					else:
						draw_string(font, tag_rect.position + Vector2(6, 20), display_title, HORIZONTAL_ALIGNMENT_LEFT, int(tag_w - 12), 11, Color(d_col.r, d_col.g, d_col.b, 1.0))

func _draw_radar_chevrons() -> void:
	if is_instance_valid(camera) and not active_enemies.is_empty():
		var half_w := 456.0
		var half_h := 246.0
		for enemy in active_enemies:
			if is_instance_valid(enemy):
				var delta_pos: Vector2 = enemy.global_position - camera.position
				if absf(delta_pos.x) > half_w or absf(delta_pos.y) > half_h:
					var angle: float = delta_pos.angle()
					var edge_dir := Vector2(cos(angle), sin(angle))
					var scale_x: float = half_w / maxf(0.001, absf(edge_dir.x))
					var scale_y: float = half_h / maxf(0.001, absf(edge_dir.y))
					var scale_factor: float = minf(scale_x, scale_y)
					var indicator_pos: Vector2 = camera.position + edge_dir * (scale_factor - 14.0)

					var col := Color("f43f5e") # Chaser crimson
					if enemy.is_in_group("dashers") or "dasher" in enemy.name.to_lower():
						col = Color("c084fc")
					elif enemy.is_in_group("shooters") or "shooter" in enemy.name.to_lower():
						col = Color("facc15")
					elif enemy.is_in_group("bosses") or "boss" in enemy.name.to_lower():
						col = Color("ec4899")

					var tip: Vector2 = indicator_pos + edge_dir * 8.0
					var left_wing: Vector2 = indicator_pos - edge_dir * 6.0 + edge_dir.orthogonal() * 6.0
					var right_wing: Vector2 = indicator_pos - edge_dir * 6.0 - edge_dir.orthogonal() * 6.0
					draw_colored_polygon(PackedVector2Array([tip, left_wing, right_wing]), col)
					draw_polyline(PackedVector2Array([left_wing, tip, right_wing]), Color("ffffff"), 1.2)


func _draw_spawn_telegraphs(ticks: int) -> void:
	if pending_spawn_telegraphs.is_empty():
		return

	var font: Font = ThemeDB.fallback_font
	for t in pending_spawn_telegraphs:
		var pos: Vector2 = t.pos
		var r: float = t.radius
		var col: Color = t.color
		var progress: float = clampf(1.0 - (t.time_left / t.time_total), 0.0, 1.0)
		var t_left: float = maxf(0.0, t.time_left)

		# 1. Subtle landing zone circular fill & perimeter
		draw_circle(pos, r, Color(col.r, col.g, col.b, 0.08 + 0.06 * progress))
		draw_arc(pos, r, 0.0, TAU, 32, Color(col.r, col.g, col.b, 0.35 + 0.15 * sin(ticks * 0.01)), 1.5)

		# 2. Dynamic contracting countdown ring
		var cur_r: float = lerpf(r * 1.85, r, progress)
		draw_arc(pos, cur_r, 0.0, TAU, 36, Color(col.r, col.g, col.b, 0.75 + 0.25 * progress), 2.2)

		# 3. Rotating central crosshair & pulsing core
		var core_r: float = 4.0 + 2.0 * sin(ticks * 0.015)
		draw_circle(pos, core_r, Color(col.r, col.g, col.b, 0.7))
		var rot_a: float = ticks * 0.002
		for a_step in range(4):
			var a: float = rot_a + a_step * (PI * 0.5)
			var dir := Vector2(cos(a), sin(a))
			draw_line(pos + dir * 6.0, pos + dir * minf(16.0, r * 0.65), col, 1.2)

		# 4. Tactical corner brackets framing spawn location
		var b: float = r * 1.08
		var br_len: float = 7.0
		var bracket_col := Color(col.r, col.g, col.b, 0.9)
		# Top-Left
		draw_line(pos + Vector2(-b, -b), pos + Vector2(-b + br_len, -b), bracket_col, 1.5)
		draw_line(pos + Vector2(-b, -b), pos + Vector2(-b, -b + br_len), bracket_col, 1.5)
		# Top-Right
		draw_line(pos + Vector2(b, -b), pos + Vector2(b - br_len, -b), bracket_col, 1.5)
		draw_line(pos + Vector2(b, -b), pos + Vector2(b, -b + br_len), bracket_col, 1.5)
		# Bottom-Left
		draw_line(pos + Vector2(-b, b), pos + Vector2(-b + br_len, b), bracket_col, 1.5)
		draw_line(pos + Vector2(-b, b), pos + Vector2(-b, b - br_len), bracket_col, 1.5)
		# Bottom-Right
		draw_line(pos + Vector2(b, b), pos + Vector2(b - br_len, b), bracket_col, 1.5)
		draw_line(pos + Vector2(b, b), pos + Vector2(b, b - br_len), bracket_col, 1.5)

		# 5. Threat Identification Tag & Countdown Pill
		if font:
			var full_label: String = "[ ! ] %s (%.1fs)" % [t.label, t_left]
			var text_sz: Vector2 = font.get_string_size(full_label, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
			var text_x := pos.x - text_sz.x * 0.5
			var text_y := pos.y - r - 12.0
			var pill_rect := Rect2(text_x - 6.0, text_y - 10.0, text_sz.x + 12.0, 15.0)
			draw_rect(pill_rect, Color(0.04, 0.08, 0.14, 0.88), true)
			draw_rect(pill_rect, Color(col.r, col.g, col.b, 0.85), false, 1.0)
			draw_string(font, Vector2(text_x, text_y + 1.0), full_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)


func _create_walls(room_rect: Rect2 = ROOM_RECT) -> void:
	for w in active_walls:
		if is_instance_valid(w):
			w.queue_free()
	active_walls.clear()

	if dungeon_layout and not dungeon_layout.corridors.is_empty():
		_create_floor_walls(dungeon_layout)
		return

	var center_x := room_rect.position.x + room_rect.size.x * 0.5
	var center_y := room_rect.position.y + room_rect.size.y * 0.5

	_add_wall(Vector2(center_x, room_rect.position.y - 10.0), Vector2(room_rect.size.x + 40.0, 20.0))
	_add_wall(Vector2(center_x, room_rect.end.y + 10.0), Vector2(room_rect.size.x + 40.0, 20.0))
	_add_wall(Vector2(room_rect.position.x - 10.0, center_y), Vector2(20.0, room_rect.size.y + 40.0))
	_add_wall(Vector2(room_rect.end.x + 10.0, center_y), Vector2(20.0, room_rect.size.y + 40.0))


func _create_floor_walls(layout: RefCounted) -> void:
	# 1. Build walls along corridors
	for c in layout.corridors:
		if c.size.x > c.size.y:
			# Horizontal corridor: top & bottom walls
			_add_wall(Vector2(c.get_center().x, c.position.y - 10.0), Vector2(c.size.x, 20.0))
			_add_wall(Vector2(c.get_center().x, c.end.y + 10.0), Vector2(c.size.x, 20.0))
		else:
			# Vertical corridor: left & right walls
			_add_wall(Vector2(c.position.x - 10.0, c.get_center().y), Vector2(20.0, c.size.y))
			_add_wall(Vector2(c.end.x + 10.0, c.get_center().y), Vector2(20.0, c.size.y))

	# 2. Build walls around each room, leaving doorways open
	for r in layout.rooms:
		var b: Rect2 = r.bounds
		var doors: Array[Rect2] = r.doorway_rects

		# Top edge
		var top_doors: Array[Rect2] = []
		for d in doors:
			if abs(d.position.y - b.position.y) < 30.0 or abs(d.get_center().y - b.position.y) < 30.0:
				top_doors.append(d)
		if top_doors.is_empty():
			_add_wall(Vector2(b.get_center().x, b.position.y - 10.0), Vector2(b.size.x + 20.0, 20.0))
		else:
			top_doors.sort_custom(func(d1, d2): return d1.position.x < d2.position.x)
			var cur_x := b.position.x
			for td in top_doors:
				if td.position.x > cur_x + 10.0:
					var w_len := td.position.x - cur_x
					_add_wall(Vector2(cur_x + w_len * 0.5, b.position.y - 10.0), Vector2(w_len, 20.0))
				cur_x = td.end.x
			if b.end.x > cur_x + 10.0:
				var w_len := b.end.x - cur_x
				_add_wall(Vector2(cur_x + w_len * 0.5, b.position.y - 10.0), Vector2(w_len, 20.0))

		# Bottom edge
		var bot_doors: Array[Rect2] = []
		for d in doors:
			if abs(d.position.y - b.end.y) < 30.0 or abs(d.get_center().y - b.end.y) < 30.0:
				bot_doors.append(d)
		if bot_doors.is_empty():
			_add_wall(Vector2(b.get_center().x, b.end.y + 10.0), Vector2(b.size.x + 20.0, 20.0))
		else:
			bot_doors.sort_custom(func(d1, d2): return d1.position.x < d2.position.x)
			var cur_x := b.position.x
			for bd in bot_doors:
				if bd.position.x > cur_x + 10.0:
					var w_len := bd.position.x - cur_x
					_add_wall(Vector2(cur_x + w_len * 0.5, b.end.y + 10.0), Vector2(w_len, 20.0))
				cur_x = bd.end.x
			if b.end.x > cur_x + 10.0:
				var w_len := b.end.x - cur_x
				_add_wall(Vector2(cur_x + w_len * 0.5, b.end.y + 10.0), Vector2(w_len, 20.0))

		# Left edge
		var left_doors: Array[Rect2] = []
		for d in doors:
			if abs(d.position.x - b.position.x) < 30.0 or abs(d.get_center().x - b.position.x) < 30.0:
				left_doors.append(d)
		if left_doors.is_empty():
			_add_wall(Vector2(b.position.x - 10.0, b.get_center().y), Vector2(20.0, b.size.y + 20.0))
		else:
			left_doors.sort_custom(func(d1, d2): return d1.position.y < d2.position.y)
			var cur_y := b.position.y
			for ld in left_doors:
				if ld.position.y > cur_y + 10.0:
					var w_len := ld.position.y - cur_y
					_add_wall(Vector2(b.position.x - 10.0, cur_y + w_len * 0.5), Vector2(20.0, w_len))
				cur_y = ld.end.y
			if b.end.y > cur_y + 10.0:
				var w_len := b.end.y - cur_y
				_add_wall(Vector2(b.position.x - 10.0, cur_y + w_len * 0.5), Vector2(20.0, w_len))

		# Right edge
		var right_doors: Array[Rect2] = []
		for d in doors:
			if abs(d.position.x - b.end.x) < 30.0 or abs(d.get_center().x - b.end.x) < 30.0:
				right_doors.append(d)
		if right_doors.is_empty():
			_add_wall(Vector2(b.end.x + 10.0, b.get_center().y), Vector2(20.0, b.size.y + 20.0))
		else:
			right_doors.sort_custom(func(d1, d2): return d1.position.y < d2.position.y)
			var cur_y := b.position.y
			for rd in right_doors:
				if rd.position.y > cur_y + 10.0:
					var w_len := rd.position.y - cur_y
					_add_wall(Vector2(b.end.x + 10.0, cur_y + w_len * 0.5), Vector2(20.0, w_len))
				cur_y = rd.end.y
			if b.end.y > cur_y + 10.0:
				var w_len := b.end.y - cur_y
				_add_wall(Vector2(b.end.x + 10.0, cur_y + w_len * 0.5), Vector2(20.0, w_len))


func _lock_room_doorways(room: RefCounted) -> void:
	_unlock_room_doorways()
	for d in room.doorway_rects:
		var barrier := StaticBody2D.new()
		barrier.position = d.get_center()
		barrier.collision_layer = 1
		barrier.collision_mask = 0
		var shape_node := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = d.size
		shape_node.shape = shape
		barrier.add_child(shape_node)
		add_child(barrier)
		active_door_barriers.append(barrier)
	queue_redraw()


func _unlock_room_doorways() -> void:
	for b in active_door_barriers:
		if is_instance_valid(b):
			b.queue_free()
	active_door_barriers.clear()
	queue_redraw()


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
	active_walls.append(wall)


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


func _add_fountain_obstacle(pos: Vector2, radius: float = 44.0) -> void:
	var obstacle := StaticBody2D.new()
	obstacle.name = "FountainObstacle"
	obstacle.position = pos
	obstacle.collision_layer = 1
	obstacle.collision_mask = 0
	var shape_node := CollisionShape2D.new()
	shape_node.name = "CollisionShape2D"
	var shape := CircleShape2D.new()
	shape.radius = radius
	shape_node.shape = shape
	obstacle.add_child(shape_node)
	add_child(obstacle)
	active_obstacles.append(obstacle)
	fountain_center = pos
	fountain_radius = radius
	fountain_rect = Rect2(pos.x - radius, pos.y - radius, radius * 2.0, radius * 2.0)
	obstacle_rects.append(fountain_rect)


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
	elif current == 0:
		ammo_label.text = "EMPTY [TAP RELOAD]"
		ammo_label.add_theme_color_override("font_color", Color("ef4444"))
	else:
		ammo_label.text = "CELLS %02d/%02d" % [current, maximum]
		if current <= 3:
			ammo_label.add_theme_color_override("font_color", Color("f97316"))
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

	# Glitch triggers ONLY when the player is hurt!
	trigger_glitch(0.85)
	add_trauma(0.40)

	# Red glow impact spike on screen corners
	vignette_intensity = minf(1.0, vignette_intensity + 0.55)

	# Floating damage indicator on player
	if is_instance_valid(player):
		spawn_damage_number(player.global_position, "-%d" % amount, Color("f43f5e"))


func _on_player_shot_fired() -> void:
	if tracker:
		tracker.record_shot_fired()


func _on_player_shot_hit(enemy: Node2D) -> void:
	if tracker:
		tracker.record_shot_hit()
	if is_instance_valid(enemy):
		var rs = get_node_or_null("/root/RunState")
		var dmg: int = 1 + (rs.damage_bonus if rs else 0)
		spawn_damage_number(enemy.global_position, "%d" % dmg, Color("38bdf8"))


func spawn_damage_number(pos: Vector2, text: String, col: Color = Color("38bdf8")) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.global_position = pos + Vector2(randf_range(-12.0, 12.0), randf_range(-18.0, -8.0))
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", col)
	lbl.z_index = 50
	add_child(lbl)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(lbl, "position:y", lbl.position.y - 28.0, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.45).set_ease(Tween.EASE_IN).set_delay(0.12)
	tween.chain().tween_callback(lbl.queue_free)


func _load_room(index: int) -> void:
	room_cleared = false
	doors_unlocked = false
	boss_active = false
	boss_ref = null
	pending_spawn_telegraphs.clear()
	if index == 0:
		floor_buff_awarded = false
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
	fountain_rect = Rect2()
	fountain_center = Vector2.ZERO

	for child in get_children():
		if child.is_in_group("projectiles") or child.has_method("_on_body_entered"):
			child.queue_free()

	active_enemies.clear()
	if spatial_index:
		spatial_index.clear()
	if squad_coordinator:
		squad_coordinator.reset()

	var rs_node = get_node_or_null("/root/RunState") if is_inside_tree() else null
	var sec_seed: int = rs_node.progression.get_current_sector_seed() if (rs_node and rs_node.progression) else (rs_node.current_seed if rs_node else 1337)
	var room_count: int = rs_node.progression.rooms_per_sector if (rs_node and rs_node.progression) else 12

	if not dungeon_layout or dungeon_layout.rooms.is_empty():
		var wave_count: int = rs_node.progression.sector_total_waves if (rs_node and rs_node.progression) else 3
		dungeon_layout = dungeon_generator.generate_dungeon(
			sec_seed,
			room_count,
			wave_count,
			true,
			rs_node.progression.difficulty if rs_node.progression else rs_node.difficulty,
			rs_node.progression.sector_index if rs_node.progression else rs_node.current_sector
		)
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
		current_room_data.exit_doors.append({
			"pos": door_pos,
			"target_room": index + 1,
			"target_type": "COMBAT",
			"upgrade_id": "",
			"upgrade_title": "CONTINUE",
			"upgrade_desc": "Proceed to the next encounter",
			"category": "ROUTE",
			"rarity": "",
			"label": "[ CONTINUE ] // PROCEED TO NEXT ENCOUNTER"
		})
		current_room_data.exit_door = door_pos

	boss_active = false
	boss_vanguard_active = false
	boss_ref = null
	if is_instance_valid(boss_bar_container):
		boss_bar_container.visible = false
	if is_instance_valid(boss_bar_bg):
		boss_bar_bg.visible = false

	# Position player at designated reachable spawn
	if is_instance_valid(player):
		player.position = current_room_data.player_spawn
		if is_instance_valid(camera):
			camera.position = player.position
			camera.reset_smoothing()

	# Dynamically create boundary walls for room bounds
	_create_walls(current_room_data.bounds if current_room_data else ROOM_RECT)

	# Place procedural obstacle geometry
	if dungeon_layout and not dungeon_layout.corridors.is_empty():
		for rm in dungeon_layout.rooms:
			for r in rm.obstacles:
				_add_obstacle(r.get_center(), r.size)
			if rm.room_type in ["START", "RECOVERY"]:
				var f_center: Vector2 = rm.bounds.get_center()
				_add_fountain_obstacle(f_center, 44.0)
	else:
		for r in current_room_data.obstacles:
			_add_obstacle(r.get_center(), r.size)
		if current_room_data and current_room_data.room_type in ["START", "RECOVERY"]:
			var f_center: Vector2 = current_room_data.bounds.get_center()
			_add_fountain_obstacle(f_center, 44.0)

	if nav_grid:
		nav_grid.build_grid(current_room_data.bounds if current_room_data else ROOM_RECT, obstacle_rects, 24.0)

	# Service chambers are safe traversal/reward stops, not extra combat waves.
	if current_room_data.room_type in ["START", "RECOVERY", "SHOP", "GIFT"]:
		_handle_non_wave_room(current_room_data.room_type)
		queue_redraw()
		_update_debug_overlay()
		return

	# Setup 3–5 combat waves for combat chambers
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
	var rs_node = get_node_or_null("/root/RunState") if is_inside_tree() else null
	match room_type:
		"START":
			var cur_sec: int = rs_node.progression.sector_index if (rs_node and rs_node.progression) else 1
			_show_director_banner(
				"CALIBRATION DOCK // SECTOR %d STAGING" % cur_sec,
				"SAFE STAGING AREA // SELECT AN INGRESS ROUTE"
			)
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
		var rarity: String = item.get("rarity", "COMMON")
		var can_afford: bool = rs != null and rs.bits >= cost
		var is_capped: bool = rs != null and rs.get_upgrade_stack_count(item_id) >= rs.get_upgrade_stack_cap(item_id)

		var status_text := "COST: %d BITS" % cost
		if is_capped:
			status_text = "[ FULLY STACKED ]"
		elif not can_afford:
			status_text = "COST: %d BITS (HAVE %d)" % [cost, (rs.bits if rs else 0)]

		card.text = "\n[ SHOP // %s ]\n%s // %s\n\n%s\n\n%s" % [
			title,
			rarity,
			status_text,
			desc,
			"Tap to purchase" if (can_afford and not is_capped) else "Unavailable"
		]
		card.disabled = not can_afford or is_capped
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.pressed.connect(func():
			if rs and rs.bits >= cost and not is_capped:
				rs.spend_bits(cost)
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
		var rarity: String = dungeon_generator.get_upgrade_rarity(item_id) if dungeon_generator else "COMMON"
		card.text = "\n[ CACHE // %s ]\n%s // FREE UPGRADE\n(STACK %d/%d)\n\nTap to extract subroutine." % [item_id, rarity, stack_count, stack_cap]
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


func _schedule_spawn_telegraph(
	pos: Vector2,
	enemy_type: String,
	label: String,
	radius: float,
	color: Color,
	spawn_callback: Callable,
	duration: float = 1.0
) -> void:
	pending_spawn_telegraphs.append({
		"pos": pos,
		"type": enemy_type,
		"label": label,
		"radius": radius,
		"color": color,
		"time_total": duration,
		"time_left": duration,
		"callback": spawn_callback
	})


func _update_spawn_telegraphs(delta: float) -> void:
	if pending_spawn_telegraphs.is_empty() or run_over or (is_inside_tree() and get_tree().paused):
		return

	var finished_indices: Array[int] = []
	for i in range(pending_spawn_telegraphs.size()):
		var t = pending_spawn_telegraphs[i]
		t.time_left -= delta
		if t.time_left <= 0.0:
			finished_indices.append(i)

	for i in range(finished_indices.size() - 1, -1, -1):
		var idx: int = finished_indices[i]
		var t = pending_spawn_telegraphs[idx]
		pending_spawn_telegraphs.remove_at(idx)
		if t.callback.is_valid():
			t.callback.call()
		if is_inside_tree():
			DEBRIS_EMITTER_SCRIPT.spawn_shards(self, t.pos, t.color, "diamond", 6)
			add_trauma(0.12)
			if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
				get_node("/root/AudioSynth").play("mutation_alert", 0.04, 2.5)


func _spawn_wave_enemies(wave_num: int) -> void:
	var rs_node = get_node_or_null("/root/RunState")
	var profile: Dictionary = tracker.get_profile() if tracker else {}
	var p_hp: int = player.health if is_instance_valid(player) else 5
	var p_max: int = player.max_health if is_instance_valid(player) else 5
	var spawn_budget: int = rs_node.progression.calculate_spawn_budget(wave_num) if (rs_node and rs_node.progression) else current_room_data.enemy_spawns.size()
	if current_room_data.room_type in ["COMBAT", "ELITE"]:
		spawn_budget = maxi(3, spawn_budget)
	if current_room_data.room_type == "ELITE":
		spawn_budget = mini(9, spawn_budget + 2)
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
	if spawns_to_create.is_empty() and current_room_data.room_type in ["COMBAT", "ELITE"]:
		# Do not silently skip a normal-room encounter if a future roster or AI
		# filter rejects every generated entry. Keep the room in a playable state.
		push_warning("Encounter roster was empty in sector %d room %d; using emergency chasers." % [
			rs_node.progression.sector_index if (rs_node and rs_node.progression) else 1,
			current_room_data.index
		])
		var emergency_offsets: Array[Vector2] = [Vector2(240.0, -180.0), Vector2(420.0, 180.0), Vector2(650.0, -60.0)]
		for enemy_index in range(mini(3, spawn_budget)):
			var emergency_pos: Vector2 = current_room_data.player_spawn + emergency_offsets[enemy_index]
			emergency_pos.x = clampf(emergency_pos.x, current_room_data.bounds.position.x + 100.0, current_room_data.bounds.end.x - 100.0)
			emergency_pos.y = clampf(emergency_pos.y, current_room_data.bounds.position.y + 100.0, current_room_data.bounds.end.y - 100.0)
			var eg = encounter_director.evolution_manager.get_genome_for_spawn("CHASER") if (encounter_director and encounter_director.evolution_manager) else null
			spawns_to_create.append({"type": "CHASER", "pos": emergency_pos, "flank_angle": 0.0, "genome": eg})
	# Boss rooms must never silently become ordinary empty/regular encounters if
	# encounter composition or budget filtering changes later.
	if current_room_data.room_type == "BOSS":
		var contains_boss := false
		for spawn in spawns_to_create:
			if spawn.type == "BOSS":
				contains_boss = true
				boss_spawn_pos = spawn.pos
				break
		if not contains_boss:
			boss_spawn_pos = Vector2(current_room_data.bounds.position.x + current_room_data.bounds.size.x * 0.70, current_room_data.bounds.get_center().y)

		# Phase 0: Security Vanguard Escort
		# The player must first defeat the security vanguard escort before the boss core unshields and spawns!
		boss_vanguard_active = true
		boss_active = false

		if boss_director and rs_node:
			var cur_sector: int = rs_node.progression.sector_index if rs_node.progression else 1
			var cur_seed: int = rs_node.current_seed if rs_node else 1337
			var last_id: String = boss_director.last_scheduled_boss_id if boss_director else ""
			current_boss_def = boss_director.select_boss_for_sector(cur_sector, cur_seed, last_id)

		var b_name: String = current_boss_def.display_name.to_upper() if current_boss_def else "NEXUS OVERLORD"
		boss_label.text = "[ BOSS // %s - CORE SHIELDED ]" % b_name
		boss_bar_fill.color = Color("475569")
		boss_bar_fill.size.x = 420.0
		if is_instance_valid(boss_hp_label):
			boss_hp_label.text = "SECURITY VANGUARD ACTIVE"
		if is_instance_valid(boss_bar_container):
			boss_bar_container.visible = true
		boss_bar_bg.visible = true

		_show_director_banner("ALERT // %s PERIMETER" % b_name, "Core shielded. Eliminate vanguard escort hostiles to unseal the Overlord!")

		# Spawn 3 vanguard escort combatants with evolved genomes
		var vanguard_specs := [
			{"scene": CHASER_SCENE, "type": "CHASER", "offset": Vector2(-120.0, -90.0), "flank": 0.50},
			{"scene": SHOOTER_SCENE, "type": "SHOOTER", "offset": Vector2(60.0, 0.0), "flank": 0.0},
			{"scene": DASHER_SCENE, "type": "DASHER", "offset": Vector2(-120.0, 90.0), "flank": 0.0}
		]
		for v in vanguard_specs:
			var v_pos: Vector2 = boss_spawn_pos + v.offset
			v_pos.x = clampf(v_pos.x, current_room_data.bounds.position.x + 80.0, current_room_data.bounds.end.x - 80.0)
			v_pos.y = clampf(v_pos.y, current_room_data.bounds.position.y + 80.0, current_room_data.bounds.end.y - 80.0)
			var v_scene: PackedScene = v.scene
			var v_type: String = v.type
			var v_flank: float = v.flank
			var spd_m: float = encounter.enemy_speed_mult * 1.05
			var tel_m: float = encounter.enemy_telegraph_mult
			var lead_v = encounter.shooter_lead
			_schedule_spawn_telegraph(
				v_pos,
				v_type,
				"VANGUARD %s" % v_type,
				34.0,
				Color("f97316"),
				func():
					var v_enemy = _spawn_enemy(v_scene, v_pos, spd_m, tel_m, v_flank, lead_v)
					if v_enemy and encounter_director and encounter_director.evolution_manager:
						var v_genome = encounter_director.evolution_manager.get_genome_for_spawn(v_type)
						if v_genome:
							v_genome.apply_to_enemy(v_enemy)
							encounter_director.evolution_manager.register_spawned_combatant(v_genome)
			)
		return

	for espawn in spawns_to_create:
		var stype: String = espawn.type
		var pos: Vector2 = espawn.pos
		var flank: float = espawn.flank_angle
		var genome: RefCounted = espawn.genome

		if stype == "BOSS":
			_schedule_spawn_telegraph(
				pos,
				"BOSS",
				"OVERLORD NEXUS",
				60.0,
				Color("ef4444"),
				func(): _spawn_boss(pos)
			)
		else:
			var scene: PackedScene = CHASER_SCENE
			var col: Color = Color("ef4444")
			if stype == "SHOOTER":
				scene = SHOOTER_SCENE
				col = Color("a855f7")
			elif stype == "DASHER":
				scene = DASHER_SCENE
				col = Color("eab308")

			var spd_m: float = encounter.enemy_speed_mult
			var tel_m: float = encounter.enemy_telegraph_mult
			var lead_v = encounter.shooter_lead
			_schedule_spawn_telegraph(
				pos,
				stype,
				stype,
				32.0,
				col,
				func():
					var enemy = _spawn_enemy(
						scene,
						pos,
						spd_m,
						tel_m,
						flank,
						lead_v,
						false
					)
					if genome and enemy:
						genome.apply_to_enemy(enemy)
						encounter_director.evolution_manager.register_spawned_combatant(genome)
			)


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
	if "nav_grid" in boss:
		boss.nav_grid = nav_grid
	if "obstacle_rects" in boss:
		boss.obstacle_rects = obstacle_rects
	if spatial_index:
		spatial_index.register_agent(boss)

	var is_mid: bool = rs_node.progression.is_mid_boss_encounter() if (rs_node and rs_node.progression) else false
	if "is_mid_boss" in boss:
		boss.is_mid_boss = is_mid

	# Assign returning mutations with trade-offs
	current_boss_mutations = boss_director.get_mutations_for_encounter(current_boss_def.boss_id) if (boss_director and current_boss_def) else []
	if boss.has_method("apply_mutations") and not current_boss_mutations.is_empty():
		boss.apply_mutations(current_boss_mutations)

	boss.connect("defeated", Callable(self, "_on_enemy_defeated").bind(boss))
	if boss.has_signal("phase_two_entered"):
		boss.connect("phase_two_entered", Callable(self, "_on_boss_phase_two_entered").bind(boss))
	add_child(boss)
	active_enemies.append(boss)
	boss_ref = boss
	boss_active = true

	# Update Boss Bar appearance
	var title_prefix := "MID-SECTOR OVERLORD" if is_mid else "BIOME FINAL OVERLORD"
	if current_boss_def:
		boss_label.text = "[ %s // %s ]" % [title_prefix, current_boss_def.display_name.to_upper()]
		boss_bar_fill.color = current_boss_def.accent_color
	else:
		boss_label.text = "[ %s // NEXUS OVERLORD ]" % title_prefix
		boss_bar_fill.color = Color("f43f5e")

	if is_instance_valid(boss_hp_label):
		boss_hp_label.text = "%d / %d HP" % [boss.health, boss.max_health]
	if is_instance_valid(boss_bar_ghost):
		boss_bar_ghost.size.x = 420.0
	boss_bar_fill.size.x = 420.0

	if is_instance_valid(boss_bar_container):
		boss_bar_container.visible = true
	boss_bar_bg.visible = true
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


func _on_boss_phase_two_entered(boss: Node2D) -> void:
	add_trauma(0.70)
	trigger_glitch(1.0)
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("boss_alarm", 0.08, 2.0)

	var b_name: String = current_boss_def.display_name.to_upper() if current_boss_def else "NEXUS OVERLORD"
	boss_label.text = "[ BOSS // %s - PHASE 2 (OVERLOAD) ]" % b_name
	boss_bar_fill.color = Color("ef4444")
	boss_bar_fill.size.x = 420.0
	if is_instance_valid(boss_bar_ghost):
		boss_bar_ghost.size.x = 420.0
	if is_instance_valid(boss_hp_label):
		boss_hp_label.text = "%d / %d HP" % [boss.health, boss.max_health]

	_show_director_banner("CRITICAL EVOLUTION // PHASE 2 ENGAGED", "Overlord overclocked! Reaction speed accelerated! Reinforcements arriving!")

	# Spawn reinforcement minions during Phase 2
	call_deferred("_spawn_phase_two_reinforcements", boss.global_position)


func _spawn_phase_two_reinforcements(boss_pos: Vector2) -> void:
	if not is_instance_valid(player) or run_over:
		return
	var minion_types: Array[PackedScene] = [CHASER_SCENE, SHOOTER_SCENE]
	var minion_fams: Array[String] = ["CHASER", "SHOOTER"]
	var offsets: Array[Vector2] = [Vector2(-130.0, -80.0), Vector2(-130.0, 80.0)]
	for i in range(2):
		var m_pos: Vector2 = boss_pos + offsets[i]
		if current_room_data:
			m_pos.x = clampf(m_pos.x, current_room_data.bounds.position.x + 80.0, current_room_data.bounds.end.x - 80.0)
			m_pos.y = clampf(m_pos.y, current_room_data.bounds.position.y + 80.0, current_room_data.bounds.end.y - 80.0)
		var m_scene: PackedScene = minion_types[i]
		var m_fam: String = minion_fams[i]
		var flank: float = 0.4 if i == 0 else 0.0
		var col: Color = Color("f43f5e") if m_fam == "CHASER" else Color("a855f7")
		_schedule_spawn_telegraph(
			m_pos,
			m_fam,
			"OVERLOAD MINION: %s" % m_fam,
			32.0,
			col,
			func():
				var enemy = _spawn_enemy(m_scene, m_pos, 1.15, 0.85, flank, 0.5)
				if enemy and encounter_director and encounter_director.evolution_manager:
					var g = encounter_director.evolution_manager.get_genome_for_spawn(m_fam)
					if g:
						g.apply_to_enemy(enemy)
						encounter_director.evolution_manager.register_spawned_combatant(g)
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
	var spawn_pos := pos
	if current_room_data:
		var pad := 65.0
		var rb: Rect2 = current_room_data.bounds
		spawn_pos.x = clampf(spawn_pos.x, rb.position.x + pad, rb.end.x - pad)
		spawn_pos.y = clampf(spawn_pos.y, rb.position.y + pad, rb.end.y - pad)
	enemy.position = spawn_pos
	if "target" in enemy:
		enemy.target = player
	if "spatial_index" in enemy:
		enemy.spatial_index = spatial_index
	if "squad_coordinator" in enemy:
		enemy.squad_coordinator = squad_coordinator
	if "obstacle_rects" in enemy:
		enemy.obstacle_rects = obstacle_rects
	if "nav_grid" in enemy:
		enemy.nav_grid = nav_grid
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
	var rs = get_node_or_null("/root/RunState")
	var is_boss_core := enemy_node == boss_ref
	var bits_reward := 2 if current_room_data and current_room_data.room_type == "ELITE" else 1
	if is_boss_core:
		bits_reward = 20 + mini(current_boss_mutations.size(), 4) * 5
	if rs:
		rs.on_enemy_eliminated(bits_reward)
	active_enemies.erase(enemy_node)
	if spatial_index:
		spatial_index.unregister_agent(enemy_node)
	if squad_coordinator:
		squad_coordinator.release_attack_token(enemy_node)

	# If Vanguard Escort is cleared, unseal and spawn the Boss Core!
	if boss_vanguard_active and active_enemies.is_empty() and pending_spawn_telegraphs.is_empty():
		boss_vanguard_active = false
		var b_name: String = current_boss_def.display_name.to_upper() if current_boss_def else "NEXUS OVERLORD"
		_show_director_banner("SECURITY BREACH // %s UNSEALED" % b_name, "Vanguard escort neutralized! Core exposed! Engaging Phase 1.")
		add_trauma(0.55)
		trigger_glitch(0.85)
		if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
			get_node("/root/AudioSynth").play("boss_alarm", 0.0, 0.0)
		_schedule_spawn_telegraph(
			boss_spawn_pos,
			"BOSS",
			"%s CORE" % b_name,
			55.0,
			Color("ef4444"),
			func(): _spawn_boss(boss_spawn_pos),
			1.2
		)
		return

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
			var is_mid: bool = rs_node.progression.is_mid_boss_encounter() if rs_node.progression else false
			var is_final: bool = rs_node.progression.is_final_boss_encounter() if rs_node.progression else false
			if is_mid:
				_show_director_banner("MID-SECTOR OVERLORD PURGED // " + current_boss_def.display_name, "+%d BITS • +3 REPAIR CELLS // SECTOR GATE ACTIVATED" % bits_reward)
			elif is_final:
				_show_director_banner("BIOME FINAL OVERLORD PURGED // " + current_boss_def.display_name, "+%d BITS // HYPERSPACE WARP PORTAL CHARGED!" % bits_reward)
			else:
				_show_director_banner("NEXUS CORE PURGED // " + current_boss_def.display_name, "+%d BITS • +3 REPAIR CELLS // GATEWAY UNLOCKED" % bits_reward)
			if current_room_data:
				current_room_data.is_cleared = true
			_unlock_room_doorways()

	DEBRIS_EMITTER_SCRIPT.spawn_shards(self, enemy_node.global_position, shard_color, shard_type, 9)
	add_trauma(0.18)
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("hit_impact", 0.12, -2.0)

	if active_enemies.is_empty() and pending_spawn_telegraphs.is_empty() and not room_cleared:
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
			current_sector_tactic,
			tracker
		)
		rs.set_evolution_log(encounter_director.evolution_manager.evolution_history)

	# If hostiles evolved, flash alert banner and play mutation audio
	if not new_adaptations.is_empty():
		var first_adap: Dictionary = new_adaptations[0]
		var f_name: String = first_adap.get("family", "HOSTILE")
		var t_num: int = first_adap.get("tier", 1)
		var m_name: String = first_adap.get("mutation", "OVERCLOCK")
		var h_mult: String = first_adap.get("health_mult", "2x HP")
		add_trauma(0.35)
		if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
			get_node("/root/AudioSynth").play("mutation_alert", 0.0, 0.0)
		_show_director_banner(
			"HOSTILE SPECIES EVOLVED // %s [TIER %d]" % [f_name, t_num],
			"%s (%s) • %s" % [m_name.replace("_", " "), h_mult, first_adap.get("tradeoff", "Hostiles learned from previous battles.")]
		)

	# In GLITCH//RUN multi-room floors, buffs are awarded only upon floor completion!
	if dungeon_layout and not dungeon_layout.corridors.is_empty():
		if current_room_data:
			current_room_data.is_cleared = true
		_unlock_room_doorways()
		var is_floor_finish: bool = current_room_data and (current_room_data.room_type == "BOSS" or current_room_data.index >= dungeon_layout.rooms.size() - 1)
		if is_floor_finish and not floor_buff_awarded:
			floor_buff_awarded = true
			_show_upgrade_draft(
				"FLOOR CLEARED // SELECT TACTICAL SUBROUTINE",
				"Sector floor neutralized. Install 1 passive subroutine buff before warping."
			)
		else:
			_show_director_banner("CHAMBER CLEARED // CORRIDORS UNSEALED", "Hostile signatures eliminated. Navigation route open.")
	else:
		_unlock_exit_doors()


func _show_upgrade_draft(
	header_text: String = "FLOOR CLEARED // SELECT TACTICAL SUBROUTINE",
	sub_text: String = "Sector floor neutralized. Install 1 passive subroutine buff before advancing.",
	on_complete: Callable = Callable()
) -> void:
	glitch_pulse = 0.0
	if is_instance_valid(glitch_material):
		glitch_material.set_shader_parameter("glitch_intensity", 0.0)
	if touch_controls:
		touch_controls.enabled = false
	get_tree().paused = true
	post_upgrade_callback = on_complete

	if is_instance_valid(draft_header_label):
		draft_header_label.text = header_text
	if is_instance_valid(draft_sub_label):
		draft_sub_label.text = sub_text

	var rs = get_node("/root/RunState")
	var choices: Array = rs.get_random_upgrade_choices(3)

	for child in upgrade_cards_box.get_children():
		child.queue_free()

	for item in choices:
		var card := Button.new()
		card.custom_minimum_size = Vector2(230, 210)
		var rarity: String = item.get("rarity", "COMMON")
		if item.id == "FIELD_REPAIR":
			card.text = "\n[ %s ]\n%s\n\n%s\n\n\"%s\"" % [item.title, rarity, item.desc, item.flavor]
		else:
			var stack_count: int = rs.get_upgrade_stack_count(item.id) + 1
			var stack_cap: int = rs.get_upgrade_stack_cap(item.id)
			card.text = "\n[ %s ]\n%s • STACK %d / %d\n\n%s\n\n\"%s\"" % [item.title, rarity, stack_count, stack_cap, item.desc, item.flavor]
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

	if post_upgrade_callback.is_valid():
		var cb := post_upgrade_callback
		post_upgrade_callback = Callable()
		cb.call()
		return

	# Unlock exit doors or unseal corridors
	if not dungeon_layout or dungeon_layout.corridors.is_empty():
		_unlock_exit_doors()
	else:
		_show_director_banner("SUBROUTINE INSTALLED // [ %s ]" % upgrade_id, "Warp portal active. Step through to proceed to the next floor.")


func _unlock_exit_doors() -> void:
	doors_unlocked = true
	var rs = get_node_or_null("/root/RunState") if is_inside_tree() else null
	if rs and current_room_data:
		# Ensure doors never offer an upgrade that is already at stack cap
		for door in current_room_data.exit_doors:
			var uid: String = door.get("upgrade_id", "")
			if uid != "" and uid != "BOSS" and uid != "NEXT_SECTOR" and uid != "SECTOR_GATE" and uid != "RECOVERY" and uid != "DATA_BITS" and uid != "FIELD_REPAIR":
				var cap: int = rs.get_upgrade_stack_cap(uid)
				if cap > 0 and rs.get_upgrade_stack_count(uid) >= cap:
					var alts = rs.get_random_upgrade_choices(1)
					if not alts.is_empty():
						var alt = alts[0]
						door.upgrade_id = alt.id
						door.upgrade_title = alt.title
						door.upgrade_desc = alt.desc
						door.label = "[ %s ] // %s" % [alt.title, alt.desc.to_upper()]
	queue_redraw()
	_show_director_banner("CHAMBER SECURED // ROUTE DOORS UNLOCKED", "Step into any forward gate to acquire its subroutine upgrade.")


func _enter_door(door: Dictionary) -> void:
	if not doors_unlocked or run_over:
		return
	doors_unlocked = false

	var rs = get_node_or_null("/root/RunState")
	if not rs:
		return

	var up_id: String = door.get("upgrade_id", "")
	var up_title: String = door.get("upgrade_title", "")
	var up_desc: String = door.get("upgrade_desc", "")

	if up_id == "RECOVERY":
		rs.heal(2)
		if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
			get_node("/root/AudioSynth").play("powerup_pickup", 0.0, 0.0)
		_show_director_banner("RECOVERY BAY // +2 HP RESTORED", "Nanite biocircuits patched.")
	elif up_id == "DATA_BITS":
		rs.add_bits(35)
		if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
			get_node("/root/AudioSynth").play("powerup_pickup", 0.0, 0.0)
		_show_director_banner("DATA CACHE RECOVERED // +35 BITS", "Currency loaded into tactical buffer.")
	elif up_id != "" and up_id != "BOSS" and up_id != "SECTOR_GATE" and up_id != "NEXT_SECTOR":
		var applied = rs.apply_upgrade(up_id)
		if not applied and up_id != "FIELD_REPAIR":
			rs.apply_upgrade("FIELD_REPAIR")
			up_title = "FIELD REPAIR"
			up_desc = "+1 HP Restored"
		if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
			get_node("/root/AudioSynth").play("powerup_pickup", 0.0, 0.0)
		_show_director_banner("SUBROUTINE INSTALLED // [ %s ]" % up_title, up_desc)
	elif door.get("target_type") == "BOSS":
		add_trauma(0.35)
		if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
			get_node("/root/AudioSynth").play("boss_alarm", 0.0, 0.0)
		_show_director_banner("WARNING: OVERLORD CORE // NEXUS ENGAGED", "Extreme hostile signature detected.")

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
			current_sector_tactic,
			tracker
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
	if encounter_director:
		encounter_director.reset()
	if tracker:
		tracker.reset()
	var rs = get_node_or_null("/root/RunState")
	if rs:
		rs.current_seed = 0
	get_tree().reload_current_scene()


func _return_to_main_menu() -> void:
	get_tree().paused = false
	if encounter_director:
		encounter_director.reset()
	if tracker:
		tracker.reset()
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
	elims_label.text = "ELIMS 00  •  BITS 00"
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
	draft_header.text = "FLOOR CLEARED // SELECT TACTICAL SUBROUTINE"
	draft_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	draft_header.add_theme_color_override("font_color", Color("38bdf8"))
	draft_header.add_theme_font_size_override("font_size", 22)
	draft_vbox.add_child(draft_header)
	draft_header_label = draft_header

	var draft_sub := Label.new()
	draft_sub.text = "Sector floor neutralized. Install 1 passive subroutine buff before advancing."
	draft_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	draft_sub.add_theme_color_override("font_color", Color("94a3b8"))
	draft_sub.add_theme_font_size_override("font_size", 14)
	draft_vbox.add_child(draft_sub)
	draft_sub_label = draft_sub

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
