class_name LevelPreviewViewport
extends SubViewportContainer
## Self-contained SubViewport rendering live animated 3D level previews with an
## isolated simulation clock (preventing animation-clock carryover across browser previews).

var sub_viewport: SubViewport
var tunnel_renderer: TunnelRenderer
var obstacle_manager: ObstacleManager
var camera: Camera3D

var preview_stage: StageData = null
var preview_time: float = 0.0
var preview_depth: float = 20.0
var auto_scroll: bool = true


func _ready() -> void:
	stretch = true
	_ensure_world()


func _ensure_world() -> void:
	if sub_viewport != null:
		return
	sub_viewport = SubViewport.new()
	sub_viewport.own_world_3d = true
	sub_viewport.size = Vector2i(520, 320)
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sub_viewport)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	TunnelRenderer.apply_cinema_environment(env, Color("070410"))
	we.environment = env
	sub_viewport.add_child(we)

	tunnel_renderer = TunnelRenderer.new()
	sub_viewport.add_child(tunnel_renderer)

	obstacle_manager = ObstacleManager.new()
	sub_viewport.add_child(obstacle_manager)

	camera = Camera3D.new()
	camera.near = 0.2
	camera.far = 220.0
	camera.fov = 80.0
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	sub_viewport.add_child(camera)


func set_stage(st: StageData) -> void:
	_ensure_world()
	preview_stage = st.duplicate_stage() if st != null else null
	# Reset isolated preview clock every time a new stage is previewed (prevents clock freeze/carryover)
	preview_time = 0.0
	preview_depth = 15.0
	if preview_stage != null:
		tunnel_renderer.reset_tunnel(preview_stage.tunnel_radius)
		obstacle_manager.reset_with_stage(preview_stage)
		step_preview(0.0)


func step_preview(delta: float) -> void:
	_ensure_world()
	if preview_stage == null:
		return
	preview_time += delta
	if auto_scroll and delta > 0.0:
		preview_depth = fmod(preview_depth + delta * 18.0, maxf(60.0, preview_stage.total_length() - 30.0))

	var player_y := -preview_depth
	camera.position = Vector3(0.0, player_y, 0.0)
	var mask := EffectCatalog.clamp_safe_mask(
		preview_stage.effect_mask_at_depth(preview_depth),
		SettingsManager.safe_photosensitivity_mode
	)
	var beat_ph := fmod(preview_time * (preview_stage.bpm / 60.0), 1.0)
	tunnel_renderer.update_tunnel(
		player_y,
		preview_time,
		mask,
		beat_ph,
		0.45,
		0.0,
		preview_stage.palette,
		preview_stage.tunnel_radius
	)
	obstacle_manager.step_and_sync(player_y, delta, beat_ph, 0.45, false)


func _process(delta: float) -> void:
	if visible and preview_stage != null:
		step_preview(delta)
