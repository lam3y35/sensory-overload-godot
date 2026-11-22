class_name StageData
extends RefCounted
## Complete serializable container for a playable dropper stage (`stage_v1`).
## Enforces schema validation to prevent corrupted custom data from silently blanking levels.

const SCHEMA_VERSION := "stage_v1"

var id: String = "custom_stage"
var level_index: int = 0
var level_title: String = "Custom"
var stage_code: String = "C-1"
var title: String = "Untitled Drop"
var author: String = "Pilot"
var source: String = "custom"
var description: String = ""
var bpm: float = 134.0
var track_index: int = 0
var base_speed: float = 42.0
var speed_ramp: float = 0.55
var tunnel_radius: float = 10.0
var palette: Array[Color] = [Color("14f1d9"), Color("ff2e93"), Color("120824")]
var sections: Array[Dictionary] = []
var obstacles: Array[ObstacleData] = []


func _init() -> void:
	if sections.is_empty():
		sections.append({
			"id": "sec_1",
			"length": 240.0,
			"effect_mask": 0,
			"transition_gap": 28.0,
		})


func total_length() -> float:
	var length_sum := 0.0
	for sec in sections:
		length_sum += maxf(40.0, float(sec.get("length", 200.0)))
	return maxf(40.0, length_sum)


func section_bounds(sec_idx: int) -> Vector2:
	var start_depth := 0.0
	for i in range(sections.size()):
		var sec_len := maxf(40.0, float(sections[i].get("length", 200.0)))
		if i == sec_idx:
			return Vector2(start_depth, start_depth + sec_len)
		start_depth += sec_len
	return Vector2(0.0, total_length())


func section_index_at_depth(depth_m: float) -> int:
	var acc := 0.0
	for i in range(sections.size()):
		acc += maxf(40.0, float(sections[i].get("length", 200.0)))
		if depth_m < acc:
			return i
	return maxi(0, sections.size() - 1)


func effect_mask_at_depth(depth_m: float) -> int:
	var idx := section_index_at_depth(depth_m)
	if idx >= 0 and idx < sections.size():
		return int(sections[idx].get("effect_mask", 0)) & EffectCatalog.MAX_MASK
	return 0


func combined_effect_mask() -> int:
	var mask := 0
	for sec in sections:
		mask |= int(sec.get("effect_mask", 0)) & EffectCatalog.MAX_MASK
	return mask


func duplicate_stage() -> StageData:
	var res := StageData.from_dict(to_dict())
	if bool(res["ok"]):
		return res["stage"] as StageData
	return StageData.new()


func to_dict() -> Dictionary:
	var palette_hex: Array[String] = []
	for col in palette:
		palette_hex.append("#" + col.to_html(true))

	var serialized_sections: Array[Dictionary] = []
	for i in range(sections.size()):
		var sec := sections[i]
		serialized_sections.append({
			"id": str(sec.get("id", "sec_%d" % (i + 1))),
			"length": float(sec.get("length", 220.0)),
			"effect_mask": int(sec.get("effect_mask", 0)) & EffectCatalog.MAX_MASK,
			"transition_gap": float(sec.get("transition_gap", 28.0)),
		})

	var serialized_obstacles: Array[Dictionary] = []
	for obs in obstacles:
		serialized_obstacles.append(obs.to_dict())

	return {
		"schema": SCHEMA_VERSION,
		"id": id,
		"level_index": level_index,
		"level_title": level_title,
		"stage_code": stage_code,
		"title": title,
		"author": author,
		"source": source,
		"description": description,
		"bpm": bpm,
		"track_index": track_index,
		"base_speed": base_speed,
		"speed_ramp": speed_ramp,
		"tunnel_radius": tunnel_radius,
		"palette": palette_hex,
		"sections": serialized_sections,
		"obstacles": serialized_obstacles,
	}


static func from_dict(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {"ok": false, "stage": null, "error": "Root JSON must be a dictionary."}
	var d: Dictionary = raw
	var schema_str := str(d.get("schema", ""))
	if schema_str != SCHEMA_VERSION:
		return {"ok": false, "stage": null, "error": "Unsupported or missing schema: '%s'." % schema_str}

	var stage_id := str(d.get("id", "")).strip_edges()
	if stage_id.is_empty():
		return {"ok": false, "stage": null, "error": "Stage id cannot be empty."}

	var sec_raw: Variant = d.get("sections", [])
	if typeof(sec_raw) != TYPE_ARRAY or (sec_raw as Array).is_empty():
		return {"ok": false, "stage": null, "error": "Stage must contain at least one section."}

	var obs_raw: Variant = d.get("obstacles", null)
	if typeof(obs_raw) != TYPE_ARRAY:
		return {"ok": false, "stage": null, "error": "Stage obstacles field must be an array."}

	var stage := StageData.new()
	stage.sections.clear()
	stage.obstacles.clear()
	stage.palette.clear()

	stage.id = stage_id
	stage.level_index = int(d.get("level_index", 0))
	stage.level_title = str(d.get("level_title", "Campaign"))
	stage.stage_code = str(d.get("stage_code", "1-A"))
	stage.title = str(d.get("title", "Untitled Stage"))
	stage.author = str(d.get("author", "Pancake Reconstruction"))
	stage.source = str(d.get("source", "custom"))
	stage.description = str(d.get("description", ""))
	stage.bpm = clampf(float(d.get("bpm", 134.0)), 60.0, 220.0)
	stage.track_index = maxi(0, int(d.get("track_index", 0)))
	stage.base_speed = clampf(float(d.get("base_speed", 42.0)), 12.0, 140.0)
	stage.speed_ramp = clampf(float(d.get("speed_ramp", 0.55)), 0.0, 5.0)
	stage.tunnel_radius = clampf(float(d.get("tunnel_radius", 10.0)), 6.0, 20.0)

	var pal_raw: Variant = d.get("palette", ["#14f1d9", "#ff2e93", "#120824"])
	if typeof(pal_raw) == TYPE_ARRAY:
		for hex_item in (pal_raw as Array):
			stage.palette.append(Color.from_string(str(hex_item), Color("14f1d9")))
	while stage.palette.size() < 3:
		stage.palette.append(Color("120824"))

	for i in range((sec_raw as Array).size()):
		var raw_s: Variant = (sec_raw as Array)[i]
		if typeof(raw_s) != TYPE_DICTIONARY:
			return {"ok": false, "stage": null, "error": "Section %d must be a dictionary." % i}
		var s: Dictionary = raw_s
		var mask_val := int(s.get("effect_mask", 0))
		if s.has("effects") and typeof(s["effects"]) == TYPE_ARRAY:
			mask_val |= EffectCatalog.build_mask_from_ids(s["effects"])
		stage.sections.append({
			"id": str(s.get("id", "sec_%d" % (i + 1))),
			"length": clampf(float(s.get("length", 220.0)), 40.0, 2000.0),
			"effect_mask": mask_val & EffectCatalog.MAX_MASK,
			"transition_gap": clampf(float(s.get("transition_gap", 28.0)), 10.0, 120.0),
		})

	for j in range((obs_raw as Array).size()):
		var obs_res := ObstacleData.from_dict((obs_raw as Array)[j])
		if not bool(obs_res["ok"]):
			return {"ok": false, "stage": null, "error": "Obstacle %d invalid: %s" % [j, str(obs_res["error"])]}
		stage.obstacles.append(obs_res["obstacle"] as ObstacleData)

	stage.sort_obstacles()
	return {"ok": true, "stage": stage, "error": ""}


func sort_obstacles() -> void:
	obstacles.sort_custom(func(a: ObstacleData, b: ObstacleData) -> bool:
		return a.depth < b.depth
	)
