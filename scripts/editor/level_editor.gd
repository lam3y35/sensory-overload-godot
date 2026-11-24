class_name LevelEditor
extends Control
## Interactive 3D Level Editor with 10 obstacle archetypes, 24-bit effect toggles,
## isolated obstacle animation preview, pre-save .bak backups, corruption-safe load guard,
## and "Play From Here" testing at the exact camera depth.

static var pending_stage: StageData = null
static var pending_depth: float = 0.0

var working_stage: StageData
var camera_depth: float = 10.0
var selected_obstacle_id: String = ""
var selected_section_idx: int = 0
var animate_preview: bool = true
var status_message: String = ""

# 3D Viewport nodes
var _vp_container: SubViewportContainer
var _viewport: SubViewport
var _tunnel_renderer: TunnelRenderer
var _obstacle_manager: ObstacleManager
var _editor_cam: Camera3D

# UI controls (populated cleanly in _build_ui)
var _status_label: Label
var _depth_label: Label
var _depth_slider: HSlider
var _title_edit: LineEdit
var _bpm_spin: SpinBox
var _speed_spin: SpinBox
var _mask_label: Label
var _obs_list: ItemList
var _effect_checks: Array[CheckBox] = []
var _prop_depth: SpinBox
var _prop_x: SpinBox
var _prop_z: SpinBox
var _prop_rx: SpinBox
var _prop_ry: SpinBox
var _prop_rz: SpinBox
var _prop_speed: SpinBox
var _prop_amp: SpinBox
var _prop_scale: SpinBox
var _prop_type: OptionButton
var _load_dialog: AcceptDialog
var _load_list: ItemList
var _syncing_ui: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.build_neon_theme()
	if pending_stage != null:
		working_stage = pending_stage.duplicate_stage()
		camera_depth = maxf(0.0, pending_depth)
		pending_stage = null
		pending_depth = 0.0
	else:
		create_new_stage()

	_build_ui()
	_refresh_all_ui()
	_sync_3d_preview(0.0)


func create_new_stage() -> void:
	working_stage = StageData.new()
	working_stage.id = "custom_%d" % int(Time.get_unix_time_from_system())
	working_stage.title = "Custom Sensory Drop"
	working_stage.author = "Pilot"
	working_stage.source = "custom"
	working_stage.bpm = 136.0
	working_stage.base_speed = 44.0
	working_stage.sections = [
		{"id": "sec_1", "length": 240.0, "effect_mask": (1 << 0) | (1 << 5) | (1 << 11), "transition_gap": 24.0},
	]
	working_stage.obstacles.clear()
	camera_depth = 0.0
	selected_section_idx = 0
	selected_obstacle_id = ""
	if _obstacle_manager != null:
		_obstacle_manager.reset_with_stage(working_stage)
	_set_status("Created new custom stage.")


func add_obstacle(obs_type: String, explicit_depth: float = -1.0) -> ObstacleData:
	if not ObstacleData.VALID_TYPES.has(obs_type):
		return null
	var obs := ObstacleData.new()
	obs.id = "obs_%d_%d" % [working_stage.obstacles.size() + 1, Time.get_ticks_usec() % 10000]
	obs.type = obs_type
	var target_depth := explicit_depth if explicit_depth >= 0.0 else clampf(camera_depth + 26.0, 5.0, working_stage.total_length() - 5.0)
	obs.depth = target_depth
	obs.section_index = working_stage.section_index_at_depth(target_depth)
	obs.seed_int = working_stage.obstacles.size() + 1
	working_stage.obstacles.append(obs)
	working_stage.sort_obstacles()
	selected_obstacle_id = obs.id
	_set_status("Added %s at %.1fm." % [obs.type, obs.depth])
	_refresh_all_ui()
	return obs


func get_selected_obstacle() -> ObstacleData:
	for obs in working_stage.obstacles:
		if obs.id == selected_obstacle_id:
			return obs
	return null


func update_selected_obstacle_field(field: String, val: Variant) -> bool:
	var obs := get_selected_obstacle()
	if obs == null:
		return false
	match field:
		"type":
			if ObstacleData.VALID_TYPES.has(str(val)):
				obs.type = str(val)
		"depth":
			obs.depth = clampf(float(val), 2.0, working_stage.total_length() - 2.0)
			working_stage.sort_obstacles()
		"offset_x":
			obs.offset_xz.x = clampf(float(val), -7.5, 7.5)
		"offset_z":
			obs.offset_xz.y = clampf(float(val), -7.5, 7.5)
		"rot_x":
			obs.rotation_deg.x = float(val)
		"rot_y":
			obs.rotation_deg.y = float(val)
		"rot_z":
			obs.rotation_deg.z = float(val)
		"speed":
			obs.speed = float(val)
		"amplitude":
			obs.amplitude = float(val)
		"scale_uniform":
			var s := clampf(float(val), 0.3, 2.5)
			obs.scale = Vector3(s, s, s)
		_:
			return false
	_refresh_obstacle_list()
	return true


func duplicate_selected_obstacle() -> ObstacleData:
	var src := get_selected_obstacle()
	if src == null:
		return null
	var copy := src.duplicate_data()
	copy.id = "obs_%d_%d" % [working_stage.obstacles.size() + 1, Time.get_ticks_usec() % 10000]
	copy.depth = clampf(src.depth + 22.0, 2.0, working_stage.total_length() - 2.0)
	working_stage.obstacles.append(copy)
	working_stage.sort_obstacles()
	selected_obstacle_id = copy.id
	_set_status("Duplicated %s at %.1fm." % [copy.type, copy.depth])
	_refresh_all_ui()
	return copy


func clear_obstacles() -> void:
	working_stage.obstacles.clear()
	selected_obstacle_id = ""
	_set_status("Cleared all obstacles.")
	_refresh_all_ui()


func delete_selected_obstacle() -> bool:
	for i in range(working_stage.obstacles.size()):
		if working_stage.obstacles[i].id == selected_obstacle_id:
			var removed_type := working_stage.obstacles[i].type
			working_stage.obstacles.remove_at(i)
			selected_obstacle_id = working_stage.obstacles[0].id if not working_stage.obstacles.is_empty() else ""
			_set_status("Deleted %s." % removed_type)
			_refresh_all_ui()
			return true
	return false


func toggle_effect_bit(bit: int, enabled: bool) -> void:
	if selected_section_idx < 0 or selected_section_idx >= working_stage.sections.size():
		return
	var sec := working_stage.sections[selected_section_idx]
	var mask := EffectCatalog.set_effect(int(sec.get("effect_mask", 0)), bit, enabled)
	sec["effect_mask"] = mask
	working_stage.sections[selected_section_idx] = sec
	_refresh_mask_label()


func save_stage(publish_community: bool = false) -> Dictionary:
	working_stage.source = "custom"
	var res := LevelRepository.save_custom_stage(working_stage)
	if bool(res["ok"]):
		var bak := str(res.get("backup_path", ""))
		var verb := "Published" if publish_community else "Saved"
		_set_status("%s '%s'%s" % [verb, working_stage.title, " (backup created)" if not bak.is_empty() else ""])
	else:
		_set_status("Save failed: " + str(res.get("error", "unknown")))
	return res


func load_stage_by_id(stage_id: String) -> Dictionary:
	var res := LevelRepository.load_custom_stage(stage_id)
	if not bool(res["ok"]):
		_set_status("Load aborted (data preserved): " + str(res.get("error", "")))
		return res
	working_stage = res["stage"] as StageData
	camera_depth = 0.0
	selected_section_idx = 0
	selected_obstacle_id = working_stage.obstacles[0].id if not working_stage.obstacles.is_empty() else ""
	if _obstacle_manager != null:
		_obstacle_manager.reset_with_stage(working_stage)
	_set_status("Loaded '%s' (%d obstacles)." % [working_stage.title, working_stage.obstacles.size()])
	_refresh_all_ui()
	return res


func build_play_from_here_params() -> Dictionary:
	pending_stage = working_stage.duplicate_stage()
	pending_depth = camera_depth
	return {
		"stage_data": working_stage.duplicate_stage(),
		"mode": ScoringManager.MODE_EDITOR_TEST,
		"start_depth": camera_depth,
		"return_to_editor": true,
	}


func play_from_here() -> void:
	var params := build_play_from_here_params()
	GameSession.set_launch_context(params)
	get_tree().change_scene_to_file("res://scenes/game_session.tscn")


func _process(delta: float) -> void:
	if Input.is_action_pressed("move_up"):
		_scrub_depth(-45.0 * delta)
	elif Input.is_action_pressed("move_down"):
		_scrub_depth(45.0 * delta)
	_sync_3d_preview(delta if animate_preview else 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("editor_play_here"):
		play_from_here()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scrub_depth(10.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scrub_depth(-10.0)


func _scrub_depth(delta_m: float) -> void:
	camera_depth = clampf(camera_depth + delta_m, 0.0, maxf(10.0, working_stage.total_length() - 10.0))
	if _depth_slider != null:
		_syncing_ui = true
		_depth_slider.value = camera_depth
		_syncing_ui = false
	if _depth_label != null:
		_depth_label.text = "Depth: %.1f / %.0fm" % [camera_depth, working_stage.total_length()]


func _sync_3d_preview(delta: float) -> void:
	if _editor_cam == null or _tunnel_renderer == null or _obstacle_manager == null:
		return
	var player_y := -camera_depth
	_editor_cam.position = Vector3(0.0, player_y, 0.0)
	var sec := working_stage.sections[clampi(selected_section_idx, 0, working_stage.sections.size() - 1)]
	var mask := int(sec.get("effect_mask", 0))
	var beat_ph := fmod(_obstacle_manager.local_time * (working_stage.bpm / 60.0), 1.0)
	_tunnel_renderer.update_tunnel(
		player_y,
		_obstacle_manager.local_time,
		mask,
		beat_ph,
		0.3,
		0.0,
		working_stage.palette,
		working_stage.tunnel_radius
	)
	_obstacle_manager.set_highlight_obstacle(selected_obstacle_id)
	_obstacle_manager.step_and_sync(player_y, delta, beat_ph, 0.3, false)


func _set_status(msg: String) -> void:
	status_message = msg
	if _status_label != null:
		_status_label.text = msg


func _build_ui() -> void:
	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_vbox)

	# Top Toolbar
	var toolbar := PanelContainer.new()
	var tb_hbox := HBoxContainer.new()
	toolbar.add_child(tb_hbox)
	root_vbox.add_child(toolbar)

	var buttons := [
		["New", func(): create_new_stage(); _refresh_all_ui()],
		["Load Custom", func(): _open_load_dialog()],
		["Save (.bak)", func(): save_stage(false)],
		["Publish Community", func(): save_stage(true)],
		["Play From Here (P)", func(): play_from_here()],
		["Back to Menu", func(): AudioSyncManager.stop_music(); get_tree().change_scene_to_file("res://scenes/main_menu.tscn")],
	]
	for b_info in buttons:
		var btn := Button.new()
		btn.text = str(b_info[0])
		btn.pressed.connect(b_info[1])
		tb_hbox.add_child(btn)

	var anim_chk := CheckButton.new()
	anim_chk.text = "Animate"
	anim_chk.button_pressed = animate_preview
	anim_chk.toggled.connect(func(on: bool): animate_preview = on)
	tb_hbox.add_child(anim_chk)

	_depth_label = Label.new()
	_depth_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_depth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tb_hbox.add_child(_depth_label)

	# Main 3-Column Body
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(body)

	# Left Panel (Metadata + 10 Obstacles + 24 Effects)
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(340, 0)
	body.add_child(left_scroll)
	var left_box := VBoxContainer.new()
	left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(left_box)

	var meta_hdr := Label.new()
	meta_hdr.text = "STAGE METADATA"
	left_box.add_child(meta_hdr)

	_title_edit = LineEdit.new()
	_title_edit.placeholder_text = "Stage Title"
	_title_edit.text_changed.connect(func(t: String): working_stage.title = t)
	left_box.add_child(_title_edit)

	var speed_row := HBoxContainer.new()
	left_box.add_child(speed_row)
	var sl := Label.new(); sl.text = "Speed:"
	_speed_spin = SpinBox.new(); _speed_spin.min_value = 15.0; _speed_spin.max_value = 110.0; _speed_spin.step = 1.0
	_speed_spin.value_changed.connect(func(v: float): if not _syncing_ui: working_stage.base_speed = v)
	var bl := Label.new(); bl.text = "BPM:"
	_bpm_spin = SpinBox.new(); _bpm_spin.min_value = 80.0; _bpm_spin.max_value = 200.0; _bpm_spin.step = 1.0
	_bpm_spin.value_changed.connect(func(v: float): if not _syncing_ui: working_stage.bpm = v)
	speed_row.add_child(sl); speed_row.add_child(_speed_spin); speed_row.add_child(bl); speed_row.add_child(_bpm_spin)

	var pal_hdr := Label.new()
	pal_hdr.text = "\nADD OBSTACLE (10 ARCHETYPES)"
	left_box.add_child(pal_hdr)

	var grid := GridContainer.new()
	grid.columns = 2
	left_box.add_child(grid)
	for t_name in ObstacleData.VALID_TYPES:
		var ob := Button.new()
		ob.text = "+ " + t_name
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ob.pressed.connect(func(): add_obstacle(t_name))
		grid.add_child(ob)

	var eff_hdr := Label.new()
	eff_hdr.text = "\n24-BIT EFFECTS (16.7M COMBOS)"
	left_box.add_child(eff_hdr)
	_mask_label = Label.new()
	left_box.add_child(_mask_label)

	_effect_checks.clear()
	for eff in EffectCatalog.EFFECTS:
		var cb := CheckBox.new()
		var bit := int(eff["bit"])
		cb.text = "[%02d] %s" % [bit, str(eff["label"])]
		cb.toggled.connect(func(on: bool): if not _syncing_ui: toggle_effect_bit(bit, on))
		left_box.add_child(cb)
		_effect_checks.append(cb)
	var pad_spacer := Control.new()
	pad_spacer.custom_minimum_size = Vector2(0, 18)
	left_box.add_child(pad_spacer)

	# Center 3D Viewport + Depth Scrubber
	var center_box := VBoxContainer.new()
	center_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(center_box)

	_vp_container = SubViewportContainer.new()
	_vp_container.stretch = true
	_vp_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vp_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_box.add_child(_vp_container)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp_container.add_child(_viewport)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	TunnelRenderer.apply_cinema_environment(env, Color("070410"))
	we.environment = env
	_viewport.add_child(we)

	_tunnel_renderer = TunnelRenderer.new()
	_viewport.add_child(_tunnel_renderer)
	_obstacle_manager = ObstacleManager.new()
	_obstacle_manager.reset_with_stage(working_stage)
	_viewport.add_child(_obstacle_manager)

	_editor_cam = Camera3D.new()
	_editor_cam.far = 220.0
	_editor_cam.fov = 80.0
	_editor_cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_viewport.add_child(_editor_cam)

	_depth_slider = HSlider.new()
	_depth_slider.min_value = 0.0
	_depth_slider.max_value = 240.0
	_depth_slider.step = 0.5
	_depth_slider.value_changed.connect(func(v: float):
		if not _syncing_ui:
			camera_depth = v
			_scrub_depth(0.0)
	)
	center_box.add_child(_depth_slider)

	# Right Panel (Obstacle List + Selected Properties)
	var right_scroll := ScrollContainer.new()
	right_scroll.custom_minimum_size = Vector2(330, 0)
	body.add_child(right_scroll)
	var right_box := VBoxContainer.new()
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(right_box)

	var list_hdr := Label.new()
	list_hdr.text = "PLACED OBSTACLES"
	right_box.add_child(list_hdr)

	_obs_list = ItemList.new()
	_obs_list.custom_minimum_size = Vector2(0, 210)
	_obs_list.item_selected.connect(func(idx: int):
		if idx >= 0 and idx < working_stage.obstacles.size():
			selected_obstacle_id = working_stage.obstacles[idx].id
			camera_depth = maxf(0.0, working_stage.obstacles[idx].depth - 22.0)
			_scrub_depth(0.0)
			_refresh_inspector()
	)
	right_box.add_child(_obs_list)

	var prop_hdr := Label.new()
	prop_hdr.text = "\nSELECTED OBSTACLE"
	right_box.add_child(prop_hdr)

	_prop_type = OptionButton.new()
	for t_name in ObstacleData.VALID_TYPES:
		_prop_type.add_item(t_name)
	_prop_type.item_selected.connect(func(idx: int):
		if not _syncing_ui:
			update_selected_obstacle_field("type", ObstacleData.VALID_TYPES[idx])
	)
	right_box.add_child(_prop_type)

	_prop_depth = _add_prop_spin(right_box, "Depth (m)", 2.0, 2000.0, 1.0, func(v: float): update_selected_obstacle_field("depth", v))
	_prop_x = _add_prop_spin(right_box, "Offset X", -7.5, 7.5, 0.25, func(v: float): update_selected_obstacle_field("offset_x", v))
	_prop_z = _add_prop_spin(right_box, "Offset Z", -7.5, 7.5, 0.25, func(v: float): update_selected_obstacle_field("offset_z", v))
	_prop_rx = _add_prop_spin(right_box, "Rot X (deg)", -180.0, 180.0, 5.0, func(v: float): update_selected_obstacle_field("rot_x", v))
	_prop_ry = _add_prop_spin(right_box, "Rot Y (deg)", -180.0, 180.0, 5.0, func(v: float): update_selected_obstacle_field("rot_y", v))
	_prop_rz = _add_prop_spin(right_box, "Rot Z (deg)", -180.0, 180.0, 5.0, func(v: float): update_selected_obstacle_field("rot_z", v))
	_prop_speed = _add_prop_spin(right_box, "Anim Speed", -5.0, 5.0, 0.1, func(v: float): update_selected_obstacle_field("speed", v))
	_prop_amp = _add_prop_spin(right_box, "Amplitude", 0.0, 3.0, 0.1, func(v: float): update_selected_obstacle_field("amplitude", v))
	_prop_scale = _add_prop_spin(right_box, "Scale", 0.3, 2.5, 0.05, func(v: float): update_selected_obstacle_field("scale_uniform", v))

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	right_box.add_child(btn_row)

	var dup_btn := Button.new()
	dup_btn.text = "Duplicate"
	dup_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dup_btn.pressed.connect(func(): duplicate_selected_obstacle())
	btn_row.add_child(dup_btn)

	var del_btn := Button.new()
	del_btn.text = "Delete"
	del_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	del_btn.pressed.connect(func(): delete_selected_obstacle())
	btn_row.add_child(del_btn)

	var clr_btn := Button.new()
	clr_btn.text = "Clear All Obstacles"
	clr_btn.pressed.connect(func(): clear_obstacles())
	right_box.add_child(clr_btn)

	# Bottom Status Bar
	_status_label = Label.new()
	_status_label.text = status_message
	root_vbox.add_child(_status_label)

	# Load Dialog
	_load_dialog = AcceptDialog.new()
	_load_dialog.title = "Load Custom Stage"
	_load_list = ItemList.new()
	_load_list.custom_minimum_size = Vector2(360, 220)
	_load_dialog.add_child(_load_list)
	_load_dialog.confirmed.connect(func():
		var sel := _load_list.get_selected_items()
		if not sel.is_empty():
			var sid := str(_load_list.get_item_metadata(sel[0]))
			load_stage_by_id(sid)
	)
	add_child(_load_dialog)


func _add_prop_spin(parent: Control, label_txt: String, mn: float, mx: float, st: float, cb: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_txt
	lbl.custom_minimum_size = Vector2(110, 0)
	var sp := SpinBox.new()
	sp.min_value = mn
	sp.max_value = mx
	sp.step = st
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.value_changed.connect(func(v: float): if not _syncing_ui: cb.call(v))
	row.add_child(lbl)
	row.add_child(sp)
	parent.add_child(row)
	return sp


func _open_load_dialog() -> void:
	_load_list.clear()
	for st in LevelRepository.list_custom_stages():
		if st.source == "custom":
			var idx := _load_list.add_item("%s (%d obs)" % [st.title, st.obstacles.size()])
			_load_list.set_item_metadata(idx, st.id)
	_load_dialog.popup_centered()


func _refresh_all_ui() -> void:
	if _title_edit == null:
		return
	_syncing_ui = true
	_title_edit.text = working_stage.title
	_speed_spin.value = working_stage.base_speed
	_bpm_spin.value = working_stage.bpm
	_depth_slider.max_value = maxf(40.0, working_stage.total_length() - 10.0)
	_depth_slider.value = camera_depth
	_depth_label.text = "Depth: %.1f / %.0fm" % [camera_depth, working_stage.total_length()]
	var sec_mask := int(working_stage.sections[clampi(selected_section_idx, 0, working_stage.sections.size() - 1)].get("effect_mask", 0))
	for i in range(mini(_effect_checks.size(), EffectCatalog.TOTAL_BITS)):
		_effect_checks[i].button_pressed = EffectCatalog.has_effect(sec_mask, i)
	_syncing_ui = false
	_refresh_mask_label()
	_refresh_obstacle_list()


func _refresh_mask_label() -> void:
	if _mask_label == null:
		return
	var sec_mask := int(working_stage.sections[clampi(selected_section_idx, 0, working_stage.sections.size() - 1)].get("effect_mask", 0))
	_mask_label.text = "Mask: 0x%06X (%d/24 active)" % [sec_mask, EffectCatalog.count_effects(sec_mask)]


func _refresh_obstacle_list() -> void:
	if _obs_list == null:
		return
	_obs_list.clear()
	for i in range(working_stage.obstacles.size()):
		var o := working_stage.obstacles[i]
		_obs_list.add_item("%.1fm — %s" % [o.depth, o.type])
		if o.id == selected_obstacle_id:
			_obs_list.select(i)
	_refresh_inspector()


func _refresh_inspector() -> void:
	if _prop_depth == null:
		return
	var obs := get_selected_obstacle()
	_syncing_ui = true
	if obs != null:
		_prop_type.select(Array(ObstacleData.VALID_TYPES).find(obs.type))
		_prop_depth.value = obs.depth
		_prop_x.value = obs.offset_xz.x
		_prop_z.value = obs.offset_xz.y
		_prop_rx.value = obs.rotation_deg.x
		_prop_ry.value = obs.rotation_deg.y
		_prop_rz.value = obs.rotation_deg.z
		_prop_speed.value = obs.speed
		_prop_amp.value = obs.amplitude
		_prop_scale.value = obs.scale.x
	_syncing_ui = false
