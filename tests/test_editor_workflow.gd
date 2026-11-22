extends Node
## Milestone 6 verification suite:
## - LevelEditor CRUD (add/edit/delete obstacles, toggle 24-bit effects)
## - Pre-save .bak backup creation and failed-load guard inside editor workflow
## - "Play From Here" launches GameSession at the exact editor camera depth
## - Isolated animation clock in LevelPreviewViewport & ObstacleManager (no carryover)

var _passed := 0
var _failed := 0


func run_suite(runner: Node) -> Dictionary:
	_test_editor_crud_and_backups(runner)
	_test_play_from_here_depth(runner)
	_test_preview_clock_isolation(runner)
	return {"passed": _passed, "failed": _failed}


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		printerr("  [FAIL] " + label)


func _test_editor_crud_and_backups(runner: Node) -> void:
	var ed := LevelEditor.new()
	runner.add_child(ed)
	ed.create_new_stage()
	ed.working_stage.id = "editor_crud_map"
	ed.working_stage.title = "Editor Test"

	var o1 := ed.add_obstacle("waffle", 45.0)
	var o2 := ed.add_obstacle("pendulum", 95.0)
	_assert_true(o1 != null and o2 != null and ed.working_stage.obstacles.size() == 2,
		"Editor adds multiple obstacle archetypes cleanly")

	ed.selected_obstacle_id = o1.id
	ed.update_selected_obstacle_field("depth", 62.5)
	_assert_true(is_equal_approx(o1.depth, 62.5), "Editor updates obstacle properties")

	ed.toggle_effect_bit(1, true)
	ed.toggle_effect_bit(12, true)
	var mask := int(ed.working_stage.sections[0]["effect_mask"])
	_assert_true(EffectCatalog.has_effect(mask, 1) and EffectCatalog.has_effect(mask, 12),
		"Editor toggles 24-bit visual effects on active section")

	var s1 := ed.save_stage(true)
	_assert_true(bool(s1["ok"]), "Editor saves and publishes custom stage")

	ed.selected_obstacle_id = o2.id
	var del_ok := ed.delete_selected_obstacle()
	_assert_true(del_ok and ed.working_stage.obstacles.size() == 1, "Editor deletes selected obstacle")

	var s2 := ed.save_stage(true)
	_assert_true(bool(s2["ok"]) and not str(s2["backup_path"]).is_empty(),
		"Re-saving in LevelEditor creates pre-save .bak backup")

	# Attempt loading nonexistent/corrupt id -> working stage stays intact!
	var bad := ed.load_stage_by_id("nonexistent_corrupt_id")
	_assert_true(not bool(bad["ok"]) and ed.working_stage.obstacles.size() == 1,
		"Failed load preserves in-editor stage without overwriting")

	ed.selected_obstacle_id = o1.id
	var dup := ed.duplicate_selected_obstacle()
	_assert_true(dup != null and ed.working_stage.obstacles.size() == 2,
		"Editor duplicates selected obstacle cleanly")
	ed.clear_obstacles()
	_assert_true(ed.working_stage.obstacles.is_empty(), "Editor clears all obstacles cleanly")
	ed.queue_free()


func _test_play_from_here_depth(runner: Node) -> void:
	var ed := LevelEditor.new()
	runner.add_child(ed)
	ed.create_new_stage()
	ed.working_stage.id = "play_here_map"
	ed.add_obstacle("cross_bars", 140.0)
	ed.camera_depth = 88.5

	var params := ed.build_play_from_here_params()
	var gs := GameSession.new()
	runner.add_child(gs)
	gs.start_session(params)
	_assert_true(absf((-gs.player.position_3d.y) - 88.5) < 0.05,
		"Play From Here spawns player directly at editor camera depth (88.5m)")
	_assert_true(gs.scoring.mode == ScoringManager.MODE_EDITOR_TEST,
		"Play From Here launches in editor_test mode with return flag")
	gs.queue_free()
	ed.queue_free()


func _test_preview_clock_isolation(runner: Node) -> void:
	var vp1 := LevelPreviewViewport.new()
	var vp2 := LevelPreviewViewport.new()
	runner.add_child(vp1)
	runner.add_child(vp2)

	var st1 := LevelRepository.get_stage_by_id("01_a")
	vp1.set_stage(st1)
	vp1.step_preview(2.5)
	_assert_true(vp1.obstacle_manager.local_time > 2.0, "Preview 1 advances its local animation clock")

	# Switching stage resets clock cleanly; preview 2 stays independent of preview 1
	vp2.set_stage(st1)
	_assert_true(is_equal_approx(vp2.obstacle_manager.local_time, 0.0),
		"Preview 2 starts at t=0.0 with zero clock carryover from Preview 1")
	vp1.set_stage(st1)
	_assert_true(is_equal_approx(vp1.obstacle_manager.local_time, 0.0),
		"Selecting a stage resets preview animation clock cleanly")
	vp1.queue_free()
	vp2.queue_free()
