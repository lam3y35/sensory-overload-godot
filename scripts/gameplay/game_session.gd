class_name GameSession
extends Node3D
## Top-level 3D gameplay orchestrator coordinating Normal, Ranked, Zen, Practice,
## WATCH Replay, and Editor Play-From-Here runs with decoupled 120 Hz logic sub-stepping,
## once-per-frame GPU sync, Hyper-Boost, Phase Dash/Parry, Energy Rings, and 3D Speed Particles.

const DEATH_FREEZE_DURATION := 0.35
const PRACTICE_GRACE_DURATION := 0.85
const LIVE_PLAYER_RADIUS := 0.27

enum SessionState {
	IDLE,
	PLAYING,
	IMPACT_FREEZE,
	DEAD,
	PAUSED,
	CLEARED,
}

static var pending_launch: Dictionary = {}

var state: int = SessionState.IDLE
var stage: StageData
var scoring: ScoringManager = ScoringManager.new()

var tunnel_renderer: TunnelRenderer
var obstacle_manager: ObstacleManager
var ring_manager: RingManager
var speed_particles: SpeedParticles
var player: PlayerController
var world_env: WorldEnvironment

var effect_compositor: Node = null
var replay_controller: Node = null
var hud_overlay: Node = null
var death_overlay: Node = null
var pause_overlay: Node = null

var launch_params: Dictionary = {}
var elapsed_time: float = 0.0
var current_speed: float = 40.0
var current_section_index: int = -1
var current_effect_mask: int = 0
var ranked_lap: int = 0
var freeze_timer: float = 0.0
var spawn_grace_timer: float = 0.0
var in_autopilot: bool = false
var boost_level: float = 0.0
var boost_override: int = -1 # -1 = read input, 0 = force off, 1 = force on
var suppress_stage_clear: bool = false
var flash_strength: float = 0.0
var flash_color: Color = Color("14f1d9")

var _hitstop_timer: float = 0.0
var _milestone_chain_tier: int = 0
var _was_boosting: bool = false
var _was_flow_locked: bool = false
var _passed_obstacles: Dictionary = {}
var _parried_ids: Dictionary = {}
var _last_impact_obs_id: String = ""
var _last_impact_obs_type: String = ""
var _last_impact_point: Vector3 = Vector3.ZERO
var _freeze_cam_pos: Vector3 = Vector3.ZERO
var _last_death_summary: Dictionary = {}
var _active_replay: ReplayData = null
var _return_to_editor: bool = false
var _start_depth: float = 0.0


static func set_launch_context(params: Dictionary) -> void:
	pending_launch = params.duplicate(true)


func _ready() -> void:
	_build_3d_environment()
	_attach_optional_subsystems()
	if not pending_launch.is_empty():
		var params := pending_launch.duplicate(true)
		pending_launch.clear()
		start_session(params)
	elif get_tree().current_scene == self:
		start_session({"stage_id": "01_a", "mode": ScoringManager.MODE_NORMAL})


func _build_3d_environment() -> void:
	if world_env == null:
		world_env = WorldEnvironment.new()
		var env := Environment.new()
		TunnelRenderer.apply_cinema_environment(env, Color("070410"))
		world_env.environment = env
		add_child(world_env)

	if tunnel_renderer == null:
		tunnel_renderer = TunnelRenderer.new()
		add_child(tunnel_renderer)

	if obstacle_manager == null:
		obstacle_manager = ObstacleManager.new()
		add_child(obstacle_manager)

	if ring_manager == null:
		ring_manager = RingManager.new()
		add_child(ring_manager)

	if speed_particles == null:
		speed_particles = SpeedParticles.new()
		add_child(speed_particles)

	if player == null:
		player = PlayerController.new()
		add_child(player)


func _attach_optional_subsystems() -> void:
	if effect_compositor == null and ResourceLoader.exists("res://scripts/gameplay/effect_compositor.gd"):
		var ec_script := load("res://scripts/gameplay/effect_compositor.gd") as GDScript
		if ec_script != null:
			effect_compositor = ec_script.new()
			add_child(effect_compositor)

	if replay_controller == null and ResourceLoader.exists("res://scripts/gameplay/replay_controller.gd"):
		var rc_script := load("res://scripts/gameplay/replay_controller.gd") as GDScript
		if rc_script != null:
			replay_controller = rc_script.new()
			add_child(replay_controller)

	if hud_overlay == null and ResourceLoader.exists("res://scripts/ui/game_hud.gd"):
		var hud_script := load("res://scripts/ui/game_hud.gd") as GDScript
		if hud_script != null:
			hud_overlay = hud_script.new()
			add_child(hud_overlay)

	if death_overlay == null and ResourceLoader.exists("res://scripts/ui/death_overlay.gd"):
		var do_script := load("res://scripts/ui/death_overlay.gd") as GDScript
		if do_script != null:
			death_overlay = do_script.new()
			add_child(death_overlay)

	if pause_overlay == null and ResourceLoader.exists("res://scripts/ui/pause_menu.gd"):
		var po_script := load("res://scripts/ui/pause_menu.gd") as GDScript
		if po_script != null:
			pause_overlay = po_script.new()
			add_child(pause_overlay)


func start_session(params: Dictionary, keep_practice_checkpoint: bool = false) -> void:
	_build_3d_environment()
	launch_params = params.duplicate(true)

	var raw_stage: Variant = params.get("stage_data", null)
	if raw_stage is StageData:
		stage = (raw_stage as StageData).duplicate_stage()
	else:
		var sid := str(params.get("stage_id", "01_a"))
		stage = LevelRepository.get_stage_by_id(sid)
		if stage == null:
			stage = LevelRepository.get_campaign_stages()[0].duplicate_stage()

	if world_env != null and world_env.environment != null and stage.palette.size() > 2:
		TunnelRenderer.apply_cinema_environment(world_env.environment, stage.palette[2])

	var run_mode := str(params.get("mode", ScoringManager.MODE_NORMAL))
	_return_to_editor = bool(params.get("return_to_editor", false))
	_start_depth = maxf(0.0, float(params.get("start_depth", 0.0)))
	_active_replay = params.get("replay_data", null) as ReplayData

	scoring.begin_run(run_mode, stage, keep_practice_checkpoint)
	elapsed_time = 0.0
	current_speed = stage.base_speed
	ranked_lap = 0
	freeze_timer = 0.0
	_hitstop_timer = 0.0
	_milestone_chain_tier = 0
	in_autopilot = false
	current_section_index = -1
	boost_level = 0.0
	flash_strength = 0.0
	_was_boosting = false
	_was_flow_locked = false
	_passed_obstacles.clear()
	_parried_ids.clear()

	var spawn_depth := _start_depth
	var spawn_xz := Vector2.ZERO
	if keep_practice_checkpoint and run_mode == ScoringManager.MODE_PRACTICE and scoring.practice_checkpoint_active:
		spawn_depth = scoring.practice_checkpoint_depth
		spawn_xz = scoring.practice_checkpoint_xz
		spawn_grace_timer = PRACTICE_GRACE_DURATION
	else:
		spawn_grace_timer = 0.45 if _start_depth > 1.0 else 0.15

	player.reset_at(spawn_depth, spawn_xz)
	tunnel_renderer.reset_tunnel(stage.tunnel_radius)
	obstacle_manager.reset_with_stage(stage)
	ring_manager.reset_with_stage(stage)
	speed_particles.reset_particles(stage.tunnel_radius)

	if run_mode == ScoringManager.MODE_NORMAL or run_mode == ScoringManager.MODE_RANKED:
		SaveManager.record_attempt(stage.id)

	var track_to_play := stage.track_index
	if SettingsManager.random_track and not keep_practice_checkpoint:
		AudioSyncManager.select_random_track()
	else:
		AudioSyncManager.start_track(track_to_play, stage.bpm, not keep_practice_checkpoint)

	if replay_controller != null:
		if run_mode == ScoringManager.MODE_WATCH and _active_replay != null:
			replay_controller.start_watch(_active_replay)
		else:
			replay_controller.start_recording(stage, run_mode)

	_sync_section_and_effects(spawn_depth)
	obstacle_manager.step_logic(player.position_3d.y, 0.0, AudioSyncManager.beat_phase)

	if hud_overlay != null and hud_overlay.has_method("configure_session"):
		hud_overlay.configure_session(self)
	if death_overlay != null and death_overlay.has_method("hide_overlay"):
		death_overlay.hide_overlay()
	if pause_overlay != null and pause_overlay.has_method("hide_pause"):
		pause_overlay.hide_pause()

	state = SessionState.PLAYING
	_set_mouse_captured(true)
	sync_visual_frame(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if state == SessionState.IDLE:
		return
	var is_accept_key := false
	if event is InputEventKey:
		var kev := event as InputEventKey
		if kev.pressed and not kev.echo and (kev.keycode == KEY_SPACE or kev.keycode == KEY_ENTER or kev.keycode == KEY_KP_ENTER):
			is_accept_key = true

	if event.is_action_pressed("pause"):
		if state == SessionState.PLAYING:
			pause_game()
		elif state == SessionState.PAUSED:
			resume_game()
		elif scoring.mode == ScoringManager.MODE_WATCH:
			exit_to_menu()
	elif event.is_action_pressed("phase_dash") and state == SessionState.PLAYING:
		if not in_autopilot and scoring.mode != ScoringManager.MODE_WATCH:
			trigger_phase_blink()
	elif event.is_action_pressed("retry") or (is_accept_key and state == SessionState.DEAD):
		if state == SessionState.PLAYING or state == SessionState.DEAD or state == SessionState.CLEARED:
			retry_run()
	elif is_accept_key and state == SessionState.CLEARED:
		if not next_stage():
			retry_run()
	elif event.is_action_pressed("place_checkpoint") and state == SessionState.PLAYING:
		if scoring.mode == ScoringManager.MODE_PRACTICE:
			scoring.set_checkpoint(-player.position_3d.y, Vector2(player.position_3d.x, player.position_3d.z))
			AudioSyncManager.play_sfx("checkpoint")
	elif event.is_action_pressed("clear_checkpoint") and state == SessionState.PLAYING:
		if scoring.mode == ScoringManager.MODE_PRACTICE:
			scoring.clear_checkpoint()


func trigger_phase_blink(dir_override: Vector2 = Vector2.ZERO) -> bool:
	if state != SessionState.PLAYING:
		return false
	if player.trigger_phase_dash(dir_override):
		AudioSyncManager.play_sfx("phase_dash")
		flash_color = Color("14f1d9")
		flash_strength = maxf(flash_strength, 0.42)
		speed_particles.emit_burst(player.position_3d + Vector3(0.0, -3.0, 0.0), Color("14f1d9"), 12)
		GameEvents.phase_dash_used.emit(false, player.get_phase_ready_ratio())
		return true
	return false


func _process(delta: float) -> void:
	# Decoupled fixed sub-stepping (logic up to 120 Hz) paired with ONCE-per-frame GPU sync!
	var clamped_dt := minf(delta, 0.05)
	var remaining := clamped_dt
	var steps := 0
	while remaining > 0.0001 and steps < 8:
		var dt := minf(remaining, 1.0 / 120.0)
		step_simulation(dt, false)
		remaining -= dt
		steps += 1
	if stage != null and (state == SessionState.PLAYING or state == SessionState.IMPACT_FREEZE):
		sync_visual_frame(clamped_dt)


func step_simulation(delta: float, sync_visuals: bool = true) -> void:
	flash_strength = maxf(0.0, flash_strength - delta * 2.6)

	if state == SessionState.IMPACT_FREEZE:
		freeze_timer -= delta
		var shake_amp := clampf(freeze_timer / DEATH_FREEZE_DURATION, 0.0, 1.0) * 0.24
		var shake_pos := _freeze_cam_pos + Vector3(
			sin(freeze_timer * 68.0) * shake_amp,
			0.0,
			cos(freeze_timer * 79.0) * shake_amp
		)
		player.set_replay_pose(shake_pos, player.current_roll)
		obstacle_manager.step_logic(player.position_3d.y, 0.0, AudioSyncManager.beat_phase)
		if sync_visuals:
			sync_visual_frame(delta)
		if freeze_timer <= 0.0:
			_finalize_death()
		return

	if state != SessionState.PLAYING:
		return

	if _hitstop_timer > 0.0:
		_hitstop_timer -= delta
		player.update_camera_effects(delta, current_effect_mask, current_speed, AudioSyncManager.bass_energy, boost_level)
		if sync_visuals:
			sync_visual_frame(delta)
		return

	elapsed_time += delta
	spawn_grace_timer = maxf(0.0, spawn_grace_timer - delta)

	if scoring.mode == ScoringManager.MODE_WATCH and replay_controller != null:
		_step_watch_mode(delta, sync_visuals)
		return

	var depth_m := maxf(0.0, -player.position_3d.y)
	in_autopilot = _is_in_transition_zone(depth_m)

	var want_boost := false
	if not in_autopilot and scoring.mode != ScoringManager.MODE_WATCH:
		if boost_override >= 0:
			want_boost = (boost_override > 0)
		elif DisplayServer.get_name() != "headless":
			want_boost = Input.is_action_pressed("boost")

	if want_boost and not _was_boosting:
		AudioSyncManager.play_sfx("boost_on")
		player.add_fov_punch(4.5)
	_was_boosting = want_boost
	boost_level = move_toward(boost_level, 1.0 if want_boost else 0.0, delta * (6.5 if want_boost else 4.5))
	GameEvents.boost_changed.emit(want_boost, boost_level)

	if want_boost and not in_autopilot:
		scoring.boost_time += delta
		scoring.flow_meter = minf(1.0, scoring.flow_meter + delta * 0.075)

	var target_speed := scoring.compute_active_speed(stage, depth_m, ranked_lap, want_boost)
	current_speed = lerpf(current_speed, target_speed, clampf(delta * 14.0, 0.0, 1.0))

	var step_res := player.apply_input_and_step(delta, current_speed, in_autopilot, Vector2.ZERO)
	var p0 := step_res["prev_pos"] as Vector3
	var p1 := step_res["curr_pos"] as Vector3
	var new_depth := maxf(0.0, -p1.y)

	scoring.add_descent_distance_score(maxf(0.0, new_depth - depth_m), want_boost)
	scoring.step(delta, false, in_autopilot)

	_sync_section_and_effects(new_depth)
	obstacle_manager.step_logic(p1.y, delta, AudioSyncManager.beat_phase)
	player.update_camera_effects(delta, current_effect_mask, current_speed, AudioSyncManager.bass_energy, boost_level)

	if replay_controller != null:
		replay_controller.record_frame(p1.y, p1.x, p1.z, player.current_roll)

	_evaluate_rings(p0, p1)
	_evaluate_collisions(p0, p1)
	_check_flow_lock_and_milestones()

	if sync_visuals:
		sync_visual_frame(delta)

	if state == SessionState.PLAYING and not suppress_stage_clear and new_depth >= stage.total_length():
		_handle_stage_end()


func sync_visual_frame(delta: float) -> void:
	if stage == null:
		return
	var p_speed := 6.0 if state == SessionState.IMPACT_FREEZE else current_speed
	var p_boost := 0.0 if state == SessionState.IMPACT_FREEZE else boost_level
	tunnel_renderer.update_tunnel(
		player.position_3d.y,
		elapsed_time,
		current_effect_mask,
		AudioSyncManager.beat_phase,
		AudioSyncManager.bass_energy,
		scoring.flow_meter,
		stage.palette,
		stage.tunnel_radius
	)
	obstacle_manager.sync_visuals(AudioSyncManager.beat_phase, AudioSyncManager.bass_energy, scoring.color_locked)
	ring_manager.step_and_sync(player.position_3d.y, delta, AudioSyncManager.beat_phase)
	speed_particles.update_particles(player.position_3d.y, delta, p_speed, p_boost, scoring.color_locked, stage.palette)
	if effect_compositor != null and effect_compositor.has_method("apply_effects"):
		effect_compositor.apply_effects(
			current_effect_mask,
			elapsed_time,
			current_speed,
			AudioSyncManager.beat_phase,
			AudioSyncManager.bass_energy,
			scoring.flow_meter,
			p_boost,
			flash_strength,
			flash_color
		)


func _step_watch_mode(delta: float, sync_visuals: bool) -> void:
	var pose: Dictionary = replay_controller.step_watch(delta)
	var pos := pose.get("pos", Vector3.ZERO) as Vector3
	var roll := float(pose.get("roll", 0.0))
	player.set_replay_pose(pos, roll)
	var depth_m := maxf(0.0, -pos.y)
	_sync_section_and_effects(depth_m)
	obstacle_manager.step_logic(pos.y, delta, AudioSyncManager.beat_phase)
	if sync_visuals:
		sync_visual_frame(delta)
	if bool(pose.get("finished", false)):
		state = SessionState.CLEARED
		_set_mouse_captured(false)


func _evaluate_rings(p0: Vector3, p1: Vector3) -> void:
	if in_autopilot:
		return
	var r_eval := ring_manager.check_collect(p0, p1)
	if not bool(r_eval["collected"]):
		return
	scoring.register_ring(str(r_eval["id"]), in_autopilot)
	player.refresh_phase_cooldown()
	var pitch := 1.0 + minf(0.55, float(scoring.streak) * 0.035)
	AudioSyncManager.play_sfx("ring", pitch)
	speed_particles.emit_burst(r_eval["pos"] as Vector3, Color("facc15"), 18)
	player.add_fov_punch(3.4)
	flash_color = Color("facc15")
	flash_strength = maxf(flash_strength, 0.55)


func _evaluate_collisions(p0: Vector3, p1: Vector3) -> void:
	var active := obstacle_manager.get_active_obstacles()
	for entry in active:
		var obs := entry["obstacle"] as ObstacleData
		var parts := entry["parts"] as Array[Dictionary]
		if obs.depth < (-p1.y - 12.0) or obs.depth > (-p0.y + 12.0):
			continue
		var eval := SweptCollision.evaluate_obstacle(p0, p1, parts, LIVE_PLAYER_RADIUS)
		if bool(eval["hit"]):
			if player.is_phase_invulnerable() and not in_autopilot and scoring.mode != ScoringManager.MODE_WATCH:
				if not _parried_ids.has(obs.id):
					_parried_ids[obs.id] = true
					scoring.register_phase_parry(obs.id)
					player.refresh_phase_cooldown()
					var p_pitch := 1.0 + minf(0.35, float(scoring.streak) * 0.02)
					AudioSyncManager.play_sfx("phase_parry", p_pitch)
					speed_particles.emit_burst(eval["impact_point"] as Vector3, Color("14f1d9"), 22)
					player.add_fov_punch(5.0)
					player.add_shake(0.32)
					flash_color = Color("14f1d9")
					flash_strength = maxf(flash_strength, 0.72)
					_hitstop_timer = 0.026
					GameEvents.phase_dash_used.emit(true, player.get_phase_ready_ratio())
				continue
			if scoring.is_indestructible() or spawn_grace_timer > 0.0 or in_autopilot:
				continue
			_trigger_impact_freeze(obs, eval["impact_point"] as Vector3)
			return
		var tier := int(eval["graze_tier"])
		if tier > SweptCollision.TIER_NONE:
			var pts := scoring.register_graze(obs.id, tier, in_autopilot)
			if pts > 0:
				if tier == SweptCollision.TIER_DEATH_WISH:
					player.refresh_phase_cooldown()
				var g_pitch := 1.0 + minf(0.45, float(scoring.streak) * 0.025)
				AudioSyncManager.play_sfx("graze_%d" % tier, g_pitch)
				player.add_fov_punch(1.8 + float(tier) * 1.1)
				player.add_shake(0.10 + float(tier) * 0.07)
				var g_col := Color("ff2e93") if tier == SweptCollision.TIER_DEATH_WISH else (Color("facc15") if tier == SweptCollision.TIER_DAREDEVIL else Color("14f1d9"))
				flash_color = g_col
				flash_strength = maxf(flash_strength, 0.42 + float(tier) * 0.14)
				speed_particles.emit_burst(p1 + Vector3(0.0, -2.5, 0.0), g_col, 10 + tier * 4)
				if replay_controller != null:
					replay_controller.record_event("graze", float(tier))
		if obs.depth < (-p1.y - 0.5) and not _passed_obstacles.has(obs.id):
			_passed_obstacles[obs.id] = true
			AudioSyncManager.play_sfx("whoosh", clampf(current_speed / 60.0, 0.85, 1.35))


func _check_flow_lock_and_milestones() -> void:
	if scoring.color_locked and not _was_flow_locked:
		_was_flow_locked = true
		AudioSyncManager.play_sfx("flow_lock")
		flash_color = Color("14f1d9")
		flash_strength = maxf(flash_strength, 0.65)
	elif not scoring.color_locked:
		_was_flow_locked = false

	var c_tier := 3 if scoring.chain_multiplier >= 8.0 else (2 if scoring.chain_multiplier >= 6.0 else (1 if scoring.chain_multiplier >= 4.0 else 0))
	if c_tier > _milestone_chain_tier:
		_milestone_chain_tier = c_tier
		match c_tier:
			1:
				GameEvents.milestone_callout.emit("UNSTOPPABLE 4.0x!", Color("14f1d9"))
			2:
				GameEvents.milestone_callout.emit("GODLIKE 6.0x!", Color("ff2e93"))
			3:
				GameEvents.milestone_callout.emit("TRANSCENDENT 8.0x!", Color("facc15"))
	elif scoring.chain_multiplier < 2.0:
		_milestone_chain_tier = 0


func _trigger_impact_freeze(obs: ObstacleData, impact_point: Vector3) -> void:
	state = SessionState.IMPACT_FREEZE
	freeze_timer = DEATH_FREEZE_DURATION
	scoring.deaths_in_run += 1
	_last_impact_obs_id = obs.id
	_last_impact_obs_type = obs.type
	_last_impact_point = impact_point
	var pullback := impact_point + Vector3(0.0, 3.8, 0.0)
	pullback.y = minf(0.0, pullback.y)
	_freeze_cam_pos = pullback
	player.add_shake(0.85)
	player.set_replay_pose(pullback, player.current_roll)
	flash_color = Color("fb7185")
	flash_strength = 0.90
	speed_particles.emit_burst(impact_point, Color("ff2e93"), 24)
	obstacle_manager.set_highlight_obstacle(obs.id)
	obstacle_manager.step_and_sync(player.position_3d.y, 0.0, AudioSyncManager.beat_phase, AudioSyncManager.bass_energy, scoring.color_locked)
	AudioSyncManager.play_sfx("death")
	AudioSyncManager.on_player_death()
	var depth_m := maxf(0.0, -player.position_3d.y)
	_last_death_summary = scoring.build_summary(depth_m, elapsed_time, false)
	_last_death_summary["obstacle_id"] = obs.id
	_last_death_summary["obstacle_type"] = obs.type


func _finalize_death() -> void:
	state = SessionState.DEAD
	_set_mouse_captured(false)
	var depth_m := maxf(0.0, -player.position_3d.y)
	if scoring.mode == ScoringManager.MODE_NORMAL or scoring.mode == ScoringManager.MODE_RANKED:
		SaveManager.record_death(
			stage.id,
			depth_m,
			Vector2(player.position_3d.x, player.position_3d.z),
			int(_last_death_summary.get("score", 0)),
			float(_last_death_summary.get("max_chain", 1.0))
		)
		if scoring.mode == ScoringManager.MODE_RANKED and replay_controller != null:
			replay_controller.finish_and_submit(stage, _last_death_summary, false)
	GameEvents.player_died.emit(_last_impact_obs_id, _last_impact_obs_type, _last_impact_point, _last_death_summary)
	if death_overlay != null and death_overlay.has_method("show_death"):
		death_overlay.show_death(_last_death_summary)


func _handle_stage_end() -> void:
	if scoring.mode == ScoringManager.MODE_RANKED:
		ranked_lap += 1
		spawn_grace_timer = 1.0
		_passed_obstacles.clear()
		_parried_ids.clear()
		player.reset_at(0.0, Vector2(player.position_3d.x, player.position_3d.z) * 0.25)
		tunnel_renderer.reset_tunnel(stage.tunnel_radius)
		ring_manager.reset_with_stage(stage)
		speed_particles.reset_particles(stage.tunnel_radius)
		flash_color = Color("facc15")
		flash_strength = 0.70
		GameEvents.milestone_callout.emit("LAP %d  //  OVERDRIVE SPEED" % (ranked_lap + 1), Color("facc15"))
		return

	state = SessionState.CLEARED
	_set_mouse_captured(false)
	AudioSyncManager.play_sfx("clear")
	var summary := scoring.build_summary(stage.total_length(), elapsed_time, true)
	if scoring.mode == ScoringManager.MODE_NORMAL:
		var next_id := LevelRepository.get_next_campaign_stage_id(stage.id)
		SaveManager.record_stage_clear(stage.id, next_id, summary)
	if (scoring.mode == ScoringManager.MODE_NORMAL or scoring.mode == ScoringManager.MODE_RANKED) and replay_controller != null:
		replay_controller.finish_and_submit(stage, summary, true)
	GameEvents.stage_cleared.emit(stage.id, scoring.mode, summary)
	if death_overlay != null and death_overlay.has_method("show_clear"):
		death_overlay.show_clear(summary)


func next_stage() -> bool:
	if stage == null:
		return false
	var next_id := LevelRepository.get_next_campaign_stage_id(stage.id)
	if next_id.is_empty():
		return false
	var next_mode := scoring.mode if scoring.mode != ScoringManager.MODE_WATCH else ScoringManager.MODE_NORMAL
	start_session({"stage_id": next_id, "mode": next_mode})
	return true


func _sync_section_and_effects(depth_m: float) -> void:
	var sec_idx := stage.section_index_at_depth(depth_m)
	current_effect_mask = scoring.compute_effective_mask(stage, depth_m, ranked_lap)
	if sec_idx != current_section_index:
		var had_prev := current_section_index >= 0
		current_section_index = sec_idx
		GameEvents.section_changed.emit(sec_idx, current_effect_mask)
		if had_prev and sec_idx > 0 and state == SessionState.PLAYING:
			GameEvents.milestone_callout.emit("SECTION %d  //  VELOCITY UP" % (sec_idx + 1), Color("38bdf8"))
			AudioSyncManager.play_sfx("section_up")


func _is_in_transition_zone(depth_m: float) -> bool:
	if stage.sections.size() <= 1:
		return false
	for i in range(stage.sections.size() - 1):
		var bounds := stage.section_bounds(i)
		var gap := float(stage.sections[i].get("transition_gap", 28.0))
		if depth_m >= (bounds.y - gap) and depth_m <= bounds.y + 4.0:
			return true
	return false


func retry_run() -> void:
	AudioSyncManager.on_retry()
	var keep_cp := (scoring.mode == ScoringManager.MODE_PRACTICE and scoring.practice_checkpoint_active)
	start_session(launch_params, keep_cp)


func pause_game() -> void:
	if state != SessionState.PLAYING:
		return
	state = SessionState.PAUSED
	_set_mouse_captured(false)
	if pause_overlay != null and pause_overlay.has_method("show_pause"):
		pause_overlay.show_pause(_return_to_editor)


func resume_game() -> void:
	if state != SessionState.PAUSED:
		return
	state = SessionState.PLAYING
	_set_mouse_captured(true)
	if pause_overlay != null and pause_overlay.has_method("hide_pause"):
		pause_overlay.hide_pause()


func return_to_editor() -> void:
	_set_mouse_captured(false)
	AudioSyncManager.stop_music()
	if ResourceLoader.exists("res://scenes/level_editor.tscn"):
		get_tree().change_scene_to_file("res://scenes/level_editor.tscn")


func exit_to_menu() -> void:
	_set_mouse_captured(false)
	AudioSyncManager.stop_music()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _set_mouse_captured(captured: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if scoring.mode == ScoringManager.MODE_WATCH:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
