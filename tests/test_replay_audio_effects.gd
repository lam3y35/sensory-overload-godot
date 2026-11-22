extends Node
## Milestones 4 & 5 verification suite:
## - EffectCompositor applying 24-bit masks & clamping photosensitive bits in Safe Mode
## - Procedural PCM WAV synthesizer generating zero-crossing seamless loops across multiple tracks
## - AudioSyncManager Pause on Death / Restart Song on Death state transitions
## - ReplayController record -> serialize -> LevelRepository save/load -> WATCH interpolation & leaderboard

var _passed := 0
var _failed := 0


func run_suite(runner: Node) -> Dictionary:
	_test_effect_compositor_and_safe_mode(runner)
	_test_procedural_audio_zero_crossing_and_fsm()
	_test_replay_roundtrip_and_watch(runner)
	return {"passed": _passed, "failed": _failed}


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		printerr("  [FAIL] " + label)


func _test_effect_compositor_and_safe_mode(runner: Node) -> void:
	var ec := EffectCompositor.new()
	runner.add_child(ec)

	SettingsManager.safe_photosensitivity_mode = false
	var mask_all := EffectCatalog.MAX_MASK
	ec.apply_effects(mask_all, 1.0, 60.0, 0.25, 0.8, 0.9)
	_assert_true(ec.last_applied_mask == EffectCatalog.MAX_MASK, "EffectCompositor applies full 24-bit mask when Safe Mode is off")

	SettingsManager.safe_photosensitivity_mode = true
	ec.apply_effects(mask_all, 1.0, 60.0, 0.25, 0.8, 0.9)
	_assert_true(
		not EffectCatalog.has_effect(ec.last_applied_mask, 16)
		and not EffectCatalog.has_effect(ec.last_applied_mask, 18)
		and not EffectCatalog.has_effect(ec.last_applied_mask, 23),
		"EffectCompositor strips Strobe (16), Invert (18), and Whiteout (23) under Safe Mode"
	)
	SettingsManager.safe_photosensitivity_mode = false
	ec.queue_free()


func _test_procedural_audio_zero_crossing_and_fsm() -> void:
	for tidx in [0, 4, 6]:
		var wav := AudioSyncManager.get_or_build_track_stream(tidx)
		var sample_count := wav.data.size() / 2
		_assert_true(sample_count > 10000 and wav.loop_mode == AudioStreamWAV.LOOP_FORWARD,
			"Procedural synth track %d builds valid looping PCM WAV (%d samples)" % [tidx, sample_count])

		var first_s := wav.data.decode_s16(0)
		var last_s := wav.data.decode_s16((sample_count - 1) * 2)
		_assert_true(abs(first_s) < 32 and abs(last_s) < 32,
			"Track %d meets zero-crossing seamless loop invariant (first=%d, last=%d)" % [tidx, first_s, last_s])

		var sq_sum := 0.0
		var step := maxi(1, sample_count / 500)
		var checked := 0
		for i in range(0, sample_count, step):
			var v := float(wav.data.decode_s16(i * 2)) / 32768.0
			sq_sum += v * v
			checked += 1
		var rms := sqrt(sq_sum / float(maxi(1, checked)))
		_assert_true(rms > 0.05, "Track %d contains non-silent musical energy (RMS=%.3f)" % [tidx, rms])

	# Verify Pause on Death / Restart Song on Death state transitions
	SettingsManager.pause_on_death = true
	SettingsManager.restart_song_on_death = false
	SettingsManager.random_track = false
	AudioSyncManager.start_track(2, 134.0, true)
	AudioSyncManager.on_player_death()
	_assert_true(AudioSyncManager.is_paused, "AudioSyncManager pauses playback on death when pause_on_death=true")
	AudioSyncManager.on_retry()
	_assert_true(not AudioSyncManager.is_paused and AudioSyncManager.current_track_index == 2,
		"AudioSyncManager resumes without changing track when restart_song_on_death=false")
	AudioSyncManager.stop_music()


func _test_replay_roundtrip_and_watch(runner: Node) -> void:
	var st := StageData.new()
	st.id = "m5_watch_stage"
	st.title = "Replay Test Stage"
	st.base_speed = 45.0
	st.sections = [{"id": "s1", "length": 180.0, "effect_mask": 1 << 5, "transition_gap": 24.0}]
	var obs := ObstacleData.new()
	obs.id = "safe_pillar"
	obs.type = "pillar_grid"
	obs.depth = 500.0
	st.obstacles.append(obs)

	var gs := GameSession.new()
	runner.add_child(gs)
	gs.start_session({"stage_data": st, "mode": ScoringManager.MODE_RANKED})
	for _i in range(45):
		gs.step_simulation(1.0 / 60.0)

	var summary := gs.scoring.build_summary(-gs.player.position_3d.y, gs.elapsed_time, true)
	var rep_id: String = gs.replay_controller.finish_and_submit(st, summary, true)
	_assert_true(not rep_id.is_empty(), "ReplayController persists Ranked replay and returns replay_id")

	var lb := LevelRepository.get_stage_leaderboard(st.id)
	_assert_true(lb.size() >= 1 and str(lb[0]["replay_id"]) == rep_id,
		"Leaderboard entry binds directly to saved replay_id for WATCH button")

	var loaded := LevelRepository.load_replay(rep_id)
	_assert_true(bool(loaded["ok"]), "LevelRepository reloads serialized replay JSON cleanly")
	var rep_obj := loaded["replay"] as ReplayData
	_assert_true(rep_obj.frames.size() >= 40, "Reloaded replay preserves 60 Hz frame samples")

	# Now launch WATCH mode in GameSession and verify playback advances smoothly
	gs.start_session({"stage_data": st, "mode": ScoringManager.MODE_WATCH, "replay_data": rep_obj})
	gs.step_simulation(0.25)
	_assert_true(gs.replay_controller.is_watching and -gs.player.position_3d.y > 5.0,
		"WATCH mode replays recorded trajectory inside live GameSession")
	gs.queue_free()
