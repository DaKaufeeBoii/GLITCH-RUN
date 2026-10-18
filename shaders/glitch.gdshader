shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float glitch_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float chromatic_offset : hint_range(0.0, 0.08) = 0.0;
uniform float scanline_alpha : hint_range(0.0, 0.3) = 0.06;

// Pseudo-random generator
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// Slicing horizontal displacement when glitching
	if (glitch_intensity > 0.005) {
		float slice_y = floor(uv.y * 32.0);
		float slice_rnd = hash(vec2(slice_y, floor(TIME * 28.0)));
		if (slice_rnd < glitch_intensity * 0.60) {
			float shift = (hash(vec2(slice_y, floor(TIME * 42.0))) - 0.5) * glitch_intensity * 0.08;
			uv.x = clamp(uv.x + shift, 0.0, 1.0);
		}

		// Digital block jitter
		vec2 block_p = floor(uv * vec2(36.0, 24.0));
		if (hash(block_p + floor(TIME * 24.0)) < glitch_intensity * 0.12) {
			uv += (vec2(hash(block_p), hash(block_p + 1.0)) - 0.5) * glitch_intensity * 0.035;
			uv = clamp(uv, 0.0, 1.0);
		}
	}

	// Chromatic Aberration (RGB channel split)
	float split = chromatic_offset + glitch_intensity * 0.022;
	float r = texture(screen_texture, vec2(clamp(uv.x + split, 0.0, 1.0), uv.y)).r;
	float g = texture(screen_texture, uv).g;
	float b = texture(screen_texture, vec2(clamp(uv.x - split, 0.0, 1.0), uv.y)).b;

	vec3 col = vec3(r, g, b);

	// Crimson damage distortion when glitching heavily
	if (glitch_intensity > 0.15) {
		float dmg_factor = (glitch_intensity - 0.15) * 0.4;
		col.r = mix(col.r, 1.0, dmg_factor);
		col.g = mix(col.g, col.g * 0.7, dmg_factor);
		col.b = mix(col.b, col.b * 0.7, dmg_factor);
	}

	// Subtle retro cyber scanlines
	float scanline = sin(uv.y * 540.0 * 3.14159) * 0.5 + 0.5;
	col -= scanline * scanline_alpha * (0.6 + glitch_intensity * 0.8);

	COLOR = vec4(col, 1.0);
}
