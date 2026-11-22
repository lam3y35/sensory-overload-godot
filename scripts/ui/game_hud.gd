extends CanvasLayer
## In-game HUD displaying score, graze tier popups, chain multiplier, Flow Color Lock,
## depth progress, active 24-bit effects count, Practice checkpoints, and WATCH playback controls.

var _session: GameSession = null
var _crosshair: CrosshairDrawer
var _stage_label: Label
var _mode_label: Label
var _fx_label: Label
var _score_label: Label
var _chain_label: Label
var _chain_bar: ProgressBar
var _flow_label: Label
var _flow_bar: ProgressBar
var _speed_label: Label
var _depth_bar: ProgressBar
var _depth_label: Label
var _graze_popup: Label
var _practice_label: Label
var _watch_banner: Label
var _autopilot_banner: Label
var _ach_toast: Label

var _popup_timer: float = 0.0
var _toast_timer: float = 0.0


func _ready() -> void:
	layer = 20
	_build_ui()
	GameEvents.graze_scored.connect(_on_graze_scored)
	GameEvents.chain_changed.connect(_on_chain_changed)
	GameEvents.flow_changed.connect(_on_flow_changed)
	GameEvents.section_changed.connect(_on_section_changed)
	GameEvents.checkpoint_updated.connect(_on_checkpoint_updated)
	GameEvents.achievement_unlocked.connect(_on_achievement_unlocked)
	GameEvents.replay_state_changed.connect(_on_replay_state_changed)


func configure_session(session: GameSession) -> void:
	_session = session
	if _session == null or _session.stage == null:
		return
	var st: StageData = _session.stage
	var mode_str: String = _session.scoring.mode.to_upper()
	_stage_label.text = "%s — %s" % [st.stage_code, st.title]
	_mode_label.text = "MODE: %s" % mode_str
	_practice_label.visible = (_session.scoring.mode == ScoringManager.MODE_PRACTICE)
	_watch_banner.visible = (_session.scoring.mode == ScoringManager.MODE_WATCH)
	_crosshair.visible = (_session.scoring.mode != ScoringManager.MODE_WATCH)
	_on_section_changed(0, st.effect_mask_at_depth(0.0))


func _process(delta: float) -> void:
	if _session == null or _session.stage == null:
		return
	var st: StageData = _session.stage
	var depth_m: float = maxf(0.0, -_session.player.position_3d.y)
	var total_m: float = st.total_length()
	_score_label.text = "%d" % _session.scoring.score
	_speed_label.text = "%.0f m/s" % _session.current_speed
	_depth_bar.max_value = total_m
	_depth_bar.value = clampf(depth_m, 0.0, total_m)
	_depth_label.text = "SEC %d/%d  |  %.0fm / %.0fm" % [
		_session.current_section_index + 1,
		_session.stage.sections.size(),
		depth_m,
		total_m,
	]
	if _session.scoring.mode == ScoringManager.MODE_RANKED and _session.ranked_lap > 0:
		_mode_label.text = "MODE: RANKED (LAP %d)" % (_session.ranked_lap + 1)
	_autopilot_banner.visible = _session.in_autopilot

	var is_playing := (_session.state == GameSession.SessionState.PLAYING)
	_crosshair.visible = is_playing and (_session.scoring.mode != ScoringManager.MODE_WATCH)
	if not is_playing:
		_graze_popup.visible = false
	elif _popup_timer > 0.0:
		_popup_timer -= delta
		_graze_popup.modulate.a = clampf(_popup_timer / 0.35, 0.0, 1.0)
	else:
		_graze_popup.visible = false

	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_ach_toast.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _session == null or _session.replay_controller == null:
		return
	if not _session.replay_controller.is_watching:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kev := event as InputEventKey
		if kev.keycode == KEY_SPACE:
			_session.replay_controller.toggle_watch_pause()
		elif kev.keycode == KEY_1 or kev.keycode == KEY_2 or kev.keycode == KEY_S:
			_session.replay_controller.cycle_watch_speed()


func _on_graze_scored(tier: int, points: int, _streak: int, _multiplier: float) -> void:
	_graze_popup.text = "%s  +%d" % [SweptCollision.tier_name(tier), points]
	match tier:
		SweptCollision.TIER_DEATH_WISH:
			_graze_popup.modulate = Color("ff2e93")
		SweptCollision.TIER_DAREDEVIL:
			_graze_popup.modulate = Color("facc15")
		_:
			_graze_popup.modulate = Color("14f1d9")
	_graze_popup.visible = true
	_popup_timer = 0.85


func _on_chain_changed(streak: int, multiplier: float, timer_ratio: float) -> void:
	_chain_label.text = "CHAIN %.1fx (%d)" % [multiplier, streak]
	_chain_bar.value = timer_ratio * 100.0


func _on_flow_changed(flow: float, color_locked: bool) -> void:
	_flow_bar.value = flow * 100.0
	_flow_label.text = "FLOW: COLOR LOCKED!" if color_locked else "FLOW: %.0f%%" % (flow * 100.0)
	_flow_label.modulate = Color("14f1d9") if color_locked else Color.WHITE


func _on_section_changed(_idx: int, effect_mask: int) -> void:
	var count := EffectCatalog.count_effects(effect_mask)
	_fx_label.text = "ACTIVE FX: %d / 24 (0x%06X)" % [count, effect_mask]


func _on_checkpoint_updated(has_cp: bool, depth_m: float) -> void:
	if has_cp:
		_practice_label.text = "PRACTICE CHECKPOINT: %.1fm  |  [C] Update  |  [X] Clear  |  [R] Respawn" % depth_m
	else:
		_practice_label.text = "PRACTICE MODE  |  [C] Place Checkpoint  |  [R] Restart"


func _on_achievement_unlocked(_id: String, title: String) -> void:
	_ach_toast.text = "ACHIEVEMENT UNLOCKED: %s" % title
	_ach_toast.visible = true
	_toast_timer = 3.2


func _on_replay_state_changed(active: bool, paused: bool, progress: float, speed_mult: float) -> void:
	_watch_banner.visible = active
	if active:
		var state_txt := "PAUSED" if paused else "PLAYING"
		_watch_banner.text = "WATCH REPLAY [%s %.1fx] — %.0f%%  |  [SPACE] Pause  [S] Speed  [ESC] Exit" % [
			state_txt, speed_mult, progress * 100.0
		]


func _build_ui() -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UITheme.build_neon_theme()
	add_child(root)

	_crosshair = CrosshairDrawer.new()
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_crosshair)

	# Top-left metadata pill
	var tl_pill := UITheme.make_hud_pill(Color("14f1d9"))
	tl_pill.position = Vector2(24, 18)
	root.add_child(tl_pill)
	var tl := VBoxContainer.new()
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl_pill.add_child(tl)
	_stage_label = Label.new(); _stage_label.add_theme_font_size_override("font_size", 22)
	UITheme.apply_hud_text_outline(_stage_label, 4)
	_mode_label = Label.new(); _mode_label.modulate = Color("14f1d9")
	UITheme.apply_hud_text_outline(_mode_label, 3)
	_fx_label = Label.new(); _fx_label.modulate = Color("e2e8f0")
	UITheme.apply_hud_text_outline(_fx_label, 3)
	tl.add_child(_stage_label); tl.add_child(_mode_label); tl.add_child(_fx_label)

	# Top-right score / chain / flow pill
	var tr_pill := UITheme.make_hud_pill(Color("ff2e93"))
	tr_pill.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr_pill.offset_left = -350
	tr_pill.offset_top = 18
	tr_pill.offset_right = -24
	tr_pill.offset_bottom = 165
	root.add_child(tr_pill)

	var tr := VBoxContainer.new()
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr_pill.add_child(tr)

	_score_label = Label.new()
	_score_label.text = "0"
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_score_label.add_theme_font_size_override("font_size", 34)
	UITheme.apply_hud_text_outline(_score_label, 4)
	tr.add_child(_score_label)

	_chain_label = Label.new()
	_chain_label.text = "CHAIN 1.0x (0)"
	_chain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UITheme.apply_hud_text_outline(_chain_label, 3)
	tr.add_child(_chain_label)

	_chain_bar = ProgressBar.new()
	_chain_bar.show_percentage = false
	_chain_bar.custom_minimum_size = Vector2(0, 8)
	tr.add_child(_chain_bar)

	_flow_label = Label.new()
	_flow_label.text = "FLOW: 0%"
	_flow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UITheme.apply_hud_text_outline(_flow_label, 3)
	tr.add_child(_flow_label)

	_flow_bar = ProgressBar.new()
	_flow_bar.show_percentage = false
	_flow_bar.custom_minimum_size = Vector2(0, 8)
	tr.add_child(_flow_bar)

	_speed_label = Label.new()
	_speed_label.text = "40 m/s"
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UITheme.apply_hud_text_outline(_speed_label, 3)
	tr.add_child(_speed_label)

	# Center banners & popup
	_graze_popup = Label.new()
	_graze_popup.set_anchors_preset(Control.PRESET_CENTER)
	_graze_popup.offset_left = -190; _graze_popup.offset_right = 190
	_graze_popup.offset_top = -95; _graze_popup.offset_bottom = -45
	_graze_popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_graze_popup.add_theme_font_size_override("font_size", 28)
	UITheme.apply_hud_text_outline(_graze_popup, 5)
	_graze_popup.visible = false
	root.add_child(_graze_popup)

	_watch_banner = Label.new()
	_watch_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_watch_banner.offset_left = -380; _watch_banner.offset_right = 380
	_watch_banner.offset_top = 20
	_watch_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_watch_banner.modulate = Color("facc15")
	UITheme.apply_hud_text_outline(_watch_banner, 4)
	_watch_banner.visible = false
	root.add_child(_watch_banner)

	_autopilot_banner = Label.new()
	_autopilot_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_autopilot_banner.offset_left = -220; _autopilot_banner.offset_right = 220
	_autopilot_banner.offset_top = 56
	_autopilot_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_autopilot_banner.text = "AUTOPILOT — SECTION TRANSITION"
	_autopilot_banner.modulate = Color("14f1d9")
	UITheme.apply_hud_text_outline(_autopilot_banner, 4)
	_autopilot_banner.visible = false
	root.add_child(_autopilot_banner)

	_ach_toast = Label.new()
	_ach_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_ach_toast.offset_left = -280; _ach_toast.offset_right = 280
	_ach_toast.offset_top = 92
	_ach_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ach_toast.modulate = Color("22c55e")
	UITheme.apply_hud_text_outline(_ach_toast, 4)
	_ach_toast.visible = false
	root.add_child(_ach_toast)

	# Bottom progress bar + practice pill
	var bot_pill := UITheme.make_hud_pill(Color("38bdf8"))
	bot_pill.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bot_pill.offset_left = -330; bot_pill.offset_right = 330
	bot_pill.offset_top = -92; bot_pill.offset_bottom = -18
	root.add_child(bot_pill)

	var bot := VBoxContainer.new()
	bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bot_pill.add_child(bot)

	_practice_label = Label.new()
	_practice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_practice_label.modulate = Color("facc15")
	UITheme.apply_hud_text_outline(_practice_label, 3)
	_practice_label.visible = false
	bot.add_child(_practice_label)

	_depth_label = Label.new()
	_depth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.apply_hud_text_outline(_depth_label, 3)
	bot.add_child(_depth_label)

	_depth_bar = ProgressBar.new()
	_depth_bar.show_percentage = false
	_depth_bar.custom_minimum_size = Vector2(0, 12)
	bot.add_child(_depth_bar)
