class_name ObstacleManager
extends Node3D
## Spawns, animates, and renders all 10 obstacle archetypes with pooled meshes,
## Early-Z opaque vs. translucent shader selection, and decoupled logic vs. visual sync.

const ACTIVE_AHEAD_M := 165.0
const ACTIVE_BEHIND_M := 14.0

var local_time: float = 0.0
var highlighted_obstacle_id: String = ""
var _last_player_y: float = 0.0

var _shader_opaque: Shader
var _shader: Shader
var _unit_box: BoxMesh
var _stage: StageData
var _node_pool: Dictionary = {} # obs_id -> Array[{mi, mat_opaque, mat_alpha}]
var _free_meshes: Array[Dictionary] = []
var _active_cache: Array[Dictionary] = [] # [{obstacle: ObstacleData, parts: Array[Dictionary]}]


func _ready() -> void:
	_ensure_shared_resources()


func _ensure_shared_resources() -> void:
	if _shader_opaque == null:
		_shader_opaque = load("res://shaders/obstacle_opaque.gdshader") as Shader
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
		var slots: Array = _node_pool[k]
		for s in slots:
			var slot := s as Dictionary
			var mi := slot["mi"] as MeshInstance3D
			if is_instance_valid(mi):
				mi.visible = false
				_free_meshes.append(slot)
	_node_pool.clear()
	_active_cache.clear()


func set_highlight_obstacle(obs_id: String) -> void:
	highlighted_obstacle_id = obs_id


func step_logic(
	player_y: float,
	delta: float,
	beat_phase: float
) -> void:
	_ensure_shared_resources()
	local_time += delta
	_last_player_y = player_y
	_active_cache.clear()
	if _stage == null:
		return

	var min_depth := (-player_y) - ACTIVE_BEHIND_M
	var max_depth := (-player_y) + ACTIVE_AHEAD_M
	for obs in _stage.obstacles:
		if obs.depth < min_depth or obs.depth > max_depth:
			continue
		var parts := compute_parts(obs, local_time, beat_phase, _stage.tunnel_radius)
		_active_cache.append({"obstacle": obs, "parts": parts})


func sync_visuals(
	beat_phase: float,
	bass_energy: float,
	flow_locked: bool
) -> void:
	_ensure_shared_resources()
	var visible_ids: Dictionary = {}
	for entry in _active_cache:
		var obs := entry["obstacle"] as ObstacleData
		var parts := entry["parts"] as Array[Dictionary]
		visible_ids[obs.id] = true
		_sync_visual_entry(obs, parts, beat_phase, bass_energy, flow_locked)

	var to_release: Array[String] = []
	for existing_id in _node_pool.keys():
		if not visible_ids.has(existing_id):
			to_release.append(str(existing_id))
	for rid in to_release:
		var slots: Array = _node_pool[rid]
		for s in slots:
			var slot := s as Dictionary
			var mi := slot["mi"] as MeshInstance3D
			if is_instance_valid(mi):
				mi.visible = false
				_free_meshes.append(slot)
		_node_pool.erase(rid)


func step_and_sync(
	player_y: float,
	delta: float,
	beat_phase: float,
	bass_energy: float,
	flow_locked: bool
) -> void:
	step_logic(player_y, delta, beat_phase)
	sync_visuals(beat_phase, bass_energy, flow_locked)


func get_active_obstacles() -> Array[Dictionary]:
	return _active_cache


func _acquire_mesh_slot() -> Dictionary:
	while not _free_meshes.is_empty():
		var recycled := _free_meshes.pop_back() as Dictionary
		var rmi := recycled["mi"] as MeshInstance3D
		if is_instance_valid(rmi):
			rmi.visible = true
			return recycled
	var mi := MeshInstance3D.new()
	mi.mesh = _unit_box
	var mat_op := ShaderMaterial.new()
	mat_op.shader = _shader_opaque
	var mat_al := ShaderMaterial.new()
	mat_al.shader = _shader
	mi.material_override = mat_op
	add_child(mi)
	return {
		"mi": mi,
		"mat_opaque": mat_op,
		"mat_alpha": mat_al,
	}


func _sync_visual_entry(
	obs: ObstacleData,
	parts: Array[Dictionary],
	beat_phase: float,
	bass_energy: float,
	flow_locked: bool
) -> void:
	if not _node_pool.has(obs.id):
		_node_pool[obs.id] = []

	var slots: Array = _node_pool[obs.id]
	while slots.size() < parts.size():
		slots.append(_acquire_mesh_slot())

	while slots.size() > parts.size():
		var extra := slots.pop_back() as Dictionary
		var emi := extra["mi"] as MeshInstance3D
		if is_instance_valid(emi):
			emi.visible = false
			_free_meshes.append(extra)

	var is_hit := (obs.id == highlighted_obstacle_id and not obs.id.is_empty())
	var bg_col := _stage.palette[2] if (_stage != null and _stage.palette.size() > 2) else Color("080314")
	var global_opaque := SettingsManager.obstacle_opacity >= 0.99

	for i in range(parts.size()):
		var p: Dictionary = parts[i]
		var slot := slots[i] as Dictionary
		var mi := slot["mi"] as MeshInstance3D
		var part_xform := p["transform"] as Transform3D
		var half_ext := p["half_extents"] as Vector3
		var layer_alpha := float(p.get("layer_alpha", 1.0))
		var use_opaque := global_opaque and layer_alpha >= 0.99

		var mat := (slot["mat_opaque"] if use_opaque else slot["mat_alpha"]) as ShaderMaterial
		if mi.material_override != mat:
			mi.material_override = mat

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
		mat.set_shader_parameter("u_half_extents", half_ext)
		mat.set_shader_parameter("u_color_primary", prim)
		mat.set_shader_parameter("u_color_accent", acc)
		mat.set_shader_parameter("u_color_bg", bg_col)
		mat.set_shader_parameter("u_layer_alpha", layer_alpha)


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
	var span := tunnel_radius * 0.94

	match obs.type:
		"waffle":
			# Clean non-overlapping 3x3 hollow voxel grid matching Steam ss_00 & trailer frames
			var spin := Basis(Vector3.UP, t_sec * sp * 0.35 + ph)
			var rot_full := (base_rot * spin).orthonormalized()
			var open_col := posmod(obs.seed_int, 3)
			var open_row := posmod(obs.seed_int / 3, 3)
			var cell := 4.4
			var rail_h := 0.42
			var bridge_hz := (cell * 0.5) - rail_h - 0.01
			for r in range(4):
				var z_off := (-1.5 + float(r)) * cell
				parts.append(_make_part(base_pos, rot_full, Vector3(0.0, 0.0, z_off), Basis.IDENTITY, Vector3(span, 0.45, rail_h), sc, 1.0, false))
			for r_band in range(3):
				var z_mid := (-1.0 + float(r_band)) * cell
				for c in range(4):
					var x_off := (-1.5 + float(c)) * cell
					parts.append(_make_part(base_pos, rot_full, Vector3(x_off, 0.0, z_mid), Basis.IDENTITY, Vector3(rail_h, 0.45, bridge_hz), sc, 1.0, false))
			var blockers := 0
			for gx in range(3):
				for gz in range(3):
					if gx == open_col and gz == open_row:
						continue
					if ((gx + gz + obs.seed_int) % 4) != 1 or blockers >= 2:
						continue
					blockers += 1
					var cx := (-1.0 + float(gx)) * cell
					var cz := (-1.0 + float(gz)) * cell
					parts.append(_make_part(base_pos, rot_full, Vector3(cx, 0.0, cz), Basis.IDENTITY, Vector3(1.55, 0.45, 1.55), sc, 0.92, true))

		"cross_bars":
			# Non-overlapping monumental X-cross blades covering center cleanly
			var spin := Basis(Vector3.UP, t_sec * sp * 1.45 + ph)
			var rot_full := (base_rot * spin).orthonormalized()
			var arm_w := 1.02
			var z_arm_len := (span - arm_w) * 0.5
			var z_arm_off := arm_w + z_arm_len + 0.01
			parts.append(_make_part(base_pos, rot_full, Vector3.ZERO, Basis.IDENTITY, Vector3(span, 0.52, arm_w), sc, 1.0, false))
			parts.append(_make_part(base_pos, rot_full, Vector3(0.0, 0.0, z_arm_off), Basis.IDENTITY, Vector3(arm_w, 0.52, z_arm_len), sc, 1.0, false))
			parts.append(_make_part(base_pos, rot_full, Vector3(0.0, 0.0, -z_arm_off), Basis.IDENTITY, Vector3(arm_w, 0.52, z_arm_len), sc, 1.0, false))

		"iris_ring":
			var pulse := 1.0 + 0.32 * amp * sin(t_sec * sp * 2.4 + beat_phase * TAU * 0.5 + ph)
			var ring_r := clampf(4.8 * pulse, 2.4, span * 0.86)
			var seg_count := 12
			for s in range(seg_count):
				var ang := (float(s) / float(seg_count)) * TAU + t_sec * sp * 0.5 + ph
				var lp := Vector3(cos(ang) * ring_r, 0.0, sin(ang) * ring_r)
				var lr := Basis(Vector3.UP, -ang)
				parts.append(_make_part(base_pos, base_rot, lp, lr, Vector3(0.88, 0.56, 1.42), sc, 1.0, (s % 2) == 1))

		"sliding_blades":
			for b in range(3):
				var dir_sign := 1.0 if (b % 2) == 0 else -1.0
				var slide_x := dir_sign * 4.6 * amp * sin(t_sec * sp * 2.1 + ph + float(b) * 1.4)
				var lp := Vector3(slide_x, -float(b) * 2.4, (-1.0 + float(b)) * 2.5)
				parts.append(_make_part(base_pos, base_rot, lp, Basis.IDENTITY, Vector3(5.2, 0.42, 1.85), sc, 1.0, (b % 2) == 1))

		"pendulum":
			var swing := 0.95 * clampf(amp, 0.3, 1.4) * sin(t_sec * sp * 2.2 + ph)
			var pivot := Vector3(0.0, 0.0, -span * 0.72)
			var swing_rot := Basis(Vector3.UP, swing)
			var arm_len := span * 0.88
			var bob_half := Vector3(2.2, 0.85, 2.2)
			var arm_half_len := maxf(0.5, (arm_len - bob_half.z) * 0.5)
			var arm_lp := pivot + swing_rot * Vector3(0.0, 0.0, arm_half_len)
			var bob_lp := pivot + swing_rot * Vector3(0.0, 0.0, arm_len)
			parts.append(_make_part(base_pos, base_rot, arm_lp, swing_rot, Vector3(0.42, 0.42, arm_half_len), sc, 1.0, true))
			parts.append(_make_part(base_pos, base_rot, bob_lp, swing_rot, bob_half, sc, 1.0, false))

		"tumbling_cube":
			var euler_angles := Vector3(1.1, 1.55, 0.85) * (t_sec * sp + ph)
			var tumble_rot := Basis.from_euler(euler_angles).orthonormalized()
			var rot_full := (base_rot * tumble_rot).orthonormalized()
			parts.append(_make_part(base_pos, rot_full, Vector3.ZERO, Basis.IDENTITY, Vector3(2.85, 2.85, 2.85), sc, 1.0, false))
			parts.append(_make_part(base_pos, rot_full, Vector3.ZERO, Basis.IDENTITY, Vector3(3.45, 0.58, 3.45), sc, 0.88, true))

		"guillotine":
			# Sculpted tunnel-spanning sliding half-wall barrier with flanking guide rails
			var wave := pow(0.5 + 0.5 * sin(t_sec * sp * 2.6 + ph), 2.4)
			var blade_z := lerpf(-span * 0.58, span * 0.16, wave)
			parts.append(_make_part(base_pos, base_rot, Vector3(-span * 0.78, 0.0, 0.0), Basis.IDENTITY, Vector3(0.55, 0.55, span * 0.92), sc, 1.0, true))
			parts.append(_make_part(base_pos, base_rot, Vector3(span * 0.78, 0.0, 0.0), Basis.IDENTITY, Vector3(0.55, 0.55, span * 0.92), sc, 1.0, true))
			parts.append(_make_part(base_pos, base_rot, Vector3(0.0, 0.0, blade_z), Basis.IDENTITY, Vector3(span * 0.68, 0.46, 2.45), sc, 1.0, false))

		"drifting_ghost":
			var gx := 4.8 * amp * sin(t_sec * sp * 1.3 + ph)
			var gz := 4.8 * amp * cos(t_sec * sp * 1.9 + ph * 0.7)
			var drift_rot := Basis(Vector3.UP, t_sec * sp * 1.1)
			var crown_rot := Basis(Vector3.UP, -t_sec * sp * 0.9 + 0.785)
			parts.append(_make_part(base_pos, base_rot, Vector3(gx, 0.0, gz), drift_rot, Vector3(2.2, 1.25, 2.2), sc, 0.88, false))
			parts.append(_make_part(base_pos, base_rot, Vector3(gx, -1.75, gz), crown_rot, Vector3(2.85, 0.52, 2.85), sc, 0.72, true))
			parts.append(_make_part(base_pos, base_rot, Vector3(gx, -3.10, gz), drift_rot, Vector3(1.55, 0.85, 1.55), sc, 0.52, false))

		"spiral_slats":
			for s in range(6):
				var ang := float(s) * 0.56 + t_sec * sp * 1.1 + ph
				var lr := Basis(Vector3.UP, ang)
				var lp := Vector3(cos(ang) * 2.8, -float(s) * 1.25, sin(ang) * 2.8)
				parts.append(_make_part(base_pos, base_rot, lp, lr, Vector3(4.3, 0.40, 1.02), sc, 1.0, (s % 2) == 1))

		"pillar_grid":
			var sway := 1.4 * amp * sin(t_sec * sp * 1.5 + ph)
			var offsets: Array[Vector2] = [
				Vector2(-4.5, -3.6),
				Vector2(4.5, -3.6),
				Vector2(0.0 + sway, 0.0),
				Vector2(-4.3, 3.8),
				Vector2(4.3, 3.8),
			]
			for idx in range(offsets.size()):
				var p2 := offsets[idx]
				parts.append(_make_part(base_pos, base_rot, Vector3(p2.x, -1.6, p2.y), Basis.IDENTITY, Vector3(1.18, 3.5, 1.18), sc, 1.0, (idx % 2) == 1))

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
