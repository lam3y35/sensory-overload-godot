extends Node
## Live GPU Player QA Harness capturing rendered PNG screenshots and quantitative
## playtest telemetry across all menus, modes, obstacles, editor, replays, shaders, and aspect ratios.

const DEFAULT_OUT_DIR := "res://qa_screenshots/before/"
const SANDBOX_ROOT := "user://qa_sandbox/"

var _out_dir: String = DEFAULT_OUT_DIR
var _metrics: Dictionary = {
	"driver": "",
	"fps_samples": {},
	"obstacle_motion_deltas": {},
	"checks": {},
	"ui_overlap_warnings": [],
	"notes": [],
}


func _ready() -> void:
	call_deferred("_run_qa")


func _run_qa() -> void:
	_clear_sandbox()
	SettingsManager.set_config_path(SANDBOX_ROOT + "settings.cfg")
	SaveManager.set_storage_root(SANDBOX_ROOT)
	LevelRepository.set_storage_root(SANDBOX_ROOT)

	var adapter := RenderingServer.get_video_adapter_name()
	var user_args := OS.get_cmdline_user_args()
	for arg in user_args:
		if arg.begins_with("--out-dir="):
			var sub := arg.trim_prefix("--out-dir=").strip_edges().validate_filename()
			if not sub.is_empty():
				_out_dir = "res://qa_screenshots/" + sub + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	_metrics["driver"] = adapter

	if user_args.has("--compat-only"):
		await _capture_compat_mode()
		_finish_and_quit()
		return

	await _capture_menus()
	await _capture_gameplay_and_modes()
	await _capture_level_editor()
	await _capture_all_ten_obstacles_and_hitboxes()
	await _capture_ultrawide()
	_save_metrics()
	_finish_and_quit()


func _snap(filename: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(_out_dir).path_join(filename)
	var err := img.save_png(abs_path)
	if err != OK:
		printerr("QA Failed saving PNG %s (err=%d)" % [abs_path, err])
	else:
		print("QA Captured: " + filename + " (%dx%d)" % [img.get_width(), img.get_height()])


func _await_seconds(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().process_frame
		t += maxf(0.001, get_process_delta_time())


func _capture_compat_mode() -> void:
	var gs_scene := load("res://scenes/game_session.tscn") as PackedScene
	var gs := gs_scene.instantiate() as GameSession
	add_child(gs)
	gs.start_session({"stage_id": "06_a", "mode": ScoringManager.MODE_ZEN})
	await _await_seconds(0.65)
	_metrics["fps_samples"]["opengl3_compat"] = Engine.get_frames_per_second()
	await _snap("19_opengl3_compatibility.png")
	gs.queue_free()
	await get_tree().process_frame


func _capture_menus() -> void:
	var menu_scene := load("res://scenes/main_menu.tscn") as PackedScene
	var menu := menu_scene.instantiate()
	add_child(menu)
	await _await_seconds(0.45)
	_check_control_overlaps("MainMenu", menu)
	await _snap("01_main_menu.png")

	# 02 - Level Select (select 02_a Vertigo)
	var ls: LevelSelect = menu._level_select
	ls.open_browser(false, ScoringManager.MODE_NORMAL)
	var st_list: ItemList = ls._stage_list
	var target_idx := 0
	for i in range(ls._stages.size()):
		if ls._stages[i].id == "02_a":
			target_idx = i
			break
	st_list.select(target_idx)
	ls._select_index(target_idx)
	await _await_seconds(1.2)
	_check_control_overlaps("LevelSelect", ls)
	await _snap("02_level_select.png")
	ls.visible = false

	# 03 - Settings & Accessibility tab
	var sm: SettingsMenu = menu._settings_menu
	sm.visible = true
	sm._tabs.current_tab = 1 # Accessibility tab
	await _await_seconds(0.25)
	_check_control_overlaps("SettingsAccessibility", sm)
	await _snap("03_settings_accessibility.png")
	sm.visible = false

	# 04 - Achievements Menu (unlock 2 realistic achievements first)
	SaveManager.unlock_achievement("FIRST_DESCENT")
	SaveManager.unlock_achievement("FIRST_DEATHWISH")
	var am: AchievementsMenu = menu._ach_menu
	am.refresh()
	am.visible = true
	await _await_seconds(0.2)
	_check_control_overlaps("AchievementsMenu", am)
	await _snap("04_achievements.png")
	am.visible = false

	menu.queue_free()
	await get_tree().process_frame


func _capture_gameplay_and_modes() -> void:
	var gs_scene := load("res://scenes/game_session.tscn") as PackedScene
	var gs := gs_scene.instantiate() as GameSession
	add_child(gs)

	# 05 - Normal Mode Gameplay (stage 01_a)
	gs.start_session({"stage_id": "01_a", "mode": ScoringManager.MODE_NORMAL})
	await _await_seconds(0.45)
	_metrics["fps_samples"]["normal_01_a"] = Engine.get_frames_per_second()
	await _snap("05_normal_gameplay.png")

	# 06 - Graze Popup, Flow Color Lock & Hyper-Boost streaks
	gs.boost_override = 1
	for i in range(6):
		gs.scoring.register_graze("qa_g_%d" % i, SweptCollision.TIER_DEATH_WISH, false)
	await _await_seconds(0.18)
	_metrics["checks"]["graze_flow_locked"] = gs.scoring.color_locked
	_metrics["checks"]["graze_score"] = gs.scoring.score
	await _snap("06_graze_and_flow.png")
	gs.boost_override = -1

	# 07 - Steer toward origin into first obstacle until IMPACT_FREEZE
	gs.player.reset_at(44.0, Vector2.ZERO)
	var hit_seen := false
	var ticks := 0
	while ticks < 240:
		await get_tree().process_frame
		ticks += 1
		if gs.state == GameSession.SessionState.IMPACT_FREEZE:
			hit_seen = true
			break
	_metrics["checks"]["hit_triggered_freeze"] = hit_seen
	if hit_seen:
		gs.set_process(false)
		gs.set_physics_process(false)
		await _snap("07_impact_freeze.png")
		gs.set_process(true)
		gs.set_physics_process(true)
		await _await_seconds(0.45)
	_metrics["checks"]["dead_state_reached"] = (gs.state == GameSession.SessionState.DEAD)
	await _snap("08_death_overlay.png")

	# 09 - Pause Menu
	gs.retry_run()
	await _await_seconds(0.25)
	gs.pause_game()
	await _await_seconds(0.15)
	await _snap("09_pause_menu.png")
	gs.resume_game()

	# 10 - High Chaos Ranked Sensory Overload (06_c) in live moving flight
	gs.start_session({"stage_id": "06_c", "mode": ScoringManager.MODE_RANKED})
	await _await_seconds(0.75)
	_metrics["fps_samples"]["ranked_06_c"] = Engine.get_frames_per_second()
	await _snap("10_sensory_overload_fx.png")

	# 11 - Practice Mode Checkpoint & Zen Section Check
	gs.start_session({"stage_id": "02_a", "mode": ScoringManager.MODE_PRACTICE})
	await _await_seconds(0.8)
	gs.scoring.set_checkpoint(-gs.player.position_3d.y, Vector2(gs.player.position_3d.x, gs.player.position_3d.z))
	await _await_seconds(0.15)
	_metrics["checks"]["practice_checkpoint_active"] = gs.scoring.practice_checkpoint_active
	await _snap("11_practice_checkpoint.png")

	# Quick Zen verification pass
	gs.start_session({"stage_id": "01_a", "mode": ScoringManager.MODE_ZEN})
	gs.player.reset_at(120.0, Vector2.ZERO)
	await _await_seconds(1.5)
	_metrics["checks"]["zen_alive_and_advancing"] = (gs.state == GameSession.SessionState.PLAYING or gs.state == GameSession.SessionState.CLEARED)

	# 12 - Replay Recording & Live WATCH Playback
	gs.start_session({"stage_id": "01_a", "mode": ScoringManager.MODE_RANKED})
	gs.player.reset_at(0.0, Vector2(3.5, 0.0))
	await _await_seconds(1.4)
	var sum := gs.scoring.build_summary(-gs.player.position_3d.y, gs.elapsed_time, false)
	var rep_id: String = gs.replay_controller.finish_and_submit(gs.stage, sum, false)
	var rep_load := LevelRepository.load_replay(rep_id)
	_metrics["checks"]["replay_saved_and_loaded"] = bool(rep_load["ok"])
	if bool(rep_load["ok"]):
		gs.start_session({
			"stage_data": gs.stage,
			"mode": ScoringManager.MODE_WATCH,
			"replay_data": rep_load["replay"],
		})
		await _await_seconds(0.6)
		_metrics["checks"]["watch_active"] = gs.replay_controller.is_watching
	await _snap("12_watch_replay.png")

	# 13 - All Hallows (07_c Maw of Midnight)
	gs.start_session({"stage_id": "07_c", "mode": ScoringManager.MODE_ZEN})
	await _await_seconds(0.75)
	_metrics["fps_samples"]["all_hallows_07_c"] = Engine.get_frames_per_second()
	await _snap("13_all_hallows.png")

	gs.queue_free()
	await get_tree().process_frame


func _capture_level_editor() -> void:
	var ed_scene := load("res://scenes/level_editor.tscn") as PackedScene
	var ed := ed_scene.instantiate() as LevelEditor
	add_child(ed)
	await _await_seconds(0.2)
	ed.create_new_stage()
	ed.working_stage.id = "qa_editor_map"
	ed.working_stage.title = "QA Editor Drop"
	ed.add_obstacle("waffle", 30.0)
	ed.add_obstacle("pendulum", 52.0)
	ed.add_obstacle("tumbling_cube", 74.0)
	ed.toggle_effect_bit(0, true)
	ed.toggle_effect_bit(1, true)
	ed.toggle_effect_bit(6, true)
	ed.toggle_effect_bit(12, true)
	ed.camera_depth = 8.0
	ed._refresh_all_ui()
	await _await_seconds(0.45)
	var save_res := ed.save_stage(true)
	_metrics["checks"]["editor_save_ok"] = bool(save_res["ok"])
	_check_control_overlaps("LevelEditor", ed)
	await _snap("14_level_editor.png")
	ed.queue_free()
	await get_tree().process_frame


func _capture_all_ten_obstacles_and_hitboxes() -> void:
	# Compute motion deltas for all 10 archetypes between t=0.0 and t=0.75
	for otype in ObstacleData.VALID_TYPES:
		var o := ObstacleData.new()
		o.id = "delta_" + otype
		o.type = otype
		o.depth = 50.0
		o.speed = 1.2
		o.amplitude = 1.0
		var p_a := ObstacleManager.compute_parts(o, 0.0, 0.0)
		var p_b := ObstacleManager.compute_parts(o, 0.75, 0.45)
		var max_pos_delta := 0.0
		var max_rot_delta := 0.0
		for i in range(mini(p_a.size(), p_b.size())):
			var xf_a := p_a[i]["transform"] as Transform3D
			var xf_b := p_b[i]["transform"] as Transform3D
			max_pos_delta = maxf(max_pos_delta, xf_a.origin.distance_to(xf_b.origin))
			var qa := xf_a.basis.get_rotation_quaternion()
			var qb := xf_b.basis.get_rotation_quaternion()
			max_rot_delta = maxf(max_rot_delta, qa.angle_to(qb))
		_metrics["obstacle_motion_deltas"][otype] = {
			"parts": p_a.size(),
			"max_pos_delta_m": snappedf(max_pos_delta, 0.001),
			"max_rot_delta_rad": snappedf(max_rot_delta, 0.001),
		}

	# Visual 5-up grids showing rendered obstacle meshes + translucent green OBB hitbox overlays
	await _render_obstacle_grid(ObstacleData.VALID_TYPES.slice(0, 5), "15_obstacles_1_to_5.png", 0.55)
	await _render_obstacle_grid(ObstacleData.VALID_TYPES.slice(5, 10), "16_obstacles_6_to_10.png", 0.55)

	# Side-by-side Pendulum t=0.0 vs t=0.75 motion check
	await _render_pendulum_motion_comparison("17_pendulum_motion_check.png")


func _render_obstacle_grid(types: PackedStringArray, filename: String, eval_time: float) -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var bg := ColorRect.new()
	bg.color = Color("0b0516")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	root.add_child(grid)

	var obb_mat := StandardMaterial3D.new()
	obb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	obb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	obb_mat.albedo_color = Color(0.1, 1.0, 0.25, 0.36)
	obb_mat.no_depth_test = false

	var obs_shader := load("res://shaders/obstacle_painted.gdshader") as Shader
	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE

	for otype in types:
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)

		var vpc := SubViewportContainer.new()
		vpc.stretch = true
		vpc.set_anchors_preset(Control.PRESET_FULL_RECT)
		cell.add_child(vpc)

		var vp := SubViewport.new()
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vpc.add_child(vp)

		var we := WorldEnvironment.new()
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color("110826")
		we.environment = env
		vp.add_child(we)

		var cam := Camera3D.new()
		cam.fov = 85.0
		cam.position = Vector3(0.0, -24.0, 0.0)
		cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		vp.add_child(cam)

		var obs := ObstacleData.new()
		obs.id = "qa_" + otype
		obs.type = otype
		obs.depth = 42.0
		obs.speed = 1.2
		obs.amplitude = 1.0
		obs.seed_int = 2
		var parts := ObstacleManager.compute_parts(obs, eval_time, 0.25)

		for p in parts:
			var xf := p["transform"] as Transform3D
			var he := p["half_extents"] as Vector3
			# Visual Mesh
			var mi := MeshInstance3D.new()
			mi.mesh = unit_box
			var sm := ShaderMaterial.new()
			sm.shader = obs_shader
			sm.set_shader_parameter("u_color_primary", obs.color_primary)
			sm.set_shader_parameter("u_color_accent", obs.color_accent)
			mi.material_override = sm
			mi.transform = Transform3D(xf.basis.scaled_local(he * 2.0), xf.origin)
			vp.add_child(mi)

			# Green OBB Overlay slightly expanded by 0.04m so wireframe/box overlay shows exact alignment
			var hit_mi := MeshInstance3D.new()
			hit_mi.mesh = unit_box
			hit_mi.material_override = obb_mat
			hit_mi.transform = Transform3D(xf.basis.scaled_local((he + Vector3.ONE * 0.04) * 2.0), xf.origin)
			vp.add_child(hit_mi)

		var lbl := Label.new()
		lbl.text = " %s (%d OBBs)" % [otype.to_upper(), parts.size()]
		lbl.add_theme_font_size_override("font_size", 18)
		lbl.modulate = Color("14f1d9")
		cell.add_child(lbl)

	await _await_seconds(0.15)
	await _snap(filename)
	root.queue_free()
	await get_tree().process_frame


func _render_pendulum_motion_comparison(filename: String) -> void:
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	var obs_shader := load("res://shaders/obstacle_painted.gdshader") as Shader
	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE

	for t_val in [0.0, 0.75]:
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root.add_child(cell)

		var vpc := SubViewportContainer.new()
		vpc.stretch = true
		vpc.set_anchors_preset(Control.PRESET_FULL_RECT)
		cell.add_child(vpc)

		var vp := SubViewport.new()
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vpc.add_child(vp)

		var we := WorldEnvironment.new()
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color("110826")
		we.environment = env
		vp.add_child(we)

		var cam := Camera3D.new()
		cam.fov = 82.0
		cam.position = Vector3(0.0, -24.0, 0.0)
		cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		vp.add_child(cam)

		var obs := ObstacleData.new()
		obs.id = "pend_check"
		obs.type = "pendulum"
		obs.depth = 42.0
		obs.speed = 1.2
		obs.amplitude = 1.0
		var parts := ObstacleManager.compute_parts(obs, t_val, 0.0)
		for p in parts:
			var xf := p["transform"] as Transform3D
			var he := p["half_extents"] as Vector3
			var mi := MeshInstance3D.new()
			mi.mesh = unit_box
			var sm := ShaderMaterial.new()
			sm.shader = obs_shader
			mi.material_override = sm
			mi.transform = Transform3D(xf.basis.scaled_local(he * 2.0), xf.origin)
			vp.add_child(mi)

		var lbl := Label.new()
		lbl.text = " PENDULUM at t = %.2fs" % t_val
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.modulate = Color("facc15")
		cell.add_child(lbl)

	await _await_seconds(0.15)
	await _snap(filename)
	root.queue_free()
	await get_tree().process_frame


func _capture_ultrawide() -> void:
	DisplayServer.window_set_size(Vector2i(1680, 720))
	var gs_scene := load("res://scenes/game_session.tscn") as PackedScene
	var gs := gs_scene.instantiate() as GameSession
	add_child(gs)
	gs.start_session({"stage_id": "01_c", "mode": ScoringManager.MODE_NORMAL})
	await _await_seconds(0.5)
	await _snap("18_ultrawide_hud.png")
	gs.queue_free()
	await get_tree().process_frame


func _check_control_overlaps(screen_name: String, root_ctrl: Control) -> void:
	var btns: Array[Control] = []
	_collect_visible_buttons(root_ctrl, btns)
	for i in range(btns.size()):
		var ra := btns[i].get_global_rect()
		if ra.size.x <= 1.0 or ra.size.y <= 1.0:
			continue
		for j in range(i + 1, btns.size()):
			var rb := btns[j].get_global_rect()
			if rb.size.x <= 1.0 or rb.size.y <= 1.0:
				continue
			if ra.intersects(rb):
				_metrics["ui_overlap_warnings"].append("%s: '%s' overlaps '%s'" % [screen_name, btns[i].name, btns[j].name])


func _collect_visible_buttons(node: Node, out: Array[Control]) -> void:
	if node is Control:
		var c := node as Control
		if not c.visible:
			return
		if c is BaseButton:
			out.append(c)
	for child in node.get_children():
		_collect_visible_buttons(child, out)


func _save_metrics() -> void:
	var path := _out_dir.path_join("qa_metrics.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_metrics, "\t"))


func _finish_and_quit() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioSyncManager.stop_music()
	get_tree().quit(0)


func _clear_sandbox() -> void:
	var abs_root := ProjectSettings.globalize_path(SANDBOX_ROOT)
	if DirAccess.dir_exists_absolute(abs_root):
		_rm_dir_recursive(abs_root)
	DirAccess.make_dir_recursive_absolute(abs_root)


func _rm_dir_recursive(abs_path: String) -> void:
	var dir := DirAccess.open(abs_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var item := dir.get_next()
	while not item.is_empty():
		var child := abs_path.path_join(item)
		if dir.current_is_dir():
			_rm_dir_recursive(child)
			DirAccess.remove_absolute(child)
		else:
			DirAccess.remove_absolute(child)
		item = dir.get_next()
	dir.list_dir_end()
