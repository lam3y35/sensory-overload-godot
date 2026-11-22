shader_type spatial;
render_mode unshaded, cull_back;

uniform float u_time = 0.0;
uniform float u_player_y = 0.0;
uniform float u_beat_phase = 0.0;
uniform float u_bass_energy = 0.0;
uniform float u_flow = 0.0;
uniform float u_flow_locked = 0.0;
uniform vec4 u_color_primary : source_color = vec4(0.08, 0.95, 0.85, 1.0);
uniform vec4 u_color_accent : source_color = vec4(1.0, 0.18, 0.58, 1.0);
uniform vec4 u_color_bg : source_color = vec4(0.05, 0.02, 0.12, 1.0);

uniform float u_bit_breathing = 0.0;
uniform float u_bit_twist = 0.0;
uniform float u_bit_wobble = 0.0;
uniform float u_bit_pulse = 0.0;
uniform float u_bit_palette_cycle = 0.0;
uniform float u_bit_checker = 1.0;
uniform float u_bit_wireframe = 0.0;
uniform float u_bit_depth_fog = 0.0;

varying vec4 v_custom;
varying vec3 v_world_pos;
varying float v_depth_rel;

vec3 hue_rotate(vec3 col, float angle) {
	const vec3 k = vec3(0.57735026919);
	float cos_a = cos(angle);
	float sin_a = sin(angle);
	return col * cos_a + cross(k, col) * sin_a + k * dot(k, col) * (1.0 - cos_a);
}

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	vec4 world_origin = MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float rel_y = u_player_y - world_origin.y;
	v_depth_rel = max(0.0, rel_y);

	vec3 pos = VERTEX;
	// Beat scale pulse on individual voxel wall blocks
	float beat_kick = exp(-u_beat_phase * 4.5);
	pos *= 1.0 + u_bit_pulse * 0.14 * (0.4 * beat_kick + 0.6 * u_bass_energy);

	vec4 wp = MODEL_MATRIX * vec4(pos, 1.0);

	// Breathing radial expansion/contraction along tunnel depth
	float breath = sin(rel_y * 0.12 - u_time * 3.1) * 0.85 * u_bit_breathing;
	vec2 radial_dir = normalize(wp.xz + vec2(0.0001));
	wp.xz += radial_dir * breath;

	// Axial corkscrew twist with depth
	float twist_angle = rel_y * 0.018 * u_bit_twist * sin(u_time * 0.65 + 0.7);
	float ct = cos(twist_angle);
	float st = sin(twist_angle);
	wp.xz = mat2(vec2(ct, -st), vec2(st, ct)) * wp.xz;

	// Serpentine tunnel wobble ahead of player
	wp.x += sin(rel_y * 0.055 - u_time * 2.4) * 1.45 * u_bit_wobble;
	wp.z += cos(rel_y * 0.048 - u_time * 2.0) * 1.45 * u_bit_wobble;

	v_world_pos = wp.xyz;
	VERTEX = (inverse(MODEL_MATRIX) * wp).xyz;
}

void fragment() {
	float beat_kick = exp(-u_beat_phase * 4.0);
	float ring_idx = v_custom.r;
	float alt_flag = v_custom.g;

	vec3 c_prim = u_color_primary.rgb;
	vec3 c_acc = u_color_accent.rgb;
	if (u_bit_palette_cycle > 0.5 || u_flow_locked > 0.5) {
		float shift = u_time * (0.55 + 0.9 * u_flow_locked) + ring_idx * 0.35;
		c_prim = hue_rotate(c_prim, shift);
		c_acc = hue_rotate(c_acc, shift * 1.15);
	}

	// Checkerboard alternation + subtle voxel bevel
	float checker = mix(0.35, 1.0, alt_flag);
	if (u_bit_checker > 0.5) {
		float scroll = step(0.5, fract(ring_idx * 0.5 - u_time * 1.8));
		checker = mix(0.22, 1.0, abs(alt_flag - scroll));
	}

	vec2 edge_dist = min(UV, 1.0 - UV);
	float edge_min = min(edge_dist.x, edge_dist.y);
	float bevel = smoothstep(0.0, 0.14, edge_min);
	float wire = 1.0 - smoothstep(0.02, 0.085, edge_min);

	vec3 base_col = mix(u_color_bg.rgb * 1.8, mix(c_prim, c_acc, alt_flag), checker);
	base_col *= mix(0.68, 1.08, bevel);

	// Wireframe glow overlay + beat music-lock pulse
	float glow_boost = u_bit_wireframe * wire * (1.2 + 0.8 * beat_kick);
	float lock_boost = u_flow_locked * beat_kick * 0.45;
	vec3 final_col = base_col + c_acc * glow_boost + mix(c_prim, c_acc, 0.5) * lock_boost;

	// Depth fog fade down the shaft
	float fog_dist = mix(155.0, 115.0 + 30.0 * sin(u_time * 4.0), u_bit_depth_fog);
	float fog_t = clamp(v_depth_rel / max(40.0, fog_dist), 0.0, 1.0);
	fog_t = pow(fog_t, 1.45);
	ALBEDO = mix(final_col, u_color_bg.rgb, fog_t);
}
