shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float glitch_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float chromatic_offset : hint_range(0.0, 0.04) = 0.0;
uniform float scanline_alpha : hint_range(0.0, 0.3) = 0.08;

// Pseudo-random generator
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// Slicing horizontal displacement when glitching
	if (glitch_intensity > 0.01) {
		float slice_y = floor(uv.y * 36.0);
		float slice_rnd = hash(vec2(slice_y, floor(TIME * 22.0)));
		if (slice_rnd < glitch_intensity * 0.45) {
			float shift = (hash(vec2(slice_y, floor(TIME * 33.0))) - 0.5) * glitch_intensity * 0.06;
			uv.x = clamp(uv.x + shift, 0.0, 1.0);
		}
	}

	// Chromatic Aberration (RGB channel split)
	float split = chromatic_offset + glitch_intensity * 0.015;
	float r = texture(screen_texture, vec2(clamp(uv.x + split, 0.0, 1.0), uv.y)).r;
	float g = texture(screen_texture, uv).g;
	float b = texture(screen_texture, vec2(clamp(uv.x - split, 0.0, 1.0), uv.y)).b;

	vec3 col = vec3(r, g, b);

	// Subtle cyber scanlines
	float scanline = sin(uv.y * 540.0 * 3.14159) * 0.5 + 0.5;
	col -= scanline * scanline_alpha;

	COLOR = vec4(col, 1.0);
}
