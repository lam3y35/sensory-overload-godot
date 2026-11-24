class_name CrosshairDrawer
extends Control
## Clean precision dropper crosshair with ultra-subtle micro Phase-Blink & Flow cues,
## leaving the central flight sightline unobstructed.

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
	var sz := SettingsManager.crosshair_size * (1.0 + boost_ratio * 0.10 + beat_kick * 0.04)
	var th := SettingsManager.crosshair_thickness
	var shape := SettingsManager.crosshair_shape

	if show_telemetry and not preview_mode:
		# Subtle slim Phase Blink readiness arc only while recharging or firing (keeps center minimal!)
		var dp := c + Vector2(0.0, 22.0 * sz)
		if phase_active:
			draw_circle(dp, 3.2, Color("ff9f1c"))
		elif phase_ready_ratio < 0.99:
			draw_arc(dp, 5.0, -PI * 0.5, -PI * 0.5 + TAU * phase_ready_ratio, 14, Color(1.0, 1.0, 1.0, 0.65), 1.6)
		elif boost_ratio > 0.20:
			draw_arc(c, 16.0 * sz, 0.0, TAU, 24, Color(1.0, 0.62, 0.11, 0.32 * boost_ratio), 1.5)

	match shape:
		SettingsManager.CrosshairShape.DOT:
			draw_circle(c, maxf(2.0, 3.0 * sz), Color(0.0, 0.0, 0.0, 0.78))
			draw_circle(c, maxf(1.4, 2.0 * sz), col)

		SettingsManager.CrosshairShape.CROSS:
			var arm := 10.0 * sz
			var gap := 3.5 * sz
			draw_line(c + Vector2(-arm, 0), c + Vector2(-gap, 0), col, th)
			draw_line(c + Vector2(gap, 0), c + Vector2(arm, 0), col, th)
			draw_line(c + Vector2(0, -arm), c + Vector2(0, -gap), col, th)
			draw_line(c + Vector2(0, gap), c + Vector2(0, arm), col, th)

		SettingsManager.CrosshairShape.RING:
			var rad := 9.0 * sz
			draw_arc(c, rad, 0.0, TAU, 36, Color(0.0, 0.0, 0.0, 0.68), th + 2.0)
			draw_arc(c, rad, 0.0, TAU, 36, col, th)
			draw_circle(c, maxf(1.4, th * 0.7), col)

		SettingsManager.CrosshairShape.OUTLINED_PLUS:
			var arm := 11.0 * sz
			var gap := 3.5 * sz
			var bg := Color(0.0, 0.0, 0.0, 0.88)
			draw_line(c + Vector2(-arm - 1.0, 0), c + Vector2(-gap + 1.0, 0), bg, th + 2.2)
			draw_line(c + Vector2(gap - 1.0, 0), c + Vector2(arm + 1.0, 0), bg, th + 2.2)
			draw_line(c + Vector2(0, -arm - 1.0), c + Vector2(0, -gap + 1.0), bg, th + 2.2)
			draw_line(c + Vector2(0, gap - 1.0), c + Vector2(0, arm + 1.0), bg, th + 2.2)
			draw_line(c + Vector2(-arm, 0), c + Vector2(-gap, 0), col, th)
			draw_line(c + Vector2(gap, 0), c + Vector2(arm, 0), col, th)
			draw_line(c + Vector2(0, -arm), c + Vector2(0, -gap), col, th)
			draw_line(c + Vector2(0, gap), c + Vector2(0, arm), col, th)
