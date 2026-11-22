extends Control
## Main Menu Hub rendered over a live animated 3D psychedelic voxel tunnel backdrop.

var _vp: SubViewport
var _tunnel: TunnelRenderer
var _cam: Camera3D
var _bg_time: float = 0.0
var _bg_depth: float = 0.0
var _palette: Array[Color] = [Color("14f1d9"), Color("ff2e93"), Color("0d051a")]

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


func _process(delta: float) -> void:
	_bg_time += delta
	_bg_depth += delta * 24.0
	if _cam != null and _tunnel != null:
		_cam.position = Vector3(0.0, -_bg_depth, 0.0)
		_cam.rotation = Vector3(-PI * 0.5, 0.0, _bg_time * 0.14)
		var mask := (1 << 0) | (1 << 1) | (1 << 4) | (1 << 5) | (1 << 6)
		_tunnel.update_tunnel(-_bg_depth, _bg_time, mask, fmod(_bg_time * 2.1, 1.0), 0.35, 0.5, _palette, 10.0)


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
	env.background_color = Color("0d051a")
	env.glow_enabled = true
	we.environment = env
	_vp.add_child(we)

	_tunnel = TunnelRenderer.new()
	_vp.add_child(_tunnel)

	_cam = Camera3D.new()
	_cam.far = 220.0
	_cam.fov = 84.0
	_cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_vp.add_child(_cam)


func _build_menu_ui() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.01, 0.06, 0.42)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	_menu_holder = CenterContainer.new()
	_menu_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_menu_holder)

	_menu_card = PanelContainer.new()
	_menu_card.custom_minimum_size = Vector2(540, 520)
	_menu_holder.add_child(_menu_card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_menu_card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 11)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "SENSORY OVERLOAD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	UITheme.apply_hud_text_outline(title, 4)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "Godot 4 Clean-Room Precision Dropper Reconstruction"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color("14f1d9")
	vbox.add_child(sub)

	var items := [
		["Play Campaign (7 Levels / 21 Stages)", func(): _level_select.open_browser(false, ScoringManager.MODE_NORMAL)],
		["Ranked Endless Mode", func(): _level_select.open_browser(false, ScoringManager.MODE_RANKED)],
		["Zen / Practice Modes", func(): _level_select.open_browser(false, ScoringManager.MODE_ZEN)],
		["Community & Custom Maps", func(): _level_select.open_browser(true, ScoringManager.MODE_NORMAL)],
		["Level Editor", func(): get_tree().change_scene_to_file("res://scenes/level_editor.tscn")],
		["Achievements & Stats", func(): _ach_menu.refresh(); _ach_menu.visible = true],
		["Settings & Accessibility", func(): _settings_menu.visible = true],
		["Quit", func(): get_tree().quit(0)],
	]

	for entry in items:
		var btn := Button.new()
		btn.text = str(entry[0])
		btn.custom_minimum_size = Vector2(0, 42)
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
