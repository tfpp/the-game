extends GutTest

const Overlay := preload("res://features/touch_controls/touch_controls.gd")
const Camera := preload("res://features/third_person/third_person.gd")
const Settings := preload("res://features/settings/settings.gd")
const PLAYER := preload("res://core/player/player.tscn")

var _overlay: Overlay
var _saved_preferences: String
var _saved_device: int
var _saved_touch: bool
var _saved_joypad: int


func before_each() -> void:
	_saved_preferences = SettingsStore.load_text(Overlay.STORE_NAME)
	SettingsStore.save_data(Overlay.STORE_NAME, {})
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
	_overlay.set_process(false)


func after_each() -> void:
	Controls.pause()
	Controls.device = _saved_device
	Controls.touch_available = _saved_touch
	Controls.joypad = _saved_joypad
	SettingsStore.save_text(Overlay.STORE_NAME, _saved_preferences)


func _touch(index: int, point: Vector2, pressed: bool = true) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point * _overlay.ui_scale
	event.pressed = pressed
	_overlay._input(event)


func _drag(index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point * _overlay.ui_scale
	_overlay._input(event)


func _player() -> Player:
	var player := PLAYER.instantiate() as Player
	add_child_autofree(player)
	player.set_physics_process(false)
	return player


func _camera() -> Camera:
	var camera := Camera.new()
	add_child_autofree(camera)
	camera.set_process(false)
	return camera


func test_default_off_reclaims_entire_stick_area_for_first_person_swipe_aim() -> void:
	var player := _player()
	_camera()
	assert_false(_overlay.first_person_aim_enabled)
	assert_false(_overlay.aim_stick_active())
	var center := _overlay.aim_center()
	_touch(1, center)
	assert_eq(_overlay.aim_finger, -1)
	assert_eq(_overlay.look_finger, 1)
	_drag(1, center + Vector2(20, -10))
	player._physics_process(0.0)
	assert_lt(player.yaw, 0.0)
	assert_gt(player.pitch, 0.0)
	assert_eq(player.net_yaw, player.yaw)
	assert_eq(player.net_pitch, player.pitch)
	var yaw := player.yaw
	_overlay._process(0.1)
	player._physics_process(0.0)
	assert_eq(player.yaw, yaw, "Holding a swipe finger does not continuously aim")
	_touch(1, center, false)
	assert_eq(_overlay.look_finger, -1)


func test_settings_toggle_persists_and_reopens_with_saved_state() -> void:
	var settings := Settings.new()
	add_child_autofree(settings)
	assert_true(settings.pages().has(_overlay))
	assert_eq(_overlay.settings_page_label(), "Touch controls")
	settings.open()
	settings.show_page(_overlay)
	var content := settings._body.get_child(0) as VBoxContainer
	var toggle := content.get_child(0) as CheckButton
	assert_false(toggle.button_pressed)
	toggle.button_pressed = true
	assert_true(_overlay.aim_stick_active())
	assert_eq(SettingsStore.load_data(Overlay.STORE_NAME), {"first_person_aim_enabled": true})
	var restored := Overlay.new()
	add_child_autofree(restored)
	assert_true(restored.first_person_aim_enabled)
	settings.go_back()
	settings.show_page(_overlay)
	content = settings._body.get_child(0) as VBoxContainer
	toggle = content.get_child(0) as CheckButton
	assert_true(toggle.button_pressed)
	toggle.button_pressed = false
	assert_false(_overlay.aim_stick_active())
	var disabled := Overlay.new()
	add_child_autofree(disabled)
	assert_false(disabled.first_person_aim_enabled)
	settings.close()


func test_swipe_and_stick_both_work_when_first_person_toggle_is_on() -> void:
	var player := _player()
	_camera()
	_overlay.set_first_person_aim_enabled(true)
	_touch(1, _overlay.aim_center())
	_drag(1, _overlay.aim_center() + Vector2(76, 0))
	_touch(2, Vector2(700, 250))
	_drag(2, Vector2(720, 240))
	assert_eq(_overlay.aim_finger, 1)
	assert_eq(_overlay.look_finger, 2)
	_overlay._process(0.1)
	player._physics_process(0.0)
	assert_lt(player.yaw, -0.25, "Stick and swipe both turn the player")
	assert_gt(player.pitch, 0.0, "Swipe still raises aim")
	_touch(2, Vector2(720, 240), false)
	_overlay._process(0.1)
	assert_gt(Controls.consume_look(0.1).x, 0.0, "Releasing swipe does not stop the stick")


func test_disabling_held_stick_preserves_movement_and_requires_fresh_swipe() -> void:
	_overlay.set_first_person_aim_enabled(true)
	_touch(1, _overlay.move_center())
	_drag(1, _overlay.move_center() + Vector2(76, 0))
	_touch(2, _overlay.aim_center() + Vector2(76, 0))
	_overlay.set_first_person_aim_enabled(false)
	assert_eq(_overlay.aim_finger, -1)
	assert_eq(_overlay.aim_value, Vector2.ZERO)
	assert_eq(Controls.movement(), Vector2.RIGHT)
	_drag(2, _overlay.aim_center() + Vector2(40, 0))
	_overlay._process(0.1)
	assert_eq(Controls.consume_look(0.1), Vector2.ZERO)
	_touch(2, _overlay.aim_center(), false)
	_touch(2, _overlay.aim_center())
	assert_eq(_overlay.look_finger, 2)


func test_camera_toggle_keeps_third_person_stick_and_clears_it_on_first_person_return() -> void:
	_player()
	var camera := _camera()
	_touch(9, _overlay.camera_button().get_center())
	assert_true(camera.enabled)
	assert_true(_overlay.aim_stick_active())
	_touch(1, _overlay.aim_center() + Vector2(76, 0))
	_overlay._process(0.1)
	assert_gt(Controls.consume_look(0.1).x, 0.0)
	_touch(2, Vector2(700, 250))
	_drag(2, Vector2(720, 240))
	assert_ne(camera._orbit, Vector2.ZERO, "Third-person swipes still orbit")
	assert_eq(Controls.consume_look(0.0), Vector2.ZERO)
	_touch(2, Vector2(720, 240), false)
	_touch(9, _overlay.camera_button().get_center())
	assert_false(camera.enabled)
	_overlay._process(0.1)
	assert_eq(_overlay.aim_finger, -1)
	assert_eq(Controls.consume_look(0.1), Vector2.ZERO)
	assert_false(_overlay.first_person_aim_enabled, "CAM does not change the saved preference")
	_touch(1, _overlay.aim_center(), false)
	_touch(1, _overlay.aim_center())
	assert_eq(_overlay.look_finger, 1)
	_overlay.set_first_person_aim_enabled(true)
	camera.toggle_camera()
	camera.toggle_camera()
	assert_true(_overlay.aim_stick_active(), "Opt-in survives camera changes")
