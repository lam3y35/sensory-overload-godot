class_name TunnelRenderer
extends Node3D
## High-density carved axis-aligned 3D voxel tunnel renderer with zero coplanar brick Z-fighting,
## tiered radial depth relief, wall-mounted emissive sconces, and analytical sconce lighting.

const RING_COUNT := 46
const RING_SPACING := 2.40
const VOX_PITCH := 1.48
const CARVE_RADIUS_VOX := 7.35

const SCONCE_RING_PERIOD := 12
const SCONCE_SLOTS := 5

var _multi_mesh_inst: MultiMeshInstance3D
var _shader_mat: ShaderMaterial
var _sconce_mm_inst: MultiMeshInstance3D
var _sconce_mat: ShaderMaterial

var _ring_cells: Array[Dictionary] = []
var _tunnel_radius: float = 10.0
var _last_start_ring: int = -999999


func _ready() -> void:
	_setup_multimesh()


func _build_ring_cells() -> void:
	if not _ring_cells.is_empty():
		return
	var selected: Dictionary = {}
	for ix in range(-9, 10):
		for iz in range(-9, 10):
			var rc := sqrt(float(ix * ix + iz * iz))
			if rc < CARVE_RADIUS_VOX:
				continue
			# 4-connected interior boundary + the 4 diagonal corner plugs (±6, ±6) -> 48 cells with ZERO XZ overlaps
			var is_edge_4 := (
				sqrt(float((ix + 1) * (ix + 1) + iz * iz)) < CARVE_RADIUS_VOX
				or sqrt(float((ix - 1) * (ix - 1) + iz * iz)) < CARVE_RADIUS_VOX
				or sqrt(float(ix * ix + (iz + 1) * (iz + 1))) < CARVE_RADIUS_VOX
				or sqrt(float(ix * ix + (iz - 1) * (iz - 1))) < CARVE_RADIUS_VOX
			)
			var is_diag_corner := (absi(ix) == 6 and absi(iz) == 6)
			if not (is_edge_4 or is_diag_corner):
				continue
			selected[Vector2i(ix, iz)] = true

	for k in selected.keys():
		var cell := k as Vector2i
		var ix := cell.x
		var iz := cell.y
		var sx_sign := 1.0 if ix > 0 else (-1.0 if ix < 0 else 0.0)
		var sz_sign := 1.0 if iz > 0 else (-1.0 if iz < 0 else 0.0)
		var ax := absi(ix)
		var az := absi(iz)

		# Strictly < 1.0 lateral scale eliminates all brick-to-brick face interpenetration / Z-fighting
		var scale_x := 0.992
		var scale_z := 0.992
		var outward_dir := Vector2(sx_sign, sz_sign)
		var base_shift := Vector2.ZERO
		var is_corner := false
		if ax > az:
			scale_x = 2.65
			outward_dir = Vector2(sx_sign, 0.0)
			base_shift = Vector2(sx_sign * (scale_x * 0.5 - 0.5) * VOX_PITCH, 0.0)
		elif az > ax:
			scale_z = 2.65
			outward_dir = Vector2(0.0, sz_sign)
			base_shift = Vector2(0.0, sz_sign * (scale_z * 0.5 - 0.5) * VOX_PITCH)
		else:
			is_corner = true
			scale_x = 2.15
			scale_z = 2.15
			outward_dir = Vector2(sx_sign, sz_sign).normalized()
			base_shift = Vector2(
				sx_sign * (scale_x * 0.5 - 0.5) * VOX_PITCH,
				sz_sign * (scale_z * 0.5 - 0.5) * VOX_PITCH
			)

		var ang := fmod(atan2(float(iz), float(ix)) + TAU, TAU)
		_ring_cells.append({
			"ix": ix,
			"iz": iz,
			"base_xz": Vector2(float(ix), float(iz)) * VOX_PITCH + base_shift,
			"outward_dir": outward_dir,
			"scale_x": scale_x,
			"scale_z": scale_z,
			"angle_norm": ang / TAU,
			"is_sconce_side": (az == 0 and ax >= 7),
			"is_corner": is_corner,
		})


func _setup_multimesh() -> void:
	_build_ring_cells()
	var cell_count := _ring_cells.size()

	if _multi_mesh_inst == null:
		_multi_mesh_inst = MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.instance_count = RING_COUNT * cell_count

		var box := BoxMesh.new()
		# Strict 0.992 vertical/lateral inset creates clean dark mortar seams with ZERO Z-fighting across all GPU drivers
		box.size = Vector3(VOX_PITCH, RING_SPACING * 0.992, VOX_PITCH)
		mm.mesh = box

		var shader := load("res://shaders/voxel_tunnel.gdshader") as Shader
		_shader_mat = ShaderMaterial.new()
		_shader_mat.shader = shader
		_multi_mesh_inst.material_override = _shader_mat
		_multi_mesh_inst.multimesh = mm
		_multi_mesh_inst.extra_cull_margin = 200.0
		_multi_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_multi_mesh_inst)

	if _sconce_mm_inst == null:
		_sconce_mm_inst = MultiMeshInstance3D.new()
		var smm := MultiMesh.new()
		smm.transform_format = MultiMesh.TRANSFORM_3D
		smm.instance_count = SCONCE_SLOTS * 2
		var sbox := BoxMesh.new()
		sbox.size = Vector3(0.32, 1.55, 1.00)
		smm.mesh = sbox

		var sshader := load("res://shaders/voxel_sconce.gdshader") as Shader
		_sconce_mat = ShaderMaterial.new()
		_sconce_mat.shader = sshader
		_sconce_mm_inst.material_override = _sconce_mat
		_sconce_mm_inst.multimesh = smm
		_sconce_mm_inst.extra_cull_margin = 200.0
		_sconce_mm_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_sconce_mm_inst)


func reset_tunnel(radius: float = 10.0) -> void:
	_tunnel_radius = radius
	_last_start_ring = -999999
	_setup_multimesh()


func update_tunnel(
	player_y: float,
	elapsed_time: float,
	effect_mask: int,
	beat_phase: float,
	bass_energy: float,
	flow: float,
	palette: Array[Color],
	radius: float = 10.0
) -> void:
	_setup_multimesh()
	if not is_equal_approx(_tunnel_radius, radius):
		_tunnel_radius = radius
		_last_start_ring = -999999

	var current_ring := int(floor((-player_y) / RING_SPACING)) - 3
	if current_ring != _last_start_ring:
		var mm := _multi_mesh_inst.multimesh
		if _last_start_ring == -999999 or absi(current_ring - _last_start_ring) >= RING_COUNT:
			for r_offset in range(RING_COUNT):
				_write_ring(mm, current_ring + r_offset)
		elif current_ring > _last_start_ring:
			for ring_idx in range(_last_start_ring + RING_COUNT, current_ring + RING_COUNT):
				_write_ring(mm, ring_idx)
		else:
			for ring_idx in range(current_ring, _last_start_ring):
				_write_ring(mm, ring_idx)
		_last_start_ring = current_ring

	var c_prim := palette[0] if palette.size() > 0 else Color("c2188a")
	var c_acc := palette[1] if palette.size() > 1 else Color("2e1a7a")
	var c_bg := palette[2] if palette.size() > 2 else Color("070410")

	var b_breath := 1.0 if EffectCatalog.has_effect(effect_mask, 0) else 0.0
	var b_twist := 1.0 if EffectCatalog.has_effect(effect_mask, 1) else 0.0
	var b_wobble := 1.0 if EffectCatalog.has_effect(effect_mask, 2) else 0.0
	var b_pulse := 1.0 if EffectCatalog.has_effect(effect_mask, 3) else 0.0
	var b_pal := 1.0 if EffectCatalog.has_effect(effect_mask, 4) else 0.0
	var b_chk := 1.0 if EffectCatalog.has_effect(effect_mask, 5) else 0.0
	var b_wire := 1.0 if EffectCatalog.has_effect(effect_mask, 6) else 0.0
	var b_fog := 1.0 if EffectCatalog.has_effect(effect_mask, 7) else 0.0

	_shader_mat.set_shader_parameter("u_time", elapsed_time)
	_shader_mat.set_shader_parameter("u_player_y", player_y)
	_shader_mat.set_shader_parameter("u_beat_phase", beat_phase)
	_shader_mat.set_shader_parameter("u_bass_energy", bass_energy)
	_shader_mat.set_shader_parameter("u_flow", flow)
	_shader_mat.set_shader_parameter("u_flow_locked", 1.0 if flow >= 0.70 else 0.0)
	_shader_mat.set_shader_parameter("u_sconce_spacing", float(SCONCE_RING_PERIOD) * RING_SPACING)
	_shader_mat.set_shader_parameter("u_tunnel_radius", _tunnel_radius)
	_shader_mat.set_shader_parameter("u_color_primary", c_prim)
	_shader_mat.set_shader_parameter("u_color_accent", c_acc)
	_shader_mat.set_shader_parameter("u_color_bg", c_bg)

	_shader_mat.set_shader_parameter("u_bit_breathing", b_breath)
	_shader_mat.set_shader_parameter("u_bit_twist", b_twist)
	_shader_mat.set_shader_parameter("u_bit_wobble", b_wobble)
	_shader_mat.set_shader_parameter("u_bit_pulse", b_pulse)
	_shader_mat.set_shader_parameter("u_bit_palette_cycle", b_pal)
	_shader_mat.set_shader_parameter("u_bit_checker", b_chk)
	_shader_mat.set_shader_parameter("u_bit_wireframe", b_wire)
	_shader_mat.set_shader_parameter("u_bit_depth_fog", b_fog)

	_sconce_mat.set_shader_parameter("u_time", elapsed_time)
	_sconce_mat.set_shader_parameter("u_player_y", player_y)
	_sconce_mat.set_shader_parameter("u_beat_phase", beat_phase)
	_sconce_mat.set_shader_parameter("u_bass_energy", bass_energy)
	_sconce_mat.set_shader_parameter("u_color_bg", c_bg)
	_sconce_mat.set_shader_parameter("u_bit_breathing", b_breath)
	_sconce_mat.set_shader_parameter("u_bit_twist", b_twist)
	_sconce_mat.set_shader_parameter("u_bit_wobble", b_wobble)
	_sconce_mat.set_shader_parameter("u_bit_depth_fog", b_fog)

	_update_sconce_blocks(current_ring)


func _update_sconce_blocks(start_ring: int) -> void:
	var r_scale := _tunnel_radius / 10.0
	var first_sconce_idx := int(floor(float(start_ring + 2) / float(SCONCE_RING_PERIOD)))
	var wall_x := 10.12 * r_scale
	var smm := _sconce_mm_inst.multimesh
	for s_slot in range(SCONCE_SLOTS):
		var ring_num := (first_sconce_idx + s_slot) * SCONCE_RING_PERIOD
		var y_pos := -float(ring_num) * RING_SPACING
		smm.set_instance_transform(s_slot * 2, Transform3D(Basis.IDENTITY, Vector3(-wall_x, y_pos, 0.0)))
		smm.set_instance_transform(s_slot * 2 + 1, Transform3D(Basis.IDENTITY, Vector3(wall_x, y_pos, 0.0)))


func _write_ring(mm: MultiMesh, ring_idx: int) -> void:
	var cell_count := _ring_cells.size()
	var slot := posmod(ring_idx, RING_COUNT)
	var y_pos := -float(ring_idx) * RING_SPACING
	var r_scale := _tunnel_radius / 10.0
	var is_collar := (posmod(ring_idx, 12) == 0)
	var is_sconce_row := (posmod(ring_idx, SCONCE_RING_PERIOD) == 0)

	for ci in range(cell_count):
		var c: Dictionary = _ring_cells[ci]
		var inst_idx := slot * cell_count + ci

		var h1 := _hash_01(ring_idx * 73856093 ^ ci * 19349663)
		var h_cluster := _hash_01((ring_idx >> 1) * 83492791 ^ (ci >> 1) * 297121507)

		var step_band := floorf((h1 * 0.55 + h_cluster * 0.45) * 4.99)
		var step_m := (step_band - 1.2) * 0.36 + (h1 - 0.5) * 0.06
		if is_collar:
			step_m = -0.32 + (h1 - 0.5) * 0.05
		elif is_sconce_row and bool(c["is_sconce_side"]):
			step_m = 0.0
		if bool(c["is_corner"]):
			step_m = clampf(step_m, 0.05, 0.55)

		var base_xz := (c["base_xz"] as Vector2) * r_scale
		var out_dir := c["outward_dir"] as Vector2
		var final_xz := base_xz + out_dir * (step_m * r_scale)

		var pos := Vector3(final_xz.x, y_pos, final_xz.y)
		var b := Basis.IDENTITY.scaled_local(Vector3(float(c["scale_x"]) * r_scale, 1.0, float(c["scale_z"]) * r_scale))
		mm.set_instance_transform(inst_idx, Transform3D(b, pos))

		var crevice_ao := clampf(0.96 - step_m * 0.24, 0.56, 1.10)
		mm.set_instance_custom_data(inst_idx, Color(float(ring_idx), float(c["angle_norm"]), crevice_ao, h1))


static func apply_cinema_environment(env: Environment, bg_color: Color = Color("06050b")) -> void:
	if env == null:
		return
	env.background_mode = Environment.BG_COLOR
	env.background_color = bg_color * 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.00
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = 0.45
	env.glow_strength = 0.95
	env.glow_bloom = 0.14
	env.glow_hdr_threshold = 1.15
	env.set("glow_levels/4", 0.0)
	env.set("glow_levels/5", 0.0)
	env.set("glow_levels/6", 0.0)
	env.set("glow_levels/7", 0.0)


static func _hash_01(seed_val: int) -> float:
	var x := (seed_val ^ (seed_val >> 13)) * 1274126177
	x = x ^ (x >> 16)
	return float(x & 0xFFFF) / 65535.0
