shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform float u_time = 0.0;
uniform float u_speed = 40.0;
uniform float u_beat_phase = 0.0;
uniform float u_bass_energy = 0.0;
uniform float u_flow = 0.0;
uniform float u_safe_mode = 0.0;
uniform float u_boost = 0.0;
uniform float u_flash_strength = 0.0;
uniform vec4 u_flash_color : source_color = vec4(0.08, 0.95, 0.85, 1.0);

uniform float u_bit_speed_lines = 0.0;
uniform float u_bit_chromatic = 0.0;
uniform float u_bit_kaleidoscope = 0.0;
uniform float u_bit_fisheye = 0.0;
uniform float u_bit_barrel = 0.0;
uniform float u_bit_strobe = 0.0;
uniform float u_bit_hue_shift = 0.0;
uniform float u_bit_invert = 0.0;
uniform float u_bit_scanlines = 0.0;
uniform float u_bit_vignette = 0.0;
uniform float u_bit_pixel_crunch = 0.0;
uniform float u_bit_contrast = 0.0;
uniform float u_bit_whiteout = 0.0;

vec3 shift_hue(vec3 col, float angle) {
	const vec3 k = vec3(0.57735026919);
	float c = cos(angle);
	float s = sin(angle);
	return col * c + cross(k, col) * s + k * dot(k, col) * (1.0 - c);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv - vec2(0.5);
	float r = length(centered);
	float ang = atan(centered.y, centered.x);
	float beat_kick = exp(-u_beat_phase * 4.5);

	// 1) Subtle pixel crunch quantization
	if (u_bit_pixel_crunch > 0.5) {
		float px_scale = mix(540.0, 220.0, clamp(u_bass_energy * 0.65 + beat_kick * 0.35, 0.0, 1.0));
		vec2 grid = vec2(px_scale, px_scale * 0.5625);
		uv = (floor(uv * grid) + vec2(0.5)) / grid;
		centered = uv - vec2(0.5);
		r = length(centered);
		ang = atan(centered.y, centered.x);
	}

	// 2) Fisheye & Barrel Ripple distortion (smooth, continuous UVs)
	if (u_bit_fisheye > 0.5) {
		float strength = 0.28 + 0.12 * u_bass_energy;
		float factor = 1.0 + strength * r * r;
		uv = vec2(0.5) + centered * factor;
	}
	if (u_bit_barrel > 0.5) {
		float wave = sin(r * 22.0 - u_time * 8.0) * 0.010 * (0.5 + beat_kick);
		vec2 dir = normalize(centered + vec2(0.0001));
		uv += dir * wave;
	}

	vec2 safe_uv = clamp(uv, vec2(0.001), vec2(0.999));
	vec3 col = texture(screen_texture, safe_uv).rgb;

	// 3) Chromatic Aberration (peripheral RGB split scaled by velocity & Boost)
	float boost_clamp = clamp(u_boost, 0.0, 1.0);
	if (u_bit_chromatic > 0.5 || boost_clamp > 0.05) {
		float speed_norm = clamp((u_speed - 36.0) / 70.0, 0.15, 1.35);
		float split_base = (u_bit_chromatic > 0.5) ? (0.0035 + 0.0055 * speed_norm + 0.0045 * beat_kick) : 0.0;
		float split = (split_base + boost_clamp * 0.0075) * smoothstep(0.14, 0.55, r);
		vec2 dir = normalize(safe_uv - vec2(0.5) + vec2(0.0001));
		float cr = texture(screen_texture, clamp(safe_uv + dir * split, vec2(0.001), vec2(0.999))).r;
		float cb = texture(screen_texture, clamp(safe_uv - dir * split, vec2(0.001), vec2(0.999))).b;
		col = vec3(cr, col.g, cb);
	}

	// 4) Peripheral Kaleidoscope Color Blend (zero UV branch-cut tearing, razor-sharp center)
	if (u_bit_kaleidoscope > 0.5) {
		float segs = 6.0;
		float sector = 6.2831853 / segs;
		float mod_ang = abs(mod(ang + u_time * 0.25, sector) - sector * 0.5);
		vec2 k_uv = clamp(vec2(0.5) + vec2(cos(mod_ang), sin(mod_ang)) * r, vec2(0.001), vec2(0.999));
		vec3 k_col = texture(screen_texture, k_uv).rgb;
		float blend_k = smoothstep(0.32, 0.62, r) * 0.42;
		col = mix(col, k_col, blend_k);
	}

	// 5) Controlled Hue Accents & Crisp Contrast Overdrive
	if (u_bit_hue_shift > 0.5) {
		col = mix(col, shift_hue(col, u_time * 0.75 + r * 1.1), 0.35);
	}
	if (u_bit_contrast > 0.5) {
		float c_amt = 1.14 + 0.18 * u_flow;
		col = clamp((col - 0.5) * c_amt + 0.5, vec3(0.0), vec3(1.0));
	}

	// 6) Crisp radial anime/arcade speed streaks around outer viewport + subtle scanlines
	if (u_bit_scanlines > 0.5) {
		float scan = 0.93 + 0.07 * sin(uv.y * 540.0 + u_time * 16.0);
		col *= scan;
	}
	float spd_factor = clamp((u_speed - 44.0) / 52.0, 0.30, 1.0);
	float streak_driver = max(u_bit_speed_lines * spd_factor, boost_clamp);
	if (streak_driver > 0.05) {
		float radial_mask = smoothstep(0.24, 0.62, r);
		float s_ray1 = pow(max(0.0, sin(ang * 32.0 + sin(ang * 7.0) * 1.4)), 10.0);
		float s_ray2 = pow(max(0.0, sin(ang * 54.0 + cos(ang * 11.0) * 1.1 + 1.5)), 14.0);
		float streak_flow1 = smoothstep(0.28, 0.96, fract(r * 1.45 - u_time * (2.6 + 2.2 * streak_driver) + sin(ang * 5.0) * 0.35));
		float streak_flow2 = smoothstep(0.35, 0.98, fract(r * 2.15 - u_time * (3.4 + 2.8 * streak_driver) + cos(ang * 9.0) * 0.45));
		float streak_int = (s_ray1 * streak_flow1 * 0.55 + s_ray2 * streak_flow2 * 0.45) * radial_mask * streak_driver;
		vec3 streak_col = mix(vec3(0.95, 0.97, 1.0), vec3(1.0, 0.85, 0.45), boost_clamp * 0.55);
		col += streak_col * streak_int * 0.42;
	}

	// 7) Vignette Throb + Event Edge Flash Juice (Grazes, Rings, Boost, Impact)
	if (u_bit_vignette > 0.5) {
		float vig = smoothstep(0.32, 0.82 - 0.08 * beat_kick, r);
		col = mix(col, col * 0.42, vig * 0.62);
	}
	if (u_flash_strength > 0.005) {
		float edge_flash = smoothstep(0.18, 0.72, r) * 0.85 + 0.15;
		col += u_flash_color.rgb * u_flash_strength * edge_flash * 0.55;
	}

	// 8) Photosensitive Effects (strictly gated off when u_safe_mode > 0.5)
	float allow_flash = 1.0 - step(0.5, u_safe_mode);
	if (u_bit_invert > 0.5 && allow_flash > 0.5) {
		float inv_pulse = step(0.90, beat_kick) * 0.38;
		col = mix(col, vec3(1.0) - col, inv_pulse);
	}
	if (u_bit_strobe > 0.5 && allow_flash > 0.5) {
		col += vec3(0.16 * pow(beat_kick, 2.0));
	}
	if (u_bit_whiteout > 0.5 && allow_flash > 0.5) {
		float glare = (0.10 + 0.22 * beat_kick) * (1.0 - smoothstep(0.0, 0.65, r));
		col = mix(col, vec3(1.0), clamp(glare, 0.0, 0.45));
	}

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
