extends Node
## Milestone 3 verification suite:
## - ScoringManager 3-tier graze points, upgrade bonus, MAX_CHAIN (8.0x) cap, chain decay
## - Flow Meter color lock (>= 70%) & GRAZE_ALL_STAGE bonus
## - Zen mode surviving obstacle hit AND advancing cleanly across sections
## - Practice mode checkpoint placement, respawn at checkpoint depth, and clear
## - Ranked mode speed escalation & endless lap wrapping
## - GameSession 0.35s delayed death freeze transitioning cleanly to DEAD state

var _passed := 0
var _failed := 0


func run_suite(runner: Node) -> Dictionary:
	_test_scoring_chains_and_flow()
	_test_zen_section_advancement_and_indestructibility(runner)
	_test_practice_checkpoints(runner)
	_test_ranked_speed_escalation_and_lap(runner)
	_test_boost_and_energy_rings(runner)
	_test_delayed_death_freeze(runner)
	return {"passed": _passed, "failed": _failed}


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		printerr("  [FAIL] " + label)


func _build_two_section_test_stage(obs_depth: float) -> StageData:
	var st := StageData.new()
	st.id = "m3_test_stage"
	st.title = "M3 Test"
	st.base_speed = 40.0
	st.speed_ramp = 0.5
	st.sections = [
		{"id": "s1", "length": 80.0, "effect_mask": 1 << 0, "transition_gap": 15.0},
		{"id": "s2", "length": 80.0, "effect_mask": (1 << 0) | (1 << 4), "transition_gap": 15.0},
	]
	var obs := ObstacleData.new()
	obs.id = "wall_obs"
	obs.type = "cross_bars"
	obs.depth = obs_depth
	obs.speed = 0.0
	st.obstacles.append(obs)
	return st


func _test_scoring_chains_and_flow() -> void:
	var st := _build_two_section_test_stage(50.0)
	var sm := ScoringManager.new()
	sm.begin_run(ScoringManager.MODE_NORMAL, st)

	var p1 := sm.register_graze("o1", SweptCollision.TIER_NEAR_MISS)
	_assert_true(p1 == 100 and sm.streak == 1, "Near Miss awards 100 pts and +1 streak")

	# Push streak to MAX_CHAIN (42+ streak -> 8.0x) and flow >= 0.70
	for i in range(15):
		sm.register_graze("dw_%d" % i, SweptCollision.TIER_DEATH_WISH)
	_assert_true(is_equal_approx(sm.chain_multiplier, 8.0), "Chain multiplier caps cleanly at 8.0x (MAX_CHAIN)")
	_assert_true(sm.color_locked and sm.reached_flow_lock, "Flow meter locks colors above 70% threshold")

	# Chain decays back to 1.0x after 5.0 seconds without grazes
	sm.step(5.0, false, false)
	_assert_true(sm.streak == 0 and is_equal_approx(sm.chain_multiplier, 1.0), "Chain resets to 1.0x after decay timeout")


func _test_zen_section_advancement_and_indestructibility(runner: Node) -> void:
	var st := _build_two_section_test_stage(40.0)
	var gs := GameSession.new()
	runner.add_child(gs)
	gs.start_session({"stage_data": st, "mode": ScoringManager.MODE_ZEN})

	# Step straight down at origin directly through the cross_bars obstacle at depth 40m into section 2 (depth > 80m)
	for _i in range(150):
		gs.step_simulation(0.02)
		if gs.state != GameSession.SessionState.PLAYING:
			break

	_assert_true(gs.state == GameSession.SessionState.PLAYING or gs.state == GameSession.SessionState.CLEARED,
		"Zen mode survives direct obstacle impact without entering IMPACT_FREEZE/DEAD")
	_assert_true(gs.current_section_index == 1, "Zen mode advances past section 0 into section 1 despite obstacle collision")
	_assert_true(gs.scoring.score == 0, "Zen mode maintains zero competitive score")
	gs.queue_free()


func _test_practice_checkpoints(runner: Node) -> void:
	var st := _build_two_section_test_stage(90.0)
	var gs := GameSession.new()
	runner.add_child(gs)
	gs.start_session({"stage_data": st, "mode": ScoringManager.MODE_PRACTICE})

	# Advance down to ~55m and place checkpoint
	for _i in range(70):
		gs.step_simulation(0.02)
	var cp_depth := -gs.player.position_3d.y
	gs.scoring.set_checkpoint(cp_depth, Vector2(1.2, -0.8))
	_assert_true(gs.scoring.practice_checkpoint_active and cp_depth > 30.0, "Practice mode records custom checkpoint at depth")

	# Retry run and verify player respawns at checkpoint depth
	gs.retry_run()
	var respawn_depth := -gs.player.position_3d.y
	_assert_true(absf(respawn_depth - cp_depth) < 0.05, "Practice retry respawns cleanly at active checkpoint depth")
	gs.scoring.clear_checkpoint()
	_assert_true(not gs.scoring.practice_checkpoint_active, "Practice checkpoint clears cleanly")
	gs.queue_free()


func _test_ranked_speed_escalation_and_lap(runner: Node) -> void:
	var st := _build_two_section_test_stage(999.0) # No hit obstacle so we reach stage end
	var gs := GameSession.new()
	runner.add_child(gs)
	gs.start_session({"stage_data": st, "mode": ScoringManager.MODE_RANKED})
	var initial_speed := gs.scoring.compute_active_speed(st, 0.0, 0)

	# Run past 160m stage end to wrap into ranked lap 1
	for _i in range(280):
		gs.step_simulation(0.02)
	var lap1_speed := gs.current_speed
	_assert_true(gs.ranked_lap >= 1 and gs.state == GameSession.SessionState.PLAYING,
		"Ranked mode wraps endlessly across stage boundary into lap 1+")
	_assert_true(lap1_speed > initial_speed, "Ranked mode escalates descent speed over depth and laps")
	gs.queue_free()


func _test_boost_and_energy_rings(runner: Node) -> void:
	var st := _build_two_section_test_stage(999.0)
	var gs := GameSession.new()
	runner.add_child(gs)

	# 1) Measure normal baseline speed and score over 0.5s
	gs.start_session({"stage_data": st, "mode": ScoringManager.MODE_NORMAL})
	gs.boost_override = 0
	for _i in range(30):
		gs.step_simulation(1.0 / 60.0)
	var normal_spd := gs.current_speed
	var normal_score := gs.scoring.score

	# 2) Measure Hyper-Boost speed and distance score over 0.5s
	gs.start_session({"stage_data": st, "mode": ScoringManager.MODE_NORMAL})
	gs.boost_override = 1
	for _i in range(30):
		gs.step_simulation(1.0 / 60.0)
	var boost_spd := gs.current_speed
	var boost_score := gs.scoring.score
	_assert_true(boost_spd > normal_spd * 1.35, "Hyper-Boost accelerates descent velocity significantly (%.1f > %.1f)" % [boost_spd, normal_spd])
	_assert_true(boost_score > normal_score * 2, "Hyper-Boost doubles descent distance score rate (%d > %d)" % [boost_score, normal_score])

	# 3) Verify RingManager generation and check_collect pickup + ScoringManager reward
	var rings: Array[Dictionary] = gs.ring_manager.get_rings()
	_assert_true(rings.size() >= 1, "RingManager generates deterministic Energy Rings across stage")
	var first_ring: Dictionary = rings[0]
	var rd := float(first_ring["depth"])
	var rxz := first_ring["xz"] as Vector2
	var res: Dictionary = gs.ring_manager.check_collect(Vector3(rxz.x, -(rd - 1.5), rxz.y), Vector3(rxz.x, -(rd + 1.5), rxz.y))
	_assert_true(bool(res["collected"]), "RingManager detects swept trajectory passing through Energy Ring")
	var prev_streak := gs.scoring.streak
	var r_pts := gs.scoring.register_ring(str(res["id"]), false)
	_assert_true(r_pts >= 300 and gs.scoring.rings_collected == 1 and gs.scoring.streak == prev_streak + 1,
		"Ring collection awards >= 300 base pts, increments rings_collected, and builds streak")
	gs.queue_free()


func _test_delayed_death_freeze(runner: Node) -> void:
	var st := _build_two_section_test_stage(25.0)
	var gs := GameSession.new()
	runner.add_child(gs)
	gs.start_session({"stage_data": st, "mode": ScoringManager.MODE_NORMAL})

	# Advance until colliding with cross_bars at 25m
	var entered_freeze := false
	for _i in range(100):
		gs.step_simulation(0.02)
		if gs.state == GameSession.SessionState.IMPACT_FREEZE:
			entered_freeze = true
			break

	_assert_true(entered_freeze, "Normal mode enters 0.35s IMPACT_FREEZE upon hitting obstacle")
	_assert_true(gs.obstacle_manager.highlighted_obstacle_id == "wall_obs",
		"Impact freeze highlights the exact colliding obstacle")

	# Step 0.20s -> still frozen; step another 0.20s -> transitions to DEAD
	gs.step_simulation(0.20)
	_assert_true(gs.state == GameSession.SessionState.IMPACT_FREEZE, "Remains frozen at 0.20s (< 0.35s)")
	gs.step_simulation(0.20)
	_assert_true(gs.state == GameSession.SessionState.DEAD, "Transitions cleanly to DEAD state after 0.35s impact freeze")
	gs.queue_free()
