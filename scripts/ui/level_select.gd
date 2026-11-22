class_name LevelSelect
extends Control
## Campaign (7 Levels / 21 Stages) & Community Maps Browser featuring:
## - Isolated live 3D LevelPreviewViewport
## - Mode selector (Normal / Ranked / Zen / Practice)
## - Per-map isolated stats & stage leaderboards with working WATCH replay button

signal closed()

var _is_community_tab: bool = false
var _selected_mode: String = ScoringManager.MODE_NORMAL
var _stages: Array[StageData] = []
var _selected_stage: StageData = null

var _stage_list: ItemList
var _preview_vp: LevelPreviewViewport
var _info_lbl: Label
var _stats_lbl: Label
var _lb_container: VBoxContainer
var _launch_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.build_neon_theme()
	_build_ui()


func open_browser(community_tab: bool = false, default_mode: String = ScoringManager.MODE_NORMAL) -> void:
	_is_community_tab = community_tab
	_selected_mode = default_mode
	visible = true
	_reload_stage_list()


func _reload_stage_list() -> void:
	_stage_list.clear()
	_stages = LevelRepository.list_custom_stages() if _is_community_tab else LevelRepository.get_campaign_stages()
	for i in range(_stages.size()):
		var st := _stages[i]
		var unlocked := _is_community_tab or SaveManager.is_stage_unlocked(st.id) or _selected_mode == ScoringManager.MODE_ZEN
		var cleared := SaveManager.cleared_stage_ids.has(st.id)
		var tag := "[CLEAR]" if cleared else ("[OPEN]" if unlocked else "[LOCKED]")
		_stage_list.add_item("%s %s — %s (%.0f m/s)" % [tag, st.stage_code, st.title, st.base_speed])

	if not _stages.is_empty():
		_stage_list.select(0)
		_select_index(0)


func _select_index(idx: int) -> void:
	if idx < 0 or idx >= _stages.size():
		return
	_selected_stage = _stages[idx]
	_preview_vp.set_stage(_selected_stage)

	var fx_count := EffectCatalog.count_effects(_selected_stage.combined_effect_mask())
	_info_lbl.text = "%s\n%s  |  BPM: %.0f  |  Speed: %.0f m/s  |  Length: %.0fm  |  %d Obstacles  |  %d FX bits" % [
		_selected_stage.level_title,
		_selected_stage.title,
		_selected_stage.bpm,
		_selected_stage.base_speed,
		_selected_stage.total_length(),
		_selected_stage.obstacles.size(),
		fx_count,
	]

	var ms := SaveManager.get_map_stats(_selected_stage.id)
	_stats_lbl.text = "Attempts: %d   |   Clears: %d   |   Best Score: %d   |   Best Chain: %.1fx" % [
		int(ms.get("attempts", 0)),
		int(ms.get("clears", 0)),
		int(ms.get("high_score", 0)),
		float(ms.get("best_chain", 1.0)),
	]

	var unlocked := _is_community_tab or SaveManager.is_stage_unlocked(_selected_stage.id) or _selected_mode == ScoringManager.MODE_ZEN
	_launch_btn.disabled = not unlocked
	_launch_btn.text = "LAUNCH (%s)" % _selected_mode.to_upper() if unlocked else "LOCKED (Clear Previous or Toggle Unlock All)"
	_rebuild_leaderboard(_selected_stage.id)


func _rebuild_leaderboard(stage_id: String) -> void:
	for c in _lb_container.get_children():
		c.queue_free()
	var rows := LevelRepository.get_stage_leaderboard(stage_id)
	if rows.is_empty():
		var empty := Label.new(); empty.text = "No ranked/cleared runs recorded yet."
		_lb_container.add_child(empty)
		return

	for i in range(mini(6, rows.size())):
		var r: Dictionary = rows[i]
		var row_box := HBoxContainer.new()
		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.text = "#%d %s — %d pts (%.1fx)" % [
			i + 1, str(r.get("player_name", "Pilot")), int(r.get("score", 0)), float(r.get("max_chain", 1.0))
		]
		var watch_btn := Button.new()
		watch_btn.text = "WATCH"
		var rep_id := str(r.get("replay_id", ""))
		watch_btn.disabled = rep_id.is_empty()
		watch_btn.pressed.connect(func(): _watch_replay(rep_id))
		row_box.add_child(lbl)
		row_box.add_child(watch_btn)
		_lb_container.add_child(row_box)


func _watch_replay(replay_id: String) -> void:
	if _selected_stage == null or replay_id.is_empty():
		return
	var res := LevelRepository.load_replay(replay_id)
	if not bool(res["ok"]):
		return
	GameSession.set_launch_context({
		"stage_data": _selected_stage,
		"mode": ScoringManager.MODE_WATCH,
		"replay_data": res["replay"],
	})
	get_tree().change_scene_to_file("res://scenes/game_session.tscn")


func _launch_selected() -> void:
	if _selected_stage == null:
		return
	GameSession.set_launch_context({
		"stage_data": _selected_stage,
		"mode": _selected_mode,
	})
	get_tree().change_scene_to_file("res://scenes/game_session.tscn")


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.015, 0.08, 0.96)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	# Top Bar
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	root.add_child(top)

	var camp_btn := Button.new(); camp_btn.text = "Campaign (7 Levels / 21 Stages)"
	camp_btn.pressed.connect(func(): _is_community_tab = false; _reload_stage_list())
	var comm_btn := Button.new(); comm_btn.text = "Community & Custom Maps"
	comm_btn.pressed.connect(func(): _is_community_tab = true; _reload_stage_list())
	var unlock_btn := Button.new(); unlock_btn.text = "Unlock All Campaign"
	unlock_btn.pressed.connect(func():
		for st in LevelRepository.get_campaign_stages():
			SaveManager.unlock_stage(st.id)
		SaveManager.save_to_disk()
		_reload_stage_list()
	)
	var back_btn := Button.new(); back_btn.text = "Back"
	back_btn.pressed.connect(func(): visible = false; closed.emit())
	top.add_child(camp_btn); top.add_child(comm_btn); top.add_child(unlock_btn)
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(spacer)
	top.add_child(back_btn)

	# Main split
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 20)
	root.add_child(split)

	_stage_list = ItemList.new()
	_stage_list.custom_minimum_size = Vector2(460, 0)
	_stage_list.item_selected.connect(_select_index)
	split.add_child(_stage_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	split.add_child(right)

	_preview_vp = LevelPreviewViewport.new()
	_preview_vp.custom_minimum_size = Vector2(0, 320)
	_preview_vp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_preview_vp)

	_info_lbl = Label.new()
	right.add_child(_info_lbl)

	_stats_lbl = Label.new()
	_stats_lbl.modulate = Color("14f1d9")
	right.add_child(_stats_lbl)

	# Mode selector
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	right.add_child(mode_row)
	for m_pair in [
		["Normal", ScoringManager.MODE_NORMAL],
		["Ranked (Endless)", ScoringManager.MODE_RANKED],
		["Zen (No Death)", ScoringManager.MODE_ZEN],
		["Practice (Checkpoints)", ScoringManager.MODE_PRACTICE],
	]:
		var m_btn := Button.new()
		m_btn.text = str(m_pair[0])
		var m_id := str(m_pair[1])
		m_btn.pressed.connect(func():
			_selected_mode = m_id
			_select_index(_stage_list.get_selected_items()[0] if not _stage_list.get_selected_items().is_empty() else 0)
		)
		mode_row.add_child(m_btn)

	_launch_btn = Button.new()
	_launch_btn.custom_minimum_size = Vector2(0, 46)
	_launch_btn.pressed.connect(_launch_selected)
	right.add_child(_launch_btn)

	var lb_hdr := Label.new(); lb_hdr.text = "STAGE LEADERBOARD (LOCAL + WATCH REPLAYS)"
	right.add_child(lb_hdr)
	_lb_container = VBoxContainer.new()
	right.add_child(_lb_container)
