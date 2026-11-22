extends Node
## Persists and applies controls, audio, graphics, accessibility, and crosshair settings.
## [BASED ON VERIFIED FINDING] Supports exact 1.00x mouse sensitivity step, 20%-100% obstacle
## opacity override, outline brightness/thickness sliders, speed-line toggle, and crosshair customizer.

enum InputMode {
	HYBRID_MOUSE_AND_KEYS = 0,
	MOUSE_ONLY = 1,
	KEYBOARD_ONLY = 2,
	CONTROLLER = 3,
}

enum CrosshairShape {
	DOT = 0,
	CROSS = 1,
	RING = 2,
	OUTLINED_PLUS = 3,
}

var _config_path: String = "user://settings.cfg"

# Controls
var mouse_sensitivity: float = 1.00
var input_mode: int = InputMode.HYBRID_MOUSE_AND_KEYS
var invert_y: bool = false

# Accessibility & Readability
var obstacle_opacity: float = 1.00
var outline_brightness: float = 1.15
var outline_thickness: float = 0.35
var speed_lines_enabled: bool = true
var safe_photosensitivity_mode: bool = false
var camera_comfort: bool = false

# Crosshair
var crosshair_shape: int = CrosshairShape.OUTLINED_PLUS
var crosshair_color: Color = Color("14f1d9")
var crosshair_size: float = 1.0
var crosshair_thickness: float = 2.0

# Audio
var master_volume: float = 0.85
var music_volume: float = 0.80
var sfx_volume: float = 0.85
var pause_on_death: bool = false
var restart_song_on_death: bool = false
var random_track: bool = false

# Display
var fov_base: float = 82.0
var fullscreen: bool = false
var vsync: bool = true


func _ready() -> void:
	_ensure_input_actions()
	load_settings()
	apply_all()


func set_config_path(path: String) -> void:
	_config_path = path
	reset_defaults()
	load_settings()


func reset_defaults() -> void:
	mouse_sensitivity = 1.00
	input_mode = InputMode.HYBRID_MOUSE_AND_KEYS
	invert_y = false
	obstacle_opacity = 1.00
	outline_brightness = 1.15
	outline_thickness = 0.35
	speed_lines_enabled = true
	safe_photosensitivity_mode = false
	camera_comfort = false
	crosshair_shape = CrosshairShape.OUTLINED_PLUS
	crosshair_color = Color("14f1d9")
	crosshair_size = 1.0
	crosshair_thickness = 2.0
	master_volume = 0.85
	music_volume = 0.80
	sfx_volume = 0.85
	pause_on_death = false
	restart_song_on_death = false
	random_track = false
	fov_base = 82.0
	fullscreen = false
	vsync = true


func set_mouse_sensitivity(val: float) -> void:
	mouse_sensitivity = snappedf(clampf(val, 0.20, 3.00), 0.05)


func set_obstacle_opacity(val: float) -> void:
	obstacle_opacity = clampf(val, 0.20, 1.00)


func set_outline_brightness(val: float) -> void:
	outline_brightness = clampf(val, 0.0, 2.0)


func set_outline_thickness(val: float) -> void:
	outline_thickness = clampf(val, 0.0, 1.0)


func save_settings() -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "input_mode", input_mode)
	cfg.set_value("controls", "invert_y", invert_y)

	cfg.set_value("accessibility", "obstacle_opacity", obstacle_opacity)
	cfg.set_value("accessibility", "outline_brightness", outline_brightness)
	cfg.set_value("accessibility", "outline_thickness", outline_thickness)
	cfg.set_value("accessibility", "speed_lines_enabled", speed_lines_enabled)
	cfg.set_value("accessibility", "safe_photosensitivity_mode", safe_photosensitivity_mode)
	cfg.set_value("accessibility", "camera_comfort", camera_comfort)

	cfg.set_value("crosshair", "shape", crosshair_shape)
	cfg.set_value("crosshair", "color", "#" + crosshair_color.to_html(true))
	cfg.set_value("crosshair", "size", crosshair_size)
	cfg.set_value("crosshair", "thickness", crosshair_thickness)

	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "pause_on_death", pause_on_death)
	cfg.set_value("audio", "restart_song_on_death", restart_song_on_death)
	cfg.set_value("audio", "random_track", random_track)

	cfg.set_value("display", "fov_base", fov_base)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "vsync", vsync)

	var parent_dir := _config_path.get_base_dir()
	if not parent_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(parent_dir))
	return cfg.save(_config_path)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_config_path) != OK:
		return
	set_mouse_sensitivity(float(cfg.get_value("controls", "mouse_sensitivity", 1.00)))
	input_mode = clampi(int(cfg.get_value("controls", "input_mode", InputMode.HYBRID_MOUSE_AND_KEYS)), 0, 3)
	invert_y = bool(cfg.get_value("controls", "invert_y", false))

	set_obstacle_opacity(float(cfg.get_value("accessibility", "obstacle_opacity", 1.00)))
	set_outline_brightness(float(cfg.get_value("accessibility", "outline_brightness", 1.15)))
	set_outline_thickness(float(cfg.get_value("accessibility", "outline_thickness", 0.35)))
	speed_lines_enabled = bool(cfg.get_value("accessibility", "speed_lines_enabled", true))
	safe_photosensitivity_mode = bool(cfg.get_value("accessibility", "safe_photosensitivity_mode", false))
	camera_comfort = bool(cfg.get_value("accessibility", "camera_comfort", false))

	crosshair_shape = clampi(int(cfg.get_value("crosshair", "shape", CrosshairShape.OUTLINED_PLUS)), 0, 3)
	crosshair_color = Color.from_string(str(cfg.get_value("crosshair", "color", "#14f1d9")), Color("14f1d9"))
	crosshair_size = clampf(float(cfg.get_value("crosshair", "size", 1.0)), 0.5, 2.5)
	crosshair_thickness = clampf(float(cfg.get_value("crosshair", "thickness", 2.0)), 1.0, 6.0)

	master_volume = clampf(float(cfg.get_value("audio", "master_volume", 0.85)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music_volume", 0.80)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", 0.85)), 0.0, 1.0)
	pause_on_death = bool(cfg.get_value("audio", "pause_on_death", false))
	restart_song_on_death = bool(cfg.get_value("audio", "restart_song_on_death", false))
	random_track = bool(cfg.get_value("audio", "random_track", false))

	fov_base = clampf(float(cfg.get_value("display", "fov_base", 82.0)), 65.0, 110.0)
	fullscreen = bool(cfg.get_value("display", "fullscreen", false))
	vsync = bool(cfg.get_value("display", "vsync", true))


func apply_all() -> void:
	_apply_bus_volume(&"Master", master_volume)
	_apply_bus_volume(&"Music", music_volume)
	_apply_bus_volume(&"SFX", sfx_volume)

	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
		)
		var target_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != target_mode:
			DisplayServer.window_set_mode(target_mode)

	GameEvents.settings_changed.emit()


func _apply_bus_volume(bus_name: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.0001, linear)))


func _ensure_input_actions() -> void:
	var bindings := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"pause": [KEY_ESCAPE],
		"retry": [KEY_R],
		"place_checkpoint": [KEY_C],
		"clear_checkpoint": [KEY_X],
		"editor_play_here": [KEY_P, KEY_F5],
	}
	for action_name in bindings.keys():
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name, 0.2)
		if InputMap.action_get_events(action_name).is_empty():
			for keycode in bindings[action_name]:
				var ev := InputEventKey.new()
				ev.keycode = int(keycode)
				InputMap.action_add_event(action_name, ev)
