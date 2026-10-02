extends GutTest

const PLAYER := preload("res://core/player/player.tscn")
const FEATURE := preload("res://features/player_models/feature.tscn")
const WHEEL := preload("res://features/player_models/emote_wheel.gd")

var _models: PlayerModels
var _wheel: Control
var _player: Player


func before_each() -> void:
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_models = FEATURE.instantiate() as PlayerModels
	add_child_autofree(_models)
	_models.set_process(false)
	_wheel = _models.get_node("EmoteUI/Wheel") as Control
	Controls.device = Controls.Device.GAMEPAD
	Controls.start()


func after_each() -> void:
	_wheel.close(false, false)
	Controls.pause()
	Controls.device = Controls.Device.KEYBOARD
	await get_tree().process_frame


func _key(pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_B
	event.pressed = pressed
	return event


func test_radial_directions_and_center_cancel() -> void:
	assert_eq(WHEEL.sector(Vector2.ZERO, 10), -1)
	assert_eq(WHEEL.sector(Vector2(9, 0), 10), -1)
	assert_eq(WHEEL.sector(Vector2.UP * 100, 10), 0)
	assert_eq(WHEEL.sector(Vector2.RIGHT * 100, 10), 1)
	assert_eq(WHEEL.sector(Vector2.DOWN * 100, 10), 2)
	assert_eq(WHEEL.sector(Vector2.LEFT * 100, 10), 3)


func test_hold_pauses_gameplay_and_release_commits_only_selected_name() -> void:
	_wheel._unhandled_input(_key(true))
	assert_true(_wheel.visible)
	assert_true(_wheel.is_in_group(&"modal_ui"))
	assert_false(Controls.gameplay_active())
	assert_true(_models.emotes.is_empty())
	_wheel.select_direction(Vector2.RIGHT * 500)
	_wheel._input(_key(false))
	assert_false(_wheel.visible)
	assert_false(_wheel.is_in_group(&"modal_ui"))
	assert_true(Controls.gameplay_active())
	assert_eq(_models.emote_name(1), "wave")


func test_tap_without_direction_and_escape_cancel() -> void:
	_wheel._unhandled_input(_key(true))
	_wheel._input(_key(false))
	assert_true(_models.emotes.is_empty())
	_wheel.open(true)
	_wheel.select_direction(Vector2.UP * 500)
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	_wheel._input(escape)
	assert_false(_wheel.visible)
	assert_true(_models.emotes.is_empty())


func test_gameplay_gate_and_other_modal_are_preserved() -> void:
	Controls.pause()
	_wheel._unhandled_input(_key(true))
	assert_false(_wheel.visible)
	var modal := Node.new()
	add_child_autofree(modal)
	modal.add_to_group(&"modal_ui")
	_wheel.open(true)
	assert_false(_wheel.visible)


func test_menu_link_accepts_touch_selection() -> void:
	assert_eq(_wheel.esc_menu_label(), "Emotes")
	_wheel.esc_menu_open()
	assert_true(_wheel.visible)
	assert_false(_wheel.held)
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = (
		_wheel.get_global_transform_with_canvas()
		* (_wheel.size * 0.5 + Vector2.LEFT * _wheel.radius() * 0.65)
	)
	_wheel._input(touch)
	assert_false(_wheel.visible)
	assert_eq(_models.emote_name(1), "cheer")


func test_focus_loss_session_change_and_respawn_cancel_without_emoting() -> void:
	_wheel.open(true)
	_wheel.select_direction(Vector2.UP * 500)
	get_window().focus_exited.emit()
	assert_false(_wheel.visible)
	assert_false(Controls.playing)
	assert_true(_models.emotes.is_empty())
	_wheel.open(false)
	Network.mode_changed.emit(Network.Mode.OFFLINE)
	assert_false(_wheel.visible)
	_wheel.open(true)
	_player.queue_free()
	_wheel._process(0)
	assert_false(_wheel.visible)
	assert_true(_models.emotes.is_empty())


func test_controller_hold_uses_same_wheel_without_taking_use_button() -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_LEFT_STICK
	event.pressed = true
	_wheel._unhandled_input(event)
	assert_true(_wheel.visible)
	_wheel.select_direction(Vector2.DOWN * 500)
	event.pressed = false
	_wheel._input(event)
	assert_eq(_models.emote_name(1), "salute")


func test_resize_preserves_center_and_relative_deadzone() -> void:
	_wheel.open(false)
	_wheel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	for viewport_size: Vector2 in [Vector2(320, 568), Vector2(640, 320), Vector2(1280, 720)]:
		_wheel.size = viewport_size
		assert_lt(_wheel.radius(), minf(viewport_size.x, viewport_size.y) * 0.5)
		_wheel.select_direction(Vector2.RIGHT * _wheel.radius() * 0.1)
		assert_eq(_wheel.selected, -1)
		_wheel.select_direction(Vector2.RIGHT * _wheel.radius() * 0.65)
		assert_eq(_wheel.selected, 1)
