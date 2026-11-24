shader_type spatial;
render_mode unshaded, cull_back;

uniform float u_time = 0.0;
uniform float u_player_y = 0.0;
uniform float u_beat_phase = 0.0;
uniform float u_bass_energy = 0.0;
uniform vec4 u_sconce_color : source_color = vec4(1.0, 0.98, 1.0, 1.0);
uniform vec4 u_color_bg : source_color = vec4(0.02, 0.02, 0.04, 1.0);

uniform float u_bit_breathing = 0.0;
uniform float u_bit_twist = 0.0;
uniform float u_bit_wobble = 0.0;
uniform float u_bit_depth_fog = 0.0;

varying float v_depth_rel;

void vertex() {
	vec4 world_origin = MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float rel_y = max(0.0, u_player_y - world_origin.y);
	v_depth_rel = rel_y;

	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	float near_ramp = smoothstep(0.0, 14.0, rel_y);

	// Safe radial peristaltic breathing
	float breath = sin(rel_y * 0.10 - u_time * 2.8) * 0.65 * u_bit_breathing * near_ramp;
	vec2 radial_dir = normalize(wp.xz + vec2(0.0001));
	wp.xz += radial_dir * breath;

	float twist_angle = rel_y * 0.015 * u_bit_twist * (0.65 + 0.45 * sin(u_time * 0.55));
	float ct = cos(twist_angle);
	float st = sin(twist_angle);
	wp.xz = mat2(vec2(ct, -st), vec2(st, ct)) * wp.xz;

	float wob_ramp = smoothstep(6.0, 52.0, rel_y);
	wp.x += sin(rel_y * 0.048 - u_time * 2.0) * 2.2 * u_bit_wobble * wob_ramp;
	wp.z += cos(rel_y * 0.042 - u_time * 1.7) * 2.2 * u_bit_wobble * wob_ramp;

	vec3 origin = MODEL_MATRIX[3].xyz;
	VERTEX = wp.xyz - origin;
}

void fragment() {
	float beat_kick = exp(-u_beat_phase * 4.5);
	float pulse = 2.0 + 0.6 * beat_kick + 0.4 * u_bass_energy;
	float fog_end = mix(116.0, 86.0, u_bit_depth_fog);
	float vis = 1.0 - smoothstep(42.0, fog_end, v_depth_rel);
	ALBEDO = mix(u_color_bg.rgb * 0.25, u_sconce_color.rgb * pulse, vis);
}
