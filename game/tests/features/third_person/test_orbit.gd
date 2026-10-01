extends GutTest

const Feature := preload("res://features/third_person/third_person.gd")
const Overlay := preload("res://features/touch_controls/touch_controls.gd")
const Bindings := preload("res://features/control_scheme/input_bindings.gd")
const PLAYER := preload("res://core/player/player.tscn")

var _feature: Feature
var _player: Player
var _overlay: Overlay
var _saved_device: int
var _saved_playing: bool
var _saved_touch: bool
var _saved_joypad: int
var _saved_mouse: int
var _saved_events: Array[InputEvent]


func before_each() -> void:
	_saved_device = Controls.device
	_saved_playing = Controls.playing
	_saved_touch = Controls.touch_available
	_saved_joypad = Controls.joypad
	_saved_mouse = Input.mouse_mode
	Controls.device = Controls.Device.TOUCH
	Controls.touch_available = true
	Controls.joypad = -1
	Controls.start()
	_player = PLAYER.instantiate() as Player
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_feature = Feature.new()
	add_child_autofree(_feature)
	_saved_events = InputMap.action_get_events(Feature.ORBIT_ACTION)
	_overlay = Overlay.new()
	_overlay.size = Vector2(1280, 720)
	add_child_autofree(_overlay)


func after_each() -> void:
	Bindings.set_events(Feature.ORBIT_ACTION, _saved_events)
	Controls.clear_input()
	Controls.device = _saved_device
	Controls.playing = _saved_playing
	Controls.touch_available = _saved_touch
	Controls.joypad = _saved_joypad
	Input.mouse_mode = _saved_mouse
	get_viewport().use_xr = false


func _render() -> Camera3D:
	_player._process(0.0)
	_feature._process(0.0)
	return _player.get_node("Camera") as Camera3D


func _touch(index: int, point: Vector2, pressed: bool = true) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point * _overlay.ui_scale
	event.pressed = pressed
	_overlay._input(event)


func _drag(index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point * _overlay.ui_scale
	_overlay._input(event)


func _motion() -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.screen_relative = Vector2(100, 50)
	return event


func test_orbit_changes_camera_not_player_aim_or_body_facing() -> void:
	_player.yaw = 0.4
	_player.pitch = 0.2
	_feature.toggle_camera()
	assert_true(_feature.orbit_look(Vector2(0.6, 0.3)))
	var camera := _render()
	assert_almost_eq(camera.global_rotation.y, -0.2, 0.001)
	assert_almost_eq(camera.global_rotation.x, -0.1, 0.001)
	assert_eq(_player.yaw, 0.4)
	assert_eq(_player.pitch, 0.2)
	assert_almost_eq((_player.get_node("Body") as Node3D).rotation.y, 0.4, 0.001)
	_player._physics_process(0.0)
	assert_eq(_player.net_yaw, 0.4)
	assert_eq(_player.net_pitch, 0.2)


func test_orbit_pitch_clamps_and_toggle_resets() -> void:
	_feature.toggle_camera()
	_feature.orbit_look(Vector2(100, -100))
	assert_almost_eq(_render().global_rotation.x, Feature.PITCH_LIMIT, 0.001)
	_feature.toggle_camera()
	assert_false(_feature.orbit_look(Vector2.ONE))
	assert_eq(_render().global_rotation, Vector3.ZERO)
	_feature.toggle_camera()
	assert_eq(_render().global_rotation, Vector3.ZERO)


func test_paused_modal_and_xr_cannot_orbit_or_toggle() -> void:
	_feature.toggle_camera()
	Controls.pause()
	assert_false(_feature.orbit_look(Vector2.ONE))
	_feature.toggle_camera()
	assert_true(_feature.enabled)
	Controls.start()
	var modal := Node.new()
	add_child_autofree(modal)
	modal.add_to_group(&"modal_ui")
	assert_false(_feature.orbit_look(Vector2.ONE))
	modal.remove_from_group(&"modal_ui")
	get_viewport().use_xr = true
	assert_false(_feature.orbit_look(Vector2.ONE))
	_feature.toggle_camera()
	assert_true(_feature.enabled)


func test_middle_mouse_hold_release_and_pause() -> void:
	_feature.toggle_camera()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_MIDDLE
	mouse.pressed = true
	_feature._input(mouse)
	_feature._input(_motion())
	var rotation := _render().global_rotation
	assert_lt(rotation.y, 0.0)
	mouse.pressed = false
	_feature._input(mouse)
	_feature._input(_motion())
	assert_eq(_render().global_rotation, rotation, "Release keeps the orbit but stops rotation")
	mouse.pressed = true
	_feature._input(mouse)
	Controls.pause()
	Controls.start()
	_feature._input(_motion())
	assert_eq(_render().global_rotation, rotation, "Pause releases the modifier")


func test_mouse_orbit_dispatch_does_not_reach_player_aim() -> void:
	_feature.toggle_camera()
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_MIDDLE
	mouse.pressed = true
	_feature._input(mouse)
	get_viewport().push_input(_motion())
	assert_eq(_player.yaw, 0.0)
	assert_eq(_player.pitch, 0.0)
	assert_lt(_render().global_rotation.y, 0.0)


func test_rebound_key_replaces_middle_mouse() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_O
	key.pressed = true
	Bindings.bind(Feature.ORBIT_ACTION, false, key)
	assert_eq(Bindings.label_for(Feature.ORBIT_ACTION), "Orbit third-person camera (hold)")
	_feature.toggle_camera()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_MIDDLE
	mouse.pressed = true
	_feature._input(mouse)
	_feature._input(_motion())
	assert_eq(_render().global_rotation, Vector3.ZERO)
	_feature._input(key)
	_feature._input(_motion())
	assert_lt(_render().global_rotation.y, 0.0)


func test_camera_button_and_swipe_keep_move_and_jump_independent() -> void:
	_touch(1, Vector2(150, 500))
	_drag(1, Vector2(226, 500))
	_touch(2, _overlay.camera_button().get_center())
	assert_true(_feature.enabled)
	assert_eq(_overlay.look_finger, -1, "Camera press must not become a look finger")
	_touch(2, _overlay.camera_button().get_center(), false)
	_touch(3, Vector2(700, 300))
	_drag(3, Vector2(720, 310))
	assert_eq(Controls.consume_look(0.016), Vector2.ZERO, "Orbit must not turn the player")
	assert_lt(_render().global_rotation.y, 0.0)
	assert_eq(Controls.movement(), Vector2.RIGHT)
	_touch(4, _overlay.jump_center())
	assert_true(Controls.consume_jump())
	_touch(3, Vector2(720, 310), false)
	_touch(2, _overlay.camera_button().get_center())
	assert_false(_feature.enabled)
	_touch(3, Vector2(700, 300))
	_drag(3, Vector2(720, 310))
	assert_gt(Controls.consume_look(0.016).x, 0.0, "First-person swipe still aims")


func test_camera_button_bounds_on_phone_sizes_and_safe_area() -> void:
	for screen: Vector2 in [Vector2(390, 844), Vector2(844, 390), Vector2(600, 360)]:
		_overlay.size = screen
		_overlay._resize_layout()
		_overlay.safe_bounds = Rect2(Vector2(20, 10), _overlay.ui_size - Vector2(40, 30))
		var button := _overlay.camera_button()
		assert_true(_overlay.safe_bounds.encloses(button))
		assert_false(button.intersects(_overlay.pause_button()))
		for target: Vector2 in [
			_overlay.use_center(), _overlay.fire_center(), _overlay.jump_center()
		]:
			var closest := target.clamp(button.position, button.end)
			assert_gt(target.distance_to(closest), 62.0)


func test_orbit_resets_when_local_player_is_replaced() -> void:
	_feature.toggle_camera()
	_feature.orbit_look(Vector2.ONE)
	_player.free()
	_feature._process(0.0)
	assert_false(_feature.orbit_look(Vector2.ONE))
	_player = PLAYER.instantiate() as Player
	add_child_autofree(_player)
	_player.set_physics_process(false)
	assert_true(_feature.enabled)
	assert_eq(_render().global_rotation, Vector3.ZERO)


func test_collision_sweep_follows_orbited_direction() -> void:
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.2, 10, 10)
	collider.shape = shape
	wall.add_child(collider)
	wall.position.x = -1.5
	add_child_autofree(wall)
	await wait_physics_frames(2)
	_feature.toggle_camera()
	_feature.orbit_look(Vector2(PI / 2, 0))
	var camera := _render()
	assert_lt(camera.global_position.x, -1.0)
	assert_gt(camera.global_position.x, -1.4)
