extends Control
## Shared animated blueprint backdrop for secondary screens.

var accent := Color("38bdf8")
var clock := 0.0
var rng := RandomNumberGenerator.new()
var next_tear := 0.8
var tear_remaining := 0.0
var tear_bands: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(true)
	rng.randomize()


func _process(delta: float) -> void:
	clock += delta
	next_tear -= delta
	if tear_remaining > 0.0:
		tear_remaining = maxf(0.0, tear_remaining - delta)
	elif next_tear <= 0.0:
		tear_remaining = rng.randf_range(0.055, 0.11)
		next_tear = rng.randf_range(0.9, 2.1)
		tear_bands.clear()
		for i in range(rng.randi_range(2, 4)):
			tear_bands.append({
				"rect": Rect2(rng.randf_range(18.0, maxf(19.0, size.x * 0.72)), rng.randf_range(24.0, maxf(25.0, size.y - 24.0)), rng.randf_range(36.0, maxf(37.0, size.x * 0.28)), rng.randf_range(1.0, 3.0)),
				"color": Color("ff2e88") if i % 2 == 0 else accent
			})
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("040916"), true)
	var step := 32
	for x in range(0, int(size.x) + step, step):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.12, 0.28, 0.40, 0.14), 1.0)
	for y in range(0, int(size.y) + step, step):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.12, 0.28, 0.40, 0.14), 1.0)
	draw_rect(Rect2(Vector2(18, 18), size - Vector2(36, 36)), Color(accent.r, accent.g, accent.b, 0.42), false, 1.0)
	draw_line(Vector2(18, 48), Vector2(size.x - 18, 48), Color(accent.r, accent.g, accent.b, 0.32), 1.0)
	var scan_y := fposmod(clock * 90.0, maxf(1.0, size.y))
	draw_line(Vector2(20, scan_y), Vector2(size.x - 20, scan_y), Color(accent.r, accent.g, accent.b, 0.08), 2.0)
	if tear_remaining > 0.0:
		for band in tear_bands:
			var tear: Rect2 = band["rect"]
			var tear_color: Color = band["color"]
			draw_rect(tear, Color(tear_color.r, tear_color.g, tear_color.b, 0.72), true)
			draw_rect(Rect2(tear.position + Vector2(-7, 3), Vector2(tear.size.x * 0.62, 1)), Color(tear_color.r, tear_color.g, tear_color.b, 0.38), true)
