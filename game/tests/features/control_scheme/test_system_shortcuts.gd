extends GutTest

const Shortcuts := preload("res://features/control_scheme/system_shortcuts.gd")
const Login := preload("res://ui/login/login_screen.gd")

var _helper: Shortcuts
var _device: int
var _playing: bool


func before_each() -> void:
	_device = Controls.device
	_playing = Controls.playing
	# Headless cannot capture a mouse; touch exercises the same playing/modal gate.
	Controls.device = Controls.Device.TOUCH
	Controls.start()
	_helper = Shortcuts.new()
	add_child_autofree(_helper)
	_helper.macos = true


func after_each() -> void:
	_helper.remove_from_group(&"modal_ui")
	Controls.pause()
	Controls.device = _device
	Controls.playing = _playing


func _command() -> InputEventKey:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_META
	key.meta_pressed = true
	key.pressed = true
	return key


func test_command_yields_before_final_digit_and_clears_input() -> void:
	Controls.look_delta = Vector2.ONE
	Controls.jump_queued = true
	_helper._input(_command())
	assert_true(_helper.is_in_group(&"modal_ui"))
	assert_false(Controls.gameplay_active())
	assert_false(Controls.playing)
	assert_eq(Controls.look_delta, Vector2.ZERO)
	assert_false(Controls.jump_queued)
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE)


func test_focus_return_and_command_release_do_not_recapture() -> void:
	_helper._input(_command())
	Controls._focus_lost()
	Controls._focus_regained()
	var release := _command()
	release.pressed = false
	_helper._input(release)
	assert_false(Controls.playing)
	assert_true(_helper.is_in_group(&"modal_ui"))
	var menu := Login.new()
	add_child_autofree(menu)
	assert_true(menu._other_modal_ui_open(), "Screenshot pause suppresses idle menu")


func test_left_click_resumes_but_modified_click_does_not() -> void:
	_helper._input(_command())
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.meta_pressed = true
	_helper._input(click)
	assert_false(Controls.playing)
	click.meta_pressed = false
	_helper._input(click)
	assert_false(_helper.is_in_group(&"modal_ui"))
	assert_true(Controls.playing)
	assert_eq(Controls.device, Controls.Device.KEYBOARD)


func test_escape_hands_off_to_normal_menu() -> void:
	watch_signals(Controls)
	_helper._input(_command())
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	_helper._input(escape)
	assert_false(_helper.is_in_group(&"modal_ui"))
	assert_signal_emitted(Controls, "menu_requested")
	assert_false(Controls.playing)


func test_other_platforms_and_unmodified_keys_keep_playing() -> void:
	_helper.macos = false
	_helper._input(_command())
	assert_true(Controls.playing)
	_helper.macos = true
	var digit := InputEventKey.new()
	digit.physical_keycode = KEY_4
	digit.pressed = true
	_helper._input(digit)
	assert_true(Controls.playing)
	assert_false(_helper.is_in_group(&"modal_ui"))


func test_existing_modal_is_not_taken_over() -> void:
	var panel := Node.new()
	add_child_autofree(panel)
	panel.add_to_group(&"modal_ui")
	_helper._input(_command())
	assert_false(_helper.is_in_group(&"modal_ui"))
	assert_true(panel.is_in_group(&"modal_ui"))
