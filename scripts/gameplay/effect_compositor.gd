class_name EffectCompositor
extends CanvasLayer
## Drives the 24-bit post-processing screen shader synchronized to EffectCatalog,
## AudioSyncManager beat/FFT energy, Flow meter, and SettingsManager Accessibility overrides.

var _rect: ColorRect
var _mat: ShaderMaterial
var last_applied_mask: int = 0
var last_safe_mode: bool = false


func _ready() -> void:
	layer = 5
	_ensure_postprocess_quad()


func _ensure_postprocess_quad() -> void:
	if _rect != null:
		return
	_rect = ColorRect.new()
	_rect.name = "PostProcessQuad"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shader := load("res://shaders/sensory_postprocess.gdshader") as Shader
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_rect.material = _mat
	add_child(_rect)


func apply_effects(
	raw_mask: int,
	elapsed_time: float,
	speed: float,
	beat_phase: float,
	bass_energy: float,
	flow: float,
	boost_level: float = 0.0,
	flash_strength: float = 0.0,
	flash_color: Color = Color("14f1d9")
) -> void:
	_ensure_postprocess_quad()
	last_safe_mode = SettingsManager.safe_photosensitivity_mode
	var eff_mask := EffectCatalog.clamp_safe_mask(raw_mask, last_safe_mode)
	last_applied_mask = eff_mask

	var speed_lines_on := EffectCatalog.has_effect(eff_mask, 11) and SettingsManager.speed_lines_enabled
	var effective_boost := clampf(boost_level, 0.0, 1.0) if SettingsManager.speed_lines_enabled else clampf(boost_level * 0.25, 0.0, 0.25)
	var has_screen_fx := ((eff_mask & (~((1 << 11) - 1))) != 0) or boost_level > 0.01 or flash_strength > 0.01
	_rect.visible = has_screen_fx
	if not has_screen_fx:
		return
	_mat.set_shader_parameter("u_time", elapsed_time)
	_mat.set_shader_parameter("u_speed", speed)
	_mat.set_shader_parameter("u_beat_phase", beat_phase)
	_mat.set_shader_parameter("u_bass_energy", bass_energy)
	_mat.set_shader_parameter("u_flow", flow)
	_mat.set_shader_parameter("u_safe_mode", 1.0 if last_safe_mode else 0.0)
	_mat.set_shader_parameter("u_boost", effective_boost)
	_mat.set_shader_parameter("u_flash_strength", clampf(flash_strength, 0.0, 1.0))
	_mat.set_shader_parameter("u_flash_color", flash_color)

	_mat.set_shader_parameter("u_bit_speed_lines", 1.0 if speed_lines_on else 0.0)
	_mat.set_shader_parameter("u_bit_chromatic", 1.0 if EffectCatalog.has_effect(eff_mask, 12) else 0.0)
	_mat.set_shader_parameter("u_bit_kaleidoscope", 1.0 if EffectCatalog.has_effect(eff_mask, 13) else 0.0)
	_mat.set_shader_parameter("u_bit_fisheye", 1.0 if EffectCatalog.has_effect(eff_mask, 14) else 0.0)
	_mat.set_shader_parameter("u_bit_barrel", 1.0 if EffectCatalog.has_effect(eff_mask, 15) else 0.0)
	_mat.set_shader_parameter("u_bit_strobe", 1.0 if EffectCatalog.has_effect(eff_mask, 16) else 0.0)
	_mat.set_shader_parameter("u_bit_hue_shift", 1.0 if EffectCatalog.has_effect(eff_mask, 17) else 0.0)
	_mat.set_shader_parameter("u_bit_invert", 1.0 if EffectCatalog.has_effect(eff_mask, 18) else 0.0)
	_mat.set_shader_parameter("u_bit_scanlines", 1.0 if EffectCatalog.has_effect(eff_mask, 19) else 0.0)
	_mat.set_shader_parameter("u_bit_vignette", 1.0 if EffectCatalog.has_effect(eff_mask, 20) else 0.0)
	_mat.set_shader_parameter("u_bit_pixel_crunch", 1.0 if EffectCatalog.has_effect(eff_mask, 21) else 0.0)
	_mat.set_shader_parameter("u_bit_contrast", 1.0 if EffectCatalog.has_effect(eff_mask, 22) else 0.0)
	_mat.set_shader_parameter("u_bit_whiteout", 1.0 if EffectCatalog.has_effect(eff_mask, 23) else 0.0)
