class_name UITheme
extends RefCounted
## Commercial brutalist architectural UI theme factory powered by bundled OFL fonts
## (Russo One display, Chakra Petch bold / bold-italic / semibold UI & HUD).

const FONT_DISPLAY_PATH := "res://assets/fonts/RussoOne-Regular.ttf"
const FONT_BOLD_PATH := "res://assets/fonts/ChakraPetch-Bold.ttf"
const FONT_ITALIC_PATH := "res://assets/fonts/ChakraPetch-BoldItalic.ttf"
const FONT_REGULAR_PATH := "res://assets/fonts/ChakraPetch-SemiBold.ttf"

const COL_BG := Color(0.039, 0.043, 0.059, 0.92)
const COL_SURFACE := Color(0.067, 0.075, 0.106, 0.94)
const COL_HOVER := Color(0.110, 0.125, 0.176, 0.98)
const COL_PRESSED := Color(0.180, 0.055, 0.085, 0.98)
const COL_BORDER := Color(0.20, 0.23, 0.30, 0.90)
const COL_AMBER := Color("ff9f1c")
const COL_CRIMSON := Color("ff1e3c")
const COL_CYAN := Color("38bdf8")
const COL_EMERALD := Color("22c55e")
const COL_TEXT := Color("f8fafc")
const COL_MUTED := Color("94a3b8")

static var _cached_theme: Theme = null
static var _font_display: Font = null
static var _font_bold: Font = null
static var _font_italic: Font = null
static var _font_regular: Font = null


static func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f := ResourceLoader.load(path) as Font
		if f != null:
			return f
	return ThemeDB.fallback_font


static func font_display() -> Font:
	if _font_display == null:
		_font_display = _load_font(FONT_DISPLAY_PATH)
	return _font_display


static func font_bold() -> Font:
	if _font_bold == null:
		_font_bold = _load_font(FONT_BOLD_PATH)
	return _font_bold


static func font_italic() -> Font:
	if _font_italic == null:
		_font_italic = _load_font(FONT_ITALIC_PATH)
	return _font_italic


static func font_regular() -> Font:
	if _font_regular == null:
		_font_regular = _load_font(FONT_REGULAR_PATH)
	return _font_regular


static func build_neon_theme() -> Theme:
	if _cached_theme != null:
		return _cached_theme

	var t := Theme.new()
	t.default_font = font_regular()
	t.default_font_size = 16

	# Brutalist dark architectural PanelContainer with crisp hairline frame
	var panel_box := StyleBoxFlat.new()
	panel_box.bg_color = COL_BG
	panel_box.border_color = COL_BORDER
	panel_box.set_border_width_all(1)
	panel_box.border_width_top = 2
	panel_box.set_corner_radius_all(2)
	panel_box.content_margin_left = 18
	panel_box.content_margin_right = 18
	panel_box.content_margin_top = 14
	panel_box.content_margin_bottom = 14
	t.set_stylebox("panel", "PanelContainer", panel_box)

	# Crisp sharp-corner buttons with directional amber hover accent bar
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = COL_SURFACE
	btn_normal.border_color = COL_BORDER
	btn_normal.set_border_width_all(1)
	btn_normal.set_corner_radius_all(2)
	btn_normal.content_margin_left = 16
	btn_normal.content_margin_right = 16
	btn_normal.content_margin_top = 9
	btn_normal.content_margin_bottom = 9
	t.set_stylebox("normal", "Button", btn_normal)

	var btn_hover := btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = COL_HOVER
	btn_hover.border_color = COL_AMBER
	btn_hover.border_width_left = 4
	t.set_stylebox("hover", "Button", btn_hover)
	t.set_stylebox("focus", "Button", btn_hover)

	var btn_pressed := btn_normal.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = COL_PRESSED
	btn_pressed.border_color = COL_CRIMSON
	btn_pressed.border_width_left = 4
	t.set_stylebox("pressed", "Button", btn_pressed)

	var btn_disabled := btn_normal.duplicate() as StyleBoxFlat
	btn_disabled.bg_color = Color(0.05, 0.05, 0.07, 0.65)
	btn_disabled.border_color = Color(0.22, 0.24, 0.30, 0.45)
	t.set_stylebox("disabled", "Button", btn_disabled)

	t.set_font("font", "Button", font_bold())
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.48, 0.56, 0.72))
	t.set_color("font_color", "Button", COL_TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", COL_AMBER)

	# TabContainer
	var tab_panel := panel_box.duplicate() as StyleBoxFlat
	tab_panel.bg_color = Color(0.047, 0.051, 0.071, 0.95)
	tab_panel.border_color = COL_BORDER
	tab_panel.set_border_width_all(1)
	t.set_stylebox("panel", "TabContainer", tab_panel)

	var tab_sel := btn_hover.duplicate() as StyleBoxFlat
	tab_sel.border_width_left = 1
	tab_sel.border_width_top = 3
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)

	var tab_unsel := btn_normal.duplicate() as StyleBoxFlat
	t.set_stylebox("tab_unselected", "TabContainer", tab_unsel)
	t.set_font("font", "TabContainer", font_bold())

	# ItemList & LineEdit
	var list_bg := StyleBoxFlat.new()
	list_bg.bg_color = Color(0.035, 0.039, 0.055, 0.95)
	list_bg.border_color = COL_BORDER
	list_bg.set_border_width_all(1)
	list_bg.set_corner_radius_all(2)
	list_bg.content_margin_left = 10
	list_bg.content_margin_right = 10
	list_bg.content_margin_top = 8
	list_bg.content_margin_bottom = 8
	t.set_stylebox("panel", "ItemList", list_bg)
	t.set_stylebox("normal", "LineEdit", list_bg)

	# ProgressBar
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(0.08, 0.09, 0.12, 0.88)
	pb_bg.set_corner_radius_all(1)
	t.set_stylebox("background", "ProgressBar", pb_bg)

	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = COL_AMBER
	pb_fill.set_corner_radius_all(1)
	t.set_stylebox("fill", "ProgressBar", pb_fill)

	_cached_theme = t
	return t


static func make_hud_pill(accent: Color = COL_AMBER) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.039, 0.055, 0.78)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.85)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(1)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	return p


static func apply_hud_text_outline(lbl: Label, outline_px: int = 4) -> void:
	lbl.add_theme_color_override("font_outline_color", Color(0.01, 0.01, 0.02, 0.96))
	lbl.add_theme_constant_override("outline_size", outline_px)
	lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)


static func style_display_label(lbl: Label, font_px: int, use_italic: bool = false) -> void:
	lbl.add_theme_font_override("font", font_italic() if use_italic else font_display())
	lbl.add_theme_font_size_override("font_size", font_px)
	apply_hud_text_outline(lbl, maxi(3, font_px / 8))
