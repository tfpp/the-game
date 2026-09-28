extends GutTest
## `features/control_scheme/`: rebinding actions from the Settings > Controls page
## (keyboard & mouse and controller slots, capture, conflicts, reset, persistence).

const ControlScheme := preload("res://features/control_scheme/control_scheme.gd")
const Bindings := preload("res://features/control_scheme/input_bindings.gd")
const PLAYER := preload("res://core/player/player.tscn")
const STORE_PATH := "user://controls.cfg"
const TEST_ACTION := &"test_control_scheme_action"

var _saved_device: int
var _saved_scheme: int
var _saved_sensitivity: float
var _saved_stick: float
var _saved_touch: float
var _saved_events: Dictionary = {}
var _node: ControlScheme


func before_each() -> void:
	_saved_device = Controls.device
	_saved_scheme = Controls.scheme
	_saved_sensitivity = Controls.sensitivity
	_saved_stick = Controls.stick_sensitivity
	_saved_touch = Controls.touch_sensitivity
	for action: StringName in InputMap.get_actions():
		_saved_events[action] = InputMap.action_get_events(action)
	_clear_store()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_K
	Controls.ensure_action(TEST_ACTION, [key])
	Controls.device = Controls.Device.TOUCH
	Controls.start()
	_node = _new_node()


func after_each() -> void:
	Controls.pause()
	Controls.device = _saved_device
	Controls.apply_scheme(_saved_scheme)
	Controls.sensitivity = _saved_sensitivity
	Controls.stick_sensitivity = _saved_stick
	Controls.touch_sensitivity = _saved_touch
	InputMap.erase_action(TEST_ACTION)
	for action: StringName in _saved_events:
		Bindings.set_events(action, _saved_events[action])
	_clear_store()


func test_rebinding_a_key_replaces_only_the_primary_binding() -> void:
	_node.begin_capture(&"jump", false)
	assert_true(_node.settings_page_input(_key(KEY_J)))
	assert_eq(_physical_keys("jump"), [KEY_J])
	var jump := InputMap.action_get_events("jump")
	assert_eq(jump.size(), 2, "Controller jump is kept")
	assert_true(_node.capture.is_empty(), "Capture ends after one press")


func test_rebinding_a_controller_button() -> void:
	_node.begin_capture(&"jump", true)
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_Y
	button.pressed = true
	assert_true(_node.settings_page_input(button))
	var pads: Array[int] = []
	for event: InputEvent in InputMap.action_get_events("jump"):
		if event is InputEventJoypadButton:
			pads.append((event as InputEventJoypadButton).button_index)
	assert_eq(pads, [JOY_BUTTON_Y])
	assert_eq(_physical_keys("jump"), [KEY_SPACE], "Keyboard jump is untouched")


func test_controller_capture_ignores_keys() -> void:
	_node.begin_capture(&"jump", true)
	assert_true(_node.settings_page_input(_key(KEY_J)), "Swallowed so it can't hit the UI")
	assert_eq(_physical_keys("jump"), [KEY_SPACE])
	assert_false(_node.capture.is_empty(), "Still waiting for a controller button")


func test_esc_cancels_capture_without_binding() -> void:
	_node.begin_capture(&"jump", false)
	assert_true(_node.settings_page_input(_key(KEY_ESCAPE)))
	assert_true(_node.capture.is_empty())
	assert_eq(_physical_keys("jump"), [KEY_SPACE])


func test_no_capture_leaves_input_alone() -> void:
	assert_false(_node.settings_page_input(_key(KEY_J)))


func test_mouse_buttons_can_be_bound() -> void:
	_node.begin_capture(TEST_ACTION, false)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	assert_true(_node.settings_page_input(click))
	var events := InputMap.action_get_events(TEST_ACTION)
	assert_eq(events.size(), 1)
	assert_eq((events[0] as InputEventMouseButton).button_index, MOUSE_BUTTON_RIGHT)


func test_rebinds_persist_across_a_restart() -> void:
	_node.rebind(TEST_ACTION, false, _key(KEY_O))
	Bindings.set_events(TEST_ACTION, [_key(KEY_K)])
	var reloaded := _new_node()
	reloaded.apply_overrides()
	assert_eq(_physical_keys(TEST_ACTION), [KEY_O])


func test_reset_restores_default_bindings() -> void:
	_node.rebind(TEST_ACTION, false, _key(KEY_O))
	_node.rebind(&"jump", false, _key(KEY_J))
	_node.reset_bindings()
	assert_eq(_physical_keys(TEST_ACTION), [KEY_K])
	assert_eq(_physical_keys("jump"), [KEY_SPACE])
	_new_node().apply_overrides()
	assert_eq(_physical_keys(TEST_ACTION), [KEY_K], "The reset is saved too")


func test_preset_resets_movement_keys_but_keeps_other_rebinds() -> void:
	_node.rebind(&"move_forward", false, _key(KEY_Z))
	_node.rebind(TEST_ACTION, false, _key(KEY_O))
	_node.set_scheme(Controls.Scheme.RIGHT_HANDED)
	assert_eq(_physical_keys("move_forward"), [KEY_W])
	assert_eq(_physical_keys(TEST_ACTION), [KEY_O])


func test_conflicts_flag_shared_keys() -> void:
	_node.rebind(TEST_ACTION, false, _key(KEY_SPACE))
	assert_true(Bindings.conflicts(TEST_ACTION, false).has(&"jump"))
	assert_true(Bindings.conflicts(&"jump", false).has(TEST_ACTION))
	assert_true(Bindings.conflicts(TEST_ACTION, true).is_empty())


func _new_node() -> ControlScheme:
	var node := ControlScheme.new()
	add_child_autofree(node)
	return node


func _spawn_player(display_name: String) -> Player:
	var player := PLAYER.instantiate() as Player
	player.display_name = display_name
	add_child_autofree(player)
	return player


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	return event


func _physical_keys(action: StringName) -> Array[int]:
	var keys: Array[int] = []
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			keys.append((event as InputEventKey).physical_keycode)
	return keys


func _texts(root: Node) -> Array[String]:
	var result: Array[String] = []
	for child: Node in root.find_children("*", "Label", true, false):
		result.append((child as Label).text)
	return result


func _clear_store() -> void:
	if FileAccess.file_exists(STORE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE_PATH))


func test_left_and_right_modifiers_bind_separately() -> void:
	_node.begin_capture(TEST_ACTION, false)
	assert_true(_node.settings_page_input(_sided(KEY_SHIFT, KEY_LOCATION_RIGHT)))
	assert_true(InputMap.event_is_action(_sided(KEY_SHIFT, KEY_LOCATION_RIGHT), TEST_ACTION))
	assert_false(
		InputMap.event_is_action(_sided(KEY_SHIFT, KEY_LOCATION_LEFT), TEST_ACTION),
		"Right Shift binding ignores Left Shift"
	)
	assert_eq(InputLabels.action_label(TEST_ACTION, false), "Right Shift")


func test_sided_binding_persists_across_a_restart() -> void:
	_node.rebind(TEST_ACTION, false, _sided(KEY_ALT, KEY_LOCATION_LEFT))
	Bindings.set_events(TEST_ACTION, [_key(KEY_K)])
	_new_node().apply_overrides()
	var key := InputMap.action_get_events(TEST_ACTION)[0] as InputEventKey
	assert_eq(key.physical_keycode, KEY_ALT)
	assert_eq(key.location, KEY_LOCATION_LEFT)


func test_sided_and_unsided_modifiers_conflict_but_opposite_sides_do_not() -> void:
	Controls.apply_scheme(Controls.Scheme.LEFT_HANDED)  # Jump on plain Shift.
	_node.rebind(TEST_ACTION, false, _sided(KEY_SHIFT, KEY_LOCATION_LEFT))
	assert_true(Bindings.conflicts(TEST_ACTION, false).has(&"jump"), "Shift fires on Left Shift")
	_node.rebind(&"jump", false, _sided(KEY_SHIFT, KEY_LOCATION_RIGHT))
	assert_false(Bindings.conflicts(TEST_ACTION, false).has(&"jump"))


func _sided(keycode: Key, location: KeyLocation) -> InputEventKey:
	var event := _key(keycode)
	event.location = location
	return event
