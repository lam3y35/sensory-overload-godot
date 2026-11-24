shader_type spatial;
render_mode unshaded, cull_back;

uniform float u_time = 0.0;
uniform float u_player_y = 0.0;
uniform float u_beat_phase = 0.0;
uniform float u_bass_energy = 0.0;
uniform float u_flow = 0.0;
uniform float u_flow_locked = 0.0;
uniform float u_sconce_spacing = 28.8;
uniform float u_tunnel_radius = 10.0;
uniform vec4 u_color_primary : source_color = vec4(0.76, 0.10, 0.54, 1.0);
uniform vec4 u_color_accent : source_color = vec4(0.18, 0.10, 0.48, 1.0);
uniform vec4 u_color_bg : source_color = vec4(0.025, 0.015, 0.055, 1.0);

uniform float u_bit_breathing = 0.0;
uniform float u_bit_twist = 0.0;
uniform float u_bit_wobble = 0.0;
uniform float u_bit_pulse = 0.0;
uniform float u_bit_palette_cycle = 0.0;
uniform float u_bit_checker = 0.0;
uniform float u_bit_wireframe = 0.0;
uniform float u_bit_depth_fog = 0.0;

varying flat vec4 v_custom;
varying float v_depth_rel;
varying vec3 v_world_norm;
varying vec3 v_world_pos;
varying flat vec3 v_lp_l;
varying flat vec3 v_lp_r;

vec3 hue_rotate(vec3 col, float angle) {
	const vec3 k = vec3(0.57735026919);
	float cos_a = cos(angle);
	float sin_a = sin(angle);
	return col * cos_a + cross(k, col) * sin_a + k * dot(k, col) * (1.0 - cos_a);
}

vec3 eval_sconce_world(float sy, float wall_x) {
	if (u_bit_breathing < 0.5 && u_bit_twist < 0.5 && u_bit_wobble < 0.5) {
		return vec3(wall_x, sy, 0.0);
	}
	float rel_y = max(0.0, u_player_y - sy);
	float near_ramp = smoothstep(0.0, 14.0, rel_y);
	float breath = sin(rel_y * 0.10 - u_time * 2.8) * 0.65 * u_bit_breathing * near_ramp;
	float sx = wall_x + sign(wall_x) * breath;
	float twist_angle = rel_y * 0.015 * u_bit_twist * (0.65 + 0.45 * sin(u_time * 0.55));
	float ct = cos(twist_angle);
	float st = sin(twist_angle);
	vec2 twisted_xz = mat2(vec2(ct, -st), vec2(st, ct)) * vec2(sx, 0.0);
	float wob_ramp = smoothstep(6.0, 52.0, rel_y);
	twisted_xz.x += sin(rel_y * 0.048 - u_time * 2.0) * 2.2 * u_bit_wobble * wob_ramp;
	twisted_xz.y += cos(rel_y * 0.042 - u_time * 1.7) * 2.2 * u_bit_wobble * wob_ramp;
	return vec3(twisted_xz.x, sy, twisted_xz.y);
}

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float rel_y = max(0.0, u_player_y - origin.y);
	v_depth_rel = rel_y;

	float beat_kick = exp(-u_beat_phase * 4.5);
	float near_ramp = smoothstep(0.0, 14.0, rel_y);

	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);

	// Safe radial peristaltic breathing + subtle beat pulse inward (never inflates bricks into neighbors!)
	float breath = sin(rel_y * 0.10 - u_time * 2.8) * 0.65 * u_bit_breathing * near_ramp;
	float beat_push = -u_bit_pulse * 0.24 * (0.4 * beat_kick + 0.6 * u_bass_energy) * near_ramp;
	vec2 radial_dir = normalize(wp.xz + vec2(0.0001));
	wp.xz += radial_dir * (breath + beat_push);

	float twist_angle = rel_y * 0.015 * u_bit_twist * (0.65 + 0.45 * sin(u_time * 0.55));
	float ct = cos(twist_angle);
	float st = sin(twist_angle);
	wp.xz = mat2(vec2(ct, -st), vec2(st, ct)) * wp.xz;

	float wob_ramp = smoothstep(6.0, 52.0, rel_y);
	wp.x += sin(rel_y * 0.048 - u_time * 2.0) * 2.2 * u_bit_wobble * wob_ramp;
	wp.z += cos(rel_y * 0.042 - u_time * 1.7) * 2.2 * u_bit_wobble * wob_ramp;

	vec3 wn = normalize(NORMAL);
	wn.xz = mat2(vec2(ct, -st), vec2(st, ct)) * wn.xz;
	v_world_norm = normalize(wn);
	v_world_pos = wp.xyz;

	float s_period = max(8.0, u_sconce_spacing);
	float s_idx = round(-origin.y / s_period);
	float sy = -s_idx * s_period;
	float wall_x = 8.5 * (u_tunnel_radius / 10.0);
	v_lp_l = eval_sconce_world(sy, -wall_x);
	v_lp_r = eval_sconce_world(sy, wall_x);

	// Fast analytical local transform back from wp (TunnelRenderer instances have axis-aligned positive scales)
	vec3 inv_scale = vec3(1.0 / length(MODEL_MATRIX[0].xyz), 1.0 / length(MODEL_MATRIX[1].xyz), 1.0 / length(MODEL_MATRIX[2].xyz));
	VERTEX = (wp.xyz - origin) * inv_scale;
}

void fragment() {
	float beat_kick = exp(-u_beat_phase * 4.2);
	float ring_idx = round(v_custom.r);
	float ang_norm = v_custom.g;
	float crevice_ao = clamp(v_custom.b, 0.52, 1.08);
	float vox_hash = v_custom.a;

	vec3 c_prim = u_color_primary.rgb;
	vec3 c_acc = u_color_accent.rgb;
	vec3 c_void = clamp(u_color_bg.rgb * 0.30, vec3(0.005, 0.004, 0.010), vec3(0.045, 0.04, 0.07));

	if (u_bit_palette_cycle > 0.5) {
		float shift = u_time * 0.42 + ring_idx * 0.09;
		c_prim = hue_rotate(c_prim, shift);
		c_acc = hue_rotate(c_acc, shift * 1.12);
	}

	float ang_cell = floor(ang_norm * 24.0 + 0.05);
	float band_wave = sin(ring_idx * 0.24 + sin(ang_norm * 12.56637) * 1.25);
	float color_mix = smoothstep(-0.22, 0.22, band_wave);

	if (u_bit_twist > 0.5) {
		float spiral = sin((ring_idx * 0.32 + ang_norm * 18.849556) - u_time * 0.8);
		color_mix = step(0.0, spiral);
	}
	if (u_bit_checker > 0.5) {
		float chk = mod(floor(ring_idx * 0.5 + 0.05) + floor(ang_cell * 0.5 + 0.05), 2.0);
		color_mix = mix(color_mix, chk, 0.72);
	}

	vec3 voxel_col = mix(c_prim, c_acc, color_mix);

	// Subtle recessed dark architectural band every 12 rings
	float is_collar = 1.0 - step(0.5, mod(abs(ring_idx), 12.0));
	voxel_col = mix(voxel_col, voxel_col * 0.72, is_collar * 0.85);

	float tone_var = 0.88 + 0.22 * vox_hash;
	voxel_col *= tone_var;

	vec2 edge_dist = min(UV, 1.0 - UV);
	float min_edge = min(edge_dist.x, edge_dist.y);
	float face_mortar = mix(0.68, 1.02, smoothstep(0.0, 0.055, min_edge));

	vec3 d_l = v_lp_l - v_world_pos;
	vec3 d_r = v_lp_r - v_world_pos;
	float att_l = 1.0 / (1.0 + dot(d_l, d_l) * 0.011);
	float att_r = 1.0 / (1.0 + dot(d_r, d_r) * 0.011);
	float ndl_l = max(0.0, dot(v_world_norm, normalize(d_l)));
	float ndl_r = max(0.0, dot(v_world_norm, normalize(d_r)));
	float sconce_power = 1.48 + 0.25 * beat_kick + 0.20 * u_bass_energy;
	float sconce_lit = (ndl_l * att_l + ndl_r * att_r) * sconce_power;

	vec3 d_cam = vec3(0.0, u_player_y - 3.0, 0.0) - v_world_pos;
	float cam_d2 = dot(d_cam, d_cam);
	float ndl_cam = max(0.0, dot(v_world_norm, normalize(d_cam)));
	float headlamp_lit = 0.46 * ndl_cam / (1.0 + cam_d2 * 0.0028);

	float total_light = 0.24 * crevice_ao * face_mortar + (sconce_lit + headlamp_lit) * face_mortar * (0.72 + 0.28 * crevice_ao);
	vec3 lit_col = voxel_col * total_light;

	float wire_mask = (1.0 - smoothstep(0.01, 0.055, min_edge)) * u_bit_wireframe;
	if (u_flow_locked > 0.5) {
		lit_col *= 1.15;
		lit_col += mix(c_prim, vec3(1.0), 0.35) * (0.10 + 0.14 * beat_kick) * (1.0 - smoothstep(0.0, 0.07, min_edge));
	}
	if (wire_mask > 0.01) {
		lit_col += mix(c_prim, vec3(0.95), 0.45) * wire_mask * (0.65 + 0.35 * beat_kick);
	}

	float fog_far = mix(98.0, 74.0 + 9.0 * sin(u_time * 2.2), u_bit_depth_fog);
	float fog_t = pow(clamp((v_depth_rel - 20.0) / max(30.0, fog_far), 0.0, 1.0), 1.38);
	ALBEDO = mix(lit_col, c_void, fog_t);
}
