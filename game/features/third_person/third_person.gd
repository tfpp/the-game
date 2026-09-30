extends Node
## Local camera preference. Runs after Player has placed its first-person camera.

const ACTION := &"toggle_third_person"
const DISTANCE := 3.0
const CAMERA_RADIUS := 0.2

var enabled := false
var _shape := SphereShape3D.new()


func _ready() -> void:
	process_priority = 10
	_shape.radius = CAMERA_RADIUS
	var key := InputEventKey.new()
	key.physical_keycode = KEY_V
	var legacy_key := InputEventKey.new()
	legacy_key.physical_keycode = KEY_F3
	Controls.ensure_action(ACTION, [key, legacy_key])


func _unhandled_input(event: InputEvent) -> void:
	if get_viewport().use_xr:
		return
	if not Controls.gameplay_active() or not event.is_action_pressed(ACTION):
		return
	if get_tree().get_first_node_in_group(&"local_player") == null:
		return
	enabled = not enabled
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	if player == null or player.is_queued_for_deletion():
		return
	var body := player.get_node("Body") as Node3D
	body.visible = enabled and not get_viewport().use_xr
	if not enabled or get_viewport().use_xr:
		return
	body.rotation.y = player.yaw
	var camera := player.get_node("Camera") as Camera3D
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
