shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ─── Weathered Gothic Stone Wall Shader ─────────────────────────────────────
// Used for columns, arches, and perimeter walls.

uniform vec4 stone_dark    : source_color = vec4(0.07, 0.06, 0.08, 1.0);
uniform vec4 stone_light   : source_color = vec4(0.18, 0.16, 0.20, 1.0);
uniform vec4 rust_color    : source_color = vec4(0.25, 0.10, 0.04, 1.0);
uniform vec4 lichen_color  : source_color = vec4(0.08, 0.14, 0.08, 1.0);
uniform float scale        : hint_range(0.1, 5.0) = 1.5;
uniform float roughness_v  : hint_range(0.0, 1.0) = 0.92;
uniform float lichen_amount : hint_range(0.0, 1.0) = 0.15;
uniform float rust_amount  : hint_range(0.0, 1.0) = 0.12;
uniform float damage_pattern : hint_range(0.0, 1.0) = 0.4;  // Crumble/damage marks

float hash31(vec3 p) {
	p = fract(p * vec3(443.8975, 397.2973, 491.1871));
	p += dot(p.xyz, p.yzx + 19.19);
	return fract(p.x * p.y * p.z);
}

float fbm3(vec3 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * hash31(p);
		p = p * 2.01 + vec3(1.7, 9.2, 3.4);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec3 p = VERTEX * scale;

	float n = fbm3(p);
	float n2 = fbm3(p * 2.5 + vec3(3.3, 7.1, 2.8));

	// Base stone
	vec3 col = mix(stone_dark.rgb, stone_light.rgb, n);

	// Damage marks / pitting
	float damage = smoothstep(0.5, 0.7, n2) * damage_pattern;
	col = mix(col, stone_dark.rgb * 0.4, damage);

	// Rust streaks (vertical)
	float rust = smoothstep(0.6, 0.8, fbm3(p * vec3(0.3, 1.5, 0.3))) * rust_amount;
	col = mix(col, rust_color.rgb, rust);

	// Lichen on top surfaces
	float up_factor = clamp(dot(NORMAL, vec3(0.0, 1.0, 0.0)), 0.0, 1.0);
	float lichen = fbm3(p * 2.0 + vec3(5.0)) * up_factor * lichen_amount;
	col = mix(col, lichen_color.rgb, lichen);

	// Very subtle rune emissive
	float rune = smoothstep(0.88, 1.0, n) * 0.03;
	vec3 emissive = vec3(0.2, 0.05, 0.4) * rune;

	ALBEDO    = col;
	ROUGHNESS = roughness_v + n * 0.08;
	METALLIC  = 0.0;
	EMISSION  = emissive;
}
