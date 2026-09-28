extends GutTest

const Overlay := preload("res://features/touch_controls/touch_controls.gd")
const Login := preload("res://ui/login/login_screen.gd")
var _overlay: Control
var _saved_device: int
var _saved_touch: bool
var _saved_joypad: int


func before_each() -> void:
	_saved_device = Controls.device
	_saved_touch = Controls.touch_available
	_saved_joypad = Controls.joypad
	Controls.device = Controls.Device.TOUCH
	Controls.touch_available = true
	Controls.joypad = -1
	Controls.start()
	_overlay = Overlay.new()
	_overlay.size = Vector2(1280, 720)
	add_child_autofree(_overlay)


func after_each() -> void:
	Controls.pause()
	Controls.device = _saved_device
	Controls.touch_available = _saved_touch
	Controls.joypad = _saved_joypad
	Input.action_release("move_forward")


func test_default_bindings_are_left_handed_and_sensitivity_unchanged() -> void:
	var saved_scheme := Controls.scheme
	Controls.apply_scheme(Controls.Scheme.LEFT_HANDED)
	var expected := {
		"move_forward": [KEY_UP],
		"move_back": [KEY_DOWN],
		"move_left": [KEY_LEFT],
		"move_right": [KEY_RIGHT]
	}
	for action: String in expected:
		var keys: Array[int] = []
		for event: InputEvent in InputMap.action_get_events(action):
			keys.append((event as InputEventKey).physical_keycode)
		assert_eq(keys, expected[action])
	var jump := InputMap.action_get_events("jump")
	assert_eq(jump.size(), 4)
	assert_eq((jump[0] as InputEventKey).physical_keycode, KEY_SHIFT)
	assert_eq((jump[1] as InputEventMouseButton).button_index, MOUSE_BUTTON_WHEEL_DOWN)
	assert_eq((jump[2] as InputEventMouseButton).button_index, MOUSE_BUTTON_WHEEL_UP)
	assert_eq((jump[3] as InputEventJoypadButton).button_index, JOY_BUTTON_A)
	assert_almost_eq(Controls.look_radians_per_count(), deg_to_rad(0.044), 0.000001)
	Controls.apply_scheme(saved_scheme)


func test_right_handed_scheme_restores_classic_wasd_and_space() -> void:
	var saved_scheme := Controls.scheme
	Controls.apply_scheme(Controls.Scheme.RIGHT_HANDED)
	var expected := {
		"move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D]
	}
	for action: String in expected:
		var keys: Array[int] = []
		for event: InputEvent in InputMap.action_get_events(action):
			keys.append((event as InputEventKey).physical_keycode)
		assert_eq(keys, expected[action])
	var jump := InputMap.action_get_events("jump")
	assert_eq((jump[0] as InputEventKey).physical_keycode, KEY_SPACE)
	Controls.apply_scheme(saved_scheme)


func test_radial_deadzone_and_diagonal_limit() -> void:
	assert_eq(Controls.deadzone(Vector2(0.1, 0.1)), Vector2.ZERO)
	assert_almost_eq(Controls.deadzone(Vector2(0.59, 0)).x, 0.5, 0.00001)
	assert_almost_eq(Controls.deadzone(Vector2.ONE).length(), 1.0, 0.00001)


func test_independent_touch_move_look_jump_and_release() -> void:
	_touch(2, Vector2(150, 500))
	_drag(2, Vector2(226, 500))
	assert_eq(Controls.movement(), Vector2.RIGHT)
	_touch(3, Vector2(700, 300))
	_drag(3, Vector2(720, 310))
	assert_gt(Controls.consume_look(0.016).x, 0.0)
	_touch(4, _overlay.jump_center())
	assert_true(Controls.consume_jump())
	assert_false(Controls.consume_jump(), "Holding a touch must not auto-bhop")
	_touch(4, _overlay.jump_center(), false)
	assert_eq(Controls.movement(), Vector2.RIGHT, "Releasing jump keeps move finger")
	_touch(2, Vector2(226, 500), false)
	assert_eq(Controls.movement(), Vector2.ZERO)


func test_controller_hides_touch_and_clears_fingers() -> void:
	_touch(2, Vector2(150, 500))
	_drag(2, Vector2(226, 500))
	Controls._joy_connection_changed(0, true)
	assert_false(Controls.touch_visible())
	assert_true(Controls.gameplay_active(), "Switching to a pad does not require mouse lock")
	assert_eq(Controls.touch_move, Vector2.ZERO)
	assert_eq(_overlay.move_finger, -1)
	_touch(3, _overlay.jump_center())
	assert_false(Controls.consume_jump(), "Touch overlay stays inactive with a controller")
	Controls._joy_connection_changed(0, false)
	assert_true(Controls.touch_visible())
	assert_false(Controls.gameplay_active(), "Disconnect pauses until resumed")


func test_menu_and_focus_loss_clear_pending_input() -> void:
	_touch(2, Vector2(150, 500))
	_drag(2, Vector2(226, 500))
	_touch(3, _overlay.jump_center())
	Controls._focus_lost()
	assert_eq(Controls.movement(), Vector2.ZERO)
	assert_eq(_overlay.move_finger, -1)
	Controls.start()
	assert_false(Controls.consume_jump())
	assert_eq(Controls.consume_look(0.016), Vector2.ZERO)


func test_modal_blocks_movement_look_and_jump() -> void:
	var modal := Node.new()
	add_child_autofree(modal)
	modal.add_to_group(&"modal_ui")
	Controls.touch_move = Vector2.ONE
	Controls.look_delta = Vector2.ONE
	Controls.jump_queued = true
	assert_eq(Controls.movement(), Vector2.ZERO)
	assert_eq(Controls.consume_look(0.016), Vector2.ZERO)
	assert_false(Controls.consume_jump())


func test_resize_and_cancel_release_touch() -> void:
	_touch(2, Vector2(150, 500))
	_drag(2, Vector2(226, 500))
	var cancel := InputEventScreenTouch.new()
	cancel.index = 2
	cancel.canceled = true
	_overlay._input(cancel)
	assert_eq(Controls.movement(), Vector2.ZERO)
	_touch(3, Vector2(700, 300))
	_overlay.size = Vector2(720, 1280)
	_overlay._resize_layout()
	assert_eq(_overlay.look_finger, -1)
	assert_true(_overlay.safe_bounds.has_point(_overlay.jump_center()))


func test_controller_jump_is_one_press_and_start_is_menu_request() -> void:
	Controls.joypad = 0
	Controls.select_device(Controls.Device.GAMEPAD)
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	button.pressed = true
	Controls._unhandled_input(button)
	assert_true(Controls.consume_jump())
	assert_false(Controls.consume_jump())
	watch_signals(Controls)
	button.button_index = JOY_BUTTON_START
	Controls._input(button)
	assert_signal_emitted(Controls, "menu_requested")


func test_touch_menu_resume_does_not_capture_mouse() -> void:
	var menu := Login.new()
	add_child_autofree(menu)
	menu.open_menu()
	assert_false(Controls.gameplay_active())
	menu._resume()
	assert_true(Controls.gameplay_active())
	assert_ne(Input.mouse_mode, Input.MOUSE_MODE_CAPTURED)


func _touch(index: int, position: Vector2, pressed: bool = true) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	_overlay._input(event)


func _drag(index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	_overlay._input(event)


func test_analog_strength_scales_speed_without_changing_full_input() -> void:
	var cfg := MovementConfig.new()
	var full := Vector3.ZERO
	var half := Vector3.ZERO
	for tick: int in 256:
		full = SourceMovement.step(full, Vector3.FORWARD, true, false, cfg, 1.0 / 64.0).velocity
		half = (
			SourceMovement.step(half, Vector3.FORWARD, true, false, cfg, 1.0 / 64.0, 0.5).velocity
		)
	assert_almost_eq(full.length(), cfg.max_speed_m(), 0.001)
	assert_almost_eq(half.length(), cfg.max_speed_m() * 0.5, 0.001)


func test_emulated_mouse_does_not_replace_touch_or_gamepad() -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.device = InputEvent.DEVICE_ID_EMULATION
	Controls._input(click)
	assert_eq(Controls.device, Controls.Device.TOUCH)
	Controls._joy_connection_changed(0, true)
	Controls._input(click)
	assert_eq(Controls.device, Controls.Device.GAMEPAD)
	click.device = 0
	Controls._input(click)
	assert_eq(Controls.device, Controls.Device.KEYBOARD)


func test_gamepad_a_activates_menu_buttons() -> void:
	Controls._joy_connection_changed(0, true)
	var menu := Login.new()
	add_child_autofree(menu)
	menu.open_menu()
	menu._focus_default_button()
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	button.pressed = true
	assert_true(button.is_action_pressed("ui_accept"))
	get_viewport().push_input(button)
	await get_tree().process_frame
	assert_false(menu.visible, "A must activate the focused Resume button")
	assert_true(Controls.gameplay_active())
	assert_false(Controls.consume_jump(), "Activating Resume must not also jump")
	button.pressed = false
	get_viewport().push_input(button)
