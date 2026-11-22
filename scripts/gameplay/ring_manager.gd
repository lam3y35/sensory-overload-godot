class_name RingManager
extends Node3D
## Deterministically spawns glowing cyber Energy Rings along safe tunnel corridors,
## renders up to 16 visible rotating 12-segment neon hoops in ONE pooled MultiMesh draw call,
## and evaluates swept line-segment ring pickups with zero per-frame allocations.

const ACTIVE_AHEAD_M := 160.0
const ACTIVE_BEHIND_M := 12.0
const RING_RADIUS := 2.65
const MAX_VISIBLE_RINGS := 16
const SEGMENT_COUNT := 12

var _rings: Array[Dictionary] = []
var _mm_inst: MultiMeshInstance3D
var _local_time: float = 0.0


func _ready() -> void:
	_ensure_shared()


func _ensure_shared() -> void:
	if _mm_inst != null:
		return
	_mm_inst = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = MAX_VISIBLE_RINGS * SEGMENT_COUNT

	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mm.mesh = box

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mm_inst.material_override = mat
	_mm_inst.multimesh = mm
	_mm_inst.extra_cull_margin = 180.0
	add_child(_mm_inst)


func reset_with_stage(stage: StageData) -> void:
	_ensure_shared()
	_rings.clear()
	_local_time = 0.0
	clear_all()
	if stage == null:
		return

	var total_len := stage.total_length()
	var seed_hash := stage.id.hash()
	var d := 34.0
	var idx := 0
	var playable := clampf(stage.tunnel_radius * 0.56, 3.2, 6.2)

	while d < total_len - 22.0:
		idx += 1
		var depth_val := d
		for obs in stage.obstacles:
			if absf(obs.depth - depth_val) < 7.0:
				depth_val = obs.depth + 8.5
				break
		if depth_val >= total_len - 18.0:
			break
		var best_xz := Vector2(
			sin(float(idx) * 1.45 + float(seed_hash & 255) * 0.05) * playable * 0.68,
			cos(float(idx) * 1.15 + float((seed_hash >> 4) & 255) * 0.05) * playable * 0.68
		)
		_rings.append({
			"id": "%s_ring_%02d" % [stage.id, idx],
			"depth": depth_val,
			"xz": best_xz,
			"collected": false,
		})
		d += 36.0 + float((idx * 7) % 9)


func clear_all() -> void:
	_ensure_shared()
	var mm := _mm_inst.multimesh
	var total := MAX_VISIBLE_RINGS * SEGMENT_COUNT
	var hidden := Transform3D(Basis.IDENTITY.scaled_local(Vector3.ZERO), Vector3(0.0, 100.0, 0.0))
	for i in range(total):
		mm.set_instance_transform(i, hidden)
		mm.set_instance_color(i, Color(1, 1, 1, 0))


func check_collect(p0: Vector3, p1: Vector3) -> Dictionary:
	var min_y := minf(p0.y, p1.y) - 0.9
	var max_y := maxf(p0.y, p1.y) + 0.9
	for ring in _rings:
		if bool(ring["collected"]):
			continue
		var ring_depth := float(ring["depth"])
		var ring_y := -ring_depth
		if ring_y < min_y or ring_y > max_y:
			continue

		var dy := p1.y - p0.y
		var t := 0.5
		if absf(dy) > 1e-5:
			t = clampf((ring_y - p0.y) / dy, 0.0, 1.0)
		var sample_pt := p0.lerp(p1, t)
		var ring_xz := ring["xz"] as Vector2
		var dist_xz := Vector2(sample_pt.x - ring_xz.x, sample_pt.z - ring_xz.y).length()
		if absf(sample_pt.y - ring_y) <= 0.95 and dist_xz <= RING_RADIUS:
			ring["collected"] = true
			return {
				"collected": true,
				"id": str(ring["id"]),
				"pos": Vector3(ring_xz.x, ring_y, ring_xz.y),
			}
	return {"collected": false, "id": "", "pos": Vector3.ZERO}


func step_and_sync(player_y: float, delta: float, beat_phase: float) -> void:
	_ensure_shared()
	_local_time += delta
	var min_depth := (-player_y) - ACTIVE_BEHIND_M
	var max_depth := (-player_y) + ACTIVE_AHEAD_M
	var beat_kick := exp(-beat_phase * 4.2)

	var mm := _mm_inst.multimesh
	var ring_slot := 0
	var rad := RING_RADIUS * (0.94 + 0.08 * beat_kick)
	var chord_len := 2.0 * rad * sin(PI / float(SEGMENT_COUNT)) * 0.94
	var c_gold := Color("facc15")
	var c_cyan := Color("14f1d9")

	for ring in _rings:
		if ring_slot >= MAX_VISIBLE_RINGS:
			break
		if bool(ring["collected"]):
			continue
		var d := float(ring["depth"])
		if d < min_depth or d > max_depth:
			continue

		var rxz := ring["xz"] as Vector2
		var center := Vector3(rxz.x, -d, rxz.y)
		var spin := _local_time * 2.1 + center.y * 0.08
		var dist_rel := maxf(0.0, player_y - center.y)
		var alpha := smoothstep_val(162.0, 122.0, dist_rel) * 0.96

		for seg in range(SEGMENT_COUNT):
			var inst_idx := ring_slot * SEGMENT_COUNT + seg
			var ang := (float(seg) / float(SEGMENT_COUNT)) * TAU + spin
			var seg_pos := center + Vector3(cos(ang) * rad, 0.0, sin(ang) * rad)
			var b := Basis(Vector3.UP, -ang + PI * 0.5).scaled_local(Vector3(chord_len, 0.24, 0.24))
			mm.set_instance_transform(inst_idx, Transform3D(b, seg_pos))
			var col := c_gold if (seg % 2 == 0) else c_cyan
			col.a = alpha
			mm.set_instance_color(inst_idx, col)
		ring_slot += 1

	var total := MAX_VISIBLE_RINGS * SEGMENT_COUNT
	var hide_xform := Transform3D(Basis.IDENTITY.scaled_local(Vector3.ZERO), Vector3(0.0, player_y + 60.0, 0.0))
	for empty_idx in range(ring_slot * SEGMENT_COUNT, total):
		mm.set_instance_transform(empty_idx, hide_xform)
		mm.set_instance_color(empty_idx, Color(1, 1, 1, 0))


func get_rings() -> Array[Dictionary]:
	return _rings


static func smoothstep_val(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
