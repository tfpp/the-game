extends GutTest
## `features/control_scheme/control_scheme.gd`: the Settings > Controls page.
## Right-handed-by-default input (except for DoctorDalek, who gets left-handed),
## handedness presets, look sensitivity and per-action rebinding, all persisted.

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


func test_defaults_to_right_handed_wasd_and_space_jump() -> void:
	assert_eq(Controls.scheme, Controls.Scheme.RIGHT_HANDED)
	assert_eq(_physical_keys("move_forward"), [KEY_W])
	assert_eq(_physical_keys("move_back"), [KEY_S])
	assert_eq(_physical_keys("move_left"), [KEY_A])
	assert_eq(_physical_keys("move_right"), [KEY_D])
	assert_eq(_physical_keys("jump"), [KEY_SPACE])


func test_apply_scheme_switches_to_left_handed_arrows_and_shift() -> void:
	Controls.apply_scheme(Controls.Scheme.LEFT_HANDED)
	assert_eq(_physical_keys("move_forward"), [KEY_UP])
	assert_eq(_physical_keys("move_back"), [KEY_DOWN])
	assert_eq(_physical_keys("move_left"), [KEY_LEFT])
	assert_eq(_physical_keys("move_right"), [KEY_RIGHT])
	assert_eq(_physical_keys("jump"), [KEY_SHIFT])


func test_scroll_wheel_and_controller_a_still_jump_in_either_scheme() -> void:
	for scheme: int in [Controls.Scheme.LEFT_HANDED, Controls.Scheme.RIGHT_HANDED]:
		Controls.apply_scheme(scheme)
		var jump := InputMap.action_get_events("jump")
		assert_eq((jump[1] as InputEventMouseButton).button_index, MOUSE_BUTTON_WHEEL_DOWN)
		assert_eq((jump[2] as InputEventMouseButton).button_index, MOUSE_BUTTON_WHEEL_UP)
		assert_eq((jump[3] as InputEventJoypadButton).button_index, JOY_BUTTON_A)


func test_default_resolves_to_left_handed_for_doctor_dalek() -> void:
	assert_eq(
		Controls.scheme,
		Controls.Scheme.RIGHT_HANDED,
		"Guessed right-handed before we know who's playing"
	)
	_spawn_player("DoctorDalek")
	_node._process(0.0)
	assert_eq(Controls.scheme, Controls.Scheme.LEFT_HANDED)


func test_default_stays_right_handed_for_other_accounts() -> void:
	_spawn_player("jos")
	_node._process(0.0)
	assert_eq(Controls.scheme, Controls.Scheme.RIGHT_HANDED)


func test_default_resolution_waits_for_the_local_players_account_name() -> void:
	var player := _spawn_player("")
	_node._process(0.0)
	assert_eq(Controls.scheme, Controls.Scheme.RIGHT_HANDED, "No name yet, so still just the guess")
	player.display_name = "DoctorDalek"
	_node._process(0.0)
	assert_eq(Controls.scheme, Controls.Scheme.LEFT_HANDED)


func test_default_resolution_does_not_override_a_manual_choice() -> void:
	_node.set_scheme(Controls.Scheme.RIGHT_HANDED)
	_spawn_player("DoctorDalek")
	_node._process(0.0)
	assert_eq(
		Controls.scheme, Controls.Scheme.RIGHT_HANDED, "Manual choice wins over the account default"
	)


func test_set_scheme_switches_both_ways() -> void:
	_node.set_scheme(Controls.Scheme.LEFT_HANDED)
	assert_eq(Controls.scheme, Controls.Scheme.LEFT_HANDED)
	_node.set_scheme(Controls.Scheme.RIGHT_HANDED)
	assert_eq(Controls.scheme, Controls.Scheme.RIGHT_HANDED)


func test_scheme_persists_across_a_restart() -> void:
	_node.set_scheme(Controls.Scheme.LEFT_HANDED)
	Controls.apply_scheme(Controls.Scheme.RIGHT_HANDED)
	_new_node()
	assert_eq(Controls.scheme, Controls.Scheme.LEFT_HANDED)


func test_registers_a_controls_page_in_settings() -> void:
	assert_true(_node.is_in_group(&"settings_pages"))
	assert_false(_node.is_in_group(&"esc_menu_links"), "Controls moved under Settings")
	assert_eq(_node.settings_page_label(), "Controls")


func test_page_lists_bindings_by_section() -> void:
	var page := _node.settings_page_build()
	add_child_autofree(page)
	var titles: Array[String] = []
	for section: Dictionary in Bindings.sections():
		titles.append(str(section["title"]))
	assert_eq(titles[0], "Movement")
	assert_true(titles.has("Other"), "Unlisted feature actions still show up")
	assert_true(_texts(page).has("Keyboard & mouse"))


func test_sensitivities_are_clamped_and_persist() -> void:
	_node.set_mouse_sensitivity(3.5)
	_node.set_stick_scale(2.0)
	_node.set_touch_scale(99.0)
	Controls.sensitivity = 1.0
	Controls.stick_sensitivity = 1.0
	Controls.touch_sensitivity = 1.0
	_new_node()
	assert_almost_eq(Controls.sensitivity, 3.5, 0.0001)
	assert_almost_eq(Controls.stick_sensitivity, Controls.STICK_SENSITIVITY * 2.0, 0.0001)
	assert_almost_eq(Controls.touch_sensitivity, Controls.TOUCH_SENSITIVITY * 3.0, 0.0001)


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
