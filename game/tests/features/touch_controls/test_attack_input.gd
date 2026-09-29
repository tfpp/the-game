extends GutTest

const Overlay := preload("res://features/touch_controls/touch_controls.gd")
const AttackInput := preload("res://features/touch_controls/attack_input.gd")
var _saved_device: int
var _saved_touch: bool
var _saved_joypad: int


func before_each() -> void:
	_saved_device = Controls.device
	_saved_touch = Controls.touch_available
	_saved_joypad = Controls.joypad
	Controls.ensure_action(&"primary_action", [])
	Controls.ensure_action(&"gun_fire", [])
	Controls.device = Controls.Device.TOUCH
	Controls.touch_available = true
	Controls.joypad = -1
	Controls.start()


func after_each() -> void:
	AttackInput.send_attack(false)
	Input.flush_buffered_events()
	Controls.pause()
	Controls.device = _saved_device
	Controls.touch_available = _saved_touch
	Controls.joypad = _saved_joypad


func _touch(overlay: Control, point: Vector2, pressed: bool) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 3
	touch.position = point * overlay.ui_scale
	touch.pressed = pressed
	overlay._input(touch)
	Input.flush_buffered_events()


func test_trigger_hysteresis() -> void:
	assert_false(AttackInput.trigger_state(false, 0.4))
	assert_true(AttackInput.trigger_state(false, 0.6))
	assert_true(AttackInput.trigger_state(true, 0.4))
	assert_false(AttackInput.trigger_state(true, 0.2))


func test_fire_button_holds_attack_actions() -> void:
	var overlay: Control = Overlay.new()
	overlay.size = Vector2(1280, 720)
	add_child_autofree(overlay)
	_touch(overlay, overlay.fire_center(), true)
	assert_true(Input.is_action_pressed(&"gun_fire"))
	assert_true(Input.is_action_pressed(&"primary_action"))
	_touch(overlay, overlay.fire_center(), false)
	assert_false(Input.is_action_pressed(&"gun_fire"))
	assert_false(Input.is_action_pressed(&"primary_action"))


func test_fire_button_clear_of_other_buttons_on_small_landscape() -> void:
	var overlay: Control = Overlay.new()
	overlay.size = Vector2(844, 390)
	add_child_autofree(overlay)
	var fire: Vector2 = overlay.fire_center()
	assert_gt(fire.distance_to(overlay.jump_center()), 56.0 + 62.0)
	assert_gt(fire.distance_to(overlay.use_center()), 56.0 + 54.0)
	assert_false(overlay.pause_button().grow(56).has_point(fire))
	assert_gt(fire.y - 56.0, 0.0)


func test_right_trigger_presses_once_and_releases() -> void:
	var node: Node = AttackInput.new()
	add_child_autofree(node)
	var motion := InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_TRIGGER_RIGHT
	motion.axis_value = 0.9
	node._input(motion)
	Input.flush_buffered_events()
	assert_true(node.trigger_held)
	assert_true(Input.is_action_pressed(&"gun_fire"))
	motion.axis_value = 0.1
	node._input(motion)
	Input.flush_buffered_events()
	assert_false(node.trigger_held)
	assert_false(Input.is_action_pressed(&"primary_action"))
