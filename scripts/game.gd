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
const MINIMAP_HUD_SCRIPT := preload("res://scripts/minimap_hud.gd")
const DEBRIEF_TERMINAL_SCRIPT := preload("res://scripts/debrief_terminal.gd")
const MENU_BACKDROP_SCRIPT := preload("res://scripts/menu_backdrop.gd")
const MENU_SKIN := preload("res://scripts/menu_ui_skin.gd")
const MENU_GLITCH_SCRIPT := preload("res://scripts/menu_glitch_overlay.gd")
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
var boss_spawn_initiated := false
var boss_spawn_pos := Vector2.ZERO
var active_walls: Array[StaticBody2D] = []
var active_secret_walls: Array[StaticBody2D] = []
const SECRET_WALL_SCRIPT := preload("res://scripts/secret_wall.gd")
var active_acid_puddles: Array[Dictionary] = []
const DESTRUCTIBLE_PROP_SCRIPT := preload("res://scripts/destructible_prop.gd")
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
var health_label: Label
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
var minimap_hud: Control
var debrief_terminal: Control
var special_menu_glitch: CanvasLayer
var shop_cooldown: float = 0.0
var shop_zone_armed: bool = true
var medbay_full_hp_cooldown: float = 0.0
var acid_burn_timer: float = 0.0

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
var banner_tween: Tween
var camera_pulse_tween: Tween
var transition_layer: CanvasLayer
var transition_cover: ColorRect
var room_transition_active := false
var has_loaded_room := false

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

	# Generate a reproducible but floor-specific procedural dungeon layout.
	var first_floor_rooms: int = rs.progression.rooms_per_sector if rs.progression else rs.TOTAL_ROOMS
	var first_floor_waves: int = rs.progression.sector_total_waves if rs.progression else 3
	var is_boss_fl: bool = rs.progression.is_boss_floor() if rs.progression else true
	dungeon_layout = dungeon_generator.generate_dungeon(
		rs.progression.get_current_floor_seed() if rs.progression else rs.current_seed,
		first_floor_rooms,
		first_floor_waves,
		true,
		rs.progression.difficulty if rs.progression else rs.difficulty,
		rs.progression.sector_index if rs.progression else rs.current_sector,
		is_boss_fl
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
	_init_transition_layer()
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
	# Direct touch selection on unlocked doors (single-room arena fallback only, when room is cleared)
	var is_multi_room: bool = dungeon_layout != null and not dungeon_layout.corridors.is_empty()
	if not is_multi_room and doors_unlocked and room_cleared and active_enemies.is_empty() and pending_spawn_telegraphs.is_empty() and not run_over and current_room_data and is_instance_valid(player):
		var click_pos := Vector2.ZERO
		var is_touch := false
		if event is InputEventScreenTouch and event.pressed:
			is_touch = true
			click_pos = event.position

		if is_touch and is_instance_valid(camera):
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
			banner_timer = -1.0
			_hide_director_banner()

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

	# Update active toxic acid puddles
	if not active_acid_puddles.is_empty():
		for p_idx in range(active_acid_puddles.size() - 1, -1, -1):
			var puddle: Dictionary = active_acid_puddles[p_idx]
			puddle["timer"] = puddle.get("timer", 1.0) - delta
			var p_pos: Vector2 = puddle.get("pos", Vector2.ZERO)
			var p_rad: float = puddle.get("radius", 60.0)
			for enemy in active_enemies:
				if is_instance_valid(enemy) and p_pos.distance_to(enemy.global_position) <= p_rad:
					if enemy.has_method("take_damage") and randf() < delta * 1.5:
						enemy.take_damage(1)
					if enemy.has_method("apply_debuff"):
						enemy.apply_debuff("ACID", 1.0)
			if puddle.get("timer", 0.0) <= 0.0:
				active_acid_puddles.remove_at(p_idx)
		queue_redraw()

	if shop_cooldown > 0.0:
		shop_cooldown -= delta

	# Environmental slide on Ice, damage in Toxic Acid pools, and heat in Magma vents
	if is_instance_valid(player) and current_room_data and rs and rs.progression:
		var p_pos := player.global_position
		var cur_b_id: int = rs.progression.current_biome
		var b_conf: Dictionary = BIOME_DATA_SCRIPT.get_biome(cur_b_id)
		if b_conf.get("hazard_type", "") == "ICE":
			if player.velocity.length() > 20.0:
				player.position += player.velocity.normalized() * 32.0 * delta
		elif b_conf.get("hazard_type", "") == "LAVA":
			var vent_c: Vector2 = current_room_data.bounds.get_center()
			if p_pos.distance_to(vent_c) <= 45.0:
				var l_pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.007)
				if l_pulse > 0.88 and randf() < delta * 1.2:
					player.take_damage(1)
					add_trauma(0.35)

		# Explicit chamber floor hazards (Blue Ice Slicks, Green Acid Vats, Magma Vents)
		if "hazards" in current_room_data and current_room_data.hazards is Array:
			var on_acid := false
			for h in current_room_data.hazards:
				var h_rect: Rect2 = h.get("rect", Rect2())
				var h_type: String = h.get("type", "ACID")
				if h_rect.has_point(p_pos):
					match h_type:
						"ICE":
							# Blue box: Low-friction cryogenic slick gives speed boost & smooth slide
							if player.velocity.length() > 15.0:
								player.position += player.velocity.normalized() * 48.0 * delta
							if randf() < delta * 3.0:
								DEBRIS_EMITTER_SCRIPT.spawn_shards(self, p_pos, Color("7dd3fc"), "diamond", 2)
						"ACID", "TOXIC":
							# Green box: Toxic caustic waste pool damages player if lingering
							on_acid = true
							acid_burn_timer += delta
							if acid_burn_timer >= 1.0:
								acid_burn_timer = 0.0
								player.take_damage(1)
								add_trauma(0.25)
								trigger_glitch(0.35)
								if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
									get_node("/root/AudioSynth").play("hit_impact", 0.03, -2.5)
						"LAVA":
							var l_pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.007)
							if l_pulse > 0.85 and randf() < delta * 1.5:
								player.take_damage(1)
								add_trauma(0.35)

				# Enemies caught inside hazard patches
				for enemy in active_enemies:
					if is_instance_valid(enemy) and h_rect.has_point(enemy.global_position):
						if h_type in ["ACID", "TOXIC"]:
							if enemy.has_method("take_damage") and randf() < delta * 2.0:
								enemy.take_damage(1)
							if enemy.has_method("apply_debuff"):
								enemy.apply_debuff("ACID", 1.0)
						elif h_type == "ICE":
							if "velocity" in enemy and enemy.velocity.length() > 10.0:
								enemy.position += enemy.velocity.normalized() * 24.0 * delta
			if not on_acid:
				acid_burn_timer = maxf(0.0, acid_burn_timer - delta * 2.0)

	# Update Top HUD Hearts & Badges with Biome, Sector, Floor (FL X/Y), and Room
	if is_instance_valid(player):
		_update_hud_hearts()
		elims_label.text = "ELIMS %02d  •  BITS %02d" % [rs.score, rs.bits]
		var total_r: int = rs.progression.rooms_per_sector if (rs and rs.progression) else rs.TOTAL_ROOMS
		var cur_b: int = rs.progression.current_biome if (rs and rs.progression) else 1
		var cur_f: int = rs.progression.current_floor if (rs and rs.progression) else 1
		var tot_f: int = rs.progression.total_floors_in_sector if (rs and rs.progression) else 3
		var boss_tag := ""
		if rs and rs.progression and rs.progression.is_boss_floor():
			boss_tag = " [MID-BOSS]" if rs.progression.is_mid_boss_encounter() else " [OVERLORD]"
		var wave_text := " • W%d/%d" % [rs.current_wave, rs.waves_in_room] if rs and rs.waves_in_room > 1 else ""
		var boss_text := " • BOSS" if boss_tag != "" else ""
		sector_label.text = "B%d / S%d  •  F%d/%d  •  R%d/%d%s%s" % [cur_b, rs.current_sector, cur_f, tot_f, rs.current_room_index + 1, total_r, wave_text, boss_text]

	# Update Minimap HUD
	if is_instance_valid(minimap_hud) and rs:
		minimap_hud.update_map(rs.dungeon_layout_summary, rs.current_room_index, player)

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
	elif doors_unlocked and room_cleared and active_enemies.is_empty() and pending_spawn_telegraphs.is_empty() and not run_over and is_instance_valid(player) and current_room_data:
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
			if last_r and (last_r.is_cleared or last_r.room_type in ["EXTRACT", "START"] or (last_r.room_type == "BOSS" and room_cleared)):
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
		if inside_room.room_type in ["START", "SHOP", "RECOVERY", "GIFT", "CACHE", "SHRINE", "TRANSIT", "EXTRACT", "SECRET"]:
			doors_unlocked = true
			if inside_room.room_type in ["START", "EXTRACT"]:
				inside_room.is_cleared = true
		else:
			doors_unlocked = false

	medbay_full_hp_cooldown = maxf(0.0, medbay_full_hp_cooldown - _delta)

	# Shop Kiosk interaction (re-enterable while inside the SHOP chamber)
	if inside_room.room_type == "SHOP":
		var s_center: Vector2 = inside_room.bounds.get_center()
		var dist: float = p_pos.distance_to(s_center)
		if dist > 115.0:
			shop_zone_armed = true
		if dist < 85.0 and shop_zone_armed and shop_cooldown <= 0.0 and not upgrade_container.visible:
			inside_room.is_cleared = true
			shop_zone_armed = false
			_show_shop_interface()

	if not inside_room.is_cleared:
		if inside_room.room_type in ["COMBAT", "ELITE"] and active_enemies.is_empty() and active_door_barriers.is_empty():
			# Engage room combat lockdown
			doors_unlocked = false
			_lock_room_doorways(inside_room)
			if nav_grid:
				nav_grid.build_grid(inside_room.bounds, obstacle_rects, 24.0)
			var rs = get_node_or_null("/root/RunState")
			if rs and rs.progression:
				var prof: Dictionary = tracker.get_profile() if tracker else {}
				var p_rating: float = RunProgression.compute_performance_rating(
					player.health if is_instance_valid(player) else 5,
					player.max_health if is_instance_valid(player) else 5,
					prof
				)
				rs.progression.calculate_waves_for_current_room(inside_room.room_type, false, p_rating)
				rs.current_wave = rs.progression.current_wave
				rs.waves_in_room = rs.progression.waves_in_room
			damage_taken_this_sector = 0
			room_cleared = false
			_spawn_wave_enemies(1)
		elif inside_room.room_type == "BOSS" and not boss_active and not boss_vanguard_active and active_enemies.is_empty() and not boss_spawn_initiated:
			boss_spawn_initiated = true
			doors_unlocked = false
			_lock_room_doorways(inside_room)
			if nav_grid:
				nav_grid.build_grid(inside_room.bounds, obstacle_rects, 24.0)
			room_cleared = false
			_spawn_wave_enemies(1)
		elif inside_room.room_type in ["EXTRACT"]:
			inside_room.is_cleared = true
		elif inside_room.room_type == "TRANSIT":
			var t_center: Vector2 = inside_room.bounds.get_center()
			if p_pos.distance_to(t_center) < 85.0:
				inside_room.is_cleared = true
				var rs = get_node_or_null("/root/RunState")
				if rs:
					rs.move_speed_mult = minf(rs.move_speed_mult * 1.35, 2.5)
					rs.add_bits(15)
				if is_instance_valid(player):
					player.current_ammo = player.get_max_ammo()
					player.has_speed_overdrive = true
					player.queue_redraw()
				spawn_damage_number(player.global_position, "OVERDRIVE // +35% SPEED & +15 BITS", Color("00f0ff"))
				if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
					get_node("/root/AudioSynth").play("powerup_pickup", 0.0, 1.0)
				_show_director_banner("HYPER-CONDUIT CHARGED // OVERDRIVE ENGAGED", "+35% Thruster Acceleration & Full Ammo Recharged. +15 Bits.")
				queue_redraw()
		elif inside_room.room_type == "SECRET":
			var sec_center: Vector2 = inside_room.bounds.get_center()
			if p_pos.distance_to(sec_center) < 85.0:
				inside_room.is_cleared = true
				var rs = get_node_or_null("/root/RunState")
				if rs:
					rs.max_health += 1
					rs.heal(3)
					rs.add_bits(75)
				if is_instance_valid(player):
					player.max_health = rs.max_health if rs else player.max_health + 1
					player.health = player.max_health
					player.current_ammo = player.get_max_ammo()
					player.queue_redraw()
				spawn_damage_number(player.global_position, "+1 MAX HP & +75 BITS // FULL REPAIR", Color("c084fc"))
				if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
					get_node("/root/AudioSynth").play("powerup_pickup", 0.05, 2.5)
				_show_director_banner("QUANTUM DATA VAULT SALVAGED // +75 BITS & +1 MAX HP", "Classified military nanites infused. Vitals and ammunition fully replenished.")
				queue_redraw()
		elif inside_room.room_type == "CACHE":
			var c_center: Vector2 = inside_room.bounds.get_center()
			if p_pos.distance_to(c_center) < 85.0:
				inside_room.is_cleared = true
				var rs = get_node_or_null("/root/RunState")
				if rs:
					rs.add_bits(25)
				spawn_damage_number(player.global_position, "+25 BITS DECRYPTED", Color("f59e0b"))
				if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
					get_node("/root/AudioSynth").play("powerup_pickup", 0.0, 0.0)
				_show_director_banner("DATA CACHE RECOVERED // +25 BITS", "Encrypted cache deciphered.")
				queue_redraw()
		elif inside_room.room_type == "SHRINE":
			var s_center: Vector2 = inside_room.bounds.get_center()
			if p_pos.distance_to(s_center) < 85.0:
				inside_room.is_cleared = true
				if is_instance_valid(player):
					player.has_aegis_shield = true
					player.invulnerable_timer = 1.0
					player.queue_redraw()
				var rs = get_node_or_null("/root/RunState")
				if rs:
					rs.heal(1)
				spawn_damage_number(player.global_position, "NEURAL AEGIS ONLINE (+1 HP)", Color("818cf8"))
				if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
					get_node("/root/AudioSynth").play("powerup_pickup", 0.0, 1.5)
				_show_director_banner("NEURAL SHRINE // AEGIS ATTUNEMENT", "Nanite Aegis shield online. Will absorb the next lethal impact. +1 HP restored.")
				queue_redraw()
		elif inside_room.room_type == "RECOVERY":
			var f_center: Vector2 = inside_room.bounds.get_center()
			if p_pos.distance_to(f_center) < 85.0:
				var rs = get_node_or_null("/root/RunState")
				var cur_hp: int = player.health if is_instance_valid(player) else (rs.current_health if rs else 5)
				var max_hp: int = player.max_health if is_instance_valid(player) else (rs.max_health if rs else 5)
				if cur_hp >= max_hp:
					if medbay_full_hp_cooldown <= 0.0:
						medbay_full_hp_cooldown = 2.0
						spawn_damage_number(player.global_position, "VITALS 100% // CHARGE PRESERVED", Color("38bdf8"))
						if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
							get_node("/root/AudioSynth").play("empty_ammo", 0.05, 2.0)
				else:
					inside_room.is_cleared = true
					if rs:
						rs.heal(2)
					if is_instance_valid(player):
						player.health = mini(max_hp, cur_hp + 2)
						player.queue_redraw()
					spawn_damage_number(player.global_position, "+2 HP RESTORED", Color("22c55e"))
					if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
						get_node("/root/AudioSynth").play("powerup_pickup", 0.0, 0.0)
					_show_director_banner("RECOVERY MEDBAY // +2 HP RESTORED", "Nanite biocircuits repaired.")
					queue_redraw()
		elif inside_room.room_type == "GIFT":
			var g_center: Vector2 = inside_room.bounds.get_center()
			if p_pos.distance_to(g_center) < 85.0:
				inside_room.is_cleared = true
				queue_redraw()
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

	var nav: Dictionary = rs.advance_floor()
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
		var cur_fl: int = nav.get("floor", 1)
		var tot_fl: int = nav.get("total_floors", 3)
		var boss_notice: String = " [BOSS CHAMBER]" if nav.get("is_boss_floor", false) else ""
		_show_director_banner("FLOOR ADVANCEMENT // FLOOR %d of %d%s" % [cur_fl, tot_fl, boss_notice], "Staging tactical operations in sector grid.")
		dungeon_layout = null
		_load_room(0)


func _update_hud_hearts() -> void:
	if not is_instance_valid(hearts_box) or not is_instance_valid(player):
		return
	if is_instance_valid(health_label):
		health_label.text = "HEALTH  %d / %d" % [player.health, player.max_health]
		health_label.add_theme_color_override("font_color", Color("fb496e") if player.health <= 2 else Color("ffe4ea"))

	while hearts_box.get_child_count() < player.max_health:
		var heart_rect := TextureRect.new()
		heart_rect.custom_minimum_size = Vector2(16, 16)
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

	# 3. Draw active toxic acid puddles on floor
	for puddle in active_acid_puddles:
		var p_pos: Vector2 = puddle.get("pos", Vector2.ZERO)
		var p_rad: float = puddle.get("radius", 60.0)
		var p_col: Color = puddle.get("color", Color("22c55e"))
		var p_pulse: float = 0.7 + 0.3 * sin(float(ticks) * 0.008)
		draw_circle(p_pos, p_rad, Color(p_col.r, p_col.g, p_col.b, 0.35 * p_pulse))
		draw_arc(p_pos, p_rad, 0.0, TAU, 24, p_col, 2.0)
		draw_circle(p_pos, p_rad * 0.5, Color(p_col.r, p_col.g, p_col.b, 0.20))

	# 4. Hand-authored obstacles with slate body, cyan top trim, and telemetry LEDs
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

	# 5. Exit Doors & Holographic Route Signs (if in single room mode)
	if (not dungeon_layout or dungeon_layout.corridors.is_empty()) and current_room_data and not current_room_data.exit_doors.is_empty():
		_draw_exit_doors(current_room_data, ticks, pulse)

	# 6. Off-screen hostile radar chevrons at viewport bounds
	_draw_radar_chevrons()

	# 7. Incoming Enemy Spawn Telegraph Reticles
	_draw_spawn_telegraphs(ticks)


func _draw_multi_room_floor(layout: RefCounted, biome: Dictionary, ticks: int, pulse: float) -> void:
	var bg_floor_col: Color = biome.get("floor_color", Color("080c16"))
	var grid_color: Color = biome.get("grid_color", Color(0.0, 0.94, 1.0, 0.22))
	var wall_glow: Color = biome.get("wall_glow", Color("00f0ff"))
	var wall_inner: Color = biome.get("wall_inner", Color(0.04, 0.10, 0.18, 0.95))

	# 1. Draw Corridors
	for c in layout.corridors:
		var skip_corridor := false
		for r in layout.rooms:
			if r.is_secret and not r.is_revealed:
				if r.secret_corridor_rect == c:
					skip_corridor = true
					break
		if skip_corridor:
			continue
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

	# 2. Draw Rooms with Soul Knight-inspired floor variety & hazards
	for r in layout.rooms:
		if r.is_secret and not r.is_revealed:
			continue
		var b: Rect2 = r.bounds
		draw_rect(b, bg_floor_col, true)
		for gx in range(int(b.position.x), int(b.end.x), 64):
			draw_line(Vector2(gx, b.position.y), Vector2(gx, b.end.y), grid_color, 1.0)
		for gy in range(int(b.position.y), int(b.end.y), 64):
			draw_line(Vector2(b.position.x, gy), Vector2(b.end.x, gy), grid_color, 1.0)
		_draw_biome_floor_surface(r, b, biome, ticks, pulse)
		_draw_chamfered_room_outline(b, wall_inner, wall_glow)
		_draw_room_emblem(r.room_type, b.get_center(), pulse, b, r.is_cleared)

	# 3. Draw Doorway Thresholds & Lockdown Laser Barriers / Secret Walls
	for d_dict in layout.doorways:
		var d_rect: Rect2 = d_dict.get("rect", Rect2())
		var r_idx: int = int(d_dict.get("room_idx", -1))
		var is_secret_door: bool = d_dict.get("is_secret", false) and not d_dict.get("is_revealed", false)
		if is_secret_door:
			_draw_secret_wall_fissure(d_rect, ticks, pulse)
			continue
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

	# 4. Draw Exit Portal in Exit Room (if extract floor or boss defeated)
	if layout.exit_portal_pos != Vector2.ZERO:
		var last_r: RefCounted = layout.rooms.back()
		if last_r and (last_r.is_cleared or last_r.room_type in ["EXTRACT", "START"] or (last_r.room_type == "BOSS" and room_cleared)):
			_draw_exit_portal(layout.exit_portal_pos, pulse, biome.get("portal_color", Color.CYAN))


func _draw_secret_wall_fissure(d_rect: Rect2, ticks: int, pulse: float) -> void:
	# Holographic cracked barrier over secret doorway
	draw_rect(d_rect, Color(0.02, 0.04, 0.09, 0.96), true)
	draw_rect(d_rect, Color(0.75, 0.25, 0.95, 0.55), false, 1.2)

	# Scanlines
	var is_vert := d_rect.size.x < d_rect.size.y
	if is_vert:
		for y in range(int(d_rect.position.y), int(d_rect.end.y), 8):
			draw_line(Vector2(d_rect.position.x + 2, y), Vector2(d_rect.end.x - 2, y), Color(0.6, 0.2, 0.9, 0.25), 1.0)
	else:
		for x in range(int(d_rect.position.x), int(d_rect.end.x), 8):
			draw_line(Vector2(x, d_rect.position.y + 2), Vector2(x, d_rect.end.y - 2), Color(0.6, 0.2, 0.9, 0.25), 1.0)

	# Jagged electric fissure
	var center := d_rect.get_center()
	var crack_pts := PackedVector2Array()
	var jitter := sin(float(ticks) * 0.015) * 2.5
	if is_vert:
		crack_pts.append(Vector2(center.x, d_rect.position.y))
		crack_pts.append(Vector2(center.x - 4.0 + jitter, center.y - d_rect.size.y * 0.25))
		crack_pts.append(Vector2(center.x + 5.0 - jitter, center.y))
		crack_pts.append(Vector2(center.x - 3.0, center.y + d_rect.size.y * 0.25))
		crack_pts.append(Vector2(center.x, d_rect.end.y))
	else:
		crack_pts.append(Vector2(d_rect.position.x, center.y))
		crack_pts.append(Vector2(center.x - d_rect.size.x * 0.25, center.y - 4.0 + jitter))
		crack_pts.append(Vector2(center.x, center.y + 5.0 - jitter))
		crack_pts.append(Vector2(center.x + d_rect.size.x * 0.25, center.y - 3.0))
		crack_pts.append(Vector2(d_rect.end.x, center.y))

	# Glowing fracture outline & core
	draw_polyline(crack_pts, Color(0.85, 0.35, 1.0, 0.95), 2.5)
	draw_polyline(crack_pts, Color.WHITE, 1.0)
	draw_circle(center, 4.5 * pulse, Color("c084fc"))
	draw_circle(center, 2.0, Color.WHITE)


func _draw_biome_floor_surface(r: RefCounted, b: Rect2, biome: Dictionary, ticks: int, pulse: float) -> void:
	var pattern: String = biome.get("floor_pattern", "CIRCUITS")
	var grid_color: Color = biome.get("grid_color", Color(0.0, 0.94, 1.0, 0.22))
	var accent: Color = biome.get("accent", Color("38bdf8"))

	match pattern:
		"CIRCUITS":
			var center_pt := b.get_center()
			var trace_col := Color(grid_color.r, grid_color.g, grid_color.b, 0.35)
			draw_line(Vector2(b.position.x + 32.0, center_pt.y), Vector2(b.end.x - 32.0, center_pt.y), trace_col, 2.0)
			draw_line(Vector2(center_pt.x, b.position.y + 32.0), Vector2(center_pt.x, b.end.y - 32.0), trace_col, 2.0)
			for offset in [Vector2(-90, -70), Vector2(90, -70), Vector2(-90, 70), Vector2(90, 70)]:
				var node_pos: Vector2 = center_pt + offset
				if b.has_point(node_pos):
					draw_circle(node_pos, 3.5, accent * 0.6)
					draw_circle(node_pos, 1.5, Color.WHITE)

		"ICE_GLACIER":
			var ice_col := Color(0.5, 0.85, 1.0, 0.12 + 0.05 * sin(float(ticks) * 0.003))
			var sheet_rect := Rect2(b.position.x + 40.0, b.position.y + 40.0, b.size.x - 80.0, b.size.y - 80.0)
			draw_rect(sheet_rect, ice_col, true)
			draw_rect(sheet_rect, Color(0.6, 0.9, 1.0, 0.25), false, 1.5)
			var c := b.get_center()
			draw_line(c + Vector2(-60, -40), c + Vector2(20, -10), Color(0.8, 0.95, 1.0, 0.35), 1.5)
			draw_line(c + Vector2(20, -10), c + Vector2(70, 45), Color(0.8, 0.95, 1.0, 0.35), 1.5)
			draw_line(c + Vector2(-30, 50), c + Vector2(10, 20), Color(0.8, 0.95, 1.0, 0.35), 1.5)

		"TOXIC_VINES":
			var slime_col := Color(0.1, 0.6, 0.25, 0.14)
			var c := b.get_center()
			draw_circle(c + Vector2(-80, -40), 38.0, slime_col)
			draw_circle(c + Vector2(75, 45), 44.0, slime_col)
			draw_circle(c + Vector2(-40, 50), 30.0, slime_col)
			draw_arc(c + Vector2(-80, -40), 38.0, 0.2, 2.8, 16, Color("22c55e") * 0.4, 2.0)
			draw_arc(c + Vector2(75, 45), 44.0, 1.2, 4.2, 16, Color("22c55e") * 0.4, 2.0)

		"MAGMA_CRACKS":
			var lava_glow := Color(1.0, 0.35, 0.1, 0.20 * pulse)
			var c := b.get_center()
			var pts1 := PackedVector2Array([
				c + Vector2(-110, -50),
				c + Vector2(-40, -30),
				c + Vector2(10, -5),
				c + Vector2(80, 25),
				c + Vector2(120, 60)
			])
			draw_polyline(pts1, lava_glow * 1.5, 3.0)
			draw_polyline(pts1, Color("f97316") * 0.6, 1.5)
			var pts2 := PackedVector2Array([
				c + Vector2(-30, 70),
				c + Vector2(10, -5),
				c + Vector2(50, -60)
			])
			draw_polyline(pts2, lava_glow * 1.5, 3.0)
			draw_polyline(pts2, Color("f97316") * 0.6, 1.5)

	# Draw room hazards (Soul Knight-style floor hazards: ICE SLICKS, ACID POOLS, LAVA VENTS)
	if "hazards" in r and r.hazards is Array:
		for h in r.hazards:
			var h_rect: Rect2 = h.get("rect", Rect2())
			var h_type: String = h.get("type", "ACID")
			var h_col: Color = h.get("color", Color("22c55e"))
			match h_type:
				"ICE":
					draw_rect(h_rect, Color(0.4, 0.8, 1.0, 0.22), true)
					draw_rect(h_rect, Color("7dd3fc"), false, 1.2)
					draw_circle(h_rect.get_center(), 6.0, Color(0.8, 0.95, 1.0, 0.5))
					var font := ThemeDB.fallback_font
					if font:
						draw_string(font, h_rect.position + Vector2(6, 14), "❄ ICE SLICK (+SPEED)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("7dd3fc") * 0.9)
				"ACID", "TOXIC":
					var a_pulse := 0.7 + 0.3 * sin(float(ticks) * 0.007)
					draw_rect(h_rect, Color(0.1, 0.8, 0.2, 0.28 * a_pulse), true)
					draw_rect(h_rect, h_col, false, 1.5)
					draw_circle(h_rect.get_center(), 5.0, Color("86efac") * 0.7)
					var font := ThemeDB.fallback_font
					if font:
						draw_string(font, h_rect.position + Vector2(6, 14), "☣ CAUSTIC ACID (DMG)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("86efac") * 0.9)
				"LAVA":
					var l_pulse := 0.6 + 0.4 * sin(float(ticks) * 0.009)
					draw_rect(h_rect, Color(1.0, 0.25, 0.05, 0.32 * l_pulse), true)
					draw_rect(h_rect, Color("f97316"), false, 1.8)
					draw_circle(h_rect.get_center(), 7.0, Color("fbbf24") * 0.8)
				_:
					draw_rect(h_rect, Color(h_col.r, h_col.g, h_col.b, 0.25), true)
					draw_rect(h_rect, h_col, false, 1.2)


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
		_draw_room_emblem(room_data.room_type, active_bounds.get_center(), pulse, active_bounds, room_data.is_cleared if room_data else false)


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


func _draw_emblem_label(center_pt: Vector2, radius: float, text: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	if not font:
		return
	var viewport_size := get_viewport_rect().size
	var max_text_width := minf(280.0, viewport_size.x - 24.0)
	var f_size := 11
	var str_sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, f_size)
	while str_sz.x > max_text_width and f_size > 8:
		f_size -= 1
		str_sz = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, f_size)
	var canvas_transform := get_viewport().get_canvas_transform()
	var screen_center: Vector2 = canvas_transform * center_pt
	var pad := Vector2(6.0, 3.0)
	var screen_left := clampf(screen_center.x - str_sz.x * 0.5, 6.0 + pad.x, maxf(6.0 + pad.x, viewport_size.x - str_sz.x - pad.x - 6.0))
	var screen_baseline := clampf(screen_center.y + radius + 18.0, 76.0 + str_sz.y, viewport_size.y - 8.0)
	var label_pos := canvas_transform.affine_inverse() * Vector2(screen_left, screen_baseline)
	var bg_rect := Rect2(label_pos.x - pad.x, label_pos.y - str_sz.y + 2.0, str_sz.x + pad.x * 2.0, str_sz.y + pad.y * 2.0)
	draw_rect(bg_rect, Color(0.015, 0.04, 0.08, 0.92), true)
	draw_rect(bg_rect, color * 0.65, false, 1.2)
	draw_string(font, label_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, f_size, color)


func _draw_room_emblem(r_type: String, center_pt: Vector2, pulse: float, bounds: Rect2, is_cleared: bool = false) -> void:
	var p_dist: float = player.global_position.distance_to(center_pt) if is_instance_valid(player) else 999.0
	var is_nearby: bool = p_dist < 140.0
	var rs_node = get_node_or_null("/root/RunState") if is_inside_tree() else null

	match r_type:
		"START":
			# Ingress airlock staging dock
			var dock_col := Color("38bdf8")
			draw_circle(center_pt, 48.0, Color(0.0, 0.0, 0.0, 0.60))
			draw_circle(center_pt, 44.0, Color(0.04, 0.14, 0.24, 0.85))
			draw_arc(center_pt, 44.0, 0.0, TAU, 36, dock_col, 2.5)
			draw_arc(center_pt, 30.0, 0.0, TAU, 28, Color("67e8f9"), 1.5)
			draw_circle(center_pt, 14.0 * pulse, dock_col)
			draw_circle(center_pt, 4.0, Color.WHITE)
			for i in range(4):
				var a := float(i) * TAU / 4.0
				draw_line(center_pt + Vector2(cos(a), sin(a)) * 16.0, center_pt + Vector2(cos(a), sin(a)) * 32.0, dock_col, 2.0)
			_draw_emblem_label(center_pt, 48.0, "INGRESS DOCK // ROUTE READY", dock_col)

		"RECOVERY":
			if is_cleared:
				var dep_col := Color(0.40, 0.45, 0.50, 0.6)
				draw_circle(center_pt, 50.0, Color(0.02, 0.03, 0.05, 0.65))
				draw_arc(center_pt, 46.0, 0.0, TAU, 32, dep_col * 0.7, 1.5)
				var arm_w := 12.0
				var arm_len := 36.0
				draw_rect(Rect2(center_pt.x - arm_w * 0.5, center_pt.y - arm_len * 0.5, arm_w, arm_len), dep_col * 0.5, true)
				draw_rect(Rect2(center_pt.x - arm_len * 0.5, center_pt.y - arm_w * 0.5, arm_len, arm_w), dep_col * 0.5, true)
				_draw_emblem_label(center_pt, 50.0, "[ MEDBAY DEPLETED ]", Color(0.45, 0.50, 0.55))
			else:
				var med_col := Color("22c55e")
				var cur_hp: int = player.health if is_instance_valid(player) else (rs_node.current_health if rs_node else 5)
				var max_hp: int = player.max_health if is_instance_valid(player) else (rs_node.max_health if rs_node else 5)
				var is_full_hp: bool = cur_hp >= max_hp

				# Vertical ascending beacon beam
				draw_line(center_pt + Vector2(0, 8), center_pt + Vector2(0, -60), Color(0.13, 0.77, 0.37, 0.35 * pulse), 6.0)
				draw_line(center_pt + Vector2(0, 8), center_pt + Vector2(0, -60), Color(1.0, 1.0, 1.0, 0.65 * pulse), 2.0)

				draw_circle(center_pt, 56.0, Color(0.0, 0.0, 0.0, 0.65))
				draw_circle(center_pt, 52.0, Color(0.02, 0.18, 0.10, 0.90))
				draw_arc(center_pt, 52.0, 0.0, TAU, 36, med_col, 3.0)
				draw_arc(center_pt, 38.0, 0.0, TAU, 28, Color("4ade80") * pulse, 1.8)
				var arm_w := 14.0
				var arm_len := 42.0
				draw_rect(Rect2(center_pt.x - arm_w * 0.5, center_pt.y - arm_len * 0.5, arm_w, arm_len), med_col, true)
				draw_rect(Rect2(center_pt.x - arm_len * 0.5, center_pt.y - arm_w * 0.5, arm_len, arm_w), med_col, true)
				draw_rect(Rect2(center_pt.x - arm_w * 0.5 + 2, center_pt.y - arm_len * 0.5 + 2, arm_w - 4, arm_len - 4), Color.WHITE, true)
				draw_rect(Rect2(center_pt.x - arm_len * 0.5 + 2, center_pt.y - arm_w * 0.5 + 2, arm_len - 4, arm_w - 4), Color.WHITE, true)

				var badge_text := "RECOVERY BAY (+2 HP)"
				var badge_col := med_col
				if is_nearby:
					if is_full_hp:
						badge_text = "[ VITALS 100% // CHARGE SAVED ]"
						badge_col = Color("38bdf8")
					else:
						badge_text = ">>> STEP ONTO DAIS (+2 HP) <<<"
						badge_col = Color("4ade80")
				_draw_emblem_label(center_pt, 56.0, badge_text, badge_col)

		"SHOP":
			var s_col := Color("00f0ff")
			var b_count: int = rs_node.bits if rs_node else 0
			draw_circle(center_pt, 52.0, Color(0.0, 0.0, 0.0, 0.65))
			draw_circle(center_pt, 48.0, Color(0.02, 0.14, 0.22, 0.90))
			draw_arc(center_pt, 48.0, 0.0, TAU, 36, s_col, 3.0)
			draw_arc(center_pt, 36.0, 0.0, TAU, 28, Color("38bdf8") * pulse, 1.5)
			draw_line(center_pt + Vector2(-16, -10), center_pt + Vector2(10, -10), s_col, 3.0)
			draw_line(center_pt + Vector2(10, -10), center_pt + Vector2(6, 8), s_col, 3.0)
			draw_line(center_pt + Vector2(6, 8), center_pt + Vector2(-12, 8), s_col, 3.0)
			draw_line(center_pt + Vector2(-12, 8), center_pt + Vector2(-16, -10), s_col, 3.0)
			draw_line(center_pt + Vector2(10, -10), center_pt + Vector2(16, -16), s_col, 3.0)
			draw_circle(center_pt + Vector2(-8, 14), 3.5, s_col)
			draw_circle(center_pt + Vector2(6, 14), 3.5, s_col)

			var badge_text := "SHOP KIOSK (BITS: %d)" % b_count
			var badge_col := s_col
			if is_nearby:
				badge_text = ">>> STEP ONTO KIOSK TO BROWSE <<<"
				badge_col = Color("67e8f9")
			elif is_cleared:
				badge_text = "[ SHOP KIOSK // RE-ARMED (%d BITS) ]" % b_count
			_draw_emblem_label(center_pt, 52.0, badge_text, badge_col)

		"GIFT":
			if is_cleared:
				var dep_col := Color(0.40, 0.45, 0.50, 0.6)
				draw_circle(center_pt, 48.0, Color(0.02, 0.03, 0.05, 0.65))
				draw_arc(center_pt, 44.0, 0.0, TAU, 32, dep_col * 0.7, 1.5)
				var d_pts := PackedVector2Array([
					center_pt + Vector2(0, -16),
					center_pt + Vector2(14, 0),
					center_pt + Vector2(0, 16),
					center_pt + Vector2(-14, 0)
				])
				draw_polyline(PackedVector2Array([d_pts[0], d_pts[1], d_pts[2], d_pts[3], d_pts[0]]), dep_col * 0.6, 1.5)
				_draw_emblem_label(center_pt, 48.0, "[ GIFT CLAIMED ]", Color(0.45, 0.50, 0.55))
			else:
				var g_col := Color("c084fc")
				draw_line(center_pt + Vector2(0, 8), center_pt + Vector2(0, -60), Color(0.75, 0.52, 0.98, 0.35 * pulse), 6.0)
				draw_line(center_pt + Vector2(0, 8), center_pt + Vector2(0, -60), Color(1.0, 1.0, 1.0, 0.65 * pulse), 2.0)

				draw_circle(center_pt, 52.0, Color(0.0, 0.0, 0.0, 0.65))
				draw_circle(center_pt, 48.0, Color(0.12, 0.05, 0.22, 0.90))
				draw_arc(center_pt, 48.0, 0.0, TAU, 36, g_col, 3.0)
				var d_pts := PackedVector2Array([
					center_pt + Vector2(0, -22),
					center_pt + Vector2(20, 0),
					center_pt + Vector2(0, 22),
					center_pt + Vector2(-20, 0)
				])
				draw_colored_polygon(d_pts, Color(0.75, 0.52, 0.98, 0.40))
				var d_closed := PackedVector2Array(d_pts)
				d_closed.append(d_pts[0])
				draw_polyline(d_closed, g_col, 3.0)
				draw_circle(center_pt, 6.0 * pulse, Color.WHITE)

				var badge_text := "GIFT CACHE (FREE UPGRADE)"
				var badge_col := g_col
				if is_nearby:
					badge_text = ">>> STEP TO EXTRACT UPGRADE <<<"
					badge_col = Color("f0abfc")
				_draw_emblem_label(center_pt, 52.0, badge_text, badge_col)

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

		"EXTRACT":
			pass

		"CACHE":
			if is_cleared:
				var dep_col := Color(0.40, 0.45, 0.50, 0.6)
				draw_circle(center_pt, 48.0, Color(0.02, 0.03, 0.05, 0.65))
				draw_arc(center_pt, 44.0, 0.0, TAU, 32, dep_col * 0.7, 1.5)
				draw_rect(Rect2(center_pt.x - 14.0, center_pt.y - 12.0, 28.0, 24.0), dep_col * 0.5, false, 1.5)
				_draw_emblem_label(center_pt, 48.0, "[ CACHE DECRYPTED ]", Color(0.45, 0.50, 0.55))
			else:
				var c_col := Color("f59e0b")
				draw_line(center_pt + Vector2(0, 8), center_pt + Vector2(0, -60), Color(0.96, 0.62, 0.04, 0.35 * pulse), 6.0)
				draw_line(center_pt + Vector2(0, 8), center_pt + Vector2(0, -60), Color(1.0, 1.0, 1.0, 0.65 * pulse), 2.0)

				draw_circle(center_pt, 52.0, Color(0.0, 0.0, 0.0, 0.65))
				draw_circle(center_pt, 48.0, Color(0.18, 0.12, 0.02, 0.90))
				draw_arc(center_pt, 48.0, 0.0, TAU, 36, c_col, 3.0)
				draw_arc(center_pt, 34.0, 0.0, TAU, 28, Color("fbbf24") * pulse, 1.5)
				draw_rect(Rect2(center_pt.x - 16.0, center_pt.y - 14.0, 32.0, 28.0), c_col, false, 2.5)
				draw_line(center_pt + Vector2(-16.0, -2.0), center_pt + Vector2(16.0, -2.0), Color("fbbf24"), 2.0)
				draw_circle(center_pt + Vector2(0.0, 3.0), 3.0, Color.WHITE)

				var badge_text := "DATA CACHE (+25 BITS)"
				var badge_col := c_col
				if is_nearby:
					badge_text = ">>> STEP TO DECRYPT +25 BITS <<<"
					badge_col = Color("fde047")
				_draw_emblem_label(center_pt, 52.0, badge_text, badge_col)

		"SHRINE":
			if is_cleared:
				var dep_col := Color(0.40, 0.45, 0.50, 0.6)
				draw_circle(center_pt, 48.0, Color(0.02, 0.03, 0.05, 0.65))
				draw_arc(center_pt, 44.0, 0.0, TAU, 32, dep_col * 0.7, 1.5)
				draw_circle(center_pt, 8.0, dep_col * 0.5)
				_draw_emblem_label(center_pt, 48.0, "[ SHRINE ATTUNED ]", Color(0.45, 0.50, 0.55))
			else:
				var sh_col := Color("818cf8")
				draw_line(center_pt + Vector2(0, 8), center_pt + Vector2(0, -60), Color(0.51, 0.55, 0.97, 0.35 * pulse), 6.0)
				draw_line(center_pt + Vector2(0, 8), center_pt + Vector2(0, -60), Color(1.0, 1.0, 1.0, 0.65 * pulse), 2.0)

				draw_circle(center_pt, 54.0, Color(0.0, 0.0, 0.0, 0.65))
				draw_circle(center_pt, 50.0, Color(0.08, 0.04, 0.20, 0.90))
				draw_arc(center_pt, 50.0, 0.0, TAU, 36, sh_col, 3.0)
				draw_arc(center_pt, 36.0, 0.0, TAU, 28, Color("a5b4fc") * pulse, 1.5)
				draw_circle(center_pt, 12.0 * pulse, sh_col)
				draw_circle(center_pt, 4.0, Color.WHITE)
				for i in range(8):
					var a := float(i) * TAU / 8.0
					draw_line(center_pt + Vector2(cos(a), sin(a)) * 14.0, center_pt + Vector2(cos(a), sin(a)) * 26.0, Color("a5b4fc"), 1.5)

				var badge_text := "NEURAL SHRINE (AEGIS)"
				var badge_col := sh_col
				if is_nearby:
					badge_text = ">>> STEP FOR AEGIS SHIELD (+1 HP) <<<"
					badge_col = Color("c7d2fe")
				_draw_emblem_label(center_pt, 54.0, badge_text, badge_col)

		"TRANSIT":
			if is_cleared:
				var dep_col := Color(0.40, 0.45, 0.50, 0.6)
				draw_circle(center_pt, 46.0, Color(0.02, 0.03, 0.05, 0.65))
				draw_arc(center_pt, 42.0, 0.0, TAU, 32, dep_col * 0.7, 1.5)
				draw_line(center_pt + Vector2(-12.0, -8.0), center_pt + Vector2(0.0, 4.0), dep_col * 0.6, 2.0)
				draw_line(center_pt + Vector2(0.0, 4.0), center_pt + Vector2(12.0, -8.0), dep_col * 0.6, 2.0)
				_draw_emblem_label(center_pt, 46.0, "[ CONDUIT DISCHARGED ]", Color(0.45, 0.50, 0.55))
			else:
				var tr_col := Color("00f0ff")
				draw_line(center_pt + Vector2(0, 8), center_pt + Vector2(0, -60), Color(0.0, 0.94, 1.0, 0.35 * pulse), 6.0)
				draw_line(center_pt + Vector2(0, 8), center_pt + Vector2(0, -60), Color(1.0, 1.0, 1.0, 0.65 * pulse), 2.0)

				draw_circle(center_pt, 48.0, Color(0.0, 0.0, 0.0, 0.55))
				draw_circle(center_pt, 44.0, Color(0.03, 0.10, 0.20, 0.90))
				draw_arc(center_pt, 44.0, 0.0, TAU, 36, tr_col, 2.8)
				draw_arc(center_pt, 32.0, 0.0, TAU, 28, Color("38bdf8") * pulse, 1.8)
				var t_col := Color("38bdf8")
				draw_line(center_pt + Vector2(-16.0, -10.0), center_pt + Vector2(0.0, 6.0), t_col, 2.5)
				draw_line(center_pt + Vector2(0.0, 6.0), center_pt + Vector2(16.0, -10.0), t_col, 2.5)
				draw_line(center_pt + Vector2(-12.0, -18.0), center_pt + Vector2(0.0, -6.0), Color.WHITE, 1.8)
				draw_line(center_pt + Vector2(0.0, -6.0), center_pt + Vector2(12.0, -18.0), Color.WHITE, 1.8)
				draw_circle(center_pt + Vector2(0.0, 6.0), 3.0, Color.WHITE)

				var badge_text := "HYPER-CONDUIT (OVERDRIVE)"
				var badge_col := tr_col
				if is_nearby:
					badge_text = ">>> STEP FOR +35% SPEED & +15 BITS <<<"
					badge_col = Color("a5f3fc")
				_draw_emblem_label(center_pt, 48.0, badge_text, badge_col)

		"SECRET":
			if is_cleared:
				var dep_col := Color(0.40, 0.45, 0.50, 0.6)
				draw_circle(center_pt, 48.0, Color(0.02, 0.03, 0.05, 0.65))
				draw_arc(center_pt, 44.0, 0.0, TAU, 32, dep_col * 0.7, 1.5)
				draw_circle(center_pt, 10.0, dep_col * 0.5)
				_draw_emblem_label(center_pt, 48.0, "[ VAULT SALVAGED ]", Color(0.45, 0.50, 0.55))
			else:
				var v_col := Color("c084fc")
				draw_line(center_pt + Vector2(0, 8), center_pt + Vector2(0, -60), Color(0.75, 0.52, 0.98, 0.40 * pulse), 6.0)
				draw_line(center_pt + Vector2(0, 8), center_pt + Vector2(0, -60), Color(1.0, 1.0, 1.0, 0.70 * pulse), 2.0)

				draw_circle(center_pt, 54.0, Color(0.0, 0.0, 0.0, 0.65))
				draw_circle(center_pt, 50.0, Color(0.12, 0.04, 0.22, 0.92))
				draw_arc(center_pt, 50.0, 0.0, TAU, 40, v_col, 3.0)
				draw_arc(center_pt, 36.0, 0.0, TAU, 30, Color("e879f9") * pulse, 2.0)
				draw_circle(center_pt, 14.0 * pulse, v_col)
				draw_circle(center_pt, 5.0, Color.WHITE)

				var badge_text := "QUANTUM VAULT (+1 MAX HP & +75 BITS)"
				var badge_col := v_col
				if is_nearby:
					badge_text = ">>> STEP TO SALVAGE VAULT <<<"
					badge_col = Color("f472b6")
				_draw_emblem_label(center_pt, 54.0, badge_text, badge_col)

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
	_draw_emblem_label(pos, 42.0, "WARP EXTRACTION", portal_col)


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
	for sw in active_secret_walls:
		if is_instance_valid(sw):
			sw.queue_free()
	active_secret_walls.clear()

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

	# 3. Build destructible secret walls over unrevealed secret doorways
	for d in layout.doorways:
		if d.get("is_secret", false) and not d.get("is_revealed", false):
			var d_rect: Rect2 = d.get("rect", Rect2())
			var sec_room_idx: int = int(d.get("secret_room_idx", -1))
			var sec_wall: StaticBody2D = SECRET_WALL_SCRIPT.new() as StaticBody2D
			sec_wall.position = d_rect.get_center()
			sec_wall.game_ref = self
			sec_wall.room_index = sec_room_idx
			var c_shape := CollisionShape2D.new()
			var r_shape := RectangleShape2D.new()
			r_shape.size = d_rect.size
			c_shape.shape = r_shape
			sec_wall.add_child(c_shape)
			add_child(sec_wall)
			active_secret_walls.append(sec_wall)


func reveal_secret_room(room_idx: int) -> void:
	if not dungeon_layout:
		return
	for r in dungeon_layout.rooms:
		if r.index == room_idx:
			r.is_revealed = true
			break

	for d in dungeon_layout.doorways:
		if int(d.get("secret_room_idx", -1)) == room_idx or int(d.get("room_idx", -1)) == room_idx:
			d["is_revealed"] = true

	# Remove the secret wall physics bodies
	var remaining_walls: Array[StaticBody2D] = []
	for sw in active_secret_walls:
		if is_instance_valid(sw):
			if "room_index" in sw and sw.room_index == room_idx:
				sw.queue_free()
			else:
				remaining_walls.append(sw)
	active_secret_walls = remaining_walls

	var rs = get_node_or_null("/root/RunState")
	if rs:
		# Find by the room's stable identity rather than assuming the summary's
		# array position always matches its dungeon index.
		for room_summary in rs.dungeon_layout_summary:
			if int(room_summary.get("index", -1)) == room_idx:
				room_summary["is_secret"] = true
				room_summary["is_revealed"] = true
				break

	# Audio cue & screen shake
	add_trauma(0.35)
	trigger_glitch(0.50)
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		var synth = get_node("/root/AudioSynth")
		if synth.has_method("play"):
			synth.play("powerup_pickup", 0.05, 2.0)

	_show_director_banner("/// HIDDEN CHAMBER BREACHED // QUANTUM VAULT UNLOCKED ///", "Classified sector data core exposed. High-value salvage detected.")
	queue_redraw()


func _lock_room_doorways(room: RefCounted) -> void:
	doors_unlocked = false
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


func _add_tactical_prop(pos: Vector2, size: Vector2, ptype: String) -> Node2D:
	var prop: Node2D = DESTRUCTIBLE_PROP_SCRIPT.new()
	prop.position = pos
	prop.prop_size = size
	prop.prop_type = ptype
	prop.game_ref = self
	add_child(prop)
	active_obstacles.append(prop)
	obstacle_rects.append(Rect2(pos - size * 0.5, size))
	return prop


func on_prop_destroyed(prop: Node2D) -> void:
	if not is_instance_valid(prop):
		return
	var p_pos: Vector2 = prop.position
	var p_type: String = prop.prop_type
	active_obstacles.erase(prop)
	obstacle_rects.erase(prop.prop_rect)

	match p_type:
		"EXPLOSIVE_BARREL":
			add_trauma(0.40)
			trigger_glitch(0.60)
			if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
				get_node("/root/AudioSynth").play("hit_impact", 0.05, 3.0)
			DEBRIS_EMITTER_SCRIPT.spawn_shards(self, p_pos, Color("ef4444"), "hexagon", 12)
			for enemy in active_enemies:
				if is_instance_valid(enemy):
					var d: float = p_pos.distance_to(enemy.global_position)
					if d <= 130.0:
						if enemy.has_method("take_damage"):
							enemy.take_damage(3)
						if "velocity" in enemy:
							enemy.velocity += (enemy.global_position - p_pos).normalized() * 260.0
			if is_instance_valid(player) and p_pos.distance_to(player.global_position) <= 90.0:
				player.take_damage(1)
			for sw in active_secret_walls:
				if is_instance_valid(sw) and p_pos.distance_to(sw.global_position) <= 150.0:
					sw.take_damage(1, "explosion")

		"CRYO_CANISTER":
			add_trauma(0.25)
			if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
				get_node("/root/AudioSynth").play("powerup_pickup", 0.05, -2.0)
			DEBRIS_EMITTER_SCRIPT.spawn_shards(self, p_pos, Color("38bdf8"), "diamond", 10)
			for enemy in active_enemies:
				if is_instance_valid(enemy) and p_pos.distance_to(enemy.global_position) <= 150.0:
					if enemy.has_method("apply_debuff"):
						enemy.apply_debuff("CRYO", 3.5)
					elif "move_speed" in enemy:
						enemy.move_speed *= 0.40

		"TOXIC_VAT":
			add_trauma(0.20)
			if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
				get_node("/root/AudioSynth").play("hit_impact", 0.05, -3.0)
			DEBRIS_EMITTER_SCRIPT.spawn_shards(self, p_pos, Color("22c55e"), "chevron", 8)
			active_acid_puddles.append({
				"pos": p_pos,
				"radius": 75.0,
				"timer": 6.5,
				"color": Color("22c55e")
			})

		"DATA_PYLON":
			add_trauma(0.25)
			DEBRIS_EMITTER_SCRIPT.spawn_shards(self, p_pos, Color("00f0ff"), "diamond", 8)
			var rs = get_node_or_null("/root/RunState")
			if rs:
				rs.add_bits(15)
				_show_director_banner("DATA PYLON CACHE // +15 BITS", "Direct bit extraction successful.")

	queue_redraw()



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
	var run_state = get_node_or_null("/root/RunState")
	if run_state and run_state.selected_character_id == "BREACHER":
		ammo_label.text = "ARC STRIKE // READY"
		ammo_label.add_theme_color_override("font_color", Color("fb923c"))
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
	if is_instance_valid(camera):
		if is_instance_valid(camera_pulse_tween) and camera_pulse_tween.is_running():
			camera_pulse_tween.kill()
		camera_pulse_tween = create_tween()
		camera_pulse_tween.tween_property(camera, "zoom", Vector2(1.045, 1.045), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		camera_pulse_tween.tween_property(camera, "zoom", Vector2.ONE, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


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
	lbl.custom_minimum_size = Vector2(220.0, 34.0)
	lbl.size = lbl.custom_minimum_size
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.05, 0.95))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.z_index = 50
	var screen_pos: Vector2 = get_viewport().get_canvas_transform() * (pos + Vector2(randf_range(-18.0, 18.0), randf_range(-28.0, -12.0)))
	var viewport_size := get_viewport_rect().size
	lbl.position = Vector2(
		clampf(screen_pos.x - lbl.size.x * 0.5, 6.0, maxf(6.0, viewport_size.x - lbl.size.x - 6.0)),
		clampf(screen_pos.y - lbl.size.y * 0.5, 66.0, maxf(66.0, viewport_size.y - lbl.size.y - 12.0))
	)
	if is_instance_valid(ui_layer):
		ui_layer.add_child(lbl)
	else:
		add_child(lbl)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(lbl, "position:y", lbl.position.y - 28.0, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.45).set_ease(Tween.EASE_IN).set_delay(0.12)
	tween.chain().tween_callback(lbl.queue_free)


func _load_room(index: int) -> void:
	if room_transition_active:
		return
	var animate_swap := has_loaded_room and is_instance_valid(transition_cover)
	if animate_swap:
		room_transition_active = true
		await _animate_transition_cover(true, 0.16)

	room_cleared = false
	doors_unlocked = false
	boss_active = false
	boss_spawn_initiated = false
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
	var sec_seed: int = rs_node.progression.get_current_floor_seed() if (rs_node and rs_node.progression) else (rs_node.current_seed if rs_node else 1337)
	var room_count: int = rs_node.progression.rooms_per_sector if (rs_node and rs_node.progression) else 12

	if not dungeon_layout or dungeon_layout.rooms.is_empty():
		var wave_count: int = rs_node.progression.sector_total_waves if (rs_node and rs_node.progression) else 3
		var is_boss_fl: bool = rs_node.progression.is_boss_floor() if (rs_node and rs_node.progression) else true
		dungeon_layout = dungeon_generator.generate_dungeon(
			sec_seed,
			room_count,
			wave_count,
			true,
			rs_node.progression.difficulty if rs_node.progression else rs_node.difficulty,
			rs_node.progression.sector_index if rs_node.progression else rs_node.current_sector,
			is_boss_fl
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
	boss_spawn_initiated = false
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

	# Place procedural obstacle & tactical destructible prop geometry
	if dungeon_layout and not dungeon_layout.corridors.is_empty():
		for rm in dungeon_layout.rooms:
			for i in range(rm.obstacles.size()):
				var r: Rect2 = rm.obstacles[i]
				var ptype: String = rm.prop_types[i] if (i < rm.prop_types.size()) else ""
				if not ptype.is_empty():
					_add_tactical_prop(r.get_center(), r.size, ptype)
				else:
					_add_obstacle(r.get_center(), r.size)
			if rm.room_type == "START":
				var f_center: Vector2 = rm.bounds.get_center()
				_add_fountain_obstacle(f_center, 44.0)
	else:
		for i in range(current_room_data.obstacles.size()):
			var r: Rect2 = current_room_data.obstacles[i]
			var ptype: String = current_room_data.prop_types[i] if (i < current_room_data.prop_types.size()) else ""
			if not ptype.is_empty():
				_add_tactical_prop(r.get_center(), r.size, ptype)
			else:
				_add_obstacle(r.get_center(), r.size)
		if current_room_data and current_room_data.room_type == "START":
			var f_center: Vector2 = current_room_data.bounds.get_center()
			_add_fountain_obstacle(f_center, 44.0)

	if nav_grid:
		nav_grid.build_grid(current_room_data.bounds if current_room_data else ROOM_RECT, obstacle_rects, 24.0)

	# Service & extract chambers are safe traversal/reward stops, not extra combat waves.
	var cur_b: int = rs_node.progression.current_biome if (rs_node and rs_node.progression) else (rs_node.current_biome if rs_node else 1)
	if encounter_director:
		encounter_director.current_biome = cur_b
		if encounter_director.evolution_manager:
			encounter_director.evolution_manager.current_biome = cur_b

	if current_room_data.room_type in ["START", "RECOVERY", "SHOP", "GIFT", "EXTRACT", "CACHE", "SHRINE", "TRANSIT"]:
		_handle_non_wave_room(current_room_data.room_type)
		queue_redraw()
		_update_debug_overlay()
		has_loaded_room = true
		if animate_swap or (is_instance_valid(transition_cover) and transition_cover.modulate.a > 0.0):
			await _animate_transition_cover(false, 0.26)
			room_transition_active = false
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
	has_loaded_room = true
	if animate_swap or (is_instance_valid(transition_cover) and transition_cover.modulate.a > 0.0):
		await _animate_transition_cover(false, 0.26)
		room_transition_active = false


func _handle_non_wave_room(room_type: String) -> void:
	room_cleared = true
	var is_multi_room: bool = dungeon_layout != null and not dungeon_layout.corridors.is_empty()
	if not is_multi_room:
		doors_unlocked = true
	else:
		doors_unlocked = false
	var rs_node = get_node_or_null("/root/RunState") if is_inside_tree() else null
	if current_room_data and current_room_data.is_cleared and room_type in ["RECOVERY", "CACHE", "SHRINE", "TRANSIT", "GIFT"]:
		return
	match room_type:
		"START":
			var cur_sec: int = rs_node.progression.sector_index if (rs_node and rs_node.progression) else 1
			_show_director_banner(
				"CALIBRATION DOCK // SECTOR %d STAGING" % cur_sec,
				"SAFE STAGING AREA // SELECT AN INGRESS ROUTE"
			)
			if not is_multi_room:
				_unlock_exit_doors()
		"EXTRACT":
			_show_director_banner(
				"SECTOR EXTRACTION GATEWAY // WARP READY",
				"ROUTE TERMINUS // STEP THROUGH THE WARP PORTAL TO ADVANCE"
			)
			if not is_multi_room:
				_unlock_exit_doors()
		"RECOVERY":
			var cur_hp: int = player.health if is_instance_valid(player) else (rs_node.current_health if rs_node else 5)
			var max_hp: int = player.max_health if is_instance_valid(player) else (rs_node.max_health if rs_node else 5)
			if cur_hp >= max_hp:
				if is_instance_valid(player):
					spawn_damage_number(player.global_position, "VITALS 100% // CHARGE PRESERVED", Color("38bdf8"))
				_show_director_banner("RECOVERY MEDBAY // CHARGE PRESERVED", "Vitals at 100% capacity. Dais charge held in reserve.")
			else:
				if rs_node:
					rs_node.heal(2)
				if is_instance_valid(player):
					player.health = mini(max_hp, cur_hp + 2)
					player.queue_redraw()
					spawn_damage_number(player.global_position, "+2 HP RESTORED", Color("22c55e"))
				if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
					get_node("/root/AudioSynth").play("powerup_pickup", 0.0, 0.0)
				_show_director_banner("RECOVERY MEDBAY // +2 HP RESTORED", "Nanite biocircuits repaired. Route doors open.")
			if current_room_data:
				current_room_data.is_cleared = true
			if not is_multi_room:
				_unlock_exit_doors()
		"CACHE":
			if rs_node:
				rs_node.add_bits(25)
			if is_instance_valid(player):
				spawn_damage_number(player.global_position, "+25 BITS DECRYPTED", Color("f59e0b"))
			if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
				get_node("/root/AudioSynth").play("powerup_pickup", 0.0, 0.0)
			_show_director_banner("DATA CACHE RECOVERED // +25 BITS", "Encrypted cache deciphered.")
			if current_room_data:
				current_room_data.is_cleared = true
			if not is_multi_room:
				_unlock_exit_doors()
		"SHRINE":
			if is_instance_valid(player):
				player.has_aegis_shield = true
				player.invulnerable_timer = 1.0
				player.queue_redraw()
				spawn_damage_number(player.global_position, "NEURAL AEGIS ONLINE (+1 HP)", Color("818cf8"))
			if rs_node:
				rs_node.heal(1)
			if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
				get_node("/root/AudioSynth").play("powerup_pickup", 0.0, 1.5)
			_show_director_banner("NEURAL SHRINE // AEGIS ATTUNEMENT", "Nanite Aegis shield online. Will absorb the next lethal impact. +1 HP restored.")
			if current_room_data:
				current_room_data.is_cleared = true
			if not is_multi_room:
				_unlock_exit_doors()
		"TRANSIT":
			var rs = rs_node
			if rs:
				rs.move_speed_mult = minf(rs.move_speed_mult * 1.35, 2.5)
				rs.add_bits(15)
			if is_instance_valid(player):
				player.current_ammo = player.get_max_ammo()
				player.has_speed_overdrive = true
				player.queue_redraw()
				spawn_damage_number(player.global_position, "OVERDRIVE // +35% SPEED & +15 BITS", Color("00f0ff"))
			if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
				get_node("/root/AudioSynth").play("powerup_pickup", 0.0, 1.0)
			_show_director_banner("HYPER-CONDUIT CHARGED // OVERDRIVE ENGAGED", "+35% Thruster Acceleration & Full Ammo Recharged. +15 Bits.")
			if current_room_data:
				current_room_data.is_cleared = true
			if not is_multi_room:
				_unlock_exit_doors()
		"SHOP":
			_show_shop_interface()
		"GIFT":
			_show_gift_interface()
		_:
			if not is_multi_room:
				_unlock_exit_doors()


func _show_shop_interface() -> void:
	glitch_pulse = 0.0
	if is_instance_valid(glitch_material):
		glitch_material.set_shader_parameter("glitch_intensity", 0.0)
	if touch_controls:
		touch_controls.enabled = false
		touch_controls.visible = false
		if touch_controls.has_method("reset_controls"):
			touch_controls.reset_controls()
	get_tree().paused = true
	var rs = get_node_or_null("/root/RunState")
	var stock: Array = current_room_data.shop_stock if (current_room_data and "shop_stock" in current_room_data and not current_room_data.shop_stock.is_empty()) else []
	if stock.is_empty():
		stock = dungeon_generator._generate_shop_stock(RandomNumberGenerator.new())
		if current_room_data and "shop_stock" in current_room_data:
			current_room_data.shop_stock = stock

	if draft_header_label:
		draft_header_label.text = "BLACK MARKET // DATA TERMINAL"
	if draft_sub_label:
		draft_sub_label.text = "Install tactical subroutines with collected Bits. Available: %d Bits" % (rs.bits if rs else 0)

	for child in upgrade_cards_box.get_children():
		child.queue_free()

	for item in stock:
		var card := Button.new()
		card.custom_minimum_size = Vector2(190, 200)
		var item_id: String = item.get("id", "OVERCLOCK")
		var cost: int = int(item.get("cost", 5))
		var title: String = item.get("title", item_id)
		var desc: String = item.get("desc", "+Upgrade")
		var rarity: String = item.get("rarity", "COMMON")
		var is_purchased: bool = item.get("purchased", false)
		var can_afford: bool = rs != null and rs.bits >= cost
		var is_capped: bool = rs != null and rs.get_upgrade_stack_count(item_id) >= rs.get_upgrade_stack_cap(item_id)

		var status_text := "COST: %d BITS" % cost
		if is_purchased:
			status_text = "[ INSTALLED ]"
		elif is_capped:
			status_text = "[ FULLY STACKED ]"
		elif not can_afford:
			status_text = "COST: %d BITS\n(HAVE %d)" % [cost, (rs.bits if rs else 0)]

		card.text = "\n[ SHOP // %s ]\n%s\n%s\n\n%s\n\n%s" % [
			title,
			rarity,
			status_text,
			desc,
			"Tap to purchase" if (can_afford and not is_capped and not is_purchased) else ("Purchased" if is_purchased else "Unavailable")
		]
		card.disabled = not can_afford or is_capped or is_purchased
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		MENU_SKIN.style_button(card, _menu_rarity_color(rarity), true if is_purchased or is_capped else false)
		card.pressed.connect(func():
			if rs and rs.bits >= cost and not is_capped and not item.get("purchased", false):
				rs.spend_bits(cost)
				rs.apply_upgrade(item_id)
				item["purchased"] = true
				if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
					get_node("/root/AudioSynth").play("powerup_pickup", 0.0, 0.0)
				_show_shop_interface()
		)
		upgrade_cards_box.add_child(card)

	var bypass_btn := Button.new()
	bypass_btn.custom_minimum_size = Vector2(190, 200)
	bypass_btn.text = "\n[ EXIT TERMINAL ]\n\nLeave kiosk.\n\nResume run."
	MENU_SKIN.style_button(bypass_btn, Color("64748b"))
	bypass_btn.pressed.connect(_close_shop_or_gift)
	upgrade_cards_box.add_child(bypass_btn)

	upgrade_container.visible = true
	if is_instance_valid(special_menu_glitch):
		special_menu_glitch.visible = true


func _show_gift_interface() -> void:
	glitch_pulse = 0.0
	if is_instance_valid(glitch_material):
		glitch_material.set_shader_parameter("glitch_intensity", 0.0)
	if touch_controls:
		touch_controls.enabled = false
		touch_controls.visible = false
		if touch_controls.has_method("reset_controls"):
			touch_controls.reset_controls()
	get_tree().paused = true
	var rs = get_node_or_null("/root/RunState")
	var gifts: Array[Dictionary] = rs.get_random_upgrade_choices(2) if rs else []
	if gifts.is_empty():
		gifts.append(_make_gift_fallback(rs))
	elif gifts.size() == 1 and gifts[0].get("id", "") == "FIELD_REPAIR" and rs and rs.current_health >= rs.max_health:
		# A heal is not a reward when the player is already at full health.
		gifts[0] = _make_gift_fallback(rs)

	if draft_header_label:
		draft_header_label.text = "GIFT CACHE // REWARD TERMINAL"
	if draft_sub_label:
		if gifts.size() == 1 and gifts[0].get("id", "") == "DATA_BITS":
			draft_sub_label.text = "All subroutines are fully stacked. Claim this 25-bit cache instead."
		elif gifts.size() == 1 and gifts[0].get("id", "") == "FIELD_REPAIR":
			draft_sub_label.text = "All subroutines are fully stacked. Claim a 1 HP field repair instead."
		else:
			draft_sub_label.text = "Select 1 complimentary subroutine to install into memory."

	for child in upgrade_cards_box.get_children():
		child.queue_free()

	for offer in gifts:
		var card := Button.new()
		card.custom_minimum_size = Vector2(220, 170)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var item_id: String = offer.get("id", "FIELD_REPAIR")
		var title: String = offer.get("title", item_id.replace("_", " "))
		var description: String = offer.get("desc", "Install this cache reward.")
		var stack_count: int = (rs.get_upgrade_stack_count(item_id) + 1) if rs else 1
		var stack_cap: int = rs.get_upgrade_stack_cap(item_id) if (rs and item_id != "FIELD_REPAIR") else 0
		var rarity: String = offer.get("rarity", "COMMON")
		var stack_line := "RESOURCE CACHE" if item_id == "DATA_BITS" else ("FIELD REPAIR" if item_id == "FIELD_REPAIR" else "STACK %d / %d" % [stack_count, stack_cap])
		card.text = "%s\n%s  •  %s\n%s\n\nTap to claim" % [title, rarity, stack_line, description]
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		MENU_SKIN.style_button(card, _menu_rarity_color(rarity))
		card.pressed.connect(func():
			if not rs:
				return
			if item_id == "DATA_BITS":
				rs.add_bits(25)
			elif not rs.apply_upgrade(item_id):
				return
			if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
				get_node("/root/AudioSynth").play("powerup_pickup", 0.0, 0.0)
			_show_director_banner("GIFT CACHE CLAIMED // %s" % title, description)
			_close_shop_or_gift()
		)
		upgrade_cards_box.add_child(card)

	upgrade_container.z_index = 100
	upgrade_container.visible = true
	if is_instance_valid(special_menu_glitch):
		special_menu_glitch.visible = true


func _make_gift_fallback(rs) -> Dictionary:
	if rs and rs.current_health < rs.max_health:
		return {
			"id": "FIELD_REPAIR",
			"title": "FIELD REPAIR",
			"desc": "+1 HP",
			"rarity": "COMMON"
		}
	return {
		"id": "DATA_BITS",
		"title": "DATA CACHE",
		"desc": "+25 BITS",
		"rarity": "COMMON"
	}


func _close_shop_or_gift() -> void:
	upgrade_container.visible = false
	if is_instance_valid(special_menu_glitch):
		special_menu_glitch.visible = false
	if current_room_data and current_room_data.room_type == "GIFT":
		current_room_data.is_cleared = true
	get_tree().paused = false
	shop_cooldown = 1.2
	if touch_controls:
		touch_controls.enabled = true
		touch_controls.visible = true
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
	var p_rating: float = RunProgression.compute_performance_rating(p_hp, p_max, profile) if (rs_node and rs_node.progression) else 1.0
	var spawn_budget: int = rs_node.progression.calculate_spawn_budget(wave_num, p_rating) if (rs_node and rs_node.progression) else current_room_data.enemy_spawns.size()
	if current_room_data.room_type in ["COMBAT", "ELITE"]:
		spawn_budget = maxi(3, spawn_budget)
	if current_room_data.room_type == "ELITE":
		spawn_budget = mini(9, spawn_budget + 2)
	var sector_seed: int = rs_node.progression.get_current_floor_seed() if (rs_node and rs_node.progression) else 1337
	current_room_data.enemy_spawns = dungeon_generator.generate_wave_spawns(current_room_data, sector_seed, wave_num, spawn_budget)

	var encounter: Dictionary = encounter_director.prepare_encounter(
		current_room_data,
		profile,
		p_hp,
		p_max
	)
	var diff_mults: Dictionary = rs_node.progression.get_difficulty_multipliers(p_rating) if (rs_node and rs_node.progression) else {"speed_mult": 1.0, "telegraph_mult": 1.0}
	var diff_speed: float = diff_mults.get("speed_mult", 1.0)
	var diff_tele: float = diff_mults.get("telegraph_mult", 1.0)

	current_sector_tactic = encounter.tactic
	if wave_num == 1:
		_show_director_banner(encounter.banner_title, encounter.banner_sub)
	else:
		var total_w: int = rs_node.waves_in_room if rs_node else 3
		_show_director_banner("WAVE %d / %d // REINFORCEMENTS" % [wave_num, total_w], "Hostile wave engaged.")

	if rs_node and wave_num == 1:
		var cur_b: int = rs_node.progression.current_biome if (rs_node and rs_node.progression) else (rs_node.current_biome if rs_node else 1)
		var active_muts: Array[String] = []
		if cur_b > 1 and encounter_director and encounter_director.evolution_manager:
			active_muts = encounter_director.evolution_manager.get_active_mutations_summary()
		var mut_desc := ", ".join(active_muts) if not active_muts.is_empty() else "Standard swarm baseline"
		rs_node.record_tactic(rs_node.current_room_index + 1, encounter.tactic, encounter.banner_sub, mut_desc)

	# Spawn budgeted enemies for this wave
	var spawns_to_create: Array = encounter.spawn_list.slice(0, mini(spawn_budget, encounter.spawn_list.size()))
	if spawns_to_create.is_empty() and not encounter.spawn_list.is_empty():
		spawns_to_create = encounter.spawn_list
	if spawns_to_create.is_empty() and current_room_data.room_type in ["COMBAT", "ELITE"]:
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

		var cur_sector: int = rs_node.progression.sector_index if (rs_node and rs_node.progression) else 1
		if boss_director and rs_node:
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

		# Spawn vanguard escort combatants scaled by sector difficulty
		var vanguard_specs: Array[Dictionary] = []
		if cur_sector == 1:
			# Sector 1 (First Boss): Accessible 1-hostile vanguard escort
			vanguard_specs = [
				{"scene": CHASER_SCENE, "type": "CHASER", "offset": Vector2(-120.0, 0.0), "flank": 0.0}
			]
		elif cur_sector == 2:
			# Sector 2 (Mid-Boss): 2 vanguard hostiles
			vanguard_specs = [
				{"scene": CHASER_SCENE, "type": "CHASER", "offset": Vector2(-120.0, -80.0), "flank": 0.35},
				{"scene": SHOOTER_SCENE, "type": "SHOOTER", "offset": Vector2(60.0, 0.0), "flank": 0.0}
			]
		else:
			# Sector 3+ (Final Biome Boss): Full 3 vanguard escort hostiles
			vanguard_specs = [
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
			var spd_m: float = encounter.enemy_speed_mult * diff_speed * 1.05
			var tel_m: float = encounter.enemy_telegraph_mult * diff_tele
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
							_apply_encounter_modifiers(v_enemy, spd_m, tel_m, v_flank, lead_v, encounter.hazard_trail)
							encounter_director.evolution_manager.register_spawned_combatant(v_genome, v_enemy)
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

			var spd_m: float = encounter.enemy_speed_mult * diff_speed
			var tel_m: float = encounter.enemy_telegraph_mult * diff_tele
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
						_apply_encounter_modifiers(enemy, spd_m, tel_m, flank, lead_v, encounter.hazard_trail)
						encounter_director.evolution_manager.register_spawned_combatant(genome, enemy)
			)


func _spawn_boss(pos: Vector2) -> void:
	if boss_active or (is_instance_valid(boss_ref) and not boss_ref.is_queued_for_deletion()):
		return
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

	# Boss difficulty scaling: First boss is notably easier, progressively harder as depth and sectors advance
	var hp_scale := 1.0
	if cur_sector == 1:
		hp_scale = 0.55 # Sector 1 (First boss): accessible 55% health (~19-20 HP)
	elif cur_sector == 2:
		hp_scale = 0.80 # Sector 2 (Mid-boss): ~28 HP
	else:
		hp_scale = 1.0 + float(cur_sector - 3) * 0.15

	if tracker and rs_node and rs_node.progression:
		var p_prof: Dictionary = tracker.get_profile()
		var p_rating: float = RunProgression.compute_performance_rating(
			player.health if is_instance_valid(player) else 5,
			player.max_health if is_instance_valid(player) else 5,
			p_prof
		)
		if p_rating < 0.85:
			hp_scale *= 0.85
		elif p_rating > 1.30:
			hp_scale *= 1.10

	var scaled_hp: int = maxi(15, int(roundf(float(boss.max_health) * hp_scale)))
	boss.max_health = scaled_hp
	boss.health = scaled_hp
	if "dash_speed" in boss and cur_sector == 1:
		boss.dash_speed *= 0.85 # Forgiving dash speed on first boss

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
	var rs_node = get_node_or_null("/root/RunState")
	var cur_sector: int = rs_node.progression.sector_index if (rs_node and rs_node.progression) else 1
	var minion_count := 1 if cur_sector == 1 else 2
	var minion_types: Array[PackedScene] = [CHASER_SCENE, SHOOTER_SCENE]
	var minion_fams: Array[String] = ["CHASER", "SHOOTER"]
	var offsets: Array[Vector2] = [Vector2(-130.0, -80.0), Vector2(-130.0, 80.0)]
	for i in range(minion_count):
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
						_apply_encounter_modifiers(enemy, 1.15, 0.85, flank, 0.5, false)
						encounter_director.evolution_manager.register_spawned_combatant(g, enemy)
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


func _apply_encounter_modifiers(
	enemy: Node2D,
	speed_mult: float,
	_telegraph_mult: float,
	flank_angle: float,
	lead_prediction: float,
	hazard_trail: bool
) -> void:
	if not is_instance_valid(enemy):
		return
	# Genome application picks the species behavior; the director's room-level
	# modifiers are layered afterward so they remain effective for this spawn.
	if "move_speed" in enemy:
		enemy.move_speed *= speed_mult
	if "patrol_speed" in enemy:
		enemy.patrol_speed *= speed_mult
	if "lunge_speed" in enemy:
		enemy.lunge_speed *= speed_mult
	if flank_angle != 0.0 and "flank_angle" in enemy:
		enemy.flank_angle = flank_angle
		if "is_flanker" in enemy:
			enemy.is_flanker = true
	if lead_prediction > 0.0 and "lead_prediction" in enemy:
		enemy.lead_prediction = maxf(float(enemy.lead_prediction), lead_prediction)
	if hazard_trail and "has_hazard_trail" in enemy:
		enemy.has_hazard_trail = true


func _on_enemy_defeated(enemy_node: Node2D) -> void:
	if run_over:
		return
	if encounter_director and encounter_director.evolution_manager and is_instance_valid(enemy_node) and "genome" in enemy_node:
		encounter_director.evolution_manager.record_combatant_defeated(enemy_node.genome, enemy_node)
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
		if current_room_data and current_room_data.room_type == "BOSS":
			if is_boss_core:
				room_cleared = true
				_on_room_cleared()
			return
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
	var cur_biome: int = rs.progression.current_biome if (rs and rs.progression) else (rs.current_biome if rs else 1)
	if encounter_director and tracker and rs:
		encounter_director.current_biome = cur_biome
		if encounter_director.evolution_manager:
			encounter_director.evolution_manager.current_biome = cur_biome
		new_adaptations = encounter_director.record_encounter_result(
			maxi(0, rs.progression.sector_index - 1) if rs.progression else maxi(0, rs.current_sector - 1),
			damage_taken_this_sector,
			sector_combat_time,
			tracker.get_profile(),
			current_sector_tactic,
			tracker,
			cur_biome,
			true
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
		MENU_SKIN.style_button(card, _menu_rarity_color(rarity))
		card.pressed.connect(_on_upgrade_selected.bind(item.id))
		upgrade_cards_box.add_child(card)

	upgrade_container.visible = true
	if is_instance_valid(special_menu_glitch):
		special_menu_glitch.visible = true


func _on_upgrade_selected(upgrade_id: String) -> void:
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("ui_click", 0.0, 0.0)
	upgrade_container.visible = false
	if is_instance_valid(special_menu_glitch):
		special_menu_glitch.visible = false
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


func _menu_rarity_color(rarity: String) -> Color:
	match rarity.to_upper():
		"RARE":
			return Color("c084fc")
		"UNCOMMON":
			return Color("22c55e")
		_:
			return Color("38bdf8")


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
	if not doors_unlocked or not room_cleared or not active_enemies.is_empty() or not pending_spawn_telegraphs.is_empty() or run_over:
		return
	if dungeon_layout and not dungeon_layout.corridors.is_empty():
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
	var cur_biome: int = rs.progression.current_biome if (rs and rs.progression) else (rs.current_biome if rs else 1)
	if encounter_director and tracker and rs:
		encounter_director.current_biome = cur_biome
		if encounter_director.evolution_manager:
			encounter_director.evolution_manager.current_biome = cur_biome
		encounter_director.record_encounter_result(
			maxi(0, rs.progression.sector_index - 1) if rs.progression else maxi(0, rs.current_sector - 1),
			damage_taken_this_sector,
			sector_combat_time,
			tracker.get_profile(),
			current_sector_tactic,
			tracker,
			cur_biome,
			false
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
	special_menu_glitch = MENU_GLITCH_SCRIPT.new()
	special_menu_glitch.layer = 30
	special_menu_glitch.visible = false
	add_child(special_menu_glitch)

	# Full and Empty Heart textures from assets/ui/hearts.png
	if hearts_tex:
		full_heart_tex = AtlasTexture.new()
		full_heart_tex.atlas = hearts_tex
		full_heart_tex.region = Rect2(0, 0, 32, 32)

		empty_heart_tex = AtlasTexture.new()
		empty_heart_tex.atlas = hearts_tex
		empty_heart_tex.region = Rect2(32, 0, 32, 32)

	# Responsive top HUD: health has its own high-contrast card so it stays visible
	# instead of being covered by the combat telemetry at narrow viewport sizes.
	var top_bar := PanelContainer.new()
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 12
	top_bar.offset_top = 10
	top_bar.offset_right = -12
	top_bar.offset_bottom = 58
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = Color(0.015, 0.03, 0.07, 0.94)
	top_style.border_color = Color(0.0, 0.75, 0.95, 0.42)
	top_style.set_border_width_all(1)
	top_style.set_corner_radius_all(10)
	top_style.content_margin_left = 7
	top_style.content_margin_right = 7
	top_style.content_margin_top = 5
	top_style.content_margin_bottom = 5
	top_bar.add_theme_stylebox_override("panel", top_style)
	ui_layer.add_child(top_bar)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 7)
	top_bar.add_child(top_row)

	var health_card := PanelContainer.new()
	health_card.custom_minimum_size = Vector2(150, 38)
	var health_style := StyleBoxFlat.new()
	health_style.bg_color = Color(0.16, 0.025, 0.065, 0.96)
	health_style.border_color = Color("fb496e")
	health_style.set_border_width_all(1)
	health_style.set_corner_radius_all(7)
	health_style.content_margin_left = 8
	health_style.content_margin_right = 8
	health_style.content_margin_top = 3
	health_style.content_margin_bottom = 3
	health_card.add_theme_stylebox_override("panel", health_style)
	top_row.add_child(health_card)
	var health_stack := VBoxContainer.new()
	health_stack.add_theme_constant_override("separation", 0)
	health_card.add_child(health_stack)
	health_label = Label.new()
	health_label.text = "HEALTH  5 / 5"
	health_label.add_theme_font_size_override("font_size", 13)
	health_label.add_theme_color_override("font_color", Color("ffe4ea"))
	health_stack.add_child(health_label)
	hearts_box = HBoxContainer.new()
	hearts_box.add_theme_constant_override("separation", 1)
	health_stack.add_child(hearts_box)

	var telemetry_pill := PanelContainer.new()
	telemetry_pill.custom_minimum_size = Vector2(220, 38)
	var telemetry_style := StyleBoxFlat.new()
	telemetry_style.bg_color = Color(0.03, 0.06, 0.12, 0.94)
	telemetry_style.border_color = Color("1e293b")
	telemetry_style.set_border_width_all(1)
	telemetry_style.set_corner_radius_all(8)
	telemetry_style.content_margin_left = 8
	telemetry_style.content_margin_right = 8
	telemetry_pill.add_theme_stylebox_override("panel", telemetry_style)
	top_row.add_child(telemetry_pill)
	var telemetry_vbox := VBoxContainer.new()
	telemetry_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	telemetry_vbox.add_theme_constant_override("separation", 1)
	telemetry_pill.add_child(telemetry_vbox)
	elims_label = Label.new()
	elims_label.text = "ELIMS 0  •  BITS 0"
	elims_label.add_theme_color_override("font_color", Color("38bdf8"))
	elims_label.add_theme_font_size_override("font_size", 11)
	telemetry_vbox.add_child(elims_label)
	ammo_label = Label.new()
	ammo_label.text = "CELLS 16 / 16"
	ammo_label.add_theme_color_override("font_color", Color("00f0ff"))
	ammo_label.add_theme_font_size_override("font_size", 11)
	telemetry_vbox.add_child(ammo_label)

	var sector_pill := PanelContainer.new()
	sector_pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sector_pill.custom_minimum_size = Vector2(160, 38)
	var sector_style := StyleBoxFlat.new()
	sector_style.bg_color = Color(0.02, 0.05, 0.10, 0.94)
	sector_style.border_color = Color("1e293b")
	sector_style.set_border_width_all(1)
	sector_style.set_corner_radius_all(8)
	sector_style.content_margin_left = 8
	sector_style.content_margin_right = 8
	sector_pill.add_theme_stylebox_override("panel", sector_style)
	top_row.add_child(sector_pill)
	sector_label = Label.new()
	sector_label.text = "BIOME 1 • SEC 1 • RM 1/6"
	sector_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sector_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sector_label.clip_text = true
	sector_label.add_theme_color_override("font_color", Color("38bdf8"))
	sector_label.add_theme_font_size_override("font_size", 11)
	sector_pill.add_child(sector_label)

	var pause_btn := Button.new()
	pause_btn.custom_minimum_size = Vector2(48, 38)
	pause_btn.text = "Ⅱ"
	var pause_btn_style := StyleBoxFlat.new()
	pause_btn_style.bg_color = Color(0.06, 0.10, 0.20, 0.95)
	pause_btn_style.border_color = Color("38bdf8")
	pause_btn_style.set_border_width_all(1)
	pause_btn_style.set_corner_radius_all(7)
	pause_btn.add_theme_stylebox_override("normal", pause_btn_style)
	pause_btn.add_theme_stylebox_override("hover", pause_btn_style)
	pause_btn.add_theme_stylebox_override("pressed", pause_btn_style)
	pause_btn.add_theme_color_override("font_color", Color("38bdf8"))
	pause_btn.pressed.connect(func():
		if not run_over and is_instance_valid(pause_menu):
			pause_menu.open_pause()
	)
	top_row.add_child(pause_btn)

	# Minimap remains anchored to the top-right on every aspect ratio.
	minimap_hud = MINIMAP_HUD_SCRIPT.new()
	minimap_hud.anchor_left = 1.0
	minimap_hud.anchor_right = 1.0
	minimap_hud.anchor_top = 0.0
	minimap_hud.anchor_bottom = 0.0
	minimap_hud.offset_left = -154.0
	minimap_hud.offset_right = -12.0
	minimap_hud.offset_top = 66.0
	minimap_hud.offset_bottom = 162.0
	minimap_hud.minimap_tapped.connect(func():
		if not run_over and is_instance_valid(pause_menu):
			pause_menu.open_pause()
	)
	ui_layer.add_child(minimap_hud)

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
	close_dbg_btn.text = "CLOSE"
	close_dbg_btn.pressed.connect(toggle_debug_overlay)
	dbg_btns_hbox.add_child(close_dbg_btn)

	hint_label = Label.new()
	hint_label.position = Vector2(24, 46)
	hint_label.text = "MOVE  •  AIM + FIRE  •  DASH  •  RELOAD  •  TAP Ⅱ TO PAUSE"
	hint_label.add_theme_color_override("font_color", Color("64748b"))
	hint_label.add_theme_font_size_override("font_size", 11)
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

	var draft_bg := MENU_BACKDROP_SCRIPT.new()
	draft_bg.accent = Color("c084fc")
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


func _init_transition_layer() -> void:
	transition_layer = CanvasLayer.new()
	transition_layer.name = "ScreenTransitions"
	transition_layer.layer = 50
	transition_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(transition_layer)
	transition_cover = ColorRect.new()
	transition_cover.name = "RoomReveal"
	transition_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	transition_cover.color = Color("030712")
	transition_cover.modulate.a = 1.0
	transition_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transition_layer.add_child(transition_cover)


func _animate_transition_cover(covered: bool, duration: float) -> void:
	if not is_instance_valid(transition_cover):
		return
	transition_cover.visible = true
	var target_alpha := 1.0 if covered else 0.0
	var transition_tween := create_tween()
	transition_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	transition_tween.set_trans(Tween.TRANS_CUBIC)
	transition_tween.set_ease(Tween.EASE_IN_OUT)
	transition_tween.tween_property(transition_cover, "modulate:a", target_alpha, duration)
	await transition_tween.finished
	if not covered:
		transition_cover.visible = false


func _show_director_banner(title: String, sub: String) -> void:
	if not is_instance_valid(director_banner):
		return
	if is_instance_valid(banner_tween) and banner_tween.is_running():
		banner_tween.kill()
	banner_title.text = title
	banner_sub.text = sub
	director_banner.visible = true
	director_banner.modulate.a = 0.0
	director_banner.position.y = 56.0
	director_banner.pivot_offset = director_banner.size * 0.5
	director_banner.scale = Vector2(0.96, 0.96)
	banner_tween = create_tween().set_parallel(true)
	banner_tween.tween_property(director_banner, "modulate:a", 1.0, 0.16)
	banner_tween.tween_property(director_banner, "position:y", 68.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	banner_tween.tween_property(director_banner, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	banner_timer = 4.0
	add_trauma(0.28)
	if Engine.has_singleton("AudioSynth") or get_node_or_null("/root/AudioSynth"):
		get_node("/root/AudioSynth").play("mutation_alert", 0.05, 0.0)


func _hide_director_banner() -> void:
	if not is_instance_valid(director_banner):
		return
	if is_instance_valid(banner_tween) and banner_tween.is_running():
		banner_tween.kill()
	banner_tween = create_tween().set_parallel(true)
	banner_tween.tween_property(director_banner, "modulate:a", 0.0, 0.18)
	banner_tween.tween_property(director_banner, "position:y", 56.0, 0.18)
	banner_tween.chain().tween_callback(func(): director_banner.visible = false)


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

	var active_muts: Array[String] = []
	if encounter_director and encounter_director.evolution_manager:
		active_muts = encounter_director.evolution_manager.get_active_mutations_summary()
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
