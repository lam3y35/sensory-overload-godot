shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform float u_time = 0.0;
uniform float u_speed = 40.0;
uniform float u_beat_phase = 0.0;
uniform float u_bass_energy = 0.0;
uniform float u_flow = 0.0;
uniform float u_safe_mode = 0.0;

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

	// 1) Pixel crunch quantization
	if (u_bit_pixel_crunch > 0.5) {
		float px_scale = mix(480.0, 140.0, clamp(u_bass_energy * 0.8 + beat_kick * 0.4, 0.0, 1.0));
		vec2 grid = vec2(px_scale, px_scale * 0.5625);
		uv = (floor(uv * grid) + vec2(0.5)) / grid;
		centered = uv - vec2(0.5);
		r = length(centered);
		ang = atan(centered.y, centered.x);
	}

	// 2) Peripheral kaleidoscope angular symmetry
	if (u_bit_kaleidoscope > 0.5) {
		float segs = 6.0;
		float sector = 6.2831853 / segs;
		float mod_ang = abs(mod(ang + u_time * 0.3, sector) - sector * 0.5);
		vec2 k_uv = vec2(0.5) + vec2(cos(mod_ang), sin(mod_ang)) * r;
		float blend_k = smoothstep(0.18, 0.55, r) * 0.52;
		uv = mix(uv, k_uv, blend_k);
		centered = uv - vec2(0.5);
		r = length(centered);
	}

	// 3) Fisheye & Barrel Ripple distortion
	if (u_bit_fisheye > 0.5) {
		float strength = 0.35 + 0.15 * u_bass_energy;
		float factor = 1.0 + strength * r * r;
		uv = vec2(0.5) + centered * factor;
	}
	if (u_bit_barrel > 0.5) {
		float wave = sin(r * 26.0 - u_time * 9.0) * 0.014 * (0.5 + beat_kick);
		vec2 dir = normalize(centered + vec2(0.0001));
		uv += dir * wave;
	}

	vec2 safe_uv = clamp(uv, vec2(0.001), vec2(0.999));

	// 4) Chromatic Aberration (RGB split)
	vec3 col = texture(screen_texture, safe_uv).rgb;
	if (u_bit_chromatic > 0.5) {
		float speed_norm = clamp((u_speed - 30.0) / 60.0, 0.2, 1.2);
		float split = (0.004 + 0.008 * speed_norm + 0.006 * beat_kick) * r;
		vec2 dir = normalize(safe_uv - vec2(0.5) + vec2(0.0001));
		float cr = texture(screen_texture, clamp(safe_uv + dir * split, vec2(0.001), vec2(0.999))).r;
		float cb = texture(screen_texture, clamp(safe_uv - dir * split, vec2(0.001), vec2(0.999))).b;
		col = vec3(cr, col.g, cb);
	}

	// 5) Hue Shift & Contrast Overdrive
	if (u_bit_hue_shift > 0.5) {
		col = shift_hue(col, u_time * 1.15 + r * 1.6);
	}
	if (u_bit_contrast > 0.5) {
		float c_amt = 1.18 + 0.22 * u_flow;
		col = clamp((col - 0.5) * c_amt + 0.5, vec3(0.0), vec3(1.0));
	}

	// 6) Scanlines & Radial Speed Lines
	if (u_bit_scanlines > 0.5) {
		float scan = 0.90 + 0.10 * sin(uv.y * 620.0 + u_time * 18.0);
		col *= scan;
	}
	if (u_bit_speed_lines > 0.5) {
		float radial_mask = smoothstep(0.28, 0.56, r);
		float ang_id = floor((ang + 3.14159265) * 14.0);
		float h = fract(sin(ang_id * 127.1) * 43758.5453);
		float spoke = pow(max(0.0, sin((ang + h * 6.2831853) * 28.0)), 14.0);
		float streak_anim = smoothstep(0.45, 0.95, fract(r * 2.2 - u_time * (2.6 + h * 1.8) + h));
		col += vec3(0.65, 0.97, 1.0) * radial_mask * spoke * streak_anim * 0.42;
	}

	// 7) Vignette Throb
	if (u_bit_vignette > 0.5) {
		float vig = smoothstep(0.28, 0.78 - 0.10 * beat_kick, r);
		col = mix(col, col * 0.35, vig * 0.72);
	}

	// 8) Photosensitive Effects (strictly gated off when u_safe_mode > 0.5)
	float allow_flash = 1.0 - step(0.5, u_safe_mode);
	if (u_bit_invert > 0.5 && allow_flash > 0.5) {
		float inv_pulse = step(0.88, beat_kick) * 0.45;
		col = mix(col, vec3(1.0) - col, inv_pulse);
	}
	if (u_bit_strobe > 0.5 && allow_flash > 0.5) {
		col += vec3(0.22 * pow(beat_kick, 2.0));
	}
	if (u_bit_whiteout > 0.5 && allow_flash > 0.5) {
		float glare = (0.14 + 0.28 * beat_kick) * (1.0 - smoothstep(0.0, 0.65, r));
		col = mix(col, vec3(1.0), clamp(glare, 0.0, 0.55));
	}

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
