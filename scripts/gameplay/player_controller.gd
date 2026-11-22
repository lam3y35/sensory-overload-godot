class_name PlayerController
extends Node3D
## First-person vertical dropper controller supporting screen-aligned Mouse/Keyboard/Gamepad steering
## under camera roll, zero double-integration drift, smooth cylindrical boundary slide,
## dynamic boost FOV punch, and subtle micro-shake feedback.

const PLAY_RADIUS := 8.6
const KEY_MAX_SPEED := 26.0
const KEY_ACCEL := 220.0
const KEY_DAMP := 20.0
const MOUSE_SCALE := 0.018

var camera: Camera3D
var position_3d: Vector3 = Vector3.ZERO
var velocity_xz: Vector2 = Vector2.ZERO
var current_roll: float = 0.0
var spiral_roll_acc: float = 0.0
var fov_punch: float = 0.0
var shake_trauma: float = 0.0

var _bank_vel_x: float = 0.0
var _shake_phase: float = 0.0
var _pending_mouse_delta: Vector2 = Vector2.ZERO


func _ready() -> void:
	_ensure_camera()


func _ensure_camera() -> void:
	if camera != null:
		return
	camera = Camera3D.new()
	camera.name = "DropCamera"
	camera.near = 0.15
	camera.far = 260.0
	camera.fov = SettingsManager.fov_base
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	add_child(camera)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_pending_mouse_delta += mm.relative


func reset_at(depth_m: float, xz: Vector2 = Vector2.ZERO) -> void:
	_ensure_camera()
	var clamped_xz := clamp_xz_to_tunnel(xz)
	position_3d = Vector3(clamped_xz.x, -maxf(0.0, depth_m), clamped_xz.y)
	velocity_xz = Vector2.ZERO
	current_roll = 0.0
	spiral_roll_acc = 0.0
	fov_punch = 0.0
	shake_trauma = 0.0
	_bank_vel_x = 0.0
	_pending_mouse_delta = Vector2.ZERO
	_sync_camera_transform()


func set_replay_pose(pos: Vector3, roll_rad: float) -> void:
	_ensure_camera()
	position_3d = pos
	current_roll = roll_rad
	fov_punch = 0.0
	shake_trauma = 0.0
	_sync_camera_transform()


func add_fov_punch(deg: float) -> void:
	fov_punch = clampf(fov_punch + deg, 0.0, 14.0)


func add_shake(amount: float) -> void:
	shake_trauma = clampf(shake_trauma + amount, 0.0, 1.0)


func get_screen_axes_xz() -> Dictionary:
	_ensure_camera()
	var cb := camera.transform.basis
	var right_xz := Vector2(cb.x.x, cb.x.z)
	if right_xz.length_squared() < 1e-6:
		right_xz = Vector2.RIGHT
	else:
		right_xz = right_xz.normalized()
	var down_xz := Vector2(-cb.y.x, -cb.y.z)
	if down_xz.length_squared() < 1e-6:
		down_xz = Vector2.DOWN
	else:
		down_xz = down_xz.normalized()
	return {"right": right_xz, "down": down_xz}


func apply_input_and_step(
	delta: float,
	forward_speed: float,
	autopilot: bool,
	autopilot_target_xz: Vector2 = Vector2.ZERO
) -> Dictionary:
	var prev_pos := position_3d
	var mouse_delta := _pending_mouse_delta
	_pending_mouse_delta = Vector2.ZERO

	if autopilot:
		var offset := autopilot_target_xz - Vector2(position_3d.x, position_3d.z)
		var desired_vel := offset * 5.2
		if desired_vel.length() > KEY_MAX_SPEED:
			desired_vel = desired_vel.normalized() * KEY_MAX_SPEED
		velocity_xz = velocity_xz.lerp(desired_vel, clampf(delta * 9.0, 0.0, 1.0))
		position_3d.x += velocity_xz.x * delta
		position_3d.z += velocity_xz.y * delta
		_bank_vel_x = lerpf(_bank_vel_x, velocity_xz.x, clampf(delta * 10.0, 0.0, 1.0))
	else:
		var sens := SettingsManager.mouse_sensitivity
		var mode := SettingsManager.input_mode
		var allow_mouse := (mode == SettingsManager.InputMode.HYBRID_MOUSE_AND_KEYS or mode == SettingsManager.InputMode.MOUSE_ONLY)
		var allow_keys := (mode == SettingsManager.InputMode.HYBRID_MOUSE_AND_KEYS or mode == SettingsManager.InputMode.KEYBOARD_ONLY)
		var allow_pad := (mode == SettingsManager.InputMode.HYBRID_MOUSE_AND_KEYS or mode == SettingsManager.InputMode.CONTROLLER)

		var steer_vec := Vector2.ZERO
		if allow_keys:
			steer_vec.x += Input.get_axis("move_left", "move_right")
			steer_vec.y += Input.get_axis("move_up", "move_down")
		if allow_pad:
			var jx := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
			var jy := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
			if absf(jx) > 0.12:
				steer_vec.x += jx
			if absf(jy) > 0.12:
				steer_vec.y += jy
		if SettingsManager.invert_y:
			steer_vec.y = -steer_vec.y

		if steer_vec.length_squared() > 1.0:
			steer_vec = steer_vec.normalized()

		var axes := get_screen_axes_xz()
		var right_xz := axes["right"] as Vector2
		var down_xz := axes["down"] as Vector2
		var screen_steer_world := right_xz * steer_vec.x + down_xz * steer_vec.y

		if screen_steer_world.length_squared() > 0.001:
			velocity_xz += screen_steer_world * KEY_ACCEL * sens * delta
			if velocity_xz.length() > KEY_MAX_SPEED:
				velocity_xz = velocity_xz.normalized() * KEY_MAX_SPEED
		else:
			velocity_xz = velocity_xz.move_toward(Vector2.ZERO, KEY_DAMP * KEY_MAX_SPEED * delta * 0.45)

		position_3d.x += velocity_xz.x * delta
		position_3d.z += velocity_xz.y * delta

		var instant_screen_vx := steer_vec.x * KEY_MAX_SPEED * 0.85
		if allow_mouse and mouse_delta.length_squared() > 0.0:
			var my := -mouse_delta.y if SettingsManager.invert_y else mouse_delta.y
			var mouse_screen := Vector2(mouse_delta.x, my) * MOUSE_SCALE * sens
			var mouse_world := right_xz * mouse_screen.x + down_xz * mouse_screen.y
			position_3d.x += mouse_world.x
			position_3d.z += mouse_world.y
			# Track horizontal mouse motion purely for visual bank roll — never double-integrate into velocity_xz!
			instant_screen_vx += clampf(mouse_screen.x / maxf(delta, 0.004), -KEY_MAX_SPEED, KEY_MAX_SPEED) * 0.75

		_bank_vel_x = lerpf(_bank_vel_x, instant_screen_vx, clampf(delta * 14.0, 0.0, 1.0))

	# Smooth cylindrical boundary constraint (zeroes only outward radial velocity -> no wall lockup)
	var xz := Vector2(position_3d.x, position_3d.z)
	var dist := xz.length()
	if dist > PLAY_RADIUS:
		var normal := xz / dist
		xz = normal * PLAY_RADIUS
		position_3d.x = xz.x
		position_3d.z = xz.y
		var outward := velocity_xz.dot(normal)
		if outward > 0.0:
			velocity_xz -= normal * outward

	position_3d.y -= forward_speed * delta
	_sync_camera_transform()
	return {"prev_pos": prev_pos, "curr_pos": position_3d}


func update_camera_effects(
	delta: float,
	effect_mask: int,
	speed: float,
	bass_energy: float,
	boost_level: float = 0.0
) -> void:
	_ensure_camera()
	var comfort_scale := 0.35 if SettingsManager.camera_comfort else 1.0
	var bank := clampf(-_bank_vel_x * 0.015, -0.26, 0.26) * comfort_scale
	if EffectCatalog.has_effect(effect_mask, 10): # HORIZON_SWAY
		bank *= 1.75
	if EffectCatalog.has_effect(effect_mask, 8): # CAMERA_SPIRAL_ROLL
		spiral_roll_acc += delta * 0.78 * comfort_scale
	else:
		spiral_roll_acc = lerpf(spiral_roll_acc, 0.0, clampf(delta * 4.5, 0.0, 1.0))

	current_roll = lerpf(current_roll, bank + spiral_roll_acc, clampf(delta * 12.0, 0.0, 1.0))

	fov_punch = lerpf(fov_punch, 0.0, clampf(delta * 8.5, 0.0, 1.0))
	shake_trauma = maxf(0.0, shake_trauma - delta * 2.8)
	_shake_phase += delta * 52.0

	var target_fov := SettingsManager.fov_base
	var speed_bonus := clampf((speed - 40.0) * 0.24, 0.0, 14.0)
	target_fov += speed_bonus * comfort_scale
	if EffectCatalog.has_effect(effect_mask, 9): # CAMERA_FOV_SURGE
		target_fov += (bass_energy * 7.5) * comfort_scale
	target_fov += (clampf(boost_level, 0.0, 1.0) * 12.0 + fov_punch) * comfort_scale
	camera.fov = lerpf(camera.fov, clampf(target_fov, 65.0, 122.0), clampf(delta * 10.0, 0.0, 1.0))
	_sync_camera_transform(comfort_scale)


func _sync_camera_transform(comfort_scale: float = 1.0) -> void:
	position = position_3d
	if camera != null:
		if shake_trauma > 0.001:
			var mag := shake_trauma * shake_trauma * 0.24 * comfort_scale
			camera.position = Vector3(sin(_shake_phase * 1.13) * mag, 0.0, cos(_shake_phase * 1.37) * mag)
		else:
			camera.position = Vector3.ZERO
		camera.rotation = Vector3(-PI * 0.5, 0.0, current_roll)


static func clamp_xz_to_tunnel(xz: Vector2) -> Vector2:
	var length := xz.length()
	if length > PLAY_RADIUS:
		return (xz / length) * PLAY_RADIUS
	return xz
