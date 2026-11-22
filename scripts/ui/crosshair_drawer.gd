class_name CrosshairDrawer
extends Control
## Precision eye-centered cyber-HUD reticle displaying live Flow Lock arc,
## Boost/Chain crescent, cockpit tunnel-margin indicator, and Phase Dash diamond readiness.

var preview_mode: bool = false
var show_telemetry: bool = false
var flow_ratio: float = 0.0
var flow_locked: bool = false
var chain_ratio: float = 0.0
var chain_mult: float = 1.0
var boost_ratio: float = 0.0
var beat_kick: float = 0.0
var tunnel_pos_norm: Vector2 = Vector2.ZERO
var phase_ready_ratio: float = 1.0
var phase_active: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameEvents.settings_changed.connect(queue_redraw)


func update_telemetry(
	p_flow: float,
	p_flow_locked: bool,
	p_chain_ratio: float,
	p_chain_mult: float,
	p_boost_ratio: float,
	p_beat_kick: float,
	p_tunnel_norm: Vector2,
	p_phase_ready: float = 1.0,
	p_phase_active: bool = false
) -> void:
	show_telemetry = true
	flow_ratio = clampf(p_flow, 0.0, 1.0)
	flow_locked = p_flow_locked
	chain_ratio = clampf(p_chain_ratio, 0.0, 1.0)
	chain_mult = p_chain_mult
	boost_ratio = clampf(p_boost_ratio, 0.0, 1.0)
	beat_kick = clampf(p_beat_kick, 0.0, 1.0)
	tunnel_pos_norm = p_tunnel_norm
	phase_ready_ratio = clampf(p_phase_ready, 0.0, 1.0)
	phase_active = p_phase_active
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var col := SettingsManager.crosshair_color
	var sz := SettingsManager.crosshair_size * (1.0 + boost_ratio * 0.14 + beat_kick * 0.06)
	var th := SettingsManager.crosshair_thickness
	var shape := SettingsManager.crosshair_shape

	if show_telemetry and not preview_mode:
		var arc_r := 28.0 + boost_ratio * 4.5 + beat_kick * 1.5
		# Subtle tunnel clearance boundary circle + cockpit position dot
		draw_arc(c, arc_r, 0.0, TAU, 40, Color(0.75, 0.88, 1.0, 0.14), 1.4)
		var dot_pos := c + tunnel_pos_norm.limit_length(1.0) * (arc_r - 6.0)
		var dot_col := Color("facc15") if boost_ratio > 0.25 else Color("14f1d9")
		draw_circle(dot_pos, 3.0, Color(0.0, 0.0, 0.0, 0.75))
		draw_circle(dot_pos, 2.1, dot_col)

		# Right crescent: Flow Meter (Cyan -> blazing Gold when Color Locked)
		var flow_bg := Color(0.05, 0.04, 0.12, 0.55)
		draw_arc(c, arc_r, -0.78, 0.78, 18, flow_bg, 4.2)
		if flow_ratio > 0.01:
			var f_col := Color("facc15") if flow_locked else Color("14f1d9")
			draw_arc(c, arc_r, -0.78, lerpf(-0.78, 0.78, flow_ratio), 18, f_col, 2.8)

		# Left crescent: Boost / Chain Timer Meter
		draw_arc(c, arc_r, PI - 0.78, PI + 0.78, 18, flow_bg, 4.2)
		var left_fill := maxf(boost_ratio, chain_ratio)
		if left_fill > 0.01:
			var b_col := Color("facc15") if boost_ratio > 0.15 else Color("ff2e93")
			draw_arc(c, arc_r, PI + 0.78, lerpf(PI + 0.78, PI - 0.78, left_fill), 18, b_col, 2.8)

		# Bottom Phase Dash diamond readiness gauge
		var dp := c + Vector2(0.0, arc_r + 10.0)
		var dr := 5.2 + (2.0 if phase_active else (1.0 * beat_kick if phase_ready_ratio >= 0.99 else 0.0))
		var pts := PackedVector2Array([
			dp + Vector2(0.0, -dr),
			dp + Vector2(dr, 0.0),
			dp + Vector2(0.0, dr),
			dp + Vector2(-dr, 0.0),
		])
		if phase_active:
			draw_colored_polygon(pts, Color("facc15"))
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color.WHITE, 1.8)
		elif phase_ready_ratio >= 0.99:
			draw_colored_polygon(pts, Color("14f1d9"))
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0.0, 0.0, 0.0, 0.85), 1.4)
		else:
			draw_colored_polygon(pts, Color(0.06, 0.05, 0.14, 0.7))
			draw_arc(dp, dr + 1.5, -PI * 0.5, -PI * 0.5 + TAU * phase_ready_ratio, 16, Color("38bdf8"), 2.0)

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
