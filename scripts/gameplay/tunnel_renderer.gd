class_name TunnelRenderer
extends Node3D
## Pooled MultiMeshInstance3D voxel tunnel renderer.
## Recycles 64 rings x 16 voxel blocks dynamically ahead of the player's -Y descent.

const RING_COUNT := 64
const SEGMENTS_PER_RING := 16
const RING_SPACING := 2.5

var _multi_mesh_inst: MultiMeshInstance3D
var _shader_mat: ShaderMaterial
var _tunnel_radius: float = 10.0
var _last_start_ring: int = -999999


func _ready() -> void:
	_setup_multimesh()


func _setup_multimesh() -> void:
	if _multi_mesh_inst != null:
		return
	_multi_mesh_inst = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.instance_count = RING_COUNT * SEGMENTS_PER_RING

	var box := BoxMesh.new()
	box.size = Vector3(3.75, 2.32, 1.35)
	mm.mesh = box

	var shader := load("res://shaders/voxel_tunnel.gdshader") as Shader
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = shader
	_multi_mesh_inst.material_override = _shader_mat
	_multi_mesh_inst.multimesh = mm
	_multi_mesh_inst.extra_cull_margin = 200.0
	add_child(_multi_mesh_inst)


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

	# Modulo ring-buffer update: write full buffer only on jump/reset, otherwise update ONLY newly entered rings
	var current_ring := int(floor((-player_y) / RING_SPACING)) - 4
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

	var c_prim := palette[0] if palette.size() > 0 else Color("14f1d9")
	var c_acc := palette[1] if palette.size() > 1 else Color("ff2e93")
	var c_bg := palette[2] if palette.size() > 2 else Color("120824")

	_shader_mat.set_shader_parameter("u_time", elapsed_time)
	_shader_mat.set_shader_parameter("u_player_y", player_y)
	_shader_mat.set_shader_parameter("u_beat_phase", beat_phase)
	_shader_mat.set_shader_parameter("u_bass_energy", bass_energy)
	_shader_mat.set_shader_parameter("u_flow", flow)
	_shader_mat.set_shader_parameter("u_flow_locked", 1.0 if flow >= 0.70 else 0.0)
	_shader_mat.set_shader_parameter("u_color_primary", c_prim)
	_shader_mat.set_shader_parameter("u_color_accent", c_acc)
	_shader_mat.set_shader_parameter("u_color_bg", c_bg)

	_shader_mat.set_shader_parameter("u_bit_breathing", 1.0 if EffectCatalog.has_effect(effect_mask, 0) else 0.0)
	_shader_mat.set_shader_parameter("u_bit_twist", 1.0 if EffectCatalog.has_effect(effect_mask, 1) else 0.0)
	_shader_mat.set_shader_parameter("u_bit_wobble", 1.0 if EffectCatalog.has_effect(effect_mask, 2) else 0.0)
	_shader_mat.set_shader_parameter("u_bit_pulse", 1.0 if EffectCatalog.has_effect(effect_mask, 3) else 0.0)
	_shader_mat.set_shader_parameter("u_bit_palette_cycle", 1.0 if EffectCatalog.has_effect(effect_mask, 4) else 0.0)
	_shader_mat.set_shader_parameter("u_bit_checker", 1.0 if EffectCatalog.has_effect(effect_mask, 5) else 0.0)
	_shader_mat.set_shader_parameter("u_bit_wireframe", 1.0 if EffectCatalog.has_effect(effect_mask, 6) else 0.0)
	_shader_mat.set_shader_parameter("u_bit_depth_fog", 1.0 if EffectCatalog.has_effect(effect_mask, 7) else 0.0)


func _write_ring(mm: MultiMesh, ring_idx: int) -> void:
	var slot := posmod(ring_idx, RING_COUNT)
	var y_pos := -float(ring_idx) * RING_SPACING
	var twist_offset := float(ring_idx) * 0.04
	for seg in range(SEGMENTS_PER_RING):
		var inst_idx := slot * SEGMENTS_PER_RING + seg
		var angle := (float(seg) / float(SEGMENTS_PER_RING)) * TAU + twist_offset
		var pos := Vector3(cos(angle) * _tunnel_radius, y_pos, sin(angle) * _tunnel_radius)
		var basis := Basis(Vector3.UP, -angle + PI * 0.5)
		mm.set_instance_transform(inst_idx, Transform3D(basis, pos))
		var alt := float((ring_idx + seg) & 1)
		mm.set_instance_custom_data(inst_idx, Color(float(ring_idx), alt, float(seg) / float(SEGMENTS_PER_RING), 1.0))
