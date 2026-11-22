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
uniform vec4 u_color_bg : source_color = vec4(0.03, 0.015, 0.08, 1.0);

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
	float beat_kick = exp(-u_beat_phase * 4.5);
	pos *= 1.0 + u_bit_pulse * 0.10 * (0.4 * beat_kick + 0.6 * u_bass_energy);

	vec4 wp = MODEL_MATRIX * vec4(pos, 1.0);

	// Smooth radial breathing without wall clipping
	float breath = sin(rel_y * 0.11 - u_time * 2.8) * 0.72 * u_bit_breathing;
	vec2 radial_dir = normalize(wp.xz + vec2(0.0001));
	wp.xz += radial_dir * breath;

	// Smooth axial corkscrew twist down depth
	float twist_angle = rel_y * 0.016 * u_bit_twist * sin(u_time * 0.55 + 0.7);
	float ct = cos(twist_angle);
	float st = sin(twist_angle);
	wp.xz = mat2(vec2(ct, -st), vec2(st, ct)) * wp.xz;

	// Smooth serpentine tunnel wobble ahead of player
	wp.x += sin(rel_y * 0.050 - u_time * 2.2) * 1.25 * u_bit_wobble;
	wp.z += cos(rel_y * 0.044 - u_time * 1.9) * 1.25 * u_bit_wobble;

	v_world_pos = wp.xyz;
	VERTEX = (inverse(MODEL_MATRIX) * wp).xyz;
}

void fragment() {
	float beat_kick = exp(-u_beat_phase * 4.2);
	float ring_idx = v_custom.r;
	float alt_flag = v_custom.g;

	// Deep obsidian/midnight backdrop mixed with neon trim so obstacles always dominate figure-ground
	vec3 bg_dark = clamp(u_color_bg.rgb * 0.85, vec3(0.012, 0.006, 0.03), vec3(0.14, 0.10, 0.22));
	vec3 trim_prim = u_color_primary.rgb;
	vec3 trim_acc = u_color_accent.rgb;

	if (u_bit_palette_cycle > 0.5) {
		float shift = sin(u_time * 0.45 + ring_idx * 0.12) * 0.48;
		trim_prim = hue_rotate(trim_prim, shift);
		trim_acc = hue_rotate(trim_acc, shift * 1.15);
	}

	// Electric Overdrive palette when Flow Color Lock is active (deep indigo + cyan/magenta/gold seams)
	if (u_flow_locked > 0.5) {
		bg_dark = mix(bg_dark, vec3(0.04, 0.02, 0.14), 0.75);
		trim_prim = mix(vec3(0.08, 0.96, 0.90), vec3(0.98, 0.82, 0.22), 0.35 + 0.35 * sin(u_time * 4.0 + ring_idx * 0.25));
		trim_acc = vec3(1.0, 0.18, 0.62);
	}

	// Architectural tiled metallic luminance variation (zero harsh binary strobe)
	float panel_var = mix(0.16, 0.30, alt_flag);
	if (u_bit_checker > 0.5) {
		float wave_tile = 0.5 + 0.5 * sin(ring_idx * 1.05 - u_time * 2.4);
		panel_var = mix(0.14, 0.32, mix(alt_flag, wave_tile, 0.45));
	}

	vec2 edge_dist = min(UV, 1.0 - UV);
	float edge_min = min(edge_dist.x, edge_dist.y);
	float inner_bevel = smoothstep(0.0, 0.16, edge_min);
	float seam_line = 1.0 - smoothstep(0.012, 0.068, edge_min);

	// Smooth traveling synthwave energy rings moving down the shaft
	float energy_ring = exp(-pow(fract(ring_idx * 0.085 - u_time * 1.5) - 0.5, 2.0) * 18.0);
	float ring_pulse = energy_ring * (0.45 + 0.55 * beat_kick + 0.45 * u_bass_energy);

	vec3 panel_tint = mix(trim_prim, trim_acc, alt_flag);
	vec3 wall_base = mix(bg_dark, bg_dark * 1.35 + panel_tint * 0.22, panel_var) * mix(0.76, 1.06, inner_bevel);

	vec3 seam_col = mix(trim_prim, trim_acc, alt_flag * 0.75);
	float seam_strength = 0.34 + 0.46 * ring_pulse + u_bit_wireframe * 0.65 + u_flow_locked * (0.35 + 0.35 * beat_kick);
	vec3 final_col = wall_base + seam_col * seam_line * seam_strength + seam_col * energy_ring * 0.18;

	// Deep void fog fading distant rings seamlessly into darkness
	float fog_dist = mix(158.0, 124.0 + 18.0 * sin(u_time * 2.8), u_bit_depth_fog);
	float fog_t = clamp((v_depth_rel - 18.0) / max(45.0, fog_dist), 0.0, 1.0);
	fog_t = pow(fog_t, 1.40);
	ALBEDO = mix(final_col, bg_dark * 0.65, fog_t);
}
