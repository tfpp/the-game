extends GutTest

const Feature := preload("res://features/third_person/third_person.gd")
const PLAYER := preload("res://core/player/player.tscn")

var _feature: Feature
var _player: Player
var _previous_device: int
var _previous_playing: bool


func before_each() -> void:
	_previous_device = Controls.device
	_previous_playing = Controls.playing
	Controls.device = Controls.Device.GAMEPAD
	Controls.playing = true
	_player = PLAYER.instantiate() as Player
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_feature = Feature.new()
	add_child_autofree(_feature)


func after_each() -> void:
	Controls.device = _previous_device
	Controls.playing = _previous_playing


func _press(echo: bool = false, pressed: bool = true) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F3
	key.pressed = pressed
	key.echo = echo
	_feature._unhandled_input(key)


func test_f3_toggles_camera_and_body_and_preserves_look() -> void:
	_player.yaw = 0.6
	_player.pitch = -0.2
	_player._process(0.0)
	var camera := _player.get_node("Camera") as Camera3D
	var body := _player.get_node("Body") as Node3D
	var eye := camera.global_position
	var rotation := camera.global_rotation
	assert_false(body.visible)
	_press()
	_feature._process(0.0)
	assert_true(body.visible)
	assert_almost_eq(camera.global_position, eye + camera.global_basis.z * 3.0, Vector3.ONE * 0.01)
	assert_eq(camera.global_rotation, rotation)
	assert_almost_eq(body.rotation.y, _player.yaw, 0.0001)
	_press()
	_player._process(0.0)
	_feature._process(0.0)
	assert_false(body.visible)
	assert_eq(camera.global_position, eye)


func test_echo_release_and_paused_input_do_not_toggle() -> void:
	_press(true)
	_press(false, false)
	assert_false(_feature.enabled)
	Controls.playing = false
	_press()
	assert_false(_feature.enabled)


func test_modal_input_does_not_toggle() -> void:
	var modal := Node.new()
	add_child_autofree(modal)
	modal.add_to_group(&"modal_ui")
	_press()
	assert_false(_feature.enabled)


func test_wall_shortens_camera_distance() -> void:
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(10.0, 10.0, 0.2)
	collider.shape = shape
	wall.add_child(collider)
	wall.position.z = 1.5
	add_child_autofree(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_press()
	_player._process(0.0)
	_feature._process(0.0)
	var camera := _player.get_node("Camera") as Camera3D
	assert_gt(camera.global_position.z, 1.0)
	assert_lt(camera.global_position.z, 1.4)


func test_remote_player_is_unchanged() -> void:
	var remote := PLAYER.instantiate() as Player
	remote.set_multiplayer_authority(2)
	add_child_autofree(remote)
	var body := remote.get_node("Body") as Node3D
	_press()
	_player._process(0.0)
	_feature._process(0.0)
	assert_true(body.visible)
	assert_eq(body.rotation, Vector3.ZERO)


func test_camera_preference_survives_local_player_replacement() -> void:
	_press()
	_player.free()
	_feature._process(0.0)
	_player = PLAYER.instantiate() as Player
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player._process(0.0)
	_feature._process(0.0)
	assert_true((_player.get_node("Body") as Node3D).visible)
	assert_almost_eq((_player.get_node("Camera") as Camera3D).global_position.z, 3.0, 0.01)


func test_no_local_player_does_not_toggle() -> void:
	_player.free()
	_press()
	_feature._process(0.0)
	assert_false(_feature.enabled)
