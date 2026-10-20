extends CanvasLayer
## Full-screen signal distortion with occasional stronger tears on menu screens.

var glitch_material: ShaderMaterial
var burst_clock := 0.0
var next_burst := 2.0
var burst_duration := 0.0
var burst_strength := 0.0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	next_burst = rng.randf_range(0.8, 2.0)
	var back_buffer := BackBufferCopy.new()
	back_buffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	back_buffer.rect = get_viewport().get_visible_rect()
	add_child(back_buffer)
	var distortion := ColorRect.new()
	distortion.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	distortion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader: Shader = load("res://shaders/glitch.gdshader")
	if shader:
		glitch_material = ShaderMaterial.new()
		glitch_material.shader = shader
		distortion.material = glitch_material
		glitch_material.set_shader_parameter("glitch_intensity", 0.025)
		glitch_material.set_shader_parameter("chromatic_offset", 0.002)
		glitch_material.set_shader_parameter("scanline_alpha", 0.12)
	add_child(distortion)


func _process(delta: float) -> void:
	burst_clock += delta
	if burst_duration > 0.0:
		burst_duration = maxf(0.0, burst_duration - delta)
	if burst_clock >= next_burst:
		burst_clock = 0.0
		burst_duration = rng.randf_range(0.12, 0.24)
		burst_strength = rng.randf_range(0.65, 0.95)
		next_burst = rng.randf_range(1.4, 3.2)
	if glitch_material:
		var intensity: float = burst_strength if burst_duration > 0.0 else 0.025
		var chromatic: float = 0.002 + (0.018 if burst_duration > 0.0 else 0.0)
		glitch_material.set_shader_parameter("glitch_intensity", intensity)
		glitch_material.set_shader_parameter("chromatic_offset", chromatic)
