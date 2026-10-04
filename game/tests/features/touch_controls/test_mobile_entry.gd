extends GutTest
## Regression for #512: a missed startup probe must not trap touch behind mouse capture.

const Login := preload("res://ui/login/login_screen.gd")
const Overlay := preload("res://features/touch_controls/touch_controls.gd")
var _menu: CanvasLayer
var _overlay: Control
var _saved_device: int
var _saved_touch: bool
var _saved_joypad: int
var _saved_playing: bool


func before_each() -> void:
	_saved_device = Controls.device
	_saved_touch = Controls.touch_available
	_saved_joypad = Controls.joypad
	_saved_playing = Controls.playing
	Controls.pause()
	Controls.device = Controls.Device.KEYBOARD
	Controls.touch_available = false
	Controls.joypad = -1
	_overlay = Overlay.new()
	_overlay.size = get_viewport().get_visible_rect().size
	add_child_autofree(_overlay)
	_menu = Login.new()
	add_child_autofree(_menu)


func after_each() -> void:
	Controls.pause()
	Controls.device = _saved_device
	Controls.touch_available = _saved_touch
	Controls.joypad = _saved_joypad
	Controls.playing = _saved_playing


func test_first_touch_recovers_device_before_play_button_activation() -> void:
	_menu._idle_timeout()
	assert_eq(_menu._play_prompt.text, "Click to play")
	await get_tree().process_frame
	var point: Vector2 = _menu._play_prompt.get_global_rect().get_center()
	_touch(point)
	assert_eq(Controls.device, Controls.Device.TOUCH)
	assert_true(Controls.touch_available)
	# GUI buttons consume the mouse event Godot emulates from the physical touch.
	_click(point)
	assert_true(Controls.gameplay_active())
	assert_false(_menu._play_layer.visible)
	assert_ne(Input.mouse_mode, Input.MOUSE_MODE_CAPTURED)
	_overlay._process(0.016)
	assert_true(_overlay.visible)
	assert_eq(_overlay.move_finger, -1, "Play tap must not also start a movement stick")
	_touch(point, false)
	_click(point, false)
	var origin: Vector2 = Vector2(80, _overlay.ui_size.y - 100) * _overlay.ui_scale
	_touch(origin)
	assert_eq(_overlay.move_finger, 0)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = origin + Vector2(76, 0) * _overlay.ui_scale
	get_viewport().push_input(drag, true)
	assert_almost_eq(Controls.movement().x, 1.0, 0.00001)
	assert_almost_eq(Controls.movement().y, 0.0, 0.00001)
	_touch(drag.position, false)
	assert_eq(Controls.movement(), Vector2.ZERO)


func test_touch_resume_after_missed_detection_uses_existing_menu() -> void:
	_menu.open_menu()
	await wait_process_frames(3)
	var resume: Button
	for child: Node in _menu._box.get_children():
		if child is Button and child.text == "Resume":
			resume = child as Button
	assert_not_null(resume)
	var point := resume.get_global_rect().get_center()
	_touch(point)
	assert_false(Controls.gameplay_active(), "Touch cannot bypass a modal")
	# Activate the existing Resume callback independently of the test runner's GUI.
	resume.pressed.emit()
	assert_false(_menu.visible)
	assert_true(Controls.gameplay_active())
	assert_ne(Input.mouse_mode, Input.MOUSE_MODE_CAPTURED)
	_touch(point, false)


func test_cancel_and_release_do_not_change_device() -> void:
	var event := InputEventScreenTouch.new()
	event.pressed = true
	event.canceled = true
	Controls._input(event)
	event.canceled = false
	event.pressed = false
	Controls._input(event)
	assert_eq(Controls.device, Controls.Device.KEYBOARD)
	assert_false(Controls.touch_available)
	assert_false(Controls.playing)


func test_touch_does_not_replace_connected_controller_or_xr() -> void:
	Controls.joypad = 0
	Controls.device = Controls.Device.GAMEPAD
	_touch(Vector2(20, 20))
	assert_eq(Controls.device, Controls.Device.GAMEPAD)
	assert_true(Controls.touch_available)
	assert_false(Controls.playing)
	Controls.joypad = -1
	Controls.device = Controls.Device.XR
	_touch(Vector2(20, 20))
	assert_eq(Controls.device, Controls.Device.XR)


func test_real_mouse_can_still_switch_back_after_touch_detection() -> void:
	_touch(Vector2(20, 20))
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	click.device = InputEvent.DEVICE_ID_EMULATION
	Controls._input(click)
	assert_eq(Controls.device, Controls.Device.TOUCH)
	click.device = 0
	Controls._input(click)
	assert_eq(Controls.device, Controls.Device.KEYBOARD)


func _touch(point: Vector2, pressed: bool = true) -> void:
	var event := InputEventScreenTouch.new()
	event.position = point
	event.pressed = pressed
	get_viewport().push_input(event, true)


func _click(point: Vector2, pressed: bool = true) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.device = InputEvent.DEVICE_ID_EMULATION
	get_viewport().push_input(event, true)
