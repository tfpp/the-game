extends GutTest

const FEATURE := preload("res://features/adventure_machine/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _machine: AdventureMachine
var _player: Player
var _window_size: Vector2i
var _device: Controls.Device


func before_each() -> void:
	_window_size = get_window().size
	_device = Controls.device
	Controls.select_device(Controls.Device.GAMEPAD)
	_machine = FEATURE.instantiate() as AdventureMachine
	add_child_autofree(_machine)
	_player = PLAYER.instantiate() as Player
	_player.get_node("Sync").free()
	_player.position = _machine.position + Vector3(0, 1, 1.6)
	add_child_autofree(_player)
	_player.set_physics_process(false)
	await wait_physics_frames(4)
	_machine.use()


func after_each() -> void:
	_machine._screen.close(false)
	get_window().size = _window_size
	Controls.pause()
	Controls.select_device(_device)


func test_choice_buttons_use_original_validated_action_and_pause_movement() -> void:
	var screen := _machine._screen
	var take: Button
	for button: Button in screen._buttons:
		if button.get_meta("choice", "") == "take_magnet":
			take = button
	assert_not_null(take)
	take.pressed.emit()
	assert_eq(_machine._stories[1].inventory, ["magnet"])
	assert_eq(screen._revision, 1)
	assert_false(screen._waiting)
	assert_false(Controls.gameplay_active())
	assert_eq(Controls.movement(), Vector2.ZERO)
	screen._log_button.pressed.emit()
	assert_true(screen._history.visible)
	assert_string_contains(screen._history.text, "Pick up horseshoe magnet")
	screen._close_button.pressed.emit()
	assert_false(screen.is_open())


func test_escape_cancel_and_controller_menu_release_modal_and_delayed_page_stays_closed() -> void:
	var screen := _machine._screen
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	screen._input(event)
	assert_false(screen.is_open())
	assert_false(screen.is_in_group(&"modal_ui"))
	_machine._event(&"page", _machine._stories[1].page())
	assert_false(screen.is_open(), "Late reliable reply must not steal focus")
	_machine.use()
	Controls.menu_requested.emit()
	assert_false(screen.is_open())
	assert_false(screen.is_in_group(&"modal_ui"))


func test_phone_and_short_landscape_keep_close_visible_and_choices_scrollable() -> void:
	var screen := _machine._screen
	for size: Vector2i in [Vector2i(390, 844), Vector2i(844, 390), Vector2i(320, 568)]:
		get_window().size = size
		await wait_process_frames(4)
		screen._resize()
		await wait_process_frames(3)
		var available := get_viewport().get_visible_rect().size / screen.scale
		var rect := screen._root.get_rect()
		assert_gte(rect.position.x, 0.0)
		assert_gte(rect.position.y, 0.0)
		assert_lte(rect.end.x, available.x + 1)
		assert_lte(rect.end.y, available.y + 1)
		var close_rect := screen._close_button.get_global_rect()
		assert_lte(close_rect.end.y, available.y + 1)
		assert_gte(close_rect.position.y, rect.position.y)
		assert_gte(screen._close_button.size.y, 56.0)
		assert_true(screen._scroll.follow_focus)
		assert_gt(screen._scroll.get_v_scroll_bar().max_value, screen._scroll.size.y)
		assert_true(screen._buttons[0].has_focus())


func test_controller_focus_scrolls_actions_into_view_on_short_screen() -> void:
	var screen := _machine._screen
	get_window().size = Vector2i(844, 390)
	await wait_process_frames(5)
	var last: Button
	for button: Button in screen._buttons:
		if button.visible:
			last = button
	last.grab_focus()
	await wait_process_frames(3)
	assert_true(last.has_focus())
	assert_gt(screen._scroll.scroll_vertical, 0, "Focus navigation must reveal off-screen actions")
	var clip := screen._scroll.get_global_rect()
	var row := last.get_global_rect()
	assert_lte(row.end.y, clip.end.y + 1)
	assert_gte(row.position.y, clip.position.y - 1)


func test_leaving_range_closes_without_erasing_progress_and_pending_timeout_unblocks() -> void:
	var screen := _machine._screen
	screen._set_waiting(true)
	screen._sent_msec = Time.get_ticks_msec() - 6000
	screen._process(.25)
	assert_false(screen._waiting)
	_player.net_position += Vector3(10, 0, 0)
	screen._process(.25)
	assert_false(screen.is_open())
	assert_true(_machine._stories.has(1))
