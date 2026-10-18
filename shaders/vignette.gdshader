shader_type canvas_item;

uniform vec4 vignette_color : source_color = vec4(0.88, 0.04, 0.12, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_speed : hint_range(0.5, 12.0) = 4.0;
uniform float pulse_strength : hint_range(0.0, 0.6) = 0.25;
uniform float inner_radius : hint_range(0.0, 1.2) = 0.45;
uniform float outer_radius : hint_range(0.2, 1.8) = 1.05;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 center = vec2(0.5, 0.5);
	// Correct for 16:9 aspect ratio so vignette corners are visually symmetrical
	vec2 aspect_uv = (uv - center) * vec2(1.7778, 1.0);
	float dist = length(aspect_uv);

	// Rhythmic heartbeat breathing pulse
	float pulse = sin(TIME * pulse_speed) * pulse_strength;
	float effective_intensity = clamp(intensity + pulse * intensity, 0.0, 1.0);

	// Radial falloff from center to corners
	float vig = smoothstep(inner_radius, outer_radius, dist);
	float alpha = vig * effective_intensity;

	COLOR = vec4(vignette_color.rgb, alpha * vignette_color.a);
}
