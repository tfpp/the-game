extends GutTest

const Overlay := preload("res://features/touch_controls/touch_controls.gd")
const Camera := preload("res://features/third_person/third_person.gd")
const Attack := preload("res://features/touch_controls/attack_input.gd")
const PLAYER := preload("res://core/player/player.tscn")

var _overlay: Overlay
var _saved_device: int
var _saved_touch: bool
var _saved_joypad: int
var _saved_sensitivity: float


func before_each() -> void:
	_saved_device = Controls.device
	_saved_touch = Controls.touch_available
	_saved_joypad = Controls.joypad
	_saved_sensitivity = Controls.stick_sensitivity
	Controls.device = Controls.Device.TOUCH
	Controls.touch_available = true
	Controls.joypad = -1
	Controls.stick_sensitivity = 2.6
	Controls.ensure_action(&"primary_action", [])
	Controls.ensure_action(&"gun_fire", [])
	Controls.start()
	_overlay = Overlay.new()
	_overlay.size = Vector2(1280, 720)
	add_child_autofree(_overlay)
	_overlay.set_process(false)


func after_each() -> void:
	Controls.pause()
	Attack.send_attack(false)
	Input.flush_buffered_events()
	Controls.device = _saved_device
	Controls.touch_available = _saved_touch
	Controls.joypad = _saved_joypad
	Controls.stick_sensitivity = _saved_sensitivity


func _touch(index: int, point: Vector2, pressed: bool = true, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point * _overlay.ui_scale
	event.pressed = pressed
	event.canceled = canceled
	_overlay._input(event)
	Input.flush_buffered_events()


func _drag(index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point * _overlay.ui_scale
	# Deliberately wrong relative motion: the overlay must track pointer positions.
	event.relative = Vector2(-999, -999)
	_overlay._input(event)


func _tick(delta: float) -> Vector2:
	_overlay._process(delta)
	return Controls.consume_look(delta)


func test_alignment_and_safe_area_clearance_across_phone_sizes() -> void:
	for screen: Vector2 in [
		Vector2(390, 844), Vector2(844, 390), Vector2(600, 360), Vector2(1280, 720)
	]:
		_overlay.size = screen
		_overlay._resize_layout()
		# Simulate notch and home-indicator insets; hold refresh until after assertions.
		_overlay.safe_bounds = Rect2(Vector2(30, 10), _overlay.ui_size - Vector2(60, 40))
		assert_gte(_overlay.pause_button().position.y * _overlay.ui_scale, 72.0, "Clear HUD")
		var bounds := _overlay.safe_bounds
		var left := _overlay.move_center()
		var right := _overlay.aim_center()
		assert_eq(left.y, right.y)
		assert_eq(left.x - bounds.position.x, bounds.end.x - right.x)
		for center: Vector2 in [left, right]:
			assert_true(bounds.encloses(Rect2(center - Vector2.ONE * 76, Vector2.ONE * 152)))
		assert_gt(left.distance_to(right), Overlay.STICK_RADIUS * 2)
		var targets: Array[Vector2] = [
			_overlay.fire_center(), _overlay.use_center(), _overlay.jump_center()
		]
		for center: Vector2 in targets:
			var radius := Overlay.ACTION_RADIUS
			assert_true(bounds.encloses(Rect2(center - Vector2.ONE * radius, Vector2.ONE * 68)))
			assert_lt(center.y + radius, right.y - Overlay.STICK_RADIUS)
			for menu: Rect2 in [_overlay.camera_button(), _overlay.pause_button()]:
				assert_true(bounds.encloses(menu))
				assert_gt(center.distance_to(center.clamp(menu.position, menu.end)), radius)
		for index: int in targets.size() - 1:
			assert_gt(targets[index].distance_to(targets[index + 1]), Overlay.ACTION_RADIUS * 2)


func test_hold_continuously_aims_with_deadzone_and_diagonal_limit() -> void:
	var center := _overlay.aim_center()
	_touch(1, center)
	_drag(1, center + Vector2(5, 5))
	assert_eq(_tick(0.1), Vector2.ZERO)
	_drag(1, center + Vector2(76, 0))
	assert_almost_eq(_tick(0.1).x, 0.26, 0.00001)
	assert_almost_eq(_tick(0.1).x, 0.26, 0.00001, "Hold turns without more drag events")
	_drag(1, center + Vector2(760, -760))
	var look := _tick(0.1)
	assert_almost_eq(look.length(), 0.26, 0.00001)
	assert_gt(look.x, 0.0)
	assert_lt(look.y, 0.0)
	_drag(1, center)
	assert_eq(_tick(0.1), Vector2.ZERO)


func test_rate_scales_with_time_sensitivity_and_not_screen_pixels() -> void:
	for screen: Vector2 in [Vector2(390, 844), Vector2(844, 390)]:
		_overlay.size = screen
		_overlay._resize_layout()
		var center := _overlay.aim_center()
		_touch(1, center)
		_drag(1, center + Vector2(76, 0))
		Controls.stick_sensitivity = 3.0
		var total := Vector2.ZERO
		for frame: int in 10:
			total += _tick(0.01)
		assert_almost_eq(total.x, _tick(0.1).x, 0.00001)
		assert_almost_eq(total.x, 0.3, 0.00001)
		_touch(1, center, false)


func test_move_aim_fire_use_and_jump_keep_separate_fingers() -> void:
	_touch(1, _overlay.move_center())
	_drag(1, _overlay.move_center() + Vector2(76, 0))
	_touch(2, _overlay.aim_center())
	_drag(2, _overlay.aim_center() + Vector2(76, 0))
	_touch(3, _overlay.fire_center())
	_touch(4, _overlay.use_center())
	_touch(5, _overlay.jump_center())
	assert_true(Input.is_action_pressed(&"gun_fire"))
	assert_eq(_overlay.use_finger, 4)
	assert_eq(Controls.movement(), Vector2.RIGHT)
	assert_true(Controls.consume_jump())
	assert_false(Controls.consume_jump())
	assert_gt(_tick(0.1).x, 0.0)
	_touch(5, _overlay.jump_center(), false)
	_touch(4, _overlay.use_center(), false)
	_touch(3, _overlay.fire_center(), false)
	assert_false(Input.is_action_pressed(&"gun_fire"))
	assert_eq(Controls.movement(), Vector2.RIGHT)
	assert_gt(_tick(0.1).x, 0.0)
	_touch(2, _overlay.aim_center(), false)
	assert_eq(_tick(0.1), Vector2.ZERO)
	assert_eq(Controls.movement(), Vector2.RIGHT)


func test_stick_capture_is_not_stolen_by_other_fingers_or_buttons() -> void:
	var center := _overlay.aim_center()
	_touch(1, center + Vector2(40, 0))
	_touch(2, center)
	_drag(2, center + Vector2(-76, 0))
	assert_eq(_overlay.aim_finger, 1)
	assert_eq(_overlay.look_finger, -1)
	assert_gt(_tick(0.1).x, 0.0)
	_drag(1, _overlay.fire_center())
	assert_false(Input.is_action_pressed(&"gun_fire"), "Dragging does not press FIRE")
	_touch(2, center, false)
	assert_eq(_overlay.aim_finger, 1)
	_touch(1, center, true, true)
	assert_eq(_overlay.aim_finger, -1)
	assert_eq(_tick(0.1), Vector2.ZERO)


func test_pause_focus_resize_device_and_modal_clear_held_aim() -> void:
	for interruption: String in ["pause", "focus", "resize", "device", "modal"]:
		Controls.device = Controls.Device.TOUCH
		Controls.start()
		_touch(1, _overlay.aim_center() + Vector2(76, 0))
		var modal := Node.new()
		add_child_autofree(modal)
		match interruption:
			"pause":
				Controls.pause()
			"focus":
				Controls._focus_lost()
			"resize":
				_overlay._resize_layout()
			"device":
				Controls.select_device(Controls.Device.GAMEPAD)
			"modal":
				modal.add_to_group(&"modal_ui")
		_overlay._process(0.1)
		assert_eq(_overlay.aim_finger, -1, interruption)
		modal.remove_from_group(&"modal_ui")
		Controls.device = Controls.Device.TOUCH
		Controls.start()
		assert_eq(_tick(0.1), Vector2.ZERO, "Resuming requires a fresh touch")


func test_new_stick_turns_actual_player_aim_in_both_camera_views() -> void:
	var player := PLAYER.instantiate() as Player
	add_child_autofree(player)
	player.set_physics_process(false)
	var camera := Camera.new()
	add_child_autofree(camera)
	camera.set_process(false)
	for third_person: bool in [false, true]:
		camera.enabled = third_person
		player.yaw = 0.0
		player.pitch = 0.0
		_touch(1, _overlay.aim_center())
		_drag(1, _overlay.aim_center() + Vector2(76, -76))
		_overlay._process(0.1)
		player._physics_process(0.0)
		assert_lt(player.yaw, 0.0, "Right tilt turns aim right")
		assert_gt(player.pitch, 0.0, "Up tilt raises aim")
		assert_eq(player.net_yaw, player.yaw)
		assert_eq(player.net_pitch, player.pitch)
		assert_eq(camera._orbit, Vector2.ZERO, "AIM turns the character, not just the camera")
		_touch(1, _overlay.aim_center(), false)
