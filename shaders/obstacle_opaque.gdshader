shader_type spatial;
render_mode unshaded, cull_back;

uniform float u_time = 0.0;
uniform float u_player_y = 0.0;
uniform float u_beat_phase = 0.0;
uniform float u_bass_energy = 0.0;
uniform float u_opacity_override = 1.0;
uniform float u_outline_brightness = 1.15;
uniform float u_outline_thickness = 0.35;
uniform float u_hit_highlight = 0.0;
uniform float u_flow_locked = 0.0;

uniform vec4 u_color_primary : source_color = vec4(1.0, 0.18, 0.58, 1.0);
uniform vec4 u_color_accent : source_color = vec4(0.08, 0.95, 0.85, 1.0);
uniform vec4 u_color_bg : source_color = vec4(0.03, 0.015, 0.08, 1.0);
uniform float u_layer_alpha = 1.0;

varying vec3 v_local_norm;
varying float v_depth_rel;

void vertex() {
	v_local_norm = normalize(NORMAL);
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	v_depth_rel = max(0.0, u_player_y - wp.y);
}

void fragment() {
	float beat_kick = exp(-u_beat_phase * 4.2);

	// Directional face shading + diagonal energy shimmer for instant 3D silhouette clarity
	float stripe = 0.5 + 0.5 * sin((UV.x + UV.y) * 14.0 - u_time * 1.8);
	float face_shade = 0.54 + 0.46 * abs(dot(v_local_norm, normalize(vec3(0.45, 0.82, 0.35))));
	vec3 body_col = mix(u_color_primary.rgb, u_color_accent.rgb, stripe * 0.24) * face_shade;

	// Proximity danger glow brightens the immediate next hazard ahead of the player
	float near_boost = smoothstep(58.0, 14.0, v_depth_rel);
	body_col *= 1.0 + near_boost * 0.28 + u_flow_locked * beat_kick * 0.28 + u_bass_energy * 0.14;

	// Crisp white-hot & accent outline for unambiguous collision boundaries
	vec2 border = min(UV, 1.0 - UV);
	float min_edge = min(border.x, border.y);
	float thickness_uv = clamp(u_outline_thickness, 0.0, 1.0) * 0.17;
	float edge_mask = (thickness_uv > 0.002) ? (1.0 - smoothstep(thickness_uv * 0.42, thickness_uv, min_edge)) : 0.0;

	vec3 outline_col = mix(u_color_accent.rgb, vec3(1.0), 0.65 + 0.25 * near_boost) * u_outline_brightness * (1.20 + 0.35 * near_boost);
	vec3 final_col = mix(body_col, outline_col, edge_mask);

	// Distance depth cueing & smooth far void blend (hardware Early-Z opaque pass, zero overdraw)
	float fog_t = pow(clamp((v_depth_rel - 28.0) / 138.0, 0.0, 1.0), 1.45);
	float spawn_fade = smoothstep(168.0, 128.0, v_depth_rel);
	vec3 void_col = u_color_bg.rgb * 0.65;
	final_col = mix(final_col, void_col, clamp(max(fog_t, 1.0 - spawn_fade), 0.0, 1.0));

	// Crisp crimson-orange neon strobe highlight for the colliding obstacle during 0.35s impact freeze
	if (u_hit_highlight > 0.01) {
		float flash = 0.5 + 0.5 * sin(u_time * 32.0);
		vec3 alert_col = mix(vec3(0.94, 0.08, 0.22), vec3(1.0, 0.24, 0.16), flash) * 1.02;
		final_col = mix(final_col, alert_col, clamp(u_hit_highlight, 0.0, 1.0));
	}

	ALBEDO = final_col;
}
