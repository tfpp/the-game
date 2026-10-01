extends Node
## Local camera preference. Runs after Player has placed its first-person camera.

const ACTION := &"toggle_third_person"
const ORBIT_ACTION := &"orbit_third_person"
const PITCH_LIMIT := deg_to_rad(89.0)
const DISTANCE := 3.0
const CAMERA_RADIUS := 0.2

var enabled := false
var _shape := SphereShape3D.new()
var _orbit := Vector2.ZERO
var _orbit_held := false
var _player_id := 0


func _ready() -> void:
	process_priority = 10
	_shape.radius = CAMERA_RADIUS
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F3
	Controls.ensure_action(ACTION, [key])
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_MIDDLE
	Controls.ensure_action(ORBIT_ACTION, [mouse])
	add_to_group(&"third_person_camera")
	Controls.input_reset.connect(_reset_hold)


func _reset_hold() -> void:
	_orbit_held = false


func _input(event: InputEvent) -> void:
	if event.is_action_released(ORBIT_ACTION):
		_reset_hold()
	if not Controls.gameplay_active() or get_viewport().use_xr:
		_reset_hold()
		return
	if event.is_action_pressed(ORBIT_ACTION):
		# _input runs before the Controls autoload. Switch first so its input_reset
		# cannot immediately discard this new hold when coming from touch/gamepad.
		if (
			event is InputEventKey
			or (event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION)
		):
			Controls.select_device(Controls.Device.KEYBOARD)
		elif event is InputEventJoypadButton:
			Controls.joypad = event.device
			Controls.select_device(Controls.Device.GAMEPAD)
		_orbit_held = enabled and _local_player() != null
	if _orbit_held and event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if orbit_look(motion.screen_relative * Controls.look_radians_per_count()):
			get_viewport().set_input_as_handled()


## Touch swipes orbit without a modifier; false leaves normal first-person aim intact.
func orbit_look(change: Vector2) -> bool:
	var player := _local_player()
	if not enabled or player == null or not Controls.gameplay_active() or get_viewport().use_xr:
		return false
	_orbit.x = wrapf(_orbit.x - change.x, -PI, PI)
	var pitch := clampf(player.pitch + _orbit.y - change.y, -PITCH_LIMIT, PITCH_LIMIT)
	_orbit.y = pitch - player.pitch
	return true


## Shared by F3 and the touch camera button; never changes replicated player aim.
func toggle_camera() -> void:
	if get_viewport().use_xr or not Controls.gameplay_active() or _local_player() == null:
		return
	enabled = not enabled
	_orbit = Vector2.ZERO
	_reset_hold()


func _local_player() -> Player:
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	var id := player.get_instance_id() if is_instance_valid(player) else 0
	if id != _player_id:
		_player_id = id
		_orbit = Vector2.ZERO
		_reset_hold()
	return player


func _unhandled_input(event: InputEvent) -> void:
	if get_viewport().use_xr:
		return
	if not Controls.gameplay_active() or not event.is_action_pressed(ACTION):
		return
	if get_tree().get_first_node_in_group(&"local_player") == null:
		return
	toggle_camera()
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	# Modals and XR can suspend gameplay without calling Controls.pause().
	if not Controls.gameplay_active() or get_viewport().use_xr:
		_reset_hold()
	var player := _local_player()
	if player == null or player.is_queued_for_deletion():
		return
	var body := player.get_node("Body") as Node3D
	body.visible = enabled and not get_viewport().use_xr
	if not enabled or get_viewport().use_xr:
		return
	body.rotation.y = player.yaw
	var camera := player.get_node("Camera") as Camera3D
	camera.global_rotation = Vector3(
		clampf(player.pitch + _orbit.y, -PITCH_LIMIT, PITCH_LIMIT), player.yaw + _orbit.x, 0.0
	)
	var motion := camera.global_basis.z * DISTANCE
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.transform = Transform3D(Basis.IDENTITY, camera.global_position)
	query.motion = motion
	query.exclude = [player.get_rid()]
	var space := player.get_world_3d().direct_space_state
	# Sweeps ignore initial overlaps; stay at the eye if it is already obstructed.
	if not space.intersect_shape(query, 1).is_empty():
		body.visible = false
		return
	var fraction := space.cast_motion(query)[0]
	camera.global_position += motion * fraction
	# Avoid filling the view with our own capsule in very tight spaces.
	body.visible = DISTANCE * fraction > player.movement.hull_radius_m() + CAMERA_RADIUS
