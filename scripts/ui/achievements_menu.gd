class_name AchievementsMenu
extends Control
## Displays all 20 local achievements and lifetime descent/graze telemetry.

signal closed()

var _summary_lbl: Label
var _list_box: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.build_neon_theme()
	_build_ui()


func refresh() -> void:
	var gs := SaveManager.global_stats
	var count_unlocked := SaveManager.unlocked_achievements.size()
	_summary_lbl.text = (
		"Unlocked: %d / %d   |   Attempts: %d   |   Deaths: %d   |   Best Streak: %d\n" +
		"Total Grazes: %d  (Near Miss: %d  |  Daredevil: %d  |  Death Wish: %d)"
	) % [
		count_unlocked,
		AchievementCatalog.ACHIEVEMENTS.size(),
		int(gs.get("total_attempts", 0)),
		int(gs.get("total_deaths", 0)),
		int(gs.get("best_streak", 0)),
		int(gs.get("total_grazes", 0)),
		int(gs.get("total_near_miss", 0)),
		int(gs.get("total_daredevil", 0)),
		int(gs.get("total_death_wish", 0)),
	]

	for c in _list_box.get_children():
		c.queue_free()

	for ach in AchievementCatalog.ACHIEVEMENTS:
		var aid := str(ach["id"])
		var unlocked := SaveManager.is_achievement_unlocked(aid)
		var row := Label.new()
		row.text = "%s  %s — %s" % [
			"[UNLOCKED]" if unlocked else "[LOCKED]  ",
			str(ach["title"]),
			str(ach["description"]),
		]
		row.modulate = Color("22c55e") if unlocked else Color("94a3b8")
		_list_box.add_child(row)


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.015, 0.08, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(holder)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(860, 580)
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
	hdr.text = "ACHIEVEMENTS & LIFETIME TELEMETRY"
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.add_theme_font_size_override("font_size", 26)
	vbox.add_child(hdr)

	_summary_lbl = Label.new()
	_summary_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_lbl.modulate = Color("14f1d9")
	vbox.add_child(_summary_lbl)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_list_box)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): visible = false; closed.emit())
	vbox.add_child(close_btn)
