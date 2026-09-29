shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ─── Gothic Flagstone Shader ─────────────────────────────────────────────────
// Dark weathered stone with procedural grime, moss, and crack detail.

uniform vec4 stone_color_a : source_color = vec4(0.38, 0.36, 0.40, 1.0);
uniform vec4 stone_color_b : source_color = vec4(0.26, 0.24, 0.28, 1.0);
uniform vec4 crack_color   : source_color = vec4(0.12, 0.11, 0.13, 1.0);
uniform vec4 moss_color    : source_color = vec4(0.18, 0.32, 0.18, 1.0);
uniform float tile_scale   : hint_range(0.5, 10.0) = 3.5;
uniform float crack_sharpness : hint_range(2.0, 30.0) = 12.0;
uniform float moss_amount  : hint_range(0.0, 1.0) = 0.18;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.88;
uniform float grime_intensity : hint_range(0.0, 1.0) = 0.35;

// Simple hash functions for procedural generation
vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float voronoi(vec2 uv) {
	vec2 i = floor(uv);
	vec2 f = fract(uv);
	float dist = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = hash2(i + neighbor);
			point = 0.5 + 0.5 * sin(point * 6.2831);
			float d = length(neighbor + point - f);
			dist = min(dist, d);
		}
	}
	return dist;
}

float fbm(vec2 uv) {
	float v = 0.0;
	float a = 0.5;
	vec2 shift = vec2(100.0);
	mat2 rot = mat2(vec2(cos(0.5), sin(0.5)), vec2(-sin(0.5), cos(0.5)));
	for (int i = 0; i < 4; i++) {
		v += a * (voronoi(uv) * 0.5 + 0.5);
		uv = rot * uv * 2.0 + shift;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV * tile_scale;

	// Flagstone grid with rounded cells
	vec2 grid_uv = fract(uv);
	float crack_x = pow(1.0 - abs(grid_uv.x - 0.5) * 2.0, crack_sharpness);
	float crack_y = pow(1.0 - abs(grid_uv.y - 0.5) * 2.0, crack_sharpness);
	float stone_mask = crack_x * crack_y;

	// Per-tile variation via cell ID
	vec2 cell_id = floor(uv);
	vec2 cell_hash = hash2(cell_id);
	float stone_var = cell_hash.x * 0.25 + cell_hash.y * 0.15;

	// Base stone color
	vec3 stone_col = mix(stone_color_b.rgb, stone_color_a.rgb, stone_var + stone_mask * 0.3);

	// Grime / detail noise
	float grime = fbm(uv * 0.7 + cell_hash);
	stone_col = mix(stone_col, stone_col * 0.55, grime * grime_intensity);

	// Crack darkening
	float crack_factor = smoothstep(0.0, 0.25, stone_mask);
	stone_col = mix(crack_color.rgb, stone_col, crack_factor);

	// Moss in crevices and low spots
	float moss_mask = (1.0 - crack_factor) * moss_amount + max(0.0, -NORMAL.y * 0.5);
	stone_col = mix(stone_col, moss_color.rgb, clamp(moss_mask, 0.0, 1.0));

	// Slight emissive from torch-lit runes (very subtle)
	float rune_glow = smoothstep(0.85, 1.0, grime) * 0.04;
	vec3 emissive = vec3(0.3, 0.1, 0.5) * rune_glow;

	ALBEDO   = stone_col;
	ROUGHNESS = roughness_base + grime * 0.12 - stone_var * 0.08;
	METALLIC  = 0.0;
	EMISSION  = emissive;
}
