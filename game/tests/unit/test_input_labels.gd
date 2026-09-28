extends GutTest
## `ui/input_labels.gd`: player-facing names for bindings, used by the HUD and the
## Controls settings page.

var _saved_scheme: int


func before_each() -> void:
	_saved_scheme = Controls.scheme


func after_each() -> void:
	Controls.apply_scheme(_saved_scheme)


func test_event_labels() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	assert_eq(InputLabels.event_label(key), "W")
	key.physical_keycode = KEY_UP
	assert_eq(InputLabels.event_label(key), "Up arrow")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	assert_eq(InputLabels.event_label(mouse), "Left click")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	assert_eq(InputLabels.event_label(pad), "A / Cross")


func test_jump_label_collapses_the_wheel_and_splits_by_device() -> void:
	Controls.apply_scheme(Controls.Scheme.RIGHT_HANDED)
	assert_eq(InputLabels.action_label(&"jump", false), "Space / Wheel")
	assert_eq(InputLabels.action_label(&"jump", true), "A / Cross")


func test_movement_label_follows_the_scheme() -> void:
	Controls.apply_scheme(Controls.Scheme.RIGHT_HANDED)
	assert_eq(InputLabels.movement_label(false), "W A S D")
	Controls.apply_scheme(Controls.Scheme.LEFT_HANDED)
	assert_eq(InputLabels.movement_label(false), "Arrow keys")
	assert_eq(InputLabels.movement_label(true), "Left stick")


func test_sided_modifiers_name_their_side() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SHIFT
	assert_eq(InputLabels.event_label(key), "Shift", "Unsided binding: either Shift")
	key.location = KEY_LOCATION_LEFT
	assert_eq(InputLabels.event_label(key), "Left Shift")
	key.location = KEY_LOCATION_RIGHT
	assert_eq(InputLabels.event_label(key), "Right Shift")
	key.physical_keycode = KEY_META
	assert_true(InputLabels.event_label(key).begins_with("Right "))
	assert_ne(InputLabels.event_label(key), "Right Meta", "Uses the platform's name")
