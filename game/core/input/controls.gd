extends Node
## Registers default input actions at startup.
##
## Bindings are defined in code instead of project.godot so they're easy to read,
## diff, and merge. Features add their own actions with `ensure_action`.

signal menu_requested
signal input_reset

enum Device { KEYBOARD, GAMEPAD, TOUCH }

const MOUSE_YAW_DEGREES := 0.022  ## Source m_yaw/m_pitch: degrees per mouse count.
const DEADZONE := 0.18
const TOUCH_SENSITIVITY := 0.004
const STICK_SENSITIVITY := 2.6

var device := Device.KEYBOARD
var touch_available := false
var joypad := -1
var playing := false
var touch_move := Vector2.ZERO
var look_delta := Vector2.ZERO
var jump_queued := false

## Source-style sensitivity (same number as the `sensitivity` cvar).
var sensitivity := 2.0


func _enter_tree() -> void:
	ensure_action("move_forward", [_key(KEY_W), _key(KEY_UP)])
	ensure_action("move_back", [_key(KEY_S), _key(KEY_DOWN)])
	ensure_action("move_left", [_key(KEY_A), _key(KEY_LEFT)])
	ensure_action("move_right", [_key(KEY_D), _key(KEY_RIGHT)])
	# Scroll-wheel jump is the classic b-hop bind: each notch is one press.
	ensure_action(
		"jump", [_key(KEY_SPACE), _mouse(MOUSE_BUTTON_WHEEL_DOWN), _mouse(MOUSE_BUTTON_WHEEL_UP)]
	)
	ensure_action("release_mouse", [_key(KEY_ESCAPE)])
	# Godot 4.7 does not include a gamepad binding in ui_accept by default.
	var accept := InputEventJoypadButton.new()
	accept.button_index = JOY_BUTTON_A
	ensure_action("ui_accept", [accept])


## Radians of rotation per mouse count at the current sensitivity.
func look_radians_per_count() -> float:
	return deg_to_rad(MOUSE_YAW_DEGREES * sensitivity)


func ensure_action(action: StringName, events: Array[InputEvent]) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for event: InputEvent in events:
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	return event


func _ready() -> void:
	touch_available = DisplayServer.is_touchscreen_available()
	if OS.has_feature("web"):
		touch_available = bool(JavaScriptBridge.eval("navigator.maxTouchPoints > 0"))
	device = Device.TOUCH if touch_available else Device.KEYBOARD
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		joypad = pads[0]
		device = Device.GAMEPAD
	Input.joy_connection_changed.connect(_joy_connection_changed)
	get_window().focus_exited.connect(_focus_lost)


func touch_visible() -> bool:
	return touch_available and joypad < 0 and device == Device.TOUCH


func gameplay_active() -> bool:
	if get_tree().get_first_node_in_group(&"modal_ui"):
		return false
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED if device == Device.KEYBOARD else playing


func start() -> void:
	clear_input()
	playing = true
	if device == Device.KEYBOARD:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func pause() -> void:
	playing = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	clear_input()


func clear_input() -> void:
	touch_move = Vector2.ZERO
	look_delta = Vector2.ZERO
	jump_queued = false
	input_reset.emit()


func select_device(next: Device) -> void:
	if next == device:
		return
	var active := gameplay_active()
	clear_input()
	device = next
	playing = active
	if next != Device.KEYBOARD:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if motion.axis <= JOY_AXIS_RIGHT_Y and absf(motion.axis_value) > DEADZONE:
			joypad = motion.device
			select_device(Device.GAMEPAD)
	elif event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if button.pressed:
			joypad = button.device
			select_device(Device.GAMEPAD)
			if button.button_index == JOY_BUTTON_START:
				menu_requested.emit()
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.is_pressed():
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			select_device(Device.KEYBOARD)
	elif event is InputEventKey and event.is_pressed():
		if (
			event.is_action("move_left")
			or event.is_action("move_right")
			or event.is_action("move_forward")
			or event.is_action("move_back")
			or event.is_action("jump")
		):
			select_device(Device.KEYBOARD)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		select_device(Device.KEYBOARD)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and gameplay_active():
		var button := event as InputEventJoypadButton
		if button.pressed and button.button_index == JOY_BUTTON_A:
			jump_queued = true


func movement() -> Vector2:
	if not gameplay_active():
		return Vector2.ZERO
	var result := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if device == Device.GAMEPAD and joypad >= 0:
		result += stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
	if touch_visible():
		result += touch_move
	return result.limit_length()


func consume_jump() -> bool:
	var result := jump_queued and gameplay_active()
	jump_queued = false
	return result


func consume_look(delta: float) -> Vector2:
	var result := look_delta
	look_delta = Vector2.ZERO
	if not gameplay_active():
		return Vector2.ZERO
	if device == Device.GAMEPAD and joypad >= 0:
		result += stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y) * STICK_SENSITIVITY * delta
	return result


func stick(x_axis: JoyAxis, y_axis: JoyAxis) -> Vector2:
	return deadzone(Vector2(Input.get_joy_axis(joypad, x_axis), Input.get_joy_axis(joypad, y_axis)))


static func deadzone(value: Vector2) -> Vector2:
	var length := value.length()
	if length <= DEADZONE:
		return Vector2.ZERO
	return value / length * minf((length - DEADZONE) / (1.0 - DEADZONE), 1.0)


func _joy_connection_changed(id: int, connected: bool) -> void:
	if connected:
		joypad = id
		select_device(Device.GAMEPAD)
	elif id == joypad:
		var pads := Input.get_connected_joypads()
		joypad = -1 if pads.is_empty() else pads[0]
		select_device(
			(
				Device.GAMEPAD
				if joypad >= 0
				else (Device.TOUCH if touch_available else Device.KEYBOARD)
			)
		)
		_focus_lost()


func _focus_lost() -> void:
	var active := gameplay_active()
	pause()
	if active:
		menu_requested.emit()
