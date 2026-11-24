extends Control
## Commercial brutalist Title Screen rendered over an infinite lit 3D voxel drop shaft
## with live passing translucent obstacles, asymmetric left-aligned navigation, and hard-techno intro groove.

var _vp: SubViewport
var _tunnel: TunnelRenderer
var _obstacle_manager: ObstacleManager
var _particles: SpeedParticles
var _cam: Camera3D
var _bg_time: float = 0.0
var _bg_depth: float = 0.0
var _palette: Array[Color] = [Color("c2188a"), Color("2e1a7a"), Color("070410")]
var _showcase_stage: StageData

var _menu_holder: Control
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
	_bg_depth += delta * 36.0
	if _cam != null and _tunnel != null:
		# Subtle organic floating drift looking straight down into the abyss
		var drift_x := sin(_bg_time * 0.55) * 1.45
		var drift_z := cos(_bg_time * 0.42) * 1.45
		_cam.position = Vector3(drift_x, -_bg_depth, drift_z)
		_cam.rotation = Vector3(-PI * 0.5, 0.0, sin(_bg_time * 0.28) * 0.14)
		var mask := (1 << 0) | (1 << 1) | (1 << 3) | (1 << 5)
		_tunnel.update_tunnel(-_bg_depth, _bg_time, mask, AudioSyncManager.beat_phase, AudioSyncManager.bass_energy, 0.35, _palette, 10.0)
	if _obstacle_manager != null and _showcase_stage != null:
		# Recycle passed showcase obstacles far beyond abyssal fog for infinite seamless backdrop
		for obs in _showcase_stage.obstacles:
			if obs.depth < _bg_depth - 14.0:
				obs.depth += 264.0
		_obstacle_manager.step_and_sync(-_bg_depth, delta, AudioSyncManager.beat_phase, AudioSyncManager.bass_energy, false)
	if _particles != null:
		_particles.update_particles(-_bg_depth, delta, 54.0, 0.15, false, _palette)


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
	TunnelRenderer.apply_cinema_environment(env, _palette[2])
	we.environment = env
	_vp.add_child(we)

	_tunnel = TunnelRenderer.new()
	_vp.add_child(_tunnel)

	_showcase_stage = StageData.new()
	_showcase_stage.id = "menu_showcase"
	_showcase_stage.palette = _palette.duplicate()
	_showcase_stage.sections = [{"id": "s1", "length": 100000.0, "effect_mask": 0, "transition_gap": 0.0}]
	var types := ["waffle", "cross_bars", "tumbling_cube", "iris_ring", "guillotine", "spiral_slats"]
	for i in range(types.size()):
		var obs := ObstacleData.new()
		obs.id = "menu_obs_%d" % i
		obs.type = types[i]
		obs.depth = 38.0 + float(i) * 44.0
		obs.speed = 0.72
		obs.seed_int = i + 2
		obs.color_primary = Color("ff2e93") if (i % 2 == 0) else Color("00d4d8")
		obs.color_accent = Color("f8fafc")
		_showcase_stage.obstacles.append(obs)

	_obstacle_manager = ObstacleManager.new()
	_obstacle_manager.reset_with_stage(_showcase_stage)
	_vp.add_child(_obstacle_manager)

	_particles = SpeedParticles.new()
	_vp.add_child(_particles)
	_particles.reset_particles(10.0)

	_cam = Camera3D.new()
	_cam.far = 220.0
	_cam.fov = 88.0
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
	_menu_holder = Control.new()
	_menu_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu_holder)

	# Smooth directional left vignette scrim keeping the right 62% of the 3D tunnel completely crisp
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.025, 0.025, 0.04, 0.90), Color(0.025, 0.025, 0.04, 0.62), Color(0.025, 0.025, 0.04, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 0.34, 0.68])
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.width = 512
	gtex.height = 16
	gtex.fill_from = Vector2(0.0, 0.5)
	gtex.fill_to = Vector2(1.0, 0.5)
	var scrim := TextureRect.new()
	scrim.texture = gtex
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_holder.add_child(scrim)

	var left_col := VBoxContainer.new()
	left_col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	left_col.offset_left = 76
	left_col.offset_right = 510
	left_col.offset_top = -310
	left_col.offset_bottom = 310
	left_col.add_theme_constant_override("separation", 10)
	_menu_holder.add_child(left_col)

	# Stacked Hero Logo with subtle chromatic offset shadow
	var logo_wrap := Control.new()
	logo_wrap.custom_minimum_size = Vector2(420, 128)
	left_col.add_child(logo_wrap)

	var t_shadow_r := Label.new()
	t_shadow_r.text = "SENSORY\nOVERLOAD"
	t_shadow_r.position = Vector2(4, 3)
	t_shadow_r.modulate = Color("ff1e56")
	t_shadow_r.add_theme_font_override("font", UITheme.font_display())
	t_shadow_r.add_theme_font_size_override("font_size", 54)
	t_shadow_r.add_theme_constant_override("line_spacing", -10)
	logo_wrap.add_child(t_shadow_r)

	var t_shadow_c := Label.new()
	t_shadow_c.text = "SENSORY\nOVERLOAD"
	t_shadow_c.position = Vector2(-3, -2)
	t_shadow_c.modulate = Color("00e5ff")
	t_shadow_c.add_theme_font_override("font", UITheme.font_display())
	t_shadow_c.add_theme_font_size_override("font_size", 54)
	t_shadow_c.add_theme_constant_override("line_spacing", -10)
	logo_wrap.add_child(t_shadow_c)

	var t_main := Label.new()
	t_main.text = "SENSORY\nOVERLOAD"
	t_main.position = Vector2.ZERO
	t_main.modulate = Color.WHITE
	t_main.add_theme_font_override("font", UITheme.font_display())
	t_main.add_theme_font_size_override("font_size", 54)
	t_main.add_theme_constant_override("line_spacing", -10)
	UITheme.apply_hud_text_outline(t_main, 4)
	logo_wrap.add_child(t_main)

	var sub := Label.new()
	sub.text = "VOXEL DROPPER  //  21 STAGES  ·  HARD TECHNO OST"
	sub.modulate = Color("ff9f1c")
	sub.add_theme_font_override("font", UITheme.font_bold())
	sub.add_theme_font_size_override("font_size", 13)
	UITheme.apply_hud_text_outline(sub, 2)
	left_col.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	left_col.add_child(spacer)

	var hero_btn := Button.new()
	hero_btn.text = "DROP IN  —  PLAY"
	hero_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	hero_btn.custom_minimum_size = Vector2(0, 50)
	hero_btn.add_theme_font_override("font", UITheme.font_display())
	hero_btn.add_theme_font_size_override("font_size", 20)
	var hero_sb := StyleBoxFlat.new()
	hero_sb.bg_color = Color("ff9f1c")
	hero_sb.border_color = Color.WHITE
	hero_sb.border_width_left = 6
	hero_sb.set_corner_radius_all(2)
	hero_sb.content_margin_left = 18
	hero_btn.add_theme_stylebox_override("normal", hero_sb)
	var hero_hover := hero_sb.duplicate() as StyleBoxFlat
	hero_hover.bg_color = Color.WHITE
	hero_hover.border_color = Color("ff1e3c")
	hero_btn.add_theme_stylebox_override("hover", hero_hover)
	hero_btn.add_theme_color_override("font_color", Color("090a0f"))
	hero_btn.add_theme_color_override("font_hover_color", Color("090a0f"))
	hero_btn.pressed.connect(_launch_quick_dive)
	left_col.add_child(hero_btn)

	var items := [
		["STAGES (7 LEVELS / 21 STAGES)", func(): AudioSyncManager.play_sfx("ui_click"); _level_select.open_browser(false, ScoringManager.MODE_NORMAL)],
		["RANKED ENDLESS", func(): AudioSyncManager.play_sfx("ui_click"); _level_select.open_browser(false, ScoringManager.MODE_RANKED)],
		["ZEN / PRACTICE MODES", func(): AudioSyncManager.play_sfx("ui_click"); _level_select.open_browser(false, ScoringManager.MODE_ZEN)],
		["COMMUNITY & CUSTOM MAPS", func(): AudioSyncManager.play_sfx("ui_click"); _level_select.open_browser(true, ScoringManager.MODE_NORMAL)],
		["LEVEL EDITOR", func(): AudioSyncManager.play_sfx("ui_click"); AudioSyncManager.stop_music(); get_tree().change_scene_to_file("res://scenes/level_editor.tscn")],
		["ACHIEVEMENTS & STATS", func(): AudioSyncManager.play_sfx("ui_click"); _ach_menu.refresh(); _ach_menu.visible = true],
		["SETTINGS & ACCESSIBILITY", func(): AudioSyncManager.play_sfx("ui_click"); _settings_menu.visible = true],
		["QUIT", func(): get_tree().quit(0)],
	]

	for entry in items:
		var btn := Button.new()
		btn.text = str(entry[0])
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 38)
		btn.pressed.connect(entry[1])
		left_col.add_child(btn)

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
