class_name EffectCatalog
extends RefCounted
## Registry of the 24 combinable visual/spatial/post-process effects.
## [INDEPENDENT IMPLEMENTATION] Modeling the 2^24 = 16,777,216 combination space.

const TOTAL_BITS := 24
const MAX_MASK := 0xFFFFFF

const EFFECTS: Array[Dictionary] = [
	{"bit": 0, "id": "BREATHING_WALLS", "label": "Breathing Walls", "category": "tunnel", "photosensitive": false},
	{"bit": 1, "id": "AXIAL_TWIST", "label": "Axial Twist", "category": "tunnel", "photosensitive": false},
	{"bit": 2, "id": "TUNNEL_WOBBLE", "label": "Tunnel Wobble", "category": "tunnel", "photosensitive": false},
	{"bit": 3, "id": "BEAT_SCALE_PULSE", "label": "Beat Scale Pulse", "category": "tunnel", "photosensitive": false},
	{"bit": 4, "id": "NEON_PALETTE_CYCLE", "label": "Neon Palette Cycle", "category": "tunnel", "photosensitive": false},
	{"bit": 5, "id": "CHECKER_SCROLL", "label": "Checker Scroll", "category": "tunnel", "photosensitive": false},
	{"bit": 6, "id": "WIREFRAME_GLOW", "label": "Wireframe Glow", "category": "tunnel", "photosensitive": false},
	{"bit": 7, "id": "DEPTH_FOG_THROB", "label": "Depth Fog Throb", "category": "tunnel", "photosensitive": false},
	{"bit": 8, "id": "CAMERA_SPIRAL_ROLL", "label": "Camera Spiral Roll", "category": "camera", "photosensitive": false},
	{"bit": 9, "id": "CAMERA_FOV_SURGE", "label": "Camera FOV Surge", "category": "camera", "photosensitive": false},
	{"bit": 10, "id": "HORIZON_SWAY", "label": "Horizon Sway", "category": "camera", "photosensitive": false},
	{"bit": 11, "id": "SPEED_LINES", "label": "Speed Lines", "category": "camera", "photosensitive": false},
	{"bit": 12, "id": "CHROMATIC_ABERRATION", "label": "Chromatic Aberration", "category": "post", "photosensitive": false},
	{"bit": 13, "id": "KALEIDOSCOPE_FOLD", "label": "Kaleidoscope Fold", "category": "post", "photosensitive": false},
	{"bit": 14, "id": "FISHEYE_WARP", "label": "Fisheye Warp", "category": "post", "photosensitive": false},
	{"bit": 15, "id": "BARREL_RIPPLE", "label": "Barrel Ripple", "category": "post", "photosensitive": false},
	{"bit": 16, "id": "STROBE_FLASH", "label": "Strobe Flash", "category": "post", "photosensitive": true},
	{"bit": 17, "id": "HUE_SHIFT_SCREEN", "label": "Screen Hue Shift", "category": "post", "photosensitive": false},
	{"bit": 18, "id": "INVERT_ACCENT", "label": "Invert Accent", "category": "post", "photosensitive": true},
	{"bit": 19, "id": "SCANLINE_OVERLAY", "label": "Scanline Overlay", "category": "post", "photosensitive": false},
	{"bit": 20, "id": "VIGNETTE_THROB", "label": "Vignette Throb", "category": "post", "photosensitive": false},
	{"bit": 21, "id": "PIXEL_CRUNCH", "label": "Pixel Crunch", "category": "post", "photosensitive": false},
	{"bit": 22, "id": "CONTRAST_OVERDRIVE", "label": "Contrast Overdrive", "category": "post", "photosensitive": false},
	{"bit": 23, "id": "WHITEOUT_GLARE", "label": "Whiteout Glare", "category": "post", "photosensitive": true},
]


static func has_effect(mask: int, bit: int) -> bool:
	if bit < 0 or bit >= TOTAL_BITS:
		return false
	return ((mask & MAX_MASK) & (1 << bit)) != 0


static func set_effect(mask: int, bit: int, enabled: bool) -> int:
	if bit < 0 or bit >= TOTAL_BITS:
		return mask & MAX_MASK
	var clean := mask & MAX_MASK
	if enabled:
		return clean | (1 << bit)
	return clean & ~(1 << bit)


static func toggle_effect(mask: int, bit: int) -> int:
	return set_effect(mask, bit, not has_effect(mask, bit))


static func count_effects(mask: int) -> int:
	var clean := mask & MAX_MASK
	var count := 0
	for bit in range(TOTAL_BITS):
		if (clean & (1 << bit)) != 0:
			count += 1
	return count


static func list_active(mask: int) -> Array[Dictionary]:
	var active: Array[Dictionary] = []
	for entry in EFFECTS:
		if has_effect(mask, int(entry["bit"])):
			active.append(entry)
	return active


static func bit_for_id(effect_id: String) -> int:
	for entry in EFFECTS:
		if str(entry["id"]) == effect_id:
			return int(entry["bit"])
	return -1


static func build_mask_from_ids(ids: Array) -> int:
	var mask := 0
	for raw_id in ids:
		var bit := bit_for_id(str(raw_id))
		if bit >= 0:
			mask = set_effect(mask, bit, true)
	return mask


static func clamp_safe_mask(mask: int, safe_photosensitivity: bool) -> int:
	var clean := mask & MAX_MASK
	if not safe_photosensitivity:
		return clean
	for entry in EFFECTS:
		if bool(entry["photosensitive"]):
			clean = set_effect(clean, int(entry["bit"]), false)
	return clean
