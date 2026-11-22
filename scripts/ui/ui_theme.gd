class_name UITheme
extends RefCounted
## Cyber-neon arcade UI theme factory & high-contrast HUD styling helpers (QA-05).

static var _cached_theme: Theme = null


static func build_neon_theme() -> Theme:
	if _cached_theme != null:
		return _cached_theme

	var t := Theme.new()
	t.default_font_size = 16

	# Main PanelContainer style: deep translucent obsidian-violet with cyan neon rim
	var panel_box := StyleBoxFlat.new()
	panel_box.bg_color = Color(0.039, 0.024, 0.094, 0.90)
	panel_box.border_color = Color("14f1d9")
	panel_box.set_border_width_all(2)
	panel_box.set_corner_radius_all(8)
	panel_box.content_margin_left = 14
	panel_box.content_margin_right = 14
	panel_box.content_margin_top = 12
	panel_box.content_margin_bottom = 12
	t.set_stylebox("panel", "PanelContainer", panel_box)

	# Buttons: cyber glass normal / glowing cyan hover / magenta pressed
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.078, 0.063, 0.161, 0.92)
	btn_normal.border_color = Color("38bdf8")
	btn_normal.set_border_width_all(1)
	btn_normal.set_corner_radius_all(6)
	btn_normal.content_margin_left = 14
	btn_normal.content_margin_right = 14
	btn_normal.content_margin_top = 8
	btn_normal.content_margin_bottom = 8
	t.set_stylebox("normal", "Button", btn_normal)

	var btn_hover := btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(0.122, 0.098, 0.259, 0.96)
	btn_hover.border_color = Color("14f1d9")
	btn_hover.set_border_width_all(2)
	t.set_stylebox("hover", "Button", btn_hover)

	var btn_pressed := btn_normal.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = Color(0.176, 0.086, 0.294, 0.98)
	btn_pressed.border_color = Color("ff2e93")
	btn_pressed.set_border_width_all(2)
	t.set_stylebox("pressed", "Button", btn_pressed)

	var btn_disabled := btn_normal.duplicate() as StyleBoxFlat
	btn_disabled.bg_color = Color(0.05, 0.04, 0.09, 0.65)
	btn_disabled.border_color = Color(0.35, 0.38, 0.45, 0.5)
	t.set_stylebox("disabled", "Button", btn_disabled)
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.58, 0.65, 0.75))
	t.set_color("font_color", "Button", Color("f8fafc"))
	t.set_color("font_hover_color", "Button", Color("14f1d9"))

	# TabContainer
	var tab_panel := panel_box.duplicate() as StyleBoxFlat
	tab_panel.bg_color = Color(0.047, 0.031, 0.114, 0.94)
	tab_panel.border_color = Color("38bdf8")
	tab_panel.set_border_width_all(1)
	t.set_stylebox("panel", "TabContainer", tab_panel)

	var tab_sel := btn_hover.duplicate() as StyleBoxFlat
	tab_sel.set_corner_radius_all(4)
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)

	var tab_unsel := btn_normal.duplicate() as StyleBoxFlat
	tab_unsel.set_corner_radius_all(4)
	t.set_stylebox("tab_unselected", "TabContainer", tab_unsel)

	# ItemList & LineEdit
	var list_bg := StyleBoxFlat.new()
	list_bg.bg_color = Color(0.035, 0.022, 0.082, 0.94)
	list_bg.border_color = Color("38bdf8")
	list_bg.set_border_width_all(1)
	list_bg.set_corner_radius_all(6)
	list_bg.content_margin_left = 8
	list_bg.content_margin_right = 8
	list_bg.content_margin_top = 6
	list_bg.content_margin_bottom = 6
	t.set_stylebox("panel", "ItemList", list_bg)
	t.set_stylebox("normal", "LineEdit", list_bg)

	# ProgressBar
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(0.071, 0.047, 0.141, 0.85)
	pb_bg.border_color = Color(0.22, 0.74, 0.97, 0.45)
	pb_bg.set_border_width_all(1)
	pb_bg.set_corner_radius_all(4)
	t.set_stylebox("background", "ProgressBar", pb_bg)

	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = Color("14f1d9")
	pb_fill.set_corner_radius_all(4)
	t.set_stylebox("fill", "ProgressBar", pb_fill)

	_cached_theme = t
	return t


static func make_hud_pill(accent: Color = Color("14f1d9")) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.02, 0.085, 0.74)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.75)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	return p


static func apply_hud_text_outline(lbl: Label, outline_px: int = 4) -> void:
	lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.01, 0.05, 0.95))
	lbl.add_theme_constant_override("outline_size", outline_px)
