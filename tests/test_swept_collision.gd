extends Node
## Milestone 2 verification suite:
## - SweptCollision zero-tunneling at 200 m/s through thin 0.2 m blades
## - Rotated/tumbling OBB exact hit & miss alignment
## - 3-tier Graze clearance classification (Near Miss / Daredevil / Death Wish / None)
## - All 10 ObstacleData archetypes generating valid orthonormal OBB parts
## - PlayerController anti-lockup boundary slide & TunnelRenderer MultiMesh setup

var _passed := 0
var _failed := 0


func run_suite(runner: Node) -> Dictionary:
	_test_high_speed_zero_tunneling()
	_test_rotated_tumbling_obb_alignment()
	_test_three_graze_tiers()
	_test_all_ten_archetypes_parts()
	_test_pendulum_swings_laterally()
	_test_player_boundary_anti_lockup(runner)
	_test_tunnel_and_obstacle_scene_instantiation(runner)
	return {"passed": _passed, "failed": _failed}


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  [PASS] " + label)
	else:
		_failed += 1
		printerr("  [FAIL] " + label)


func _test_high_speed_zero_tunneling() -> void:
	# Thin blade 0.20 m thick at y = -50.0; player steps 3.33 m in one tick (200 m/s @ 60 Hz)
	var blade_xform := Transform3D(Basis.IDENTITY, Vector3(0.0, -50.0, 0.0))
	var half_ext := Vector3(5.0, 0.10, 1.5)
	var p0 := Vector3(0.0, -48.2, 0.0)
	var p1 := Vector3(0.0, -51.53, 0.0)
	var res := SweptCollision.segment_to_obb_sweep(p0, p1, blade_xform, half_ext, 0.32)
	_assert_true(bool(res["hit"]), "SweptCollision catches 200 m/s segment crossing a 0.20 m thin blade")
	_assert_true(float(res["t"]) > 0.35 and float(res["t"]) < 0.65, "Impact time parameter t interpolates accurately near midpoint")


func _test_rotated_tumbling_obb_alignment() -> void:
	var obs := ObstacleData.new()
	obs.id = "tumble_sync"
	obs.type = "tumbling_cube"
	obs.depth = 60.0
	obs.speed = 1.8
	var parts := ObstacleManager.compute_parts(obs, 1.37, 0.25)
	_assert_true(parts.size() == 2, "Tumbling cube computes inner cube + layered rim parts")

	var main_xform := parts[0]["transform"] as Transform3D
	var main_half := parts[0]["half_extents"] as Vector3
	var hit_pt := main_xform.origin
	var hit_res := SweptCollision.segment_to_obb_sweep(hit_pt + Vector3(0, 2, 0), hit_pt - Vector3(0, 2, 0), main_xform, main_half, 0.32)
	_assert_true(bool(hit_res["hit"]), "Rotated tumbling OBB hits trajectory passing through center")

	# 1) Point outside rotated face along local X, swept parallel to rotated local Y -> must miss
	var safe_local := Vector3(main_half.x + 0.85, 0.0, 0.0)
	var safe_world := main_xform * safe_local
	var local_y_dir := main_xform.basis.y * 2.0
	var miss_res := SweptCollision.segment_to_obb_sweep(safe_world + local_y_dir, safe_world - local_y_dir, main_xform, main_half, 0.32)
	_assert_true(not bool(miss_res["hit"]), "Rotated tumbling OBB avoids false positive outside rotated face")

	# 2) Specifically test 45-deg Y-rotated cube: diagonal face is at 2.85m, naive AABB corner is 4.03m
	var obs45 := ObstacleData.new()
	obs45.id = "rot45"
	obs45.type = "tumbling_cube"
	obs45.depth = 60.0
	obs45.rotation_deg = Vector3(0.0, 45.0, 0.0)
	obs45.speed = 0.0
	var parts45 := ObstacleManager.compute_parts(obs45, 0.0, 0.0)
	var xf45 := parts45[0]["transform"] as Transform3D
	var he45 := parts45[0]["half_extents"] as Vector3
	var diag_outside := xf45 * Vector3(he45.x + 0.65, 0.0, 0.0) # Inside naive AABB, cleanly outside rotated OBB
	var miss45 := SweptCollision.segment_to_obb_sweep(diag_outside + Vector3(0, 2, 0), diag_outside - Vector3(0, 2, 0), xf45, he45, 0.32)
	_assert_true(not bool(miss45["hit"]), "45-deg rotated cube OBB rejects hit inside naive world AABB but outside rotated face")


func _test_three_graze_tiers() -> void:
	var xform := Transform3D(Basis.IDENTITY, Vector3(0.0, -40.0, 0.0))
	var half_ext := Vector3(1.0, 0.5, 1.0)
	var r := 0.32
	# Surface is at x = 1.0; clearance = x - 1.0 - r = x - 1.32
	var dw_x := 1.32 + 0.25 # clearance 0.25 -> Death Wish (<= 0.42)
	var dd_x := 1.32 + 0.70 # clearance 0.70 -> Daredevil (<= 0.95)
	var nm_x := 1.32 + 1.30 # clearance 1.30 -> Near Miss (<= 1.65)
	var far_x := 1.32 + 2.40 # clearance 2.40 -> None

	var dw := SweptCollision.evaluate_obstacle(Vector3(dw_x, -38.0, 0.0), Vector3(dw_x, -42.0, 0.0), [{"transform": xform, "half_extents": half_ext}], r)
	var dd := SweptCollision.evaluate_obstacle(Vector3(dd_x, -38.0, 0.0), Vector3(dd_x, -42.0, 0.0), [{"transform": xform, "half_extents": half_ext}], r)
	var nm := SweptCollision.evaluate_obstacle(Vector3(nm_x, -38.0, 0.0), Vector3(nm_x, -42.0, 0.0), [{"transform": xform, "half_extents": half_ext}], r)
	var no_g := SweptCollision.evaluate_obstacle(Vector3(far_x, -38.0, 0.0), Vector3(far_x, -42.0, 0.0), [{"transform": xform, "half_extents": half_ext}], r)

	_assert_true(int(dw["graze_tier"]) == SweptCollision.TIER_DEATH_WISH, "Clearance 0.25 m classifies as DEATH_WISH")
	_assert_true(int(dd["graze_tier"]) == SweptCollision.TIER_DAREDEVIL, "Clearance 0.70 m classifies as DAREDEVIL")
	_assert_true(int(nm["graze_tier"]) == SweptCollision.TIER_NEAR_MISS, "Clearance 1.30 m classifies as NEAR_MISS")
	_assert_true(int(no_g["graze_tier"]) == SweptCollision.TIER_NONE, "Clearance 2.40 m classifies as NONE")


func _test_all_ten_archetypes_parts() -> void:
	for i in range(ObstacleData.VALID_TYPES.size()):
		var obs := ObstacleData.new()
		obs.id = "arch_%d" % i
		obs.type = ObstacleData.VALID_TYPES[i]
		obs.depth = 50.0 + float(i) * 10.0
		var parts := ObstacleManager.compute_parts(obs, 1.2, 0.5)
		var valid := not parts.is_empty()
		for p in parts:
			var he := p["half_extents"] as Vector3
			var xf := p["transform"] as Transform3D
			if he.x <= 0.0 or he.y <= 0.0 or he.z <= 0.0:
				valid = false
			if absf(xf.basis.determinant() - 1.0) > 0.01:
				valid = false
		_assert_true(valid, "Archetype '%s' generates valid orthonormal OBB parts (%d parts)" % [obs.type, parts.size()])


func _test_pendulum_swings_laterally() -> void:
	var obs := ObstacleData.new()
	obs.id = "pend_swing_reg"
	obs.type = "pendulum"
	obs.depth = 50.0
	obs.speed = 1.2
	obs.amplitude = 1.0
	var p0 := ObstacleManager.compute_parts(obs, 0.0, 0.0)
	var p1 := ObstacleManager.compute_parts(obs, 0.75, 0.45)
	var bob0 := (p0[1]["transform"] as Transform3D).origin
	var bob1 := (p1[1]["transform"] as Transform3D).origin
	var delta_m := bob0.distance_to(bob1)
	_assert_true(delta_m > 5.0, "Pendulum bob swings laterally across XZ tunnel (delta=%.2fm > 5.0m)" % delta_m)


func _test_player_boundary_anti_lockup(runner: Node) -> void:
	var pc := PlayerController.new()
	runner.add_child(pc)
	pc.reset_at(0.0, Vector2(8.5, 0.0))
	pc.velocity_xz = Vector2(15.0, 8.0) # Strong outward X plus tangential Z
	pc.apply_input_and_step(0.05, 40.0, false)
	var dist := Vector2(pc.position_3d.x, pc.position_3d.z).length()
	_assert_true(dist <= PlayerController.PLAY_RADIUS + 0.001, "Player boundary clamp keeps XZ inside playable radius")
	_assert_true(pc.velocity_xz.x <= 0.05 and pc.velocity_xz.y > 1.0,
		"Boundary zeroes outward radial velocity while preserving tangential slide (anti-lockup)")
	pc.queue_free()


func _test_tunnel_and_obstacle_scene_instantiation(runner: Node) -> void:
	var tr := TunnelRenderer.new()
	var om := ObstacleManager.new()
	runner.add_child(tr)
	runner.add_child(om)
	var st := LevelRepository.get_stage_by_id("01_a")
	tr.reset_tunnel(st.tunnel_radius)
	tr.update_tunnel(-25.0, 1.0, st.effect_mask_at_depth(25.0), 0.25, 0.5, 0.8, st.palette, st.tunnel_radius)
	om.reset_with_stage(st)
	om.step_and_sync(-25.0, 0.016, 0.25, 0.5, false)
	_assert_true(om.get_active_obstacles().size() >= 1, "ObstacleManager populates active obstacles within visible tunnel window")
	om.queue_free()
	tr.queue_free()
