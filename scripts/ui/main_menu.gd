extends Control
## Main Menu Hub rendered over a live animated 3D cyber-tunnel + velocity streaks + ambient groove,
## featuring 1-click Quick Dive alongside Stage Select, Ranked, Zen/Practice, Editor, and Settings.

var _vp: SubViewport
var _tunnel: TunnelRenderer
var _particles: SpeedParticles
var _cam: Camera3D
var _bg_time: float = 0.0
var _bg_depth: float = 0.0
var _palette: Array[Color] = [Color("14f1d9"), Color("ff2e93"), Color("070312")]

var _menu_holder: CenterContainer
var _menu_card: PanelContainer
var _level_select: LevelSelect
var _settings_menu: SettingsMenu
var _ach_menu: AchievementsMenu


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.build_neon_theme()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_3d_backdrop()
	_build_menu_ui()
	AudioSyncManager.start_menu_ambient()


func _process(delta: float) -> void:
	_bg_time += delta
	_bg_depth += delta * 34.0
	if _cam != null and _tunnel != null:
		_cam.position = Vector3(0.0, -_bg_depth, 0.0)
		_cam.rotation = Vector3(-PI * 0.5, 0.0, _bg_time * 0.16)
		var mask := (1 << 0) | (1 << 1) | (1 << 4) | (1 << 5) | (1 << 6)
		_tunnel.update_tunnel(-_bg_depth, _bg_time, mask, AudioSyncManager.beat_phase, AudioSyncManager.bass_energy, 0.45, _palette, 10.0)
	if _particles != null:
		_particles.update_particles(-_bg_depth, delta, 48.0, 0.25, false, _palette)


func _build_3d_backdrop() -> void:
	var vpc := SubViewportContainer.new()
	vpc.stretch = true
	vpc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vpc)

	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vpc.add_child(_vp)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("070312")
	env.glow_enabled = true
	env.glow_intensity = 0.72
	we.environment = env
	_vp.add_child(we)

	_tunnel = TunnelRenderer.new()
	_vp.add_child(_tunnel)

	_particles = SpeedParticles.new()
	_vp.add_child(_particles)
	_particles.reset_particles(10.0)

	_cam = Camera3D.new()
	_cam.far = 220.0
	_cam.fov = 86.0
	_cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_vp.add_child(_cam)


func _launch_quick_dive() -> void:
	AudioSyncManager.play_sfx("ui_click")
	var stages := LevelRepository.get_campaign_stages()
	var target_stage: StageData = stages[0] if not stages.is_empty() else null
	for st in stages:
		if SaveManager.is_stage_unlocked(st.id):
			target_stage = st
	if target_stage == null:
		return
	GameSession.set_launch_context({
		"stage_data": target_stage,
		"mode": ScoringManager.MODE_NORMAL,
	})
	get_tree().change_scene_to_file("res://scenes/game_session.tscn")


func _build_menu_ui() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.01, 0.06, 0.34)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	_menu_holder = CenterContainer.new()
	_menu_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_menu_holder)

	_menu_card = PanelContainer.new()
	_menu_card.custom_minimum_size = Vector2(560, 560)
	_menu_holder.add_child(_menu_card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	_menu_card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 9)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "SENSORY OVERLOAD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	UITheme.apply_hud_text_outline(title, 4)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "HIGH-SPEED CYBER TUNNEL ARCADE  ·  DODGE  ·  GRAZE  ·  OVERDRIVE"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.modulate = Color("14f1d9")
	vbox.add_child(sub)

	var hero_btn := Button.new()
	hero_btn.text = "▶  PLAY NOW (QUICK DIVE)"
	hero_btn.custom_minimum_size = Vector2(0, 48)
	hero_btn.add_theme_font_size_override("font_size", 19)
	var hero_sb := StyleBoxFlat.new()
	hero_sb.bg_color = Color(0.06, 0.20, 0.28, 0.96)
	hero_sb.border_color = Color("facc15")
	hero_sb.set_border_width_all(2)
	hero_sb.set_corner_radius_all(6)
	hero_btn.add_theme_stylebox_override("normal", hero_sb)
	var hero_hover := hero_sb.duplicate() as StyleBoxFlat
	hero_hover.bg_color = Color(0.10, 0.28, 0.38, 0.98)
	hero_hover.border_color = Color("14f1d9")
	hero_btn.add_theme_stylebox_override("hover", hero_hover)
	hero_btn.add_theme_color_override("font_color", Color("facc15"))
	hero_btn.pressed.connect(_launch_quick_dive)
	vbox.add_child(hero_btn)

	var items := [
		["Stage Select (7 Levels / 21 Stages)", func(): AudioSyncManager.play_sfx("ui_click"); _level_select.open_browser(false, ScoringManager.MODE_NORMAL)],
		["Ranked Endless Mode", func(): AudioSyncManager.play_sfx("ui_click"); _level_select.open_browser(false, ScoringManager.MODE_RANKED)],
		["Zen / Practice Modes", func(): AudioSyncManager.play_sfx("ui_click"); _level_select.open_browser(false, ScoringManager.MODE_ZEN)],
		["Community & Custom Maps", func(): AudioSyncManager.play_sfx("ui_click"); _level_select.open_browser(true, ScoringManager.MODE_NORMAL)],
		["Level Editor", func(): AudioSyncManager.play_sfx("ui_click"); AudioSyncManager.stop_music(); get_tree().change_scene_to_file("res://scenes/level_editor.tscn")],
		["Achievements & Stats", func(): AudioSyncManager.play_sfx("ui_click"); _ach_menu.refresh(); _ach_menu.visible = true],
		["Settings & Accessibility", func(): AudioSyncManager.play_sfx("ui_click"); _settings_menu.visible = true],
		["Quit", func(): get_tree().quit(0)],
	]

	for entry in items:
		var btn := Button.new()
		btn.text = str(entry[0])
		btn.custom_minimum_size = Vector2(0, 39)
		btn.pressed.connect(entry[1])
		vbox.add_child(btn)

	_level_select = LevelSelect.new()
	_level_select.visible = false
	_level_select.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_level_select.visibility_changed.connect(_sync_menu_card_visibility)
	add_child(_level_select)

	_settings_menu = SettingsMenu.new()
	_settings_menu.visible = false
	_settings_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_menu.visibility_changed.connect(_sync_menu_card_visibility)
	add_child(_settings_menu)

	_ach_menu = AchievementsMenu.new()
	_ach_menu.visible = false
	_ach_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ach_menu.visibility_changed.connect(_sync_menu_card_visibility)
	add_child(_ach_menu)


func _sync_menu_card_visibility() -> void:
	if _menu_holder == null:
		return
	var any_modal := (
		(_level_select != null and _level_select.visible)
		or (_settings_menu != null and _settings_menu.visible)
		or (_ach_menu != null and _ach_menu.visible)
	)
	_menu_holder.visible = not any_modal
