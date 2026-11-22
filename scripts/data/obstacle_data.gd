class_name ObstacleData
extends RefCounted
## Serializable blueprint for a single parametric or animated obstacle.
## Supports all 10 original archetypes matching the architecture specification.

const VALID_TYPES: PackedStringArray = [
	"waffle",
	"cross_bars",
	"iris_ring",
	"sliding_blades",
	"pendulum",
	"tumbling_cube",
	"guillotine",
	"drifting_ghost",
	"spiral_slats",
	"pillar_grid",
]

var id: String = ""
var type: String = "waffle"
var depth: float = 50.0
var offset_xz: Vector2 = Vector2.ZERO
var rotation_deg: Vector3 = Vector3.ZERO
var scale: Vector3 = Vector3.ONE
var speed: float = 1.0
var amplitude: float = 1.0
var phase: float = 0.0
var section_index: int = 0
var color_primary: Color = Color("ff2e93")
var color_accent: Color = Color("14f1d9")
var seed_int: int = 1


func duplicate_data() -> ObstacleData:
	var copy := ObstacleData.new()
	copy.id = id
	copy.type = type
	copy.depth = depth
	copy.offset_xz = offset_xz
	copy.rotation_deg = rotation_deg
	copy.scale = scale
	copy.speed = speed
	copy.amplitude = amplitude
	copy.phase = phase
	copy.section_index = section_index
	copy.color_primary = color_primary
	copy.color_accent = color_accent
	copy.seed_int = seed_int
	return copy


func to_dict() -> Dictionary:
	return {
		"id": id,
		"type": type,
		"depth": depth,
		"offset_xz": [offset_xz.x, offset_xz.y],
		"rotation_deg": [rotation_deg.x, rotation_deg.y, rotation_deg.z],
		"scale": [scale.x, scale.y, scale.z],
		"speed": speed,
		"amplitude": amplitude,
		"phase": phase,
		"section_index": section_index,
		"color_primary": "#" + color_primary.to_html(true),
		"color_accent": "#" + color_accent.to_html(true),
		"seed_int": seed_int,
	}


static func from_dict(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {"ok": false, "obstacle": null, "error": "Obstacle entry must be a dictionary."}
	var d: Dictionary = raw
	var obs_type := str(d.get("type", "")).strip_edges()
	if not VALID_TYPES.has(obs_type):
		return {"ok": false, "obstacle": null, "error": "Invalid obstacle type: '%s'." % obs_type}

	var obs := ObstacleData.new()
	obs.id = str(d.get("id", "obs_%d" % Time.get_ticks_usec()))
	obs.type = obs_type
	obs.depth = maxf(1.0, float(d.get("depth", 50.0)))

	var xz_raw: Variant = d.get("offset_xz", [0.0, 0.0])
	if typeof(xz_raw) == TYPE_ARRAY and (xz_raw as Array).size() >= 2:
		var arr: Array = xz_raw
		obs.offset_xz = Vector2(float(arr[0]), float(arr[1]))

	var rot_raw: Variant = d.get("rotation_deg", [0.0, 0.0, 0.0])
	if typeof(rot_raw) == TYPE_ARRAY and (rot_raw as Array).size() >= 3:
		var arr: Array = rot_raw
		obs.rotation_deg = Vector3(float(arr[0]), float(arr[1]), float(arr[2]))

	var scale_raw: Variant = d.get("scale", [1.0, 1.0, 1.0])
	if typeof(scale_raw) == TYPE_ARRAY and (scale_raw as Array).size() >= 3:
		var arr: Array = scale_raw
		obs.scale = Vector3(
			maxf(0.2, float(arr[0])),
			maxf(0.2, float(arr[1])),
			maxf(0.2, float(arr[2]))
		)

	obs.speed = float(d.get("speed", 1.0))
	obs.amplitude = float(d.get("amplitude", 1.0))
	obs.phase = float(d.get("phase", 0.0))
	obs.section_index = int(d.get("section_index", 0))
	obs.color_primary = Color.from_string(str(d.get("color_primary", "#ff2e93")), Color("ff2e93"))
	obs.color_accent = Color.from_string(str(d.get("color_accent", "#14f1d9")), Color("14f1d9"))
	obs.seed_int = int(d.get("seed_int", 1))
	return {"ok": true, "obstacle": obs, "error": ""}
