class_name ReplayController
extends Node3D
## Records 60 Hz run replays, renders 3D personal-best Ghost Markers in the tunnel,
## submits ranked runs to LevelRepository, and drives live WATCH playback.

var active_recording: ReplayData = null
var active_watch: ReplayData = null
var is_watching: bool = false
var watch_paused: bool = false
var watch_elapsed: float = 0.0
var watch_speed_mult: float = 1.0
var last_saved_replay_id: String = ""

var _ghost_root: Node3D


func start_recording(stage: StageData, mode: String) -> void:
	is_watching = false
	watch_paused = false
	active_watch = null
	last_saved_replay_id = ""

	active_recording = ReplayData.new()
	active_recording.replay_id = "rep_%s_%d" % [stage.id, Time.get_ticks_usec()]
	active_recording.stage_id = stage.id
	active_recording.mode = mode
	active_recording.player_name = "Pilot"
	active_recording.tick_hz = 60

	_spawn_ghost_markers(stage.id)
	GameEvents.replay_state_changed.emit(false, false, 0.0, 1.0)


func record_frame(y_pos: float, x_pos: float, z_pos: float, roll_rad: float) -> void:
	if active_recording == null or is_watching:
		return
	active_recording.add_frame(y_pos, x_pos, z_pos, roll_rad)


func record_event(kind: String, value: float = 0.0) -> void:
	if active_recording == null or is_watching:
		return
	active_recording.add_event(kind, value)


func finish_and_submit(stage: StageData, summary: Dictionary, cleared: bool) -> String:
	if active_recording == null or is_watching:
		return ""
	active_recording.score = int(summary.get("score", 0))
	active_recording.max_chain = float(summary.get("max_chain", 1.0))
	active_recording.duration_sec = float(summary.get("duration_sec", 0.0))
	active_recording.cleared = cleared

	if active_recording.frames.is_empty():
		return ""

	var save_res := LevelRepository.save_replay(active_recording)
	if bool(save_res["ok"]):
		last_saved_replay_id = active_recording.replay_id
		LevelRepository.submit_leaderboard_entry(
			stage.id,
			active_recording.player_name,
			active_recording.score,
			active_recording.max_chain,
			active_recording.duration_sec,
			active_recording.replay_id
		)
		return last_saved_replay_id
	return ""


func start_watch(replay: ReplayData) -> void:
	_clear_ghost_markers()
	active_recording = null
	active_watch = replay
	is_watching = replay != null
	watch_paused = false
	watch_elapsed = 0.0
	watch_speed_mult = 1.0
	GameEvents.replay_state_changed.emit(is_watching, watch_paused, 0.0, watch_speed_mult)


func step_watch(delta: float) -> Dictionary:
	if not is_watching or active_watch == null:
		return {"pos": Vector3.ZERO, "roll": 0.0, "finished": true, "progress": 1.0}
	if not watch_paused:
		watch_elapsed += delta * watch_speed_mult
	var sample := active_watch.sample_at_time(watch_elapsed)
	GameEvents.replay_state_changed.emit(true, watch_paused, float(sample["progress"]), watch_speed_mult)
	return sample


func toggle_watch_pause() -> void:
	if not is_watching:
		return
	watch_paused = not watch_paused
	GameEvents.replay_state_changed.emit(true, watch_paused, 0.0, watch_speed_mult)


func cycle_watch_speed() -> float:
	watch_speed_mult = 2.0 if watch_speed_mult < 1.5 else (0.5 if watch_speed_mult > 1.5 else 1.0)
	GameEvents.replay_state_changed.emit(true, watch_paused, 0.0, watch_speed_mult)
	return watch_speed_mult


func _spawn_ghost_markers(stage_id: String) -> void:
	_clear_ghost_markers()
	var ghosts := SaveManager.get_ghost_markers(stage_id)
	if ghosts.is_empty():
		return
	_ghost_root = Node3D.new()
	_ghost_root.name = "GhostMarkers"
	add_child(_ghost_root)

	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.80

	for g in ghosts:
		var mi := MeshInstance3D.new()
		mi.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var is_clear := str(g.get("kind", "death")) == "clear"
		mat.albedo_color = Color(0.15, 1.0, 0.72, 0.45) if is_clear else Color(1.0, 0.32, 0.65, 0.45)
		mi.material_override = mat
		mi.position = Vector3(float(g.get("x", 0.0)), -float(g.get("depth", 0.0)), float(g.get("z", 0.0)))
		_ghost_root.add_child(mi)


func _clear_ghost_markers() -> void:
	if is_instance_valid(_ghost_root):
		_ghost_root.queue_free()
	_ghost_root = null
