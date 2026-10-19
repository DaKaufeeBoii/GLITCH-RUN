extends Control
## Lightweight virtual joystick and right-side hold-to-fire area.

signal move_changed(direction: Vector2)
signal aim_changed(direction: Vector2)
signal fire_changed(is_firing: bool)
signal dash_pressed
signal reload_pressed

var enabled := true:
	set(val):
		enabled = val
		if not enabled:
			move_finger = -1
			fire_finger = -1
			move_vector = Vector2.ZERO
			fire_vector = Vector2.ZERO
			move_changed.emit(Vector2.ZERO)
			fire_changed.emit(false)
			aim_changed.emit(Vector2.ZERO)
			queue_redraw()

var move_finger := -1
var fire_finger := -1
var move_origin := Vector2.ZERO
var move_vector := Vector2.ZERO
var fire_origin := Vector2.ZERO
var fire_position := Vector2.ZERO
var fire_vector := Vector2.ZERO
var dash_ready := true
var reload_ready := true
const JOYSTICK_RADIUS := 66.0
const DASH_RADIUS := 48.0
const RELOAD_RADIUS := 36.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		reset_controls()


func reset_controls() -> void:
	move_finger = -1
	fire_finger = -1
	move_vector = Vector2.ZERO
	fire_vector = Vector2.ZERO
	move_changed.emit(Vector2.ZERO)
	fire_changed.emit(false)
	aim_changed.emit(Vector2.ZERO)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not enabled or not is_visible_in_tree() or (is_inside_tree() and get_tree().paused):
		if move_finger != -1 or fire_finger != -1:
			reset_controls()
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	var point := event.position
	if event.pressed:
		if _is_dash_button(point):
			if dash_ready:
				dash_pressed.emit()
				dash_ready = false
			return
		if _is_reload_button(point):
			if reload_ready:
				reload_pressed.emit()
				reload_ready = false
			return
		if point.x < size.x * 0.48 and move_finger == -1:
			move_finger = event.index
			move_origin = point
			_update_move(point)
		elif point.x >= size.x * 0.48 and fire_finger == -1:
			fire_finger = event.index
			fire_origin = point
			fire_position = point
			fire_changed.emit(true)
			_update_aim(point)
	else:
		if event.index == move_finger:
			move_finger = -1
			move_vector = Vector2.ZERO
			move_changed.emit(Vector2.ZERO)
		elif event.index == fire_finger:
			fire_finger = -1
			fire_vector = Vector2.ZERO
			fire_changed.emit(false)
			aim_changed.emit(Vector2.ZERO)
		if _is_dash_button(point):
			dash_ready = true
		if _is_reload_button(point):
			reload_ready = true
	queue_redraw()


func _handle_drag(event: InputEventScreenDrag) -> void:
	if event.index == move_finger:
		_update_move(event.position)
	elif event.index == fire_finger:
		fire_position = event.position
		_update_aim(event.position)
	queue_redraw()


func _update_move(point: Vector2) -> void:
	var offset := point - move_origin
	move_vector = (offset / JOYSTICK_RADIUS).limit_length(1.0)
	move_changed.emit(move_vector)
	queue_redraw()


func _update_aim(point: Vector2) -> void:
	var offset := point - fire_origin
	fire_vector = (offset / JOYSTICK_RADIUS).limit_length(1.0)
	if offset.length() > 8.0:
		aim_changed.emit(offset.normalized())
	queue_redraw()


func _is_dash_button(point: Vector2) -> bool:
	var center := Vector2(size.x - 78.0, size.y - 82.0)
	return point.distance_to(center) <= DASH_RADIUS


func _is_reload_button(point: Vector2) -> bool:
	var center := Vector2(size.x - 78.0, size.y - 180.0)
	return point.distance_to(center) <= RELOAD_RADIUS


func _draw() -> void:
	if not OS.has_feature("mobile") and not DisplayServer.is_touchscreen_available() and not ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", false):
		return
	# Movement virtual joystick (left)
	var move_center := move_origin if move_finger != -1 else Vector2(120.0, size.y - 110.0)
	draw_circle(move_center, JOYSTICK_RADIUS, Color(0.15, 0.28, 0.45, 0.24))
	draw_arc(move_center, JOYSTICK_RADIUS, 0.0, TAU, 48, Color(0.35, 0.78, 0.92, 0.55), 2.0)
	var move_knob := move_vector * 38.0 if move_finger != -1 else Vector2.ZERO
	draw_circle(move_center + move_knob, 27.0, Color(0.35, 0.78, 0.92, 0.55))

	# Dash button (bottom right)
	var dash_center := Vector2(size.x - 78.0, size.y - 82.0)
	draw_circle(dash_center, DASH_RADIUS, Color(0.72, 0.24, 0.54, 0.48))
	draw_arc(dash_center, DASH_RADIUS, 0.0, TAU, 48, Color("ff83d0"), 3.0)
	draw_string(ThemeDB.fallback_font, dash_center + Vector2(-18, 6), "DASH", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

	# Reload button (above dash button, right side)
	var reload_center := Vector2(size.x - 78.0, size.y - 180.0)
	draw_circle(reload_center, RELOAD_RADIUS, Color(0.12, 0.22, 0.38, 0.55))
	draw_arc(reload_center, RELOAD_RADIUS, 0.0, TAU, 36, Color("38bdf8"), 2.5)
	draw_arc(reload_center, RELOAD_RADIUS * 0.55, 0.4, 5.6, 24, Color("7dd3fc"), 2.0)
	draw_string(ThemeDB.fallback_font, reload_center + Vector2(-20, 4), "RELOAD", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("e0f2fe"))

	# Aim / Fire virtual joystick (right)
	if fire_finger != -1:
		draw_circle(fire_origin, JOYSTICK_RADIUS, Color(0.45, 0.32, 0.15, 0.24))
		draw_arc(fire_origin, JOYSTICK_RADIUS, 0.0, TAU, 48, Color(0.95, 0.78, 0.36, 0.55), 2.0)
		var fire_knob := fire_vector * 38.0
		draw_circle(fire_origin + fire_knob, 24.0, Color("ffc95c"))

