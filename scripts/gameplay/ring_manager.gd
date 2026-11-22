class_name RingManager
extends Node3D
## Deterministically spawns glowing cyber Energy Rings along safe tunnel corridors,
## renders rotating 8-segment octagonal hoops within the visible window, and
## evaluates swept line-segment ring pickups.

const ACTIVE_AHEAD_M := 160.0
const ACTIVE_BEHIND_M := 12.0
const RING_RADIUS := 2.65
const SEGMENT_COUNT := 8

var _rings: Array[Dictionary] = []
var _pool: Dictionary = {} # ring_id -> {root: Node3D, segs: Array[MeshInstance3D]}
var _unit_box: BoxMesh
var _mat_gold: StandardMaterial3D
var _mat_cyan: StandardMaterial3D
var _local_time: float = 0.0


func _ready() -> void:
	_ensure_shared()


func _ensure_shared() -> void:
	if _unit_box == null:
		_unit_box = BoxMesh.new()
		_unit_box.size = Vector3.ONE
	if _mat_gold == null:
		_mat_gold = StandardMaterial3D.new()
		_mat_gold.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_gold.albedo_color = Color("facc15")
		_mat_gold.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if _mat_cyan == null:
		_mat_cyan = StandardMaterial3D.new()
		_mat_cyan.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_cyan.albedo_color = Color("14f1d9")
		_mat_cyan.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func reset_with_stage(stage: StageData) -> void:
	_ensure_shared()
	clear_all()
	_rings.clear()
	_local_time = 0.0
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
		# Ensure ring never intersects an obstacle slab; nudge depth into open corridor if too close
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
	for k in _pool.keys():
		var ent: Dictionary = _pool[k]
		var r := ent["root"] as Node3D
		if is_instance_valid(r):
			r.queue_free()
	_pool.clear()


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
			_remove_visual(str(ring["id"]))
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
	var visible_ids: Dictionary = {}
	var beat_kick := exp(-beat_phase * 4.2)

	for ring in _rings:
		if bool(ring["collected"]):
			continue
		var d := float(ring["depth"])
		if d < min_depth or d > max_depth:
			continue
		var rid := str(ring["id"])
		visible_ids[rid] = true
		var rxz := ring["xz"] as Vector2
		_sync_ring_visual(rid, Vector3(rxz.x, -d, rxz.y), beat_kick)

	var to_remove: Array[String] = []
	for existing_id in _pool.keys():
		if not visible_ids.has(existing_id):
			to_remove.append(str(existing_id))
	for rid in to_remove:
		_remove_visual(rid)


func get_rings() -> Array[Dictionary]:
	return _rings


func _remove_visual(rid: String) -> void:
	if not _pool.has(rid):
		return
	var ent: Dictionary = _pool[rid]
	var r := ent["root"] as Node3D
	if is_instance_valid(r):
		r.queue_free()
	_pool.erase(rid)


func _sync_ring_visual(rid: String, world_pos: Vector3, beat_kick: float) -> void:
	if not _pool.has(rid):
		var root := Node3D.new()
		root.name = "Ring_" + rid.validate_node_name()
		add_child(root)
		var segs: Array[MeshInstance3D] = []
		for i in range(SEGMENT_COUNT):
			var mi := MeshInstance3D.new()
			mi.mesh = _unit_box
			mi.material_override = _mat_gold if (i % 2 == 0) else _mat_cyan
			root.add_child(mi)
			segs.append(mi)
		_pool[rid] = {"root": root, "segs": segs}

	var ent: Dictionary = _pool[rid]
	var root_node := ent["root"] as Node3D
	var segs_arr: Array = ent["segs"]
	root_node.position = world_pos
	var spin := _local_time * 1.9 + world_pos.y * 0.08
	var rad := RING_RADIUS * (0.94 + 0.08 * beat_kick)
	var chord_len := 2.0 * rad * sin(PI / float(SEGMENT_COUNT)) * 0.92

	for i in range(SEGMENT_COUNT):
		var mi := segs_arr[i] as MeshInstance3D
		var ang := (float(i) / float(SEGMENT_COUNT)) * TAU + spin
		var pos := Vector3(cos(ang) * rad, 0.0, sin(ang) * rad)
		var b := Basis(Vector3.UP, -ang + PI * 0.5).scaled_local(Vector3(chord_len, 0.22, 0.24))
		mi.transform = Transform3D(b, pos)
