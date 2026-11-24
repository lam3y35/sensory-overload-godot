extends CanvasLayer
## Minimalist brutalist in-game HUD inspired directly by Sensory Overload:
## - Bare bold italic Score (top-left) + Speed in CUBES/S (top-right)
## - Top-center angular V-Chevron Multiplier (X1..X8) & Elapsed Timer
## - Split horizontal top progress bar with section/finish ticks
## - Unobtrusive middle-right stacking Near-Miss / Graze feed

class _VectorGlyph extends Control:
	var kind: String = "star" # "star" or "bolt"
	var fill_color: Color = Color.WHITE

	func _init(p_kind: String = "star") -> void:
		kind = p_kind
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(22, 22)

	func _draw() -> void:
		var c := size * 0.5
		if kind == "star":
			var pts := PackedVector2Array()
			var r_out := minf(size.x, size.y) * 0.44
			var r_in := r_out * 0.42
			for i in range(10):
				var ang := -PI * 0.5 + float(i) * (PI / 5.0)
				var rad := r_out if (i % 2 == 0) else r_in
				pts.append(c + Vector2(cos(ang) * rad, sin(ang) * rad))
			draw_colored_polygon(pts, fill_color)
		elif kind == "bolt":
			var w := size.x * 0.40
			var h := size.y * 0.46
			var pts := PackedVector2Array([
				c + Vector2(w * 0.15, -h),
				c + Vector2(-w * 0.72, h * 0.08),
				c + Vector2(-w * 0.05, h * 0.08),
				c + Vector2(-w * 0.25, h),
				c + Vector2(w * 0.78, -h * 0.12),
				c + Vector2(w * 0.08, -h * 0.12),
			])
			draw_colored_polygon(pts, fill_color)


class _MultiplierChevron extends Control:
	var accent_color: Color = Color("e2e8f0")
	var mult_text: String = "X1"
	var timer_text: String = "0:00"
	var chain_ratio: float = 0.0
	var pop_scale: float = 1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var cx := size.x * 0.5
		# Dual parallel sharp V-lines opening upward from the top edge
		var top_y := 0.0
		var bot_y := 80.0
		var outer_w := 104.0
		var inner_w := 88.0

		var tri := PackedVector2Array([
			Vector2(cx - outer_w, top_y),
			Vector2(cx + outer_w, top_y),
			Vector2(cx, bot_y),
		])
		draw_colored_polygon(tri, Color(0.03, 0.035, 0.05, 0.52))

		draw_line(Vector2(cx - outer_w, top_y), Vector2(cx, bot_y), accent_color, 3.2, true)
		draw_line(Vector2(cx + outer_w, top_y), Vector2(cx, bot_y), accent_color, 3.2, true)

		var mid_y := bot_y - 12.0
		draw_line(Vector2(cx - inner_w, top_y), Vector2(cx, mid_y), Color(accent_color.r, accent_color.g, accent_color.b, 0.75), 1.8, true)
		draw_line(Vector2(cx + inner_w, top_y), Vector2(cx, mid_y), Color(accent_color.r, accent_color.g, accent_color.b, 0.75), 1.8, true)

		# Chain decay bar filling inward from apex up the chevron walls
		if chain_ratio > 0.01:
			var p_l := Vector2(cx, mid_y).lerp(Vector2(cx - inner_w, top_y), clampf(chain_ratio, 0.0, 1.0))
			var p_r := Vector2(cx, mid_y).lerp(Vector2(cx + inner_w, top_y), clampf(chain_ratio, 0.0, 1.0))
			draw_line(Vector2(cx, mid_y), p_l, Color.WHITE, 2.8, true)
			draw_line(Vector2(cx, mid_y), p_r, Color.WHITE, 2.8, true)


class _TopProgressTrack extends Control:
	var progress: float = 0.0
	var fill_color: Color = Color("38bdf8")
	var section_fracs: Array[float] = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		if w < 120.0:
			return
		var bar_y := 18.0
		var bar_h := 5.0
		var cx := w * 0.5
		var gap_half := 96.0
		var l_start := 0.0
		var r_end := w
		var total_draw := (w - gap_half * 2.0)
		if total_draw <= 20.0:
			return

		# Left track & right track segments flanking the center chevron
		var left_span := cx - gap_half - l_start
		var right_x := cx + gap_half
		var right_span := r_end - right_x

		draw_rect(Rect2(l_start, bar_y, left_span, bar_h), Color(0.06, 0.07, 0.10, 0.58))
		draw_rect(Rect2(l_start, bar_y, left_span, bar_h), Color(fill_color.r, fill_color.g, fill_color.b, 0.42), false, 1.0)
		draw_rect(Rect2(right_x, bar_y, right_span, bar_h), Color(0.06, 0.07, 0.10, 0.58))
		draw_rect(Rect2(right_x, bar_y, right_span, bar_h), Color(fill_color.r, fill_color.g, fill_color.b, 0.42), false, 1.0)

		var fill_px := clampf(progress, 0.0, 1.0) * total_draw
		if fill_px > 0.5:
			var l_fill := minf(fill_px, left_span)
			draw_rect(Rect2(l_start, bar_y, l_fill, bar_h), fill_color)
			if fill_px > left_span:
				var r_fill := minf(fill_px - left_span, right_span)
				draw_rect(Rect2(right_x, bar_y, r_fill, bar_h), fill_color)

		# Section milestone ticks + finish line flag tick
		for sf in section_fracs:
			var px := sf * total_draw
			var tx := px if px <= left_span else (right_x + (px - left_span))
			draw_line(Vector2(tx, bar_y - 5.0), Vector2(tx, bar_y + bar_h + 3.0), Color(1.0, 0.85, 0.25, 0.85), 2.0)
		draw_rect(Rect2(r_end - 3.0, bar_y - 7.0, 3.0, bar_h + 10.0), Color.WHITE)


var _session: GameSession = null
var _root: Control
var _crosshair: CrosshairDrawer

var _score_glyph: _VectorGlyph
var _score_label: Label
var _stage_sub_label: Label
var _speed_glyph: _VectorGlyph
var _speed_label: Label
var _boost_tag: Label

var _chevron: _MultiplierChevron
var _mult_label: Label
var _time_label: Label
var _top_track: _TopProgressTrack

var _feed_vbox: VBoxContainer
var _feed_rows: Array[Dictionary] = []

var _milestone_label: Label
var _intro_banner: Label
var _practice_label: Label
var _watch_banner: Label
var _autopilot_banner: Label
var _ach_toast: Label

var _milestone_timer: float = 0.0
var _intro_timer: float = 0.0
var _toast_timer: float = 0.0
var _mult_pop_timer: float = 0.0
var _chain_ratio: float = 0.0
var _last_mult_display: float = 1.0


func _ready() -> void:
	layer = 20
	_build_ui()
	GameEvents.graze_scored.connect(_on_graze_scored)
	GameEvents.ring_collected.connect(_on_ring_collected)
	GameEvents.phase_dash_used.connect(_on_phase_dash_used)
	GameEvents.milestone_callout.connect(_on_milestone_callout)
	GameEvents.chain_changed.connect(_on_chain_changed)
	GameEvents.flow_changed.connect(_on_flow_changed)
	GameEvents.boost_changed.connect(_on_boost_changed)
	GameEvents.section_changed.connect(_on_section_changed)
	GameEvents.checkpoint_updated.connect(_on_checkpoint_updated)
	GameEvents.achievement_unlocked.connect(_on_achievement_unlocked)
	GameEvents.replay_state_changed.connect(_on_replay_state_changed)


func configure_session(session: GameSession) -> void:
	_session = session
	_clear_feed()
	if _session == null or _session.stage == null:
		return
	var st: StageData = _session.stage
	var mode_tag := "" if _session.scoring.mode == ScoringManager.MODE_NORMAL else "  [%s]" % _session.scoring.mode.to_upper()
	_stage_sub_label.text = "%s · %s%s" % [st.stage_code, st.title.to_upper(), mode_tag]
	_practice_label.visible = (_session.scoring.mode == ScoringManager.MODE_PRACTICE)
	_watch_banner.visible = (_session.scoring.mode == ScoringManager.MODE_WATCH)
	_crosshair.visible = (_session.scoring.mode != ScoringManager.MODE_WATCH)
	_boost_tag.visible = false
	_milestone_label.visible = false
	_milestone_timer = 0.0
	_chain_ratio = 0.0
	_last_mult_display = 1.0

	var fracs: Array[float] = []
	var tot := maxf(1.0, st.total_length())
	var acc := 0.0
	for i in range(st.sections.size() - 1):
		acc += float(st.sections[i].get("length", 100.0))
		fracs.append(clampf(acc / tot, 0.0, 1.0))
	_top_track.section_fracs = fracs
	_top_track.progress = 0.0
	_top_track.queue_redraw()

	if _session.scoring.mode == ScoringManager.MODE_WATCH:
		_intro_banner.visible = false
		_intro_timer = 0.0
	else:
		_intro_banner.text = "%s — %s" % [st.stage_code, st.title.to_upper()]
		_intro_banner.modulate.a = 1.0
		_intro_banner.visible = true
		_intro_timer = 2.1

	_update_tier_palette(1.0, false)


func _process(delta: float) -> void:
	if _session == null or _session.stage == null:
		return
	var st: StageData = _session.stage
	var depth_m: float = maxf(0.0, -_session.player.position_3d.y)
	var total_m: float = maxf(1.0, st.total_length())

	_score_label.text = "%d" % _session.scoring.score
	_speed_label.text = "%.0f CUBES/S" % _session.current_speed
	_top_track.progress = clampf(depth_m / total_m, 0.0, 1.0)
	_top_track.queue_redraw()

	var sec_i := int(floor(_session.elapsed_time))
	_time_label.text = "%d:%02d" % [sec_i / 60, sec_i % 60]

	if _session.scoring.mode == ScoringManager.MODE_RANKED:
		_stage_sub_label.text = "%s · RANKED LAP %d" % [st.stage_code, _session.ranked_lap + 1]
	_autopilot_banner.visible = _session.in_autopilot

	var is_playing := (_session.state == GameSession.SessionState.PLAYING)
	_crosshair.visible = is_playing and (_session.scoring.mode != ScoringManager.MODE_WATCH)
	if _crosshair.visible:
		var t_norm := Vector2(_session.player.position_3d.x, _session.player.position_3d.z) / PlayerController.PLAY_RADIUS
		var beat_k := exp(-AudioSyncManager.beat_phase * 4.2)
		_crosshair.update_telemetry(
			_session.scoring.flow_meter,
			_session.scoring.color_locked,
			_chain_ratio,
			_session.scoring.chain_multiplier,
			_session.boost_level,
			beat_k,
			t_norm,
			_session.player.get_phase_ready_ratio(),
			_session.player.is_phase_invulnerable()
		)

	if _mult_pop_timer > 0.0:
		_mult_pop_timer = maxf(0.0, _mult_pop_timer - delta)
		var pop := _mult_pop_timer / 0.22
		_mult_label.pivot_offset = _mult_label.size * 0.5
		_mult_label.scale = Vector2.ONE * lerpf(1.0, 1.28, pop)

	_tick_feed(delta)

	if not is_playing:
		_milestone_label.visible = false
		_intro_banner.visible = false
		_ach_toast.visible = false
	else:
		if _intro_timer > 0.0:
			_intro_timer -= delta
			_intro_banner.modulate.a = clampf(_intro_timer / 0.65, 0.0, 1.0)
			if _intro_timer <= 0.0:
				_intro_banner.visible = false

		if _milestone_timer > 0.0:
			_milestone_timer -= delta
			_milestone_label.modulate.a = clampf(_milestone_timer / 0.45, 0.0, 1.0)
			if _milestone_timer <= 0.0:
				_milestone_label.visible = false

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


func _update_tier_palette(mult: float, locked: bool) -> void:
	var tier_col := Color("38bdf8") # X1 - cool cyan-white
	if locked or mult >= 5.0:
		tier_col = Color("ff1e3c") # X5..X8 - blazing crimson
	elif mult >= 3.0:
		tier_col = Color("ff9f1c") # X3..X4.5 - blazing amber
	elif mult >= 1.5:
		tier_col = Color("facc15") # X1.5..X2.5 - gold

	_chevron.accent_color = tier_col
	_chevron.chain_ratio = _chain_ratio
	_chevron.queue_redraw()
	_score_glyph.fill_color = tier_col
	_score_glyph.queue_redraw()
	_speed_glyph.fill_color = Color("ff9f1c") if (_session != null and _session.boost_level > 0.25) else tier_col
	_speed_glyph.queue_redraw()
	_top_track.fill_color = tier_col
	_top_track.queue_redraw()

	var m_str := "X%d" % int(round(mult)) if is_equal_approx(mult, round(mult)) else "X%.1f" % mult
	_mult_label.text = m_str
	if mult > _last_mult_display + 0.01:
		_mult_pop_timer = 0.22
	_last_mult_display = mult


func _push_feed_row(label_txt: String, pts_txt: String, border_col: Color) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(228, 28)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.025, 0.030, 0.045, 0.72)
	sb.border_color = border_col
	sb.set_border_width_all(1)
	sb.border_width_left = 3
	sb.set_corner_radius_all(1)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)

	var l_lbl := Label.new()
	l_lbl.text = label_txt
	l_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l_lbl.add_theme_font_override("font", UITheme.font_bold())
	l_lbl.add_theme_font_size_override("font_size", 13)
	l_lbl.modulate = Color.WHITE
	UITheme.apply_hud_text_outline(l_lbl, 2)
	hbox.add_child(l_lbl)

	var r_lbl := Label.new()
	r_lbl.text = pts_txt
	r_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r_lbl.add_theme_font_override("font", UITheme.font_italic())
	r_lbl.add_theme_font_size_override("font_size", 14)
	r_lbl.modulate = border_col.lerp(Color.WHITE, 0.35)
	UITheme.apply_hud_text_outline(r_lbl, 2)
	hbox.add_child(r_lbl)

	_feed_vbox.add_child(panel)
	_feed_rows.append({"node": panel, "ttl": 1.65})
	while _feed_rows.size() > 6:
		var oldest := _feed_rows.pop_front() as Dictionary
		var old_node := oldest["node"] as Control
		if is_instance_valid(old_node):
			old_node.queue_free()


func _tick_feed(delta: float) -> void:
	for i in range(_feed_rows.size() - 1, -1, -1):
		var row: Dictionary = _feed_rows[i]
		var ttl := float(row["ttl"]) - delta
		row["ttl"] = ttl
		var nd := row["node"] as Control
		if not is_instance_valid(nd) or ttl <= 0.0:
			if is_instance_valid(nd):
				nd.queue_free()
			_feed_rows.remove_at(i)
		else:
			nd.modulate.a = clampf(ttl / 0.40, 0.0, 1.0)


func _clear_feed() -> void:
	for r in _feed_rows:
		var nd := r["node"] as Control
		if is_instance_valid(nd):
			nd.queue_free()
	_feed_rows.clear()


func _on_graze_scored(tier: int, points: int, _streak: int, _multiplier: float) -> void:
	var col := Color("22c55e")
	if tier == SweptCollision.TIER_DEATH_WISH:
		col = Color("ff1e3c")
	elif tier == SweptCollision.TIER_DAREDEVIL:
		col = Color("ff9f1c")
	_push_feed_row(SweptCollision.tier_name(tier), "+%d" % points, col)


func _on_ring_collected(points: int, _streak: int, _multiplier: float) -> void:
	_push_feed_row("GATE BONUS", "+%d" % points, Color("facc15"))


func _on_phase_dash_used(is_parry: bool, _ready_ratio: float) -> void:
	if is_parry:
		_push_feed_row("PHASE PARRY", "+CHAIN", Color("38bdf8"))


func _on_milestone_callout(txt: String, col: Color) -> void:
	_milestone_label.text = txt
	_milestone_label.modulate = col.lerp(Color.WHITE, 0.20)
	_milestone_label.visible = true
	_milestone_timer = 1.35


func _on_chain_changed(_streak: int, multiplier: float, timer_ratio: float) -> void:
	_chain_ratio = clampf(timer_ratio, 0.0, 1.0)
	var locked := (_session != null and _session.scoring.color_locked)
	_update_tier_palette(multiplier, locked)


func _on_flow_changed(_flow: float, color_locked: bool) -> void:
	var mult := _session.scoring.chain_multiplier if _session != null else 1.0
	_update_tier_palette(mult, color_locked)


func _on_boost_changed(active: bool, boost_ratio: float) -> void:
	_boost_tag.visible = active or boost_ratio > 0.25
	if _speed_glyph != null and _session != null:
		_update_tier_palette(_session.scoring.chain_multiplier, _session.scoring.color_locked)


func _on_section_changed(_idx: int, _effect_mask: int) -> void:
	pass


func _on_checkpoint_updated(has_cp: bool, depth_m: float) -> void:
	if has_cp:
		_practice_label.text = "CHECKPOINT %.1fm  //  [C] UPDATE  ·  [X] CLEAR  ·  [R] RESPAWN" % depth_m
	else:
		_practice_label.text = "PRACTICE MODE  //  [C] PLACE CHECKPOINT  ·  [R] RESTART"


func _on_achievement_unlocked(_id: String, title: String) -> void:
	_ach_toast.text = "UNLOCKED // %s" % title.to_upper()
	_ach_toast.visible = true
	_toast_timer = 3.0


func _on_replay_state_changed(active: bool, paused: bool, progress: float, speed_mult: float) -> void:
	_watch_banner.visible = active
	if active:
		var state_txt := "PAUSED" if paused else "REPLAY"
		_watch_banner.text = "%s %.1fx (%.0f%%)  //  [SPACE] PAUSE  ·  [S] SPEED  ·  [ESC] EXIT" % [
			state_txt, speed_mult, progress * 100.0
		]


func _build_ui() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.build_neon_theme()
	add_child(_root)

	_crosshair = CrosshairDrawer.new()
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_crosshair)

	# 1) Top-Left Bare Italic Score + Minimal Stage Label (ZERO boxes!)
	var tl_box := VBoxContainer.new()
	tl_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl_box.position = Vector2(28, 16)
	tl_box.add_theme_constant_override("separation", 2)
	_root.add_child(tl_box)

	var score_row := HBoxContainer.new()
	score_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_row.add_theme_constant_override("separation", 8)
	score_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	tl_box.add_child(score_row)

	_score_glyph = _VectorGlyph.new("star")
	_score_glyph.custom_minimum_size = Vector2(24, 24)
	score_row.add_child(_score_glyph)

	_score_label = Label.new()
	_score_label.text = "0"
	UITheme.style_display_label(_score_label, 30, true)
	score_row.add_child(_score_label)

	_stage_sub_label = Label.new()
	_stage_sub_label.modulate = Color(0.86, 0.90, 0.96, 0.72)
	_stage_sub_label.add_theme_font_override("font", UITheme.font_bold())
	_stage_sub_label.add_theme_font_size_override("font_size", 12)
	UITheme.apply_hud_text_outline(_stage_sub_label, 2)
	tl_box.add_child(_stage_sub_label)

	# 2) Top-Right Bare Italic CUBES/S Speed Telemetry
	var tr_box := VBoxContainer.new()
	tr_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr_box.offset_left = -330
	tr_box.offset_top = 16
	tr_box.offset_right = -28
	tr_box.offset_bottom = 92
	tr_box.add_theme_constant_override("separation", 2)
	_root.add_child(tr_box)

	var speed_row := HBoxContainer.new()
	speed_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speed_row.alignment = BoxContainer.ALIGNMENT_END
	speed_row.add_theme_constant_override("separation", 8)
	tr_box.add_child(speed_row)

	_speed_glyph = _VectorGlyph.new("bolt")
	_speed_glyph.custom_minimum_size = Vector2(22, 24)
	speed_row.add_child(_speed_glyph)

	_speed_label = Label.new()
	_speed_label.text = "48 CUBES/S"
	UITheme.style_display_label(_speed_label, 28, true)
	speed_row.add_child(_speed_label)

	_boost_tag = Label.new()
	_boost_tag.text = "OVERDRIVE"
	_boost_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_boost_tag.modulate = Color("ff9f1c")
	_boost_tag.add_theme_font_override("font", UITheme.font_italic())
	_boost_tag.add_theme_font_size_override("font_size", 13)
	UITheme.apply_hud_text_outline(_boost_tag, 2)
	_boost_tag.visible = false
	tr_box.add_child(_boost_tag)

	# 3) Top-Center Split Horizontal Progress Track + Angular Multiplier Chevron
	_top_track = _TopProgressTrack.new()
	_top_track.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_top_track.offset_left = -340
	_top_track.offset_right = 340
	_top_track.offset_top = 4
	_top_track.offset_bottom = 36
	_root.add_child(_top_track)

	_chevron = _MultiplierChevron.new()
	_chevron.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_chevron.offset_left = -110
	_chevron.offset_right = 110
	_chevron.offset_top = 0
	_chevron.offset_bottom = 92
	_root.add_child(_chevron)

	_mult_label = Label.new()
	_mult_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_mult_label.offset_left = -90
	_mult_label.offset_right = 90
	_mult_label.offset_top = 6
	_mult_label.offset_bottom = 52
	_mult_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mult_label.text = "X1"
	UITheme.style_display_label(_mult_label, 38, true)
	_root.add_child(_mult_label)

	_time_label = Label.new()
	_time_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_time_label.offset_left = -80
	_time_label.offset_right = 80
	_time_label.offset_top = 82
	_time_label.offset_bottom = 110
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.text = "0:00"
	UITheme.style_display_label(_time_label, 19, true)
	_root.add_child(_time_label)

	# 4) Middle-Right Stacking Near-Miss Feed
	var feed_anchor := Control.new()
	feed_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed_anchor.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	feed_anchor.offset_left = -260
	feed_anchor.offset_right = -24
	feed_anchor.offset_top = -105
	feed_anchor.offset_bottom = 145
	_root.add_child(feed_anchor)

	_feed_vbox = VBoxContainer.new()
	_feed_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_feed_vbox.add_theme_constant_override("separation", 4)
	feed_anchor.add_child(_feed_vbox)

	# 5) Subtle non-blocking Status & Banners (strictly clear of central crosshair)
	_milestone_label = Label.new()
	_milestone_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_milestone_label.offset_left = -280
	_milestone_label.offset_right = 280
	_milestone_label.offset_top = 116
	_milestone_label.offset_bottom = 152
	_milestone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_display_label(_milestone_label, 22, true)
	_milestone_label.visible = false
	_root.add_child(_milestone_label)

	_intro_banner = Label.new()
	_intro_banner.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_intro_banner.offset_left = -360
	_intro_banner.offset_right = 360
	_intro_banner.offset_top = -64
	_intro_banner.offset_bottom = -32
	_intro_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_display_label(_intro_banner, 17, false)
	_intro_banner.modulate = Color("f8fafc")
	_intro_banner.visible = false
	_root.add_child(_intro_banner)

	_watch_banner = Label.new()
	_watch_banner.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_watch_banner.offset_left = -360
	_watch_banner.offset_right = 360
	_watch_banner.offset_top = -44
	_watch_banner.offset_bottom = -16
	_watch_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_watch_banner.modulate = Color("ff9f1c")
	UITheme.style_display_label(_watch_banner, 14, false)
	_watch_banner.visible = false
	_root.add_child(_watch_banner)

	_practice_label = Label.new()
	_practice_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_practice_label.offset_left = -360
	_practice_label.offset_right = 360
	_practice_label.offset_top = -44
	_practice_label.offset_bottom = -16
	_practice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_practice_label.modulate = Color("facc15")
	UITheme.style_display_label(_practice_label, 14, false)
	_practice_label.visible = false
	_root.add_child(_practice_label)

	_autopilot_banner = Label.new()
	_autopilot_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_autopilot_banner.offset_left = -220
	_autopilot_banner.offset_right = 220
	_autopilot_banner.offset_top = 118
	_autopilot_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_autopilot_banner.text = "TRANSITION CORRIDOR"
	_autopilot_banner.modulate = Color("38bdf8")
	UITheme.style_display_label(_autopilot_banner, 14, true)
	_autopilot_banner.visible = false
	_root.add_child(_autopilot_banner)

	_ach_toast = Label.new()
	_ach_toast.position = Vector2(28, 76)
	_ach_toast.modulate = Color("22c55e")
	UITheme.style_display_label(_ach_toast, 15, true)
	_ach_toast.visible = false
	_root.add_child(_ach_toast)
