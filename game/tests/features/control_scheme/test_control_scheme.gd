extends GutTest
## `features/control_scheme/control_scheme.gd`: left-handed-by-default input, the
## play-time unlock for the right-handed layout, and the menu that switches between them.

const ControlScheme := preload("res://features/control_scheme/control_scheme.gd")
const STORE_PATH := "user://controls.cfg"

var _saved_device: int
var _saved_scheme: int
var _node: ControlScheme


func before_each() -> void:
	_saved_device = Controls.device
	_saved_scheme = Controls.scheme
	_clear_store()
	Controls.device = Controls.Device.TOUCH
	Controls.start()
	_node = ControlScheme.new()
	add_child_autofree(_node)


func after_each() -> void:
	Controls.pause()
	Controls.device = _saved_device
	Controls.apply_scheme(_saved_scheme)
	_clear_store()


func test_defaults_to_left_handed_arrow_keys_and_shift_jump() -> void:
	assert_eq(Controls.scheme, Controls.Scheme.LEFT_HANDED)
	assert_eq(_physical_keys("move_forward"), [KEY_UP])
	assert_eq(_physical_keys("move_back"), [KEY_DOWN])
	assert_eq(_physical_keys("move_left"), [KEY_LEFT])
	assert_eq(_physical_keys("move_right"), [KEY_RIGHT])
	assert_eq(_physical_keys("jump"), [KEY_SHIFT])


func test_apply_scheme_switches_to_classic_wasd_and_space() -> void:
	Controls.apply_scheme(Controls.Scheme.RIGHT_HANDED)
	assert_eq(_physical_keys("move_forward"), [KEY_W])
	assert_eq(_physical_keys("move_back"), [KEY_S])
	assert_eq(_physical_keys("move_left"), [KEY_A])
	assert_eq(_physical_keys("move_right"), [KEY_D])
	assert_eq(_physical_keys("jump"), [KEY_SPACE])


func test_scroll_wheel_still_bhops_in_either_scheme() -> void:
	for scheme: int in [Controls.Scheme.LEFT_HANDED, Controls.Scheme.RIGHT_HANDED]:
		Controls.apply_scheme(scheme)
		var jump := InputMap.action_get_events("jump")
		assert_eq((jump[1] as InputEventMouseButton).button_index, MOUSE_BUTTON_WHEEL_DOWN)
		assert_eq((jump[2] as InputEventMouseButton).button_index, MOUSE_BUTTON_WHEEL_UP)


func test_switch_button_stays_locked_before_five_minutes_of_play() -> void:
	_node._process(ControlScheme.UNLOCK_SECONDS - 1.0)
	_node._refresh()
	assert_false(_node.unlocked())
	assert_true(_node._switch_button.disabled)


func test_switch_button_unlocks_after_five_minutes_of_play() -> void:
	_node._process(ControlScheme.UNLOCK_SECONDS)
	_node._refresh()
	assert_true(_node.unlocked())
	assert_false(_node._switch_button.disabled)


func test_played_time_only_accumulates_while_gameplay_is_active() -> void:
	Controls.pause()
	_node._process(120.0)
	assert_eq(_node.played_s, 0.0)
	Controls.start()
	_node._process(120.0)
	assert_eq(_node.played_s, 120.0)


func test_switch_button_toggles_scheme_and_is_a_no_op_while_locked() -> void:
	_node._toggle_scheme()
	assert_eq(Controls.scheme, Controls.Scheme.LEFT_HANDED, "Locked: pressing it does nothing")
	_node.played_s = ControlScheme.UNLOCK_SECONDS
	_node._toggle_scheme()
	assert_eq(Controls.scheme, Controls.Scheme.RIGHT_HANDED)
	_node._toggle_scheme()
	assert_eq(Controls.scheme, Controls.Scheme.LEFT_HANDED, "Unlocked switches both ways")


func test_choice_and_progress_persist_across_a_restart() -> void:
	_node.played_s = ControlScheme.UNLOCK_SECONDS
	_node._toggle_scheme()
	var reloaded := ControlScheme.new()
	add_child_autofree(reloaded)
	assert_eq(reloaded.played_s, ControlScheme.UNLOCK_SECONDS)
	assert_eq(Controls.scheme, Controls.Scheme.RIGHT_HANDED)


func test_remaining_text_formats_minutes_and_seconds() -> void:
	assert_eq(ControlScheme.remaining_text(125.0), "2:05")
	assert_eq(ControlScheme.remaining_text(0.0), "0:00")
	assert_eq(ControlScheme.remaining_text(-5.0), "0:00")


func test_opening_the_panel_pauses_and_joins_the_modal_group() -> void:
	_node._open()
	assert_true(_node._panel.visible)
	assert_true(_node.is_in_group(&"modal_ui"))
	assert_false(Controls.gameplay_active())
	_node._close()
	assert_false(_node._panel.visible)
	assert_false(_node.is_in_group(&"modal_ui"))
	assert_true(Controls.gameplay_active())


func test_registers_a_controls_link_in_the_esc_menu() -> void:
	assert_true(_node.is_in_group(&"esc_menu_links"))
	assert_eq(_node.esc_menu_label(), "Controls")


func test_esc_menu_open_opens_the_panel() -> void:
	_node.esc_menu_open()
	assert_true(_node._panel.visible)


func _physical_keys(action: String) -> Array[int]:
	var keys: Array[int] = []
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			keys.append((event as InputEventKey).physical_keycode)
	return keys


func _clear_store() -> void:
	if FileAccess.file_exists(STORE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE_PATH))
