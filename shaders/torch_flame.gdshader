shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, unshaded;

// ─── Torch Flame Shader ──────────────────────────────────────────────────────
// Animated stylized flame with UV distortion, flickering, and emissive glow.

uniform vec4 flame_color_hot  : source_color = vec4(1.0, 0.95, 0.5, 1.0);
uniform vec4 flame_color_mid  : source_color = vec4(1.0, 0.45, 0.05, 1.0);
uniform vec4 flame_color_cool : source_color = vec4(0.5, 0.05, 0.0, 0.0);
uniform float flicker_speed   : hint_range(0.5, 8.0) = 4.5;
uniform float flicker_amplitude : hint_range(0.0, 0.5) = 0.12;
uniform float flame_height    : hint_range(0.1, 2.0) = 0.85;
uniform float emission_strength : hint_range(1.0, 20.0) = 8.0;

// Noise
float hash(float n) { return fract(sin(n) * 43758.5453); }

float noise1d(float t) {
	float i = floor(t);
	float f = fract(t);
	return mix(hash(i), hash(i + 1.0), smoothstep(0.0, 1.0, f));
}

float noise2d(vec2 uv) {
	vec2 i = floor(uv);
	vec2 f = fract(uv);
	float a = hash(i.x + i.y * 57.0);
	float b = hash(i.x + 1.0 + i.y * 57.0);
	float c = hash(i.x + (i.y + 1.0) * 57.0);
	float d = hash(i.x + 1.0 + (i.y + 1.0) * 57.0);
	vec2 s = smoothstep(vec2(0.0), vec2(1.0), f);
	return mix(mix(a, b, s.x), mix(c, d, s.x), s.y);
}

void fragment() {
	vec2 uv = UV;

	// Flicker offset driven by TIME
	float flicker = noise1d(TIME * flicker_speed) * flicker_amplitude;
	float flicker2 = noise1d(TIME * flicker_speed * 0.7 + 3.1) * flicker_amplitude * 0.6;

	// Distort UVs for organic flame shape
	vec2 distorted_uv = uv + vec2(
		noise2d(uv * 3.0 + vec2(TIME * 0.8, 0.0)) * 0.12 + flicker,
		noise2d(uv * 2.5 + vec2(0.0, TIME * 1.2)) * 0.08 + flicker2
	);

	// Vertical gradient: hot at bottom, transparent at top
	float height_grad = 1.0 - pow(clamp(distorted_uv.y / flame_height, 0.0, 1.0), 1.5);
	// Horizontal narrowing
	float width_mask = 1.0 - pow(abs(distorted_uv.x - 0.5) * 2.2, 2.0);
	float flame_shape = clamp(height_grad * max(width_mask, 0.0), 0.0, 1.0);

	// Color gradient
	vec3 color = mix(flame_color_cool.rgb, flame_color_mid.rgb, flame_shape);
	color = mix(color, flame_color_hot.rgb, pow(flame_shape, 3.0));

	float alpha = flame_shape * flame_shape;

	ALBEDO    = color;
	EMISSION  = color * flame_shape * emission_strength;
	ALPHA     = alpha;
}
