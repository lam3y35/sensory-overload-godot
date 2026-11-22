class_name ObstacleManager
extends Node3D
## Spawns, animates, and renders all 10 obstacle archetypes with an isolated per-instance
## simulation clock, guaranteeing 1:1 Transform3D & OBB parity between visuals and SweptCollision.

const ACTIVE_AHEAD_M := 165.0
const ACTIVE_BEHIND_M := 14.0

var local_time: float = 0.0
var highlighted_obstacle_id: String = ""
var _last_player_y: float = 0.0

var _shader: Shader
var _unit_box: BoxMesh
var _stage: StageData
var _node_pool: Dictionary = {} # obs_id -> {root: Node3D, meshes: Array[MeshInstance3D], mats: Array[ShaderMaterial]}
var _active_cache: Array[Dictionary] = [] # [{obstacle: ObstacleData, parts: Array[Dictionary]}]


func _ready() -> void:
	_ensure_shared_resources()


func _ensure_shared_resources() -> void:
	if _shader == null:
		_shader = load("res://shaders/obstacle_painted.gdshader") as Shader
	if _unit_box == null:
		_unit_box = BoxMesh.new()
		_unit_box.size = Vector3.ONE


func reset_with_stage(stage: StageData) -> void:
	_ensure_shared_resources()
	clear_all()
	_stage = stage
	local_time = 0.0
	highlighted_obstacle_id = ""


func clear_all() -> void:
	for k in _node_pool.keys():
		var entry: Dictionary = _node_pool[k]
		var r := entry["root"] as Node3D
		if is_instance_valid(r):
			r.queue_free()
	_node_pool.clear()
	_active_cache.clear()


func set_highlight_obstacle(obs_id: String) -> void:
	highlighted_obstacle_id = obs_id


func step_and_sync(
	player_y: float,
	delta: float,
	beat_phase: float,
	bass_energy: float,
	flow_locked: bool
) -> void:
	_ensure_shared_resources()
	local_time += delta
	_last_player_y = player_y
	_active_cache.clear()
	if _stage == null:
		return

	var min_depth := (-player_y) - ACTIVE_BEHIND_M
	var max_depth := (-player_y) + ACTIVE_AHEAD_M
	var visible_ids: Dictionary = {}

	for obs in _stage.obstacles:
		if obs.depth < min_depth or obs.depth > max_depth:
			continue
		visible_ids[obs.id] = true
		var parts := compute_parts(obs, local_time, beat_phase, _stage.tunnel_radius)
		_active_cache.append({"obstacle": obs, "parts": parts})
		_sync_visual_entry(obs, parts, beat_phase, bass_energy, flow_locked)

	# Release obstacles outside window
	var to_remove: Array[String] = []
	for existing_id in _node_pool.keys():
		if not visible_ids.has(existing_id):
			to_remove.append(str(existing_id))
	for rid in to_remove:
		var ent: Dictionary = _node_pool[rid]
		var rn := ent["root"] as Node3D
		if is_instance_valid(rn):
			rn.queue_free()
		_node_pool.erase(rid)


func get_active_obstacles() -> Array[Dictionary]:
	return _active_cache


func _sync_visual_entry(
	obs: ObstacleData,
	parts: Array[Dictionary],
	beat_phase: float,
	bass_energy: float,
	flow_locked: bool
) -> void:
	if not _node_pool.has(obs.id):
		var container := Node3D.new()
		container.name = "Obs_" + obs.id.validate_node_name()
		add_child(container)
		_node_pool[obs.id] = {
			"root": container,
			"meshes": [],
			"mats": [],
		}

	var entry: Dictionary = _node_pool[obs.id]
	var root := entry["root"] as Node3D
	var meshes: Array = entry["meshes"]
	var mats: Array = entry["mats"]

	while meshes.size() < parts.size():
		var mi := MeshInstance3D.new()
		mi.mesh = _unit_box
		var mat := ShaderMaterial.new()
		mat.shader = _shader
		mi.material_override = mat
		root.add_child(mi)
		meshes.append(mi)
		mats.append(mat)

	while meshes.size() > parts.size():
		var extra := meshes.pop_back() as MeshInstance3D
		mats.pop_back()
		if is_instance_valid(extra):
			extra.queue_free()

	var is_hit := (obs.id == highlighted_obstacle_id and not obs.id.is_empty())
	for i in range(parts.size()):
		var p: Dictionary = parts[i]
		var mi := meshes[i] as MeshInstance3D
		var mat := mats[i] as ShaderMaterial
		var part_xform := p["transform"] as Transform3D
		var half_ext := p["half_extents"] as Vector3
		# Apply scale in local space (Rot * Scale) matching SweptCollision's analytical OBB without shear
		mi.global_transform = Transform3D(part_xform.basis.scaled_local(half_ext * 2.0), part_xform.origin)

		var use_accent := bool(p.get("use_accent", false))
		var prim := obs.color_accent if use_accent else obs.color_primary
		var acc := obs.color_primary if use_accent else obs.color_accent

		mat.set_shader_parameter("u_time", local_time)
		mat.set_shader_parameter("u_player_y", _last_player_y)
		mat.set_shader_parameter("u_beat_phase", beat_phase)
		mat.set_shader_parameter("u_bass_energy", bass_energy)
		mat.set_shader_parameter("u_opacity_override", SettingsManager.obstacle_opacity)
		mat.set_shader_parameter("u_outline_brightness", SettingsManager.outline_brightness)
		mat.set_shader_parameter("u_outline_thickness", SettingsManager.outline_thickness)
		mat.set_shader_parameter("u_hit_highlight", 1.0 if is_hit else 0.0)
		mat.set_shader_parameter("u_flow_locked", 1.0 if flow_locked else 0.0)
		mat.set_shader_parameter("u_color_primary", prim)
		mat.set_shader_parameter("u_color_accent", acc)
		var bg_col := _stage.palette[2] if (_stage != null and _stage.palette.size() > 2) else Color("080314")
		mat.set_shader_parameter("u_color_bg", bg_col)
		mat.set_shader_parameter("u_layer_alpha", float(p.get("layer_alpha", 1.0)))


static func compute_parts(
	obs: ObstacleData,
	t_sec: float,
	beat_phase: float,
	tunnel_radius: float = 10.0
) -> Array[Dictionary]:
	var base_pos := Vector3(obs.offset_xz.x, -obs.depth, obs.offset_xz.y)
	var base_rot := Basis.from_euler(Vector3(
		deg_to_rad(obs.rotation_deg.x),
		deg_to_rad(obs.rotation_deg.y),
		deg_to_rad(obs.rotation_deg.z)
	)).orthonormalized()
	var sc := obs.scale
	var sp := obs.speed
	var amp := obs.amplitude
	var ph := obs.phase
	var parts: Array[Dictionary] = []
	var span := tunnel_radius * 0.92

	match obs.type:
		"waffle":
			# Signature multi-cell voxel waffle grid with deterministic open passage cell(s)
			var spin := Basis(Vector3.UP, t_sec * sp * 0.35 + ph)
			var rot_full := (base_rot * spin).orthonormalized()
			var open_col := posmod(obs.seed_int, 3)
			var open_row := posmod(obs.seed_int / 3, 3)
			var cell := 4.4
			# Horizontal and vertical dividers + selective cell blockers leaving clear navigable gaps (non-coplanar Y extents avoid Z-fighting)
			for r in range(4):
				var z_off := (-1.5 + float(r)) * cell
				parts.append(_make_part(base_pos, rot_full, Vector3(0.0, 0.0, z_off), Basis.IDENTITY, Vector3(span, 0.45, 0.48), sc, 1.0, (r % 2) == 1))
			for c in range(4):
				var x_off := (-1.5 + float(c)) * cell
				parts.append(_make_part(base_pos, rot_full, Vector3(x_off, 0.0, 0.0), Basis.IDENTITY, Vector3(0.48, 0.49, span), sc, 1.0, (c % 2) == 0))
			for gx in range(3):
				for gz in range(3):
					if gx == open_col and gz == open_row:
						continue
					if ((gx + gz + obs.seed_int) % 4) == 0:
						continue
					var cx := (-1.0 + float(gx)) * cell
					var cz := (-1.0 + float(gz)) * cell
					parts.append(_make_part(base_pos, rot_full, Vector3(cx, 0.0, cz), Basis.IDENTITY, Vector3(1.55, 0.41, 1.55), sc, 0.96, ((gx + gz) % 2) == 1))

		"cross_bars":
			var spin := Basis(Vector3.UP, t_sec * sp * 1.45 + ph)
			var rot_full := (base_rot * spin).orthonormalized()
			parts.append(_make_part(base_pos, rot_full, Vector3.ZERO, Basis.IDENTITY, Vector3(span, 0.55, 0.95), sc, 1.0, false))
			parts.append(_make_part(base_pos, rot_full, Vector3.ZERO, Basis.IDENTITY, Vector3(0.95, 0.59, span), sc, 1.0, true))

		"iris_ring":
			var pulse := 1.0 + 0.34 * amp * sin(t_sec * sp * 2.4 + beat_phase * TAU * 0.5 + ph)
			var ring_r := clampf(4.6 * pulse, 2.3, span * 0.85)
			var seg_count := 8
			for s in range(seg_count):
				var ang := (float(s) / float(seg_count)) * TAU + t_sec * sp * 0.5 + ph
				var lp := Vector3(cos(ang) * ring_r, 0.0, sin(ang) * ring_r)
				var lr := Basis(Vector3.UP, -ang)
				parts.append(_make_part(base_pos, base_rot, lp, lr, Vector3(0.85, 0.60, 1.95), sc, 1.0, (s % 2) == 1))

		"sliding_blades":
			for b in range(3):
				var dir_sign := 1.0 if (b % 2) == 0 else -1.0
				var slide_x := dir_sign * 4.5 * amp * sin(t_sec * sp * 2.1 + ph + float(b) * 1.4)
				var lp := Vector3(slide_x, -float(b) * 2.2, (-1.0 + float(b)) * 2.4)
				parts.append(_make_part(base_pos, base_rot, lp, Basis.IDENTITY, Vector3(4.8, 0.36, 1.45), sc, 1.0, (b % 2) == 1))

		"pendulum":
			var swing := 0.95 * clampf(amp, 0.3, 1.4) * sin(t_sec * sp * 2.2 + ph)
			var pivot := Vector3(0.0, 0.0, -span * 0.72)
			var swing_rot := Basis(Vector3.UP, swing)
			var arm_len := span * 0.88
			var arm_lp := pivot + swing_rot * Vector3(0.0, 0.0, arm_len * 0.5)
			var bob_lp := pivot + swing_rot * Vector3(0.0, 0.0, arm_len)
			parts.append(_make_part(base_pos, base_rot, arm_lp, swing_rot, Vector3(0.42, 0.42, arm_len * 0.5), sc, 1.0, true))
			parts.append(_make_part(base_pos, base_rot, bob_lp, swing_rot, Vector3(2.2, 0.85, 2.2), sc, 1.0, false))

		"tumbling_cube":
			var euler_angles := Vector3(1.1, 1.55, 0.85) * (t_sec * sp + ph)
			var tumble_rot := Basis.from_euler(euler_angles).orthonormalized()
			var rot_full := (base_rot * tumble_rot).orthonormalized()
			parts.append(_make_part(base_pos, rot_full, Vector3.ZERO, Basis.IDENTITY, Vector3(2.85, 2.85, 2.85), sc, 1.0, false))
			# Layered painted outer ring for depth silhouette
			parts.append(_make_part(base_pos, rot_full, Vector3.ZERO, Basis.IDENTITY, Vector3(3.35, 0.65, 3.35), sc, 0.85, true))

		"guillotine":
			var wave := pow(0.5 + 0.5 * sin(t_sec * sp * 2.6 + ph), 3.0)
			var blade_z := lerpf(-span * 0.68, span * 0.15, wave)
			# Side guide rails
			parts.append(_make_part(base_pos, base_rot, Vector3(-span * 0.72, 0.0, 0.0), Basis.IDENTITY, Vector3(0.65, 0.65, span), sc, 1.0, true))
			parts.append(_make_part(base_pos, base_rot, Vector3(span * 0.72, 0.0, 0.0), Basis.IDENTITY, Vector3(0.65, 0.65, span), sc, 1.0, true))
			# Slamming blade
			parts.append(_make_part(base_pos, base_rot, Vector3(0.0, 0.0, blade_z), Basis.IDENTITY, Vector3(span * 0.70, 0.44, 1.95), sc, 1.0, false))

		"drifting_ghost":
			var gx := 4.8 * amp * sin(t_sec * sp * 1.3 + ph)
			var gz := 4.8 * amp * cos(t_sec * sp * 1.9 + ph * 0.7)
			var drift_rot := Basis(Vector3.UP, t_sec * sp * 1.1)
			var crown_rot := Basis(Vector3.UP, -t_sec * sp * 0.9 + 0.785)
			parts.append(_make_part(base_pos, base_rot, Vector3(gx, 0.0, gz), drift_rot, Vector3(2.2, 1.45, 2.2), sc, 0.85, false))
			parts.append(_make_part(base_pos, base_rot, Vector3(gx, -0.55, gz), crown_rot, Vector3(2.85, 0.60, 2.85), sc, 0.62, true))
			parts.append(_make_part(base_pos, base_rot, Vector3(gx, -1.25, gz), drift_rot, Vector3(1.55, 0.95, 1.55), sc, 0.42, false))

		"spiral_slats":
			for s in range(5):
				var ang := float(s) * 0.62 + t_sec * sp * 1.1 + ph
				var lr := Basis(Vector3.UP, ang)
				var lp := Vector3(cos(ang) * 2.6, -float(s) * 1.25, sin(ang) * 2.6)
				parts.append(_make_part(base_pos, base_rot, lp, lr, Vector3(4.2, 0.35, 0.92), sc, 1.0, (s % 2) == 1))

		"pillar_grid":
			var sway := 1.4 * amp * sin(t_sec * sp * 1.5 + ph)
			var offsets: Array[Vector2] = [
				Vector2(-4.4, -3.5),
				Vector2(4.4, -3.5),
				Vector2(0.0 + sway, 0.0),
				Vector2(-4.2, 3.8),
				Vector2(4.2, 3.8),
			]
			for idx in range(offsets.size()):
				var p2 := offsets[idx]
				parts.append(_make_part(base_pos, base_rot, Vector3(p2.x, -1.5, p2.y), Basis.IDENTITY, Vector3(1.15, 3.2, 1.15), sc, 1.0, (idx % 2) == 1))

		_:
			parts.append(_make_part(base_pos, base_rot, Vector3.ZERO, Basis.IDENTITY, Vector3(2.5, 0.5, 2.5), sc, 1.0, false))

	return parts


static func _make_part(
	base_pos: Vector3,
	base_rot: Basis,
	local_pos: Vector3,
	local_rot: Basis,
	local_half_extents: Vector3,
	obs_scale: Vector3,
	layer_alpha: float,
	use_accent: bool
) -> Dictionary:
	var scaled_offset := Vector3(local_pos.x * obs_scale.x, local_pos.y * obs_scale.y, local_pos.z * obs_scale.z)
	var world_pos := base_pos + base_rot * scaled_offset
	var world_rot := (base_rot * local_rot).orthonormalized()
	var world_half := Vector3(
		maxf(0.12, absf(local_half_extents.x * obs_scale.x)),
		maxf(0.12, absf(local_half_extents.y * obs_scale.y)),
		maxf(0.12, absf(local_half_extents.z * obs_scale.z))
	)
	return {
		"transform": Transform3D(world_rot, world_pos),
		"half_extents": world_half,
		"layer_alpha": layer_alpha,
		"use_accent": use_accent,
	}
