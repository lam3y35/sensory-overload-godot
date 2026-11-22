extends CanvasLayer
## In-run pause menu offering Resume, Restart, Random Song, quick Safe Mode toggle,
## Return to Editor (when testing), and Main Menu.

var _modal_root: Control
var _panel: PanelContainer
var _track_lbl: Label
var _safe_chk: CheckButton
var _editor_btn: Button


func _ready() -> void:
	layer = 40
	_build_ui()
	hide_pause()


func show_pause(is_editor_test: bool) -> void:
	_editor_btn.visible = is_editor_test
	_safe_chk.set_pressed_no_signal(SettingsManager.safe_photosensitivity_mode)
	_update_track_label()
	_modal_root.visible = true


func hide_pause() -> void:
	if _modal_root != null:
		_modal_root.visible = false


func _update_track_label() -> void:
	if _track_lbl != null:
		var idx := clampi(AudioSyncManager.current_track_index, 0, AudioSyncManager.TRACK_TITLES.size() - 1)
		_track_lbl.text = "Track: %s" % AudioSyncManager.TRACK_TITLES[idx]


func _build_ui() -> void:
	_modal_root = Control.new()
	_modal_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_root.theme = UITheme.build_neon_theme()
	add_child(_modal_root)

	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.01, 0.05, 0.62)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_root.add_child(scrim)

	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_root.add_child(holder)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(460, 380)
	holder.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var hdr := Label.new()
	hdr.text = "PAUSED"
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.add_theme_font_size_override("font_size", 28)
	vbox.add_child(hdr)

	_track_lbl = Label.new()
	_track_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_track_lbl.modulate = Color("14f1d9")
	vbox.add_child(_track_lbl)

	var resume_btn := Button.new(); resume_btn.text = "Resume (Esc)"
	resume_btn.pressed.connect(func(): get_parent().resume_game())
	vbox.add_child(resume_btn)

	var retry_btn := Button.new(); retry_btn.text = "Restart Stage (R)"
	retry_btn.pressed.connect(func(): get_parent().retry_run())
	vbox.add_child(retry_btn)

	var rand_btn := Button.new(); rand_btn.text = "Random Song"
	rand_btn.pressed.connect(func():
		AudioSyncManager.select_random_track()
		_update_track_label()
	)
	vbox.add_child(rand_btn)

	_safe_chk = CheckButton.new(); _safe_chk.text = "Photosensitivity Safe Mode"
	_safe_chk.toggled.connect(func(on: bool):
		SettingsManager.safe_photosensitivity_mode = on
		SettingsManager.save_settings()
		SettingsManager.apply_all()
	)
	vbox.add_child(_safe_chk)

	_editor_btn = Button.new(); _editor_btn.text = "Return to Editor"
	_editor_btn.pressed.connect(func(): get_parent().return_to_editor())
	vbox.add_child(_editor_btn)

	var menu_btn := Button.new(); menu_btn.text = "Main Menu"
	menu_btn.pressed.connect(func(): get_parent().exit_to_menu())
	vbox.add_child(menu_btn)
