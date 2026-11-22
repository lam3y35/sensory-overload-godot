class_name CrosshairDrawer
extends Control
## Procedural vector crosshair renderer supporting Dot, Cross, Ring, and Outlined Plus
## driven live by SettingsManager color, size, and thickness overrides.

var preview_mode: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameEvents.settings_changed.connect(queue_redraw)


func _draw() -> void:
	var c := size * 0.5
	var col := SettingsManager.crosshair_color
	var sz := SettingsManager.crosshair_size
	var th := SettingsManager.crosshair_thickness
	var shape := SettingsManager.crosshair_shape

	match shape:
		SettingsManager.CrosshairShape.DOT:
			draw_circle(c, maxf(2.0, 3.2 * sz), Color(0.0, 0.0, 0.0, 0.75))
			draw_circle(c, maxf(1.5, 2.2 * sz), col)

		SettingsManager.CrosshairShape.CROSS:
			var arm := 11.0 * sz
			var gap := 4.0 * sz
			draw_line(c + Vector2(-arm, 0), c + Vector2(-gap, 0), col, th)
			draw_line(c + Vector2(gap, 0), c + Vector2(arm, 0), col, th)
			draw_line(c + Vector2(0, -arm), c + Vector2(0, -gap), col, th)
			draw_line(c + Vector2(0, gap), c + Vector2(0, arm), col, th)

		SettingsManager.CrosshairShape.RING:
			var rad := 9.5 * sz
			draw_arc(c, rad, 0.0, TAU, 36, Color(0.0, 0.0, 0.0, 0.65), th + 2.0)
			draw_arc(c, rad, 0.0, TAU, 36, col, th)
			draw_circle(c, maxf(1.5, th * 0.75), col)

		SettingsManager.CrosshairShape.OUTLINED_PLUS:
			var arm := 12.0 * sz
			var gap := 4.0 * sz
			var bg := Color(0.0, 0.0, 0.0, 0.85)
			draw_line(c + Vector2(-arm - 1.0, 0), c + Vector2(-gap + 1.0, 0), bg, th + 2.4)
			draw_line(c + Vector2(gap - 1.0, 0), c + Vector2(arm + 1.0, 0), bg, th + 2.4)
			draw_line(c + Vector2(0, -arm - 1.0), c + Vector2(0, -gap + 1.0), bg, th + 2.4)
			draw_line(c + Vector2(0, gap - 1.0), c + Vector2(0, arm + 1.0), bg, th + 2.4)
			draw_line(c + Vector2(-arm, 0), c + Vector2(-gap, 0), col, th)
			draw_line(c + Vector2(gap, 0), c + Vector2(arm, 0), col, th)
			draw_line(c + Vector2(0, -arm), c + Vector2(0, -gap), col, th)
			draw_line(c + Vector2(0, gap), c + Vector2(0, arm), col, th)
