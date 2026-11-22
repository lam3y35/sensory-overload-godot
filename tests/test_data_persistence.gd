extends Node
## Milestone 1 verification suite:
## - EffectCatalog 24-bit operations & Safe Mode clamp
## - StageData / ObstacleData / ReplayData serialization roundtrips
## - SettingsManager exact 1.00x sensitivity step & accessibility bounds
## - SaveManager strict UUID-keyed per-map stats & ghost marker isolation
## - LevelRepository pre-save .bak rotation & corrupted JSON non-overwrite guard

var _passed := 0
var _failed := 0


func run_suite(_runner: Node) -> Dictionary:
	_test_effect_catalog()
	_test_stage_and_obstacle_roundtrip()
	_test_settings_precision_and_bounds()
	_test_save_manager_map_isolation()
	_test_repository_backups_and_corruption_guard()
	return {"passed": _passed, "failed": _failed}


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		printerr("  [FAIL] " + label)


func _test_effect_catalog() -> void:
	_assert_true(EffectCatalog.EFFECTS.size() == 24, "EffectCatalog defines exactly 24 effects")
	_assert_true(EffectCatalog.MAX_MASK == 0xFFFFFF, "MAX_MASK covers full 24-bit range (2^24 = 16,777,216 combos)")
	var mask := 0
	mask = EffectCatalog.set_effect(mask, 0, true)
	mask = EffectCatalog.set_effect(mask, 16, true) # STROBE_FLASH (photosensitive)
	mask = EffectCatalog.set_effect(mask, 23, true) # WHITEOUT_GLARE (photosensitive)
	_assert_true(EffectCatalog.count_effects(mask) == 3, "EffectCatalog counts 3 active bits accurately")
	var safe := EffectCatalog.clamp_safe_mask(mask, true)
	_assert_true(EffectCatalog.has_effect(safe, 0) and not EffectCatalog.has_effect(safe, 16) and not EffectCatalog.has_effect(safe, 23),
		"Safe photosensitivity mode clamps strobe & whiteout bits while retaining safe bit 0")


func _test_stage_and_obstacle_roundtrip() -> void:
	var st := StageData.new()
	st.id = "test_roundtrip"
	st.title = "Roundtrip Drop"
	st.bpm = 140.0
	st.sections = [
		{"id": "s1", "length": 150.0, "effect_mask": (1 << 0) | (1 << 4), "transition_gap": 24.0},
		{"id": "s2", "length": 200.0, "effect_mask": (1 << 12), "transition_gap": 28.0},
	]
	for i in range(ObstacleData.VALID_TYPES.size()):
		var obs := ObstacleData.new()
		obs.id = "obs_%d" % i
		obs.type = ObstacleData.VALID_TYPES[i]
		obs.depth = 30.0 + float(i) * 20.0
		obs.offset_xz = Vector2(1.5, -0.75)
		obs.rotation_deg = Vector3(10.0, 25.0, 45.0)
		obs.scale = Vector3(1.2, 0.8, 1.5)
		st.obstacles.append(obs)

	var dict := st.to_dict()
	var res := StageData.from_dict(dict)
	_assert_true(bool(res["ok"]), "StageData roundtrip parses cleanly")
	var parsed: StageData = res["stage"]
	_assert_true(parsed.obstacles.size() == 10, "All 10 obstacle archetypes serialize & restore cleanly")
	_assert_true(is_equal_approx(parsed.total_length(), 350.0), "StageData total_length sums sections accurately")
	_assert_true(parsed.section_index_at_depth(160.0) == 1, "section_index_at_depth resolves section 1 at 160m")


func _test_settings_precision_and_bounds() -> void:
	SettingsManager.reset_defaults()
	SettingsManager.set_mouse_sensitivity(0.98)
	_assert_true(is_equal_approx(SettingsManager.mouse_sensitivity, 1.00), "Mouse sensitivity snaps cleanly to exact 1.00x (0.05 step)")
	SettingsManager.set_mouse_sensitivity(0.01)
	_assert_true(is_equal_approx(SettingsManager.mouse_sensitivity, 0.20), "Mouse sensitivity clamps at lower bound 0.20x")
	SettingsManager.set_obstacle_opacity(0.05)
	_assert_true(is_equal_approx(SettingsManager.obstacle_opacity, 0.20), "Obstacle opacity clamps at 20% minimum override")
	var err := SettingsManager.save_settings()
	_assert_true(err == OK, "SettingsManager saves settings.cfg cleanly")
	SettingsManager.mouse_sensitivity = 2.50
	SettingsManager.load_settings()
	_assert_true(is_equal_approx(SettingsManager.mouse_sensitivity, 0.20), "SettingsManager reloads persisted values from ConfigFile")


func _test_save_manager_map_isolation() -> void:
	SaveManager.reset_in_memory()
	SaveManager.record_attempt("map_alpha")
	SaveManager.record_death("map_alpha", 142.5, Vector2(2.0, -1.0), 8400, 3.5)
	SaveManager.record_attempt("map_beta")

	var stats_a := SaveManager.get_map_stats("map_alpha")
	var stats_b := SaveManager.get_map_stats("map_beta")
	_assert_true(int(stats_a["high_score"]) == 8400 and (stats_a["ghost_markers"] as Array).size() == 1,
		"map_alpha retains high score and ghost marker")
	_assert_true(int(stats_b["high_score"]) == 0 and (stats_b["ghost_markers"] as Array).is_empty(),
		"map_beta stats and ghost markers stay completely isolated from map_alpha (no bleed)")


func _test_repository_backups_and_corruption_guard() -> void:
	var st := StageData.new()
	st.id = "bak_test_stage"
	st.title = "Backup Guard Test"
	var obs := ObstacleData.new()
	obs.id = "o1"
	obs.type = "waffle"
	obs.depth = 45.0
	st.obstacles.append(obs)

	var save1 := LevelRepository.save_custom_stage(st)
	_assert_true(bool(save1["ok"]) and str(save1["backup_path"]).is_empty(), "Initial custom save succeeds with no prior backup")

	st.title = "Backup Guard Test v2"
	var save2 := LevelRepository.save_custom_stage(st)
	_assert_true(bool(save2["ok"]) and not str(save2["backup_path"]).is_empty() and FileAccess.file_exists(str(save2["backup_path"])),
		"Overwrite save creates pre-save .bak backup file")

	# Write corrupted file separately and verify load refuses without overwriting valid files
	var corrupt_path := "user://test_sandbox/custom_levels/corrupted_stage.json"
	var cf := FileAccess.open(corrupt_path, FileAccess.WRITE)
	cf.store_string("{ broken json [")
	cf.close()

	var bad_res := LevelRepository.load_custom_stage("corrupted_stage")
	_assert_true(not bool(bad_res["ok"]) and bad_res["stage"] == null, "Corrupted JSON fails load explicitly instead of returning empty stage")

	var verify_f := FileAccess.open(corrupt_path, FileAccess.READ)
	_assert_true(verify_f.get_as_text() == "{ broken json [", "Corrupted file is preserved untouched on failed load")
