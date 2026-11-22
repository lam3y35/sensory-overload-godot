class_name PlayerController
extends Node3D
## First-person vertical dropper controller supporting Mouse, Keyboard, and Controller input,
## smooth cylindrical boundary sliding (no wall-snap or steering lockup), and Autopilot transitions.

const PLAY_RADIUS := 8.6
const KEY_MAX_SPEED := 23.0
const KEY_ACCEL := 145.0
const KEY_DAMP := 12.0
const MOUSE_SCALE := 0.018

var camera: Camera3D
var position_3d: Vector3 = Vector3.ZERO
var velocity_xz: Vector2 = Vector2.ZERO
var current_roll: float = 0.0
var spiral_roll_acc: float = 0.0
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
	_pending_mouse_delta = Vector2.ZERO
	_sync_camera_transform()


func set_replay_pose(pos: Vector3, roll_rad: float) -> void:
	_ensure_camera()
	position_3d = pos
	current_roll = roll_rad
	_sync_camera_transform()


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

		if steer_vec.length_squared() > 0.001:
			velocity_xz += steer_vec * KEY_ACCEL * sens * delta
			if velocity_xz.length() > KEY_MAX_SPEED:
				velocity_xz = velocity_xz.normalized() * KEY_MAX_SPEED
		else:
			velocity_xz = velocity_xz.move_toward(Vector2.ZERO, KEY_DAMP * KEY_MAX_SPEED * delta * 0.45)

		position_3d.x += velocity_xz.x * delta
		position_3d.z += velocity_xz.y * delta

		if allow_mouse and mouse_delta.length_squared() > 0.0:
			var my := -mouse_delta.y if SettingsManager.invert_y else mouse_delta.y
			var mouse_step := Vector2(mouse_delta.x, my) * MOUSE_SCALE * sens
			position_3d.x += mouse_step.x
			position_3d.z += mouse_step.y
			velocity_xz = velocity_xz.lerp(mouse_step / maxf(delta, 0.001), 0.35)

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
	bass_energy: float
) -> void:
	_ensure_camera()
	var comfort_scale := 0.35 if SettingsManager.camera_comfort else 1.0
	var bank := clampf(-velocity_xz.x * 0.015, -0.25, 0.25) * comfort_scale
	if EffectCatalog.has_effect(effect_mask, 10): # HORIZON_SWAY
		bank *= 1.8
	if EffectCatalog.has_effect(effect_mask, 8): # CAMERA_SPIRAL_ROLL
		spiral_roll_acc += delta * 0.85 * comfort_scale
	else:
		spiral_roll_acc = lerpf(spiral_roll_acc, 0.0, clampf(delta * 4.0, 0.0, 1.0))

	current_roll = lerpf(current_roll, bank + spiral_roll_acc, clampf(delta * 10.0, 0.0, 1.0))

	var target_fov := SettingsManager.fov_base
	if EffectCatalog.has_effect(effect_mask, 9): # CAMERA_FOV_SURGE
		var speed_bonus := clampf((speed - 32.0) * 0.35, 0.0, 16.0)
		target_fov += (speed_bonus + bass_energy * 8.5) * comfort_scale
	camera.fov = lerpf(camera.fov, clampf(target_fov, 65.0, 118.0), clampf(delta * 8.0, 0.0, 1.0))
	_sync_camera_transform()


func _sync_camera_transform() -> void:
	position = position_3d
	if camera != null:
		camera.position = Vector3.ZERO
		camera.rotation = Vector3(-PI * 0.5, 0.0, current_roll)


static func clamp_xz_to_tunnel(xz: Vector2) -> Vector2:
	var len := xz.length()
	if len > PLAY_RADIUS:
		return (xz / len) * PLAY_RADIUS
	return xz
