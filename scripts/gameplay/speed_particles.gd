class_name SpeedParticles
extends Node3D
## Pooled MultiMeshInstance3D speed-streak needles & event spark burst particles.
## Uses vertex-colored additive unshaded materials for Vulkan Forward+ & OpenGL3 Compatibility parity.

const STREAM_COUNT := 96
const BURST_COUNT := 32

var _stream_mm_inst: MultiMeshInstance3D
var _stream_data: Array[Dictionary] = []

var _burst_mm_inst: MultiMeshInstance3D
var _burst_data: Array[Dictionary] = []
var _burst_cursor: int = 0
var _radius: float = 9.4


func _ready() -> void:
	_setup_meshes()


func _setup_meshes() -> void:
	if _stream_mm_inst == null:
		_stream_mm_inst = MultiMeshInstance3D.new()
		var smm := MultiMesh.new()
		smm.transform_format = MultiMesh.TRANSFORM_3D
		smm.use_colors = true
		smm.instance_count = STREAM_COUNT
		var sbox := BoxMesh.new()
		sbox.size = Vector3.ONE
		smm.mesh = sbox

		var smat := StandardMaterial3D.new()
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.vertex_color_use_as_albedo = true
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		smat.no_depth_test = false
		_stream_mm_inst.material_override = smat
		_stream_mm_inst.multimesh = smm
		_stream_mm_inst.extra_cull_margin = 160.0
		add_child(_stream_mm_inst)

	if _burst_mm_inst == null:
		_burst_mm_inst = MultiMeshInstance3D.new()
		var bmm := MultiMesh.new()
		bmm.transform_format = MultiMesh.TRANSFORM_3D
		bmm.use_colors = true
		bmm.instance_count = BURST_COUNT
		var bbox := BoxMesh.new()
		bbox.size = Vector3.ONE
		bmm.mesh = bbox

		var bmat := StandardMaterial3D.new()
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.vertex_color_use_as_albedo = true
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_burst_mm_inst.material_override = bmat
		_burst_mm_inst.multimesh = bmm
		_burst_mm_inst.extra_cull_margin = 160.0
		add_child(_burst_mm_inst)


func reset_particles(tunnel_radius: float = 10.0) -> void:
	_setup_meshes()
	_radius = clampf(tunnel_radius * 0.88, 6.0, 12.0)
	_stream_data.clear()
	for i in range(STREAM_COUNT):
		var ang := (float(i) / float(STREAM_COUNT)) * TAU + float(i % 7) * 0.37
		var r_frac := 0.84 + 0.11 * fmod(float(i) * 0.6180339, 1.0)
		var depth_off := 4.0 + 135.0 * (float(i) / float(STREAM_COUNT))
		var spd := 0.85 + 0.55 * fmod(float(i) * 0.381966, 1.0)
		_stream_data.append({
			"ang": ang,
			"r_frac": r_frac,
			"y": -depth_off,
			"spd": spd,
		})

	_burst_data.clear()
	var bmm := _burst_mm_inst.multimesh
	for i in range(BURST_COUNT):
		_burst_data.append({
			"pos": Vector3.ZERO,
			"vel": Vector3.ZERO,
			"life": 0.0,
			"max_life": 0.45,
			"col": Color.WHITE,
		})
		bmm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled_local(Vector3.ZERO), Vector3.ZERO))
		bmm.set_instance_color(i, Color(1, 1, 1, 0))


func emit_burst(world_pos: Vector3, col: Color, count: int = 14) -> void:
	_setup_meshes()
	if _burst_data.is_empty():
		reset_particles(_radius / 0.88)
	var actual := mini(count, BURST_COUNT)
	for i in range(actual):
		var idx := _burst_cursor
		_burst_cursor = (_burst_cursor + 1) % BURST_COUNT
		var ang := (float(i) / float(maxi(1, actual))) * TAU + float(idx) * 0.31
		var spd := 12.0 + 14.0 * fmod(float(idx) * 0.618, 1.0)
		_burst_data[idx] = {
			"pos": world_pos,
			"vel": Vector3(cos(ang) * spd, 8.0 + 12.0 * fmod(float(i) * 0.37, 1.0), sin(ang) * spd),
			"life": 0.48,
			"max_life": 0.48,
			"col": col,
		}


func update_particles(
	player_y: float,
	delta: float,
	speed: float,
	boost_level: float,
	flow_locked: bool,
	palette: Array[Color]
) -> void:
	_setup_meshes()
	if _stream_data.is_empty():
		reset_particles()

	var smm := _stream_mm_inst.multimesh
	var c_norm := palette[0].lerp(Color.WHITE, 0.72) if not palette.is_empty() else Color(0.95, 0.97, 1.0)
	var c_boost := Color("ff9f1c") if boost_level > 0.25 else (Color("ff3b5c") if flow_locked else c_norm)
	var streak_len := clampf(2.2 + (speed * 0.065) * (1.0 + boost_level * 1.45), 2.0, 14.0)
	var streak_thick := lerpf(0.022, 0.048, boost_level)

	for i in range(STREAM_COUNT):
		var d: Dictionary = _stream_data[i]
		d["y"] = float(d["y"]) + delta * speed * float(d["spd"]) * (0.48 + boost_level * 0.75)
		if float(d["y"]) > player_y + 3.0:
			d["y"] = player_y - (105.0 + 35.0 * fmod(float(i) * 0.47, 1.0))
		elif float(d["y"]) < player_y - 145.0:
			d["y"] = player_y - (4.0 + 130.0 * (float(i) / float(STREAM_COUNT)))

		var rad := maxf(8.4, _radius * float(d["r_frac"]))
		var ang := float(d["ang"])
		var pos := Vector3(cos(ang) * rad, float(d["y"]), sin(ang) * rad)
		var xform := Transform3D(Basis.IDENTITY.scaled_local(Vector3(streak_thick, streak_len, streak_thick)), pos)
		smm.set_instance_transform(i, xform)

		var dist_rel := maxf(0.0, player_y - pos.y)
		var alpha := smoothstep_val(135.0, 20.0, dist_rel) * (0.14 + 0.24 * boost_level)
		var tint := c_norm.lerp(c_boost, clampf(boost_level + (0.25 if (i & 1) == 1 else 0.0), 0.0, 1.0))
		tint.a = clampf(alpha, 0.03, 0.38)
		smm.set_instance_color(i, tint)

	var bmm := _burst_mm_inst.multimesh
	for i in range(BURST_COUNT):
		var bd: Dictionary = _burst_data[i]
		var life := float(bd["life"])
		if life <= 0.0:
			bmm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled_local(Vector3.ZERO), Vector3(0.0, player_y + 40.0, 0.0)))
			bmm.set_instance_color(i, Color(1, 1, 1, 0))
			continue
		life -= delta
		bd["life"] = life
		var vel := bd["vel"] as Vector3
		var pos := (bd["pos"] as Vector3) + vel * delta
		bd["pos"] = pos
		var ratio := clampf(life / float(bd["max_life"]), 0.0, 1.0)
		var sc := Vector3(0.14, 0.35 + ratio * 0.45, 0.14) * ratio
		bmm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled_local(sc), pos))
		var col := bd["col"] as Color
		col.a = ratio * 0.95
		bmm.set_instance_color(i, col)


static func smoothstep_val(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
