extends Node
## Choreographed 60.0-second (3,600 frames @ 60 FPS) live gameplay capture director
## for Godot Movie-Maker (`--write-movie ... --fixed-fps 60`).

const TOTAL_FRAMES := 3600

var _frame: int = 0
var _gs: GameSession = null
var _ed: LevelEditor = null
var _beat_stage: int = -1
var _cold_parried: bool = false
var _dead_retried: bool = false


func _ready() -> void:
	# Silence engine playback during Movie-Maker export so studio stereo audio lays cleanly over frame-exact footage
	AudioSyncManager.stop_music()
	var master_idx := AudioServer.get_bus_index(&"Master")
	if master_idx >= 0:
		AudioServer.set_bus_mute(master_idx, true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_enter_beat(0)


func _process(_delta: float) -> void:
	if _frame >= TOTAL_FRAMES:
		get_tree().quit(0)
		return

	var t_sec := float(_frame) / 60.0
	_update_beat_transitions(t_sec)
	_steer_active_shot(t_sec)
	_frame += 1


func _update_beat_transitions(t: float) -> void:
	var target_stage := 0
	if t >= 53.0:
		target_stage = 8
	elif t >= 49.5:
		target_stage = 7
	elif t >= 46.0:
		target_stage = 6
	elif t >= 43.0:
		target_stage = 5
	elif t >= 40.0:
		target_stage = 4
	elif t >= 37.0:
		target_stage = 3
	elif t >= 34.0:
		target_stage = 2
	elif t >= 22.0:
		target_stage = 1
	elif t >= 16.0:
		target_stage = 10
	elif t >= 10.0:
		target_stage = 9
	elif t >= 4.0:
		target_stage = 11

	if target_stage == _beat_stage:
		return
	_beat_stage = target_stage
	_enter_beat(target_stage)


func _enter_beat(stage_code: int) -> void:
	match stage_code:
		0:
			# 0:00-0:04 Cold-Open Hook: Terminal velocity Boost -> Phase Parry
			_ensure_game_session()
			_gs.start_session({"stage_id": "06_c", "mode": ScoringManager.MODE_NORMAL, "start_depth": 52.0})
			_gs.boost_override = 1
			_gs.spawn_grace_timer = 0.0
			_set_hud_visible(true)
			_cold_parried = false

		11:
			# 0:04-0:10 Clean Title Drop tunnel dive
			_ensure_game_session()
			_gs.start_session({"stage_id": "01_a", "mode": ScoringManager.MODE_ZEN, "start_depth": 0.0})
			_gs.boost_override = 0
			_set_hud_visible(false)

		9:
			# 0:10-0:16 Core loop 1: Dodge, collect Rings, Graze
			_ensure_game_session()
			_gs.start_session({"stage_id": "01_b", "mode": ScoringManager.MODE_NORMAL, "start_depth": 0.0})
			_gs.boost_override = 0
			_set_hud_visible(true)

		10:
			# 0:16-0:22 Core loop 2: Corkscrew twist & chains
			_ensure_game_session()
			_gs.start_session({"stage_id": "02_a", "mode": ScoringManager.MODE_NORMAL, "start_depth": 0.0})
			_gs.boost_override = 0
			_set_hud_visible(true)

		1:
			# 0:22-0:34 Hyper-Boost + Phase Dash -> Overdrive Color Lock
			_ensure_game_session()
			_gs.start_session({"stage_id": "03_c", "mode": ScoringManager.MODE_NORMAL, "start_depth": 0.0})
			_gs.boost_override = 1
			_gs.scoring.flow_meter = 0.68
			_set_hud_visible(true)

		2:
			# 0:34-0:37 Escalation cut 1: Level 4 Peristalsis
			_ensure_game_session()
			_gs.start_session({"stage_id": "04_c", "mode": ScoringManager.MODE_ZEN, "start_depth": 110.0})
			_gs.boost_override = 1
			_gs.scoring.flow_meter = 0.85
			_set_hud_visible(true)

		3:
			# 0:37-0:40 Escalation cut 2: Level 5 Flashpoint
			_ensure_game_session()
			_gs.start_session({"stage_id": "05_c", "mode": ScoringManager.MODE_ZEN, "start_depth": 120.0})
			_gs.boost_override = 1
			_gs.scoring.flow_meter = 0.90
			_set_hud_visible(true)

		4:
			# 0:40-0:43 Escalation cut 3: Level 6 Kaleidoscope Overdrive
			_ensure_game_session()
			_gs.start_session({"stage_id": "06_c", "mode": ScoringManager.MODE_ZEN, "start_depth": 180.0})
			_gs.boost_override = 1
			_gs.scoring.flow_meter = 1.0
			_set_hud_visible(true)

		5:
			# 0:43-0:46 Escalation cut 4: Level 7 All Hallows' Pendulum & Ghost
			_ensure_game_session()
			_gs.start_session({"stage_id": "07_c", "mode": ScoringManager.MODE_ZEN, "start_depth": 95.0})
			_gs.boost_override = 1
			_set_hud_visible(true)

		6:
			# 0:46-0:49.5 Live 3D Level Editor Showcase
			_free_session()
			var ed_scene := load("res://scenes/level_editor.tscn") as PackedScene
			_ed = ed_scene.instantiate() as LevelEditor
			add_child(_ed)
			_ed.create_new_stage()
			_ed.working_stage.title = "Trailer Custom Drop"
			_ed.add_obstacle("waffle", 30.0)
			_ed.add_obstacle("pendulum", 52.0)
			_ed.add_obstacle("tumbling_cube", 74.0)
			_ed.add_obstacle("guillotine", 96.0)
			_ed.toggle_effect_bit(0, true)
			_ed.toggle_effect_bit(1, true)
			_ed.toggle_effect_bit(6, true)
			_ed.toggle_effect_bit(12, true)
			_ed.camera_depth = 4.0
			_ed._refresh_all_ui()

		7:
			# 0:49.5-0:53.0 Crimson Impact Freeze + <0.1s Instant Retry
			_free_editor()
			_ensure_game_session()
			_gs.start_session({"stage_id": "01_a", "mode": ScoringManager.MODE_NORMAL, "start_depth": 58.0})
			_gs.boost_override = 1
			_gs.spawn_grace_timer = 0.0
			_dead_retried = false
			_set_hud_visible(true)

		8:
			# 0:53.0-1:00.0 Climax Speed Vortex CTA Backdrop
			_ensure_game_session()
			_gs.start_session({"stage_id": "06_c", "mode": ScoringManager.MODE_ZEN, "start_depth": 180.0})
			_gs.boost_override = 1
			_gs.scoring.flow_meter = 1.0
			_gs.scoring.color_locked = true
			_set_hud_visible(false)


func _steer_active_shot(t: float) -> void:
	if _beat_stage == 6 and is_instance_valid(_ed):
		_ed.camera_depth += 0.16
		return

	if not is_instance_valid(_gs) or _gs.player == null:
		return

	var depth_m := maxf(0.0, -_gs.player.position_3d.y)
	match _beat_stage:
		0:
			# Cold-open: steer into upcoming obstacle then fire live Phase Parry right before collision!
			var near_obs := _find_next_obstacle(depth_m, 14.0)
			if near_obs != null and not _cold_parried and (near_obs.depth - depth_m) < 9.5:
				_cold_parried = _gs.trigger_phase_blink(Vector2(0.85, 0.25))
			elif _cold_parried and _gs.player.phase_invuln_timer <= 0.05:
				# Switch to Zen indestructibility after landing the opening parry so the hook finishes mid-flight cleanly
				_gs.scoring.mode = ScoringManager.MODE_ZEN

		11:
			# Title Dive: engage boost halfway and sweep smoothly down corridor
			_gs.boost_override = 1 if t >= 6.2 else 0
			_guide_player_xz(Vector2(sin(t * 2.1) * 2.6, cos(t * 1.7) * 2.6), 4.0)

		9, 10, 1:
			# Core Loop & Overdrive: intelligently thread Energy Rings + Phase Parry any close barrier!
			var target_xz := Vector2(sin(t * 1.4) * 3.0, cos(t * 1.1) * 3.0)
			for ring in _gs.ring_manager.get_rings():
				if bool(ring["collected"]):
					continue
				var diff := float(ring["depth"]) - depth_m
				if diff >= 1.5 and diff <= 38.0:
					target_xz = ring["xz"] as Vector2
					break
			_guide_player_xz(target_xz, 6.5)
			_auto_parry_if_imminent()

		7:
			# Beat 6b: hold center until death triggers at cross_bars (~86.6m), show DeathOverlay briefly, then Retry!
			if _gs.state == GameSession.SessionState.DEAD and not _dead_retried and t >= 51.35:
				_dead_retried = true
				_gs.retry_run()
				_gs.boost_override = 1
			elif _dead_retried:
				_guide_player_xz(Vector2(2.4, -1.6), 5.0)
				_gs.scoring.mode = ScoringManager.MODE_ZEN

		2, 3, 4, 5, 8:
			_guide_player_xz(Vector2(sin(t * 2.2) * 3.2, cos(t * 1.8) * 3.2), 5.0)


func _guide_player_xz(target_xz: Vector2, gain: float) -> void:
	var curr := Vector2(_gs.player.position_3d.x, _gs.player.position_3d.z)
	var desired_v := (target_xz - curr) * gain
	if desired_v.length() > PlayerController.KEY_MAX_SPEED:
		desired_v = desired_v.normalized() * PlayerController.KEY_MAX_SPEED
	_gs.player.velocity_xz = desired_v


func _find_next_obstacle(depth_m: float, horizon_m: float) -> ObstacleData:
	var best: ObstacleData = null
	var best_d := horizon_m
	for ent in _gs.obstacle_manager.get_active_obstacles():
		var obs := ent["obstacle"] as ObstacleData
		var diff := obs.depth - depth_m
		if diff > 0.5 and diff < best_d:
			best_d = diff
			best = obs
	return best


func _auto_parry_if_imminent() -> void:
	if _gs.state != GameSession.SessionState.PLAYING or _gs.in_autopilot:
		return
	var p := _gs.player.position_3d
	var probe_end := p + Vector3(0.0, -9.5, 0.0)
	for ent in _gs.obstacle_manager.get_active_obstacles():
		var obs := ent["obstacle"] as ObstacleData
		var parts := ent["parts"] as Array[Dictionary]
		if obs.depth < (-p.y - 2.0) or obs.depth > (-probe_end.y + 4.0):
			continue
		var eval := SweptCollision.evaluate_obstacle(p, probe_end, parts, 0.55)
		if bool(eval["hit"]):
			if not _gs.trigger_phase_blink():
				_gs.player.refresh_phase_cooldown()
				_gs.trigger_phase_blink()
			break


func _ensure_game_session() -> void:
	if is_instance_valid(_gs):
		return
	var gs_scene := load("res://scenes/game_session.tscn") as PackedScene
	_gs = gs_scene.instantiate() as GameSession
	_gs.suppress_stage_clear = true
	add_child(_gs)


func _free_session() -> void:
	if is_instance_valid(_gs):
		_gs.queue_free()
		_gs = null


func _free_editor() -> void:
	if is_instance_valid(_ed):
		_ed.queue_free()
		_ed = null


func _set_hud_visible(vis: bool) -> void:
	if is_instance_valid(_gs) and _gs.hud_overlay != null and _gs.hud_overlay.get_child_count() > 0:
		var root_ctrl := _gs.hud_overlay.get_child(0) as Control
		if root_ctrl != null:
			root_ctrl.visible = vis
