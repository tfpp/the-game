extends GutTest

const Feature := preload("res://features/third_person/third_person.gd")
const PLAYER := preload("res://core/player/player.tscn")

var _feature: Feature
var _player: Player
var _previous_device: int
var _previous_playing: bool
var _previous_events: Array[InputEvent] = []


func before_each() -> void:
	if InputMap.has_action(Feature.ACTION):
		_previous_events = InputMap.action_get_events(Feature.ACTION)
		InputMap.action_erase_events(Feature.ACTION)
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
	InputMap.action_erase_events(Feature.ACTION)
	for event: InputEvent in _previous_events:
		InputMap.action_add_event(Feature.ACTION, event)
	_previous_events = []
	Controls.device = _previous_device
	Controls.playing = _previous_playing


func _press(echo: bool = false, pressed: bool = true, code: Key = KEY_V) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = code
	key.pressed = pressed
	key.echo = echo
	_feature._unhandled_input(key)


func test_v_toggles_camera_and_body_and_preserves_look() -> void:
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


func test_legacy_f3_still_toggles() -> void:
	_press(false, true, KEY_F3)
	assert_true(_feature.enabled)
	_press()
	assert_false(_feature.enabled)


func test_v_is_not_shared_with_default_voice_or_noclip() -> void:
	var voice := preload("res://features/voice_chat/voice_chat.gd").new()
	var noclip := preload("res://features/noclip/noclip.gd").new()
	add_child_autofree(voice)
	add_child_autofree(noclip)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_V
	key.pressed = true
	assert_true(key.is_action_pressed(Feature.ACTION))
	assert_false(key.is_action_pressed(voice.TALK_ACTION))
	assert_false(key.is_action_pressed(noclip.TOGGLE_ACTION))
	key.physical_keycode = KEY_H
	assert_true(key.is_action_pressed(voice.TALK_ACTION))
	key.physical_keycode = KEY_N
	assert_true(key.is_action_pressed(noclip.TOGGLE_ACTION))


func test_rebinding_primary_camera_key_keeps_legacy_alias() -> void:
	var Bindings := preload("res://features/control_scheme/input_bindings.gd")
	var events := InputMap.action_get_events(Feature.ACTION)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_J
	key.pressed = true
	Bindings.bind(Feature.ACTION, false, key)
	assert_true(key.is_action_pressed(Feature.ACTION))
	key = InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_V
	assert_false(key.is_action_pressed(Feature.ACTION))
	key.physical_keycode = KEY_F3
	assert_true(key.is_action_pressed(Feature.ACTION))
	Bindings.set_events(Feature.ACTION, events)


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
