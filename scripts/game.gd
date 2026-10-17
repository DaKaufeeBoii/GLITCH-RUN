extends Node2D
## Owns the prototype room, its boundaries, score, and run-over UI.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemies/chaser.tscn")
const TOUCH_CONTROLS := preload("res://scripts/mobile_controls.gd")

const ROOM_RECT := Rect2(42.0, 64.0, 876.0, 424.0)

var player
var enemy
var score := 0
var run_over := false
var respawn_timer := 0.0

var status_label: Label
var hint_label: Label
var restart_button: Button


func _ready() -> void:
	_create_walls()
	_create_ui()
	_create_player()
	_create_enemy()
	queue_redraw()


func _process(delta: float) -> void:
	if run_over:
		return
	if is_instance_valid(player):
		status_label.text = "HP  %d / %d      ELIMS  %d" % [player.health, player.max_health, score]
	if not is_instance_valid(enemy) and respawn_timer > 0.0:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			_create_enemy()


func _draw() -> void:
	# Low-contrast floor grid keeps the prototype readable without finished art.
	for x in range(int(ROOM_RECT.position.x), int(ROOM_RECT.end.x), 32):
		draw_line(Vector2(x, ROOM_RECT.position.y), Vector2(x, ROOM_RECT.end.y), Color("182344"), 1.0)
	for y in range(int(ROOM_RECT.position.y), int(ROOM_RECT.end.y), 32):
		draw_line(Vector2(ROOM_RECT.position.x, y), Vector2(ROOM_RECT.end.x, y), Color("182344"), 1.0)
	draw_rect(ROOM_RECT, Color("42d9ec"), false, 2.0)


func _create_walls() -> void:
	_add_wall(Vector2(ROOM_RECT.position.x, ROOM_RECT.position.y - 10), Vector2(ROOM_RECT.size.x, 20))
	_add_wall(Vector2(ROOM_RECT.position.x, ROOM_RECT.end.y + 10), Vector2(ROOM_RECT.size.x, 20))
	_add_wall(Vector2(ROOM_RECT.position.x - 10, ROOM_RECT.position.y), Vector2(20, ROOM_RECT.size.y))
	_add_wall(Vector2(ROOM_RECT.end.x + 10, ROOM_RECT.position.y), Vector2(20, ROOM_RECT.size.y))


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


func _create_player() -> void:
	player = PLAYER_SCENE.instantiate()
	player.position = ROOM_RECT.get_center()
	player.connect("health_changed", Callable(self, "_on_player_health_changed"))
	player.connect("died", Callable(self, "_on_player_died"))
	add_child(player)

	var controls = Control.new()
	controls.set_script(TOUCH_CONTROLS)
	controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	controls.connect("move_changed", Callable(player, "set_touch_move"))
	controls.connect("aim_changed", Callable(player, "set_touch_aim"))
	controls.connect("fire_changed", Callable(player, "set_touch_fire"))
	controls.connect("dash_pressed", Callable(player, "try_dash"))
	$UI.add_child(controls)


func _create_enemy() -> void:
	if run_over or not is_instance_valid(player):
		return
	enemy = ENEMY_SCENE.instantiate()
	var spawn_direction := Vector2(1, 0.55).rotated(randf_range(-PI, PI))
	enemy.position = ROOM_RECT.get_center() + spawn_direction * 220.0
	enemy.target = player
	enemy.connect("defeated", Callable(self, "_on_enemy_defeated"))
	add_child(enemy)


func _create_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)

	status_label = Label.new()
	status_label.position = Vector2(30, 18)
	status_label.add_theme_color_override("font_color", Color("e4f7ff"))
	status_label.add_theme_font_size_override("font_size", 22)
	layer.add_child(status_label)

	hint_label = Label.new()
	hint_label.position = Vector2(30, 44)
	hint_label.text = "WASD / arrows move   •   Mouse aim + fire   •   Shift dash   •   Touch controls supported"
	hint_label.add_theme_color_override("font_color", Color("9db4d7"))
	hint_label.add_theme_font_size_override("font_size", 14)
	layer.add_child(hint_label)

	restart_button = Button.new()
	restart_button.text = "RESTART RUN"
	restart_button.position = Vector2(392, 310)
	restart_button.size = Vector2(176, 52)
	restart_button.visible = false
	restart_button.pressed.connect(_restart_run)
	layer.add_child(restart_button)


func _on_enemy_defeated() -> void:
	if run_over:
		return
	score += 1
	respawn_timer = 0.8


func _on_player_health_changed(_current: int, _maximum: int) -> void:
	if is_instance_valid(enemy):
		enemy.target = player


func _on_player_died() -> void:
	run_over = true
	if is_instance_valid(enemy):
		enemy.set_physics_process(false)
	var overlay := ColorRect.new()
	overlay.color = Color(0.01, 0.02, 0.06, 0.72)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$UI.add_child(overlay)
	# Put the dark overlay behind the game-over text and restart button.
	$UI.move_child(overlay, 0)
	var title := Label.new()
	title.text = "RUN TERMINATED"
	title.position = Vector2(350, 240)
	title.add_theme_color_override("font_color", Color("ff5578"))
	title.add_theme_font_size_override("font_size", 34)
	$UI.add_child(title)
	restart_button.visible = true


func _restart_run() -> void:
	get_tree().reload_current_scene()

