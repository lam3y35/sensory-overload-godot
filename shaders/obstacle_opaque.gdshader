shader_type spatial;
render_mode unshaded, cull_back;

uniform float u_time = 0.0;
uniform float u_player_y = 0.0;
uniform float u_beat_phase = 0.0;
uniform float u_bass_energy = 0.0;
uniform float u_opacity_override = 1.0;
uniform float u_outline_brightness = 1.28;
uniform float u_outline_thickness = 0.42;
uniform float u_hit_highlight = 0.0;
uniform float u_flow_locked = 0.0;

uniform vec3 u_half_extents = vec3(1.0, 1.0, 1.0);
uniform vec4 u_color_primary : source_color = vec4(1.0, 0.18, 0.58, 1.0);
uniform vec4 u_color_accent : source_color = vec4(0.08, 0.95, 0.85, 1.0);
uniform vec4 u_color_bg : source_color = vec4(0.02, 0.015, 0.04, 1.0);
uniform float u_layer_alpha = 1.0;

varying vec3 v_local_norm;
varying vec3 v_local_m;
varying float v_depth_rel;

void vertex() {
	v_local_norm = normalize(NORMAL);
	v_local_m = VERTEX * (u_half_extents * 2.0);
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	v_depth_rel = max(0.0, u_player_y - wp.y);
}

void fragment() {
	float beat_kick = exp(-u_beat_phase * 4.2);

	vec3 an = abs(v_local_norm);
	float edge_dist_m = 1.0;
	vec2 face_pos_m = vec2(0.0);
	if (an.y >= an.x && an.y >= an.z) {
		edge_dist_m = min(u_half_extents.x - abs(v_local_m.x), u_half_extents.z - abs(v_local_m.z));
		face_pos_m = v_local_m.xz + u_half_extents.xz;
	} else if (an.x >= an.y && an.x >= an.z) {
		edge_dist_m = min(u_half_extents.y - abs(v_local_m.y), u_half_extents.z - abs(v_local_m.z));
		face_pos_m = v_local_m.yz + u_half_extents.yz;
	} else {
		edge_dist_m = min(u_half_extents.x - abs(v_local_m.x), u_half_extents.y - abs(v_local_m.y));
		face_pos_m = v_local_m.xy + u_half_extents.xy;
	}

	vec2 vox_cell = floor((face_pos_m + vec2(0.005)) / 0.72);
	float vox_hash = fract(sin(dot(vox_cell, vec2(127.1, 311.7))) * 43758.5453);
	float vox_chk = mod(vox_cell.x + vox_cell.y, 2.0);
	float vox_tile = mix(0.84, 1.12, vox_hash * 0.65 + vox_chk * 0.35);

	float face_shade = 0.62 + 0.38 * abs(dot(v_local_norm, normalize(vec3(0.32, 0.90, 0.28))));
	float near_boost = smoothstep(54.0, 12.0, v_depth_rel);
	vec3 body_col = u_color_primary.rgb * vox_tile * face_shade;
	body_col *= 1.0 + near_boost * 0.22 + u_flow_locked * beat_kick * 0.22 + u_bass_energy * 0.12;

	float rim_w = mix(0.0, 0.15, clamp(u_outline_thickness, 0.0, 1.0));
	float aa = max(0.015, rim_w * 0.22);
	float edge_mask = (rim_w > 0.004) ? (1.0 - smoothstep(max(0.0, rim_w - aa), rim_w, edge_dist_m)) : 0.0;

	vec3 rim_col = mix(u_color_primary.rgb, vec3(1.0), 0.78) * u_outline_brightness * (1.35 + 0.38 * near_boost + 0.18 * beat_kick);
	vec3 final_col = mix(body_col, rim_col, edge_mask);

	float fog_t = pow(clamp((v_depth_rel - 34.0) / 106.0, 0.0, 1.0), 1.45);
	float spawn_fade = smoothstep(138.0, 102.0, v_depth_rel);
	final_col = mix(final_col, u_color_bg.rgb * 0.30, clamp(max(fog_t, 1.0 - spawn_fade), 0.0, 1.0));

	if (u_hit_highlight > 0.01) {
		float flash = 0.5 + 0.5 * sin(u_time * 32.0);
		vec3 alert_col = mix(vec3(0.95, 0.06, 0.20), vec3(1.0, 0.32, 0.24), flash) * 1.25;
		final_col = mix(final_col, alert_col, clamp(u_hit_highlight, 0.0, 1.0));
	}

	ALBEDO = final_col;
}
