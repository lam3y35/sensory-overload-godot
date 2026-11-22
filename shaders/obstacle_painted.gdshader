shader_type spatial;
render_mode unshaded, cull_back;

uniform float u_time = 0.0;
uniform float u_beat_phase = 0.0;
uniform float u_bass_energy = 0.0;
uniform float u_opacity_override = 1.0;
uniform float u_outline_brightness = 1.15;
uniform float u_outline_thickness = 0.35;
uniform float u_hit_highlight = 0.0;
uniform float u_flow_locked = 0.0;

uniform vec4 u_color_primary : source_color = vec4(1.0, 0.18, 0.58, 1.0);
uniform vec4 u_color_accent : source_color = vec4(0.08, 0.95, 0.85, 1.0);
uniform float u_layer_alpha = 1.0;

varying vec3 v_local_norm;

void vertex() {
	v_local_norm = normalize(NORMAL);
}

void fragment() {
	float beat_kick = exp(-u_beat_phase * 4.2);

	// Procedural layered painted voxel shading with deepened face contrast vs neon edges
	float stripe = 0.5 + 0.5 * sin((UV.x + UV.y) * 18.8495 + u_time * 1.4);
	float face_shade = 0.48 + 0.47 * abs(dot(v_local_norm, normalize(vec3(0.45, 0.82, 0.35))));
	vec3 body_col = mix(u_color_primary.rgb * 0.85, u_color_accent.rgb * 0.95, stripe * 0.32) * face_shade;

	// Beat pulse modulation when Flow Color Lock is active
	body_col *= 1.0 + u_flow_locked * beat_kick * 0.35 + u_bass_energy * 0.15;

	// Procedural crisp edge outline controlled by Accessibility sliders
	vec2 border = min(UV, 1.0 - UV);
	float min_edge = min(border.x, border.y);
	float thickness_uv = clamp(u_outline_thickness, 0.0, 1.0) * 0.16;
	float edge_mask = (thickness_uv > 0.002) ? (1.0 - smoothstep(thickness_uv * 0.45, thickness_uv, min_edge)) : 0.0;

	vec3 outline_col = mix(u_color_accent.rgb, vec3(1.0), 0.55) * u_outline_brightness * 1.15;
	vec3 final_col = mix(body_col, outline_col, edge_mask);

	// Crimson strobe highlight for the colliding obstacle during delayed impact freeze
	if (u_hit_highlight > 0.01) {
		float flash = 0.5 + 0.5 * sin(u_time * 32.0);
		vec3 alert_col = mix(vec3(1.0, 0.12, 0.16), vec3(1.0, 0.88, 0.25), flash * 0.45) * 1.6;
		final_col = mix(final_col, alert_col, clamp(u_hit_highlight, 0.0, 1.0));
	}

	ALBEDO = final_col;
	ALPHA = clamp(u_opacity_override * u_layer_alpha, 0.05, 1.0);
}
