extends CanvasLayer
## Post-impact Death / Stage Clear summary overlay showing Rank Grade, Rings Collected,
## instant Retry (R / Space), Next Stage (Enter), Watch Top Run, and Return to Editor.

var _modal_root: Control
var _panel: PanelContainer
var _title_lbl: Label
var _rank_lbl: Label
var _stats_lbl: Label
var _next_btn: Button
var _watch_btn: Button
var _editor_btn: Button
var _top_replay_id: String = ""


func _ready() -> void:
	layer = 30
	_build_ui()
	hide_overlay()


func show_death(summary: Dictionary) -> void:
	var obs_type := str(summary.get("obstacle_type", "obstacle")).to_upper().replace("_", " ")
	_title_lbl.text = "IMPACTED: %s" % obs_type
	_title_lbl.modulate = Color("fb7185")
	_populate_summary(summary, false)


func show_clear(summary: Dictionary) -> void:
	_title_lbl.text = "STAGE CLEARED!"
	_title_lbl.modulate = Color("22c55e")
	_populate_summary(summary, true)


func hide_overlay() -> void:
	if _modal_root != null:
		_modal_root.visible = false


func _populate_summary(summary: Dictionary, cleared: bool) -> void:
	var grade := str(summary.get("rank_grade", "C"))
	_rank_lbl.text = "RANK: %s" % grade
	match grade:
		"S+", "S":
			_rank_lbl.modulate = Color("facc15")
		"A":
			_rank_lbl.modulate = Color("14f1d9")
		"B":
			_rank_lbl.modulate = Color("38bdf8")
		_:
			_rank_lbl.modulate = Color("cbd5e1")

	_stats_lbl.text = (
		"Score: %d   |   Rings Collected: %d\n" +
		"Max Chain: %.1fx   |   Grazes: %d (NM: %d · DD: %d · DW: %d)\n" +
		"Depth: %.1fm   |   Time: %.2fs"
	) % [
		int(summary.get("score", 0)),
		int(summary.get("rings_collected", 0)),
		float(summary.get("max_chain", 1.0)),
		int(summary.get("total_grazes", 0)),
		int(summary.get("near_misses", 0)),
		int(summary.get("daredevils", 0)),
		int(summary.get("death_wishes", 0)),
		float(summary.get("depth", 0.0)),
		float(summary.get("duration_sec", 0.0)),
	]

	var session := get_parent()
	_top_replay_id = ""
	var has_next := false
	if session != null and session.stage != null:
		var lb := LevelRepository.get_stage_leaderboard(session.stage.id)
		if not lb.is_empty():
			_top_replay_id = str(lb[0].get("replay_id", ""))
		has_next = cleared and not LevelRepository.get_next_campaign_stage_id(session.stage.id).is_empty()

	_next_btn.visible = has_next
	_watch_btn.disabled = _top_replay_id.is_empty()
	_editor_btn.visible = session != null and session.scoring.mode == ScoringManager.MODE_EDITOR_TEST
	_modal_root.visible = true


func _build_ui() -> void:
	_modal_root = Control.new()
	_modal_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_root.theme = UITheme.build_neon_theme()
	add_child(_modal_root)

	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.01, 0.05, 0.65)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_root.add_child(scrim)

	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_root.add_child(holder)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(640, 355)
	holder.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	_title_lbl = Label.new()
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_font_size_override("font_size", 30)
	UITheme.apply_hud_text_outline(_title_lbl, 4)
	vbox.add_child(_title_lbl)

	_rank_lbl = Label.new()
	_rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rank_lbl.add_theme_font_size_override("font_size", 26)
	UITheme.apply_hud_text_outline(_rank_lbl, 4)
	vbox.add_child(_rank_lbl)

	_stats_lbl = Label.new()
	_stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_stats_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_row)

	_next_btn = Button.new()
	_next_btn.text = "Next Stage (Enter)"
	_next_btn.visible = false
	_next_btn.pressed.connect(func():
		var s := get_parent()
		if s != null and s.has_method("next_stage"):
			s.next_stage()
	)
	btn_row.add_child(_next_btn)

	var retry_btn := Button.new()
	retry_btn.text = "Retry (R / Space)"
	retry_btn.pressed.connect(func():
		var s := get_parent()
		if s != null and s.has_method("retry_run"):
			s.retry_run()
	)
	btn_row.add_child(retry_btn)

	_watch_btn = Button.new()
	_watch_btn.text = "Watch Top Run"
	_watch_btn.pressed.connect(func():
		if _top_replay_id.is_empty():
			return
		var res := LevelRepository.load_replay(_top_replay_id)
		var s := get_parent()
		if bool(res["ok"]) and s != null and s.stage != null:
			s.start_session({
				"stage_data": s.stage,
				"mode": ScoringManager.MODE_WATCH,
				"replay_data": res["replay"],
			})
	)
	btn_row.add_child(_watch_btn)

	_editor_btn = Button.new()
	_editor_btn.text = "Return to Editor"
	_editor_btn.pressed.connect(func():
		var s := get_parent()
		if s != null and s.has_method("return_to_editor"):
			s.return_to_editor()
	)
	btn_row.add_child(_editor_btn)

	var menu_btn := Button.new()
	menu_btn.text = "Main Menu"
	menu_btn.pressed.connect(func():
		var s := get_parent()
		if s != null and s.has_method("exit_to_menu"):
			s.exit_to_menu()
	)
	btn_row.add_child(menu_btn)
