class_name SettingsMenu
extends Control
## Tabbed Settings & Accessibility suite:
## - Controls (exact 0.05 step mouse sensitivity slider hitting 1.00x, Input Mode, Invert Y)
## - Accessibility (20%-100% Obstacle Opacity, Outline Brightness/Thickness, Speed Lines,
##   Photosensitivity Safe Mode, Camera Comfort, live Crosshair Customizer)
## - Audio (Master/Music/SFX, Pause on Death, Restart Song on Death, Random Track)
## - Display (Base FOV, Fullscreen, VSync)

signal closed()

var _sens_val_lbl: Label
var _opacity_val_lbl: Label
var _bright_val_lbl: Label
var _thick_val_lbl: Label
var _fov_val_lbl: Label
var _syncing: bool = false
var _tabs: TabContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.build_neon_theme()
	_build_ui()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.05, 0.92)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(holder)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(840, 580)
	holder.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var hdr := Label.new()
	hdr.text = "SETTINGS & ACCESSIBILITY"
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.add_theme_font_size_override("font_size", 26)
	vbox.add_child(hdr)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_tabs)

	_build_controls_tab()
	_build_accessibility_tab()
	_build_audio_tab()
	_build_display_tab()

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 12)
	vbox.add_child(foot)

	var reset_btn := Button.new()
	reset_btn.text = "Reset Defaults"
	reset_btn.pressed.connect(func():
		SettingsManager.reset_defaults()
		SettingsManager.save_settings()
		SettingsManager.apply_all()
		_rebuild_all_tabs()
	)
	foot.add_child(reset_btn)

	var close_btn := Button.new()
	close_btn.text = "Save & Close"
	close_btn.pressed.connect(func():
		SettingsManager.save_settings()
		SettingsManager.apply_all()
		visible = false
		closed.emit()
	)
	foot.add_child(close_btn)


func _rebuild_all_tabs() -> void:
	for c in _tabs.get_children():
		c.queue_free()
	_build_controls_tab()
	_build_accessibility_tab()
	_build_audio_tab()
	_build_display_tab()


func _build_controls_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Controls"
	tab.add_theme_constant_override("separation", 12)
	_tabs.add_child(tab)

	# Sensitivity with exact 0.05 step
	var row := HBoxContainer.new()
	tab.add_child(row)
	var lbl := Label.new(); lbl.text = "Mouse Sensitivity"; lbl.custom_minimum_size = Vector2(210, 0)
	var sl := HSlider.new()
	sl.min_value = 0.20; sl.max_value = 3.00; sl.step = 0.05
	sl.value = SettingsManager.mouse_sensitivity
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sens_val_lbl = Label.new()
	_sens_val_lbl.custom_minimum_size = Vector2(70, 0)
	_sens_val_lbl.text = "%.2fx" % SettingsManager.mouse_sensitivity
	sl.value_changed.connect(func(v: float):
		SettingsManager.set_mouse_sensitivity(v)
		_sens_val_lbl.text = "%.2fx" % SettingsManager.mouse_sensitivity
	)
	row.add_child(lbl); row.add_child(sl); row.add_child(_sens_val_lbl)

	var im_row := HBoxContainer.new()
	tab.add_child(im_row)
	var im_lbl := Label.new(); im_lbl.text = "Input Mode"; im_lbl.custom_minimum_size = Vector2(210, 0)
	var im_opt := OptionButton.new()
	im_opt.add_item("Hybrid (Mouse + Keyboard + Pad)")
	im_opt.add_item("Mouse Only")
	im_opt.add_item("Keyboard Only")
	im_opt.add_item("Controller")
	im_opt.select(SettingsManager.input_mode)
	im_opt.item_selected.connect(func(idx: int): SettingsManager.input_mode = idx)
	im_row.add_child(im_lbl); im_row.add_child(im_opt)

	var inv := CheckButton.new(); inv.text = "Invert Vertical Look / Steering"
	inv.button_pressed = SettingsManager.invert_y
	inv.toggled.connect(func(on: bool): SettingsManager.invert_y = on)
	tab.add_child(inv)


func _build_accessibility_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Accessibility"
	_tabs.add_child(scroll)
	var tab := VBoxContainer.new()
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_theme_constant_override("separation", 10)
	scroll.add_child(tab)

	_opacity_val_lbl = _add_slider_row(tab, "Obstacle Opacity", 0.20, 1.00, 0.05, SettingsManager.obstacle_opacity,
		func(v: float) -> String:
			SettingsManager.set_obstacle_opacity(v)
			return "%d%%" % int(round(SettingsManager.obstacle_opacity * 100.0))
	)
	_bright_val_lbl = _add_slider_row(tab, "Outline Brightness", 0.0, 2.0, 0.05, SettingsManager.outline_brightness,
		func(v: float) -> String:
			SettingsManager.set_outline_brightness(v)
			return "%.2f" % SettingsManager.outline_brightness
	)
	_thick_val_lbl = _add_slider_row(tab, "Outline Thickness", 0.0, 1.0, 0.05, SettingsManager.outline_thickness,
		func(v: float) -> String:
			SettingsManager.set_outline_thickness(v)
			return "%.2f" % SettingsManager.outline_thickness
	)

	var sl_chk := CheckButton.new(); sl_chk.text = "Enable Speed Lines"
	sl_chk.button_pressed = SettingsManager.speed_lines_enabled
	sl_chk.toggled.connect(func(on: bool): SettingsManager.speed_lines_enabled = on)
	tab.add_child(sl_chk)

	var safe_chk := CheckButton.new(); safe_chk.text = "Photosensitivity Safe Mode (Disables Strobe / Invert / Whiteout)"
	safe_chk.button_pressed = SettingsManager.safe_photosensitivity_mode
	safe_chk.toggled.connect(func(on: bool): SettingsManager.safe_photosensitivity_mode = on)
	tab.add_child(safe_chk)

	var cc_chk := CheckButton.new(); cc_chk.text = "Camera Comfort (Reduces Spiral Roll & Bank Intensity)"
	cc_chk.button_pressed = SettingsManager.camera_comfort
	cc_chk.toggled.connect(func(on: bool): SettingsManager.camera_comfort = on)
	tab.add_child(cc_chk)

	# Crosshair customizer with live preview
	var ch_hdr := Label.new(); ch_hdr.text = "\nCrosshair Customizer"
	tab.add_child(ch_hdr)

	var preview_panel := ColorRect.new()
	preview_panel.color = Color("120824")
	preview_panel.custom_minimum_size = Vector2(0, 72)
	tab.add_child(preview_panel)
	var ch_preview := CrosshairDrawer.new()
	ch_preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_panel.add_child(ch_preview)

	var sh_row := HBoxContainer.new(); tab.add_child(sh_row)
	var sh_lbl := Label.new(); sh_lbl.text = "Crosshair Shape"; sh_lbl.custom_minimum_size = Vector2(210, 0)
	var sh_opt := OptionButton.new()
	sh_opt.add_item("Dot"); sh_opt.add_item("Cross"); sh_opt.add_item("Ring"); sh_opt.add_item("Outlined Plus")
	sh_opt.select(SettingsManager.crosshair_shape)
	sh_opt.item_selected.connect(func(idx: int):
		SettingsManager.crosshair_shape = idx
		ch_preview.queue_redraw()
	)
	sh_row.add_child(sh_lbl); sh_row.add_child(sh_opt)

	var col_row := HBoxContainer.new(); tab.add_child(col_row)
	var col_lbl := Label.new(); col_lbl.text = "Crosshair Color"; col_lbl.custom_minimum_size = Vector2(210, 0)
	var col_pick := ColorPickerButton.new()
	col_pick.custom_minimum_size = Vector2(90, 30)
	col_pick.color = SettingsManager.crosshair_color
	col_pick.color_changed.connect(func(c: Color):
		SettingsManager.crosshair_color = c
		ch_preview.queue_redraw()
	)
	col_row.add_child(col_lbl); col_row.add_child(col_pick)

	_add_slider_row(tab, "Crosshair Size", 0.5, 2.5, 0.1, SettingsManager.crosshair_size,
		func(v: float) -> String:
			SettingsManager.crosshair_size = v
			ch_preview.queue_redraw()
			return "%.1fx" % v
	)
	_add_slider_row(tab, "Crosshair Thickness", 1.0, 6.0, 0.5, SettingsManager.crosshair_thickness,
		func(v: float) -> String:
			SettingsManager.crosshair_thickness = v
			ch_preview.queue_redraw()
			return "%.1f px" % v
	)


func _build_audio_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Audio"
	tab.add_theme_constant_override("separation", 10)
	_tabs.add_child(tab)

	_add_slider_row(tab, "Master Volume", 0.0, 1.0, 0.05, SettingsManager.master_volume,
		func(v: float) -> String:
			SettingsManager.master_volume = v
			SettingsManager.apply_all()
			return "%d%%" % int(round(v * 100.0))
	)
	_add_slider_row(tab, "Music Volume", 0.0, 1.0, 0.05, SettingsManager.music_volume,
		func(v: float) -> String:
			SettingsManager.music_volume = v
			SettingsManager.apply_all()
			return "%d%%" % int(round(v * 100.0))
	)
	_add_slider_row(tab, "SFX Volume", 0.0, 1.0, 0.05, SettingsManager.sfx_volume,
		func(v: float) -> String:
			SettingsManager.sfx_volume = v
			SettingsManager.apply_all()
			return "%d%%" % int(round(v * 100.0))
	)

	var p_death := CheckButton.new(); p_death.text = "Pause Music on Death"
	p_death.button_pressed = SettingsManager.pause_on_death
	p_death.toggled.connect(func(on: bool): SettingsManager.pause_on_death = on)
	tab.add_child(p_death)

	var r_death := CheckButton.new(); r_death.text = "Restart Song on Death / Retry"
	r_death.button_pressed = SettingsManager.restart_song_on_death
	r_death.toggled.connect(func(on: bool): SettingsManager.restart_song_on_death = on)
	tab.add_child(r_death)

	var r_track := CheckButton.new(); r_track.text = "Randomize Track on Retry"
	r_track.button_pressed = SettingsManager.random_track
	r_track.toggled.connect(func(on: bool): SettingsManager.random_track = on)
	tab.add_child(r_track)


func _build_display_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Display"
	tab.add_theme_constant_override("separation", 10)
	_tabs.add_child(tab)

	_fov_val_lbl = _add_slider_row(tab, "Base Camera FOV", 65.0, 110.0, 1.0, SettingsManager.fov_base,
		func(v: float) -> String:
			SettingsManager.fov_base = v
			return "%.0f deg" % v
	)

	var fs := CheckButton.new(); fs.text = "Fullscreen Window"
	fs.button_pressed = SettingsManager.fullscreen
	fs.toggled.connect(func(on: bool): SettingsManager.fullscreen = on)
	tab.add_child(fs)

	var vs := CheckButton.new(); vs.text = "Enable VSync"
	vs.button_pressed = SettingsManager.vsync
	vs.toggled.connect(func(on: bool): SettingsManager.vsync = on)
	tab.add_child(vs)


func _add_slider_row(parent: Control, title: String, mn: float, mx: float, st: float, init_val: float, on_change: Callable) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new(); lbl.text = title; lbl.custom_minimum_size = Vector2(210, 0)
	var sl := HSlider.new(); sl.min_value = mn; sl.max_value = mx; sl.step = st; sl.value = init_val
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val_lbl := Label.new(); val_lbl.custom_minimum_size = Vector2(75, 0)
	val_lbl.text = str(on_change.call(init_val))
	sl.value_changed.connect(func(v: float):
		val_lbl.text = str(on_change.call(v))
	)
	row.add_child(lbl); row.add_child(sl); row.add_child(val_lbl)
	return val_lbl
