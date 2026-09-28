extends GutTest
## Login screen's idle-menu detection (ui/login/login_screen.gd). Regression for #14:
## opening the chat box also popped the pause menu open on top of it, because both read
## as "not playing" through Controls.gameplay_active()'s modal_ui check.

const Login := preload("res://ui/login/login_screen.gd")


func test_other_modal_ui_open_is_false_with_nothing_else_open() -> void:
	var menu := Login.new()
	add_child_autofree(menu)
	assert_false(menu._other_modal_ui_open())


func test_other_modal_ui_open_is_true_while_the_chat_box_is_open() -> void:
	var menu := Login.new()
	add_child_autofree(menu)
	var chat := Node.new()
	add_child_autofree(chat)
	chat.add_to_group(&"modal_ui")
	assert_true(menu._other_modal_ui_open())


## Regression for #20: a dropped connection used to pop the sign-in menu open. Now it
## just schedules a silent retry (see `_attempt_reconnect`), with no menu in between.
func test_connection_failed_does_not_open_the_menu() -> void:
	var menu := Login.new()
	add_child_autofree(menu)
	menu._server_url = "ws://example.invalid"
	menu._api = AccountApi.new("")
	add_child_autofree(menu._api)
	menu._on_connection_failed("dropped")
	assert_false(menu.visible)
	assert_false(menu._reconnect_timer.is_stopped())
	assert_almost_eq(menu._reconnect_timer.wait_time, Login.RECONNECT_INTERVAL_S, 0.001)


func test_connection_failed_does_nothing_before_a_server_is_configured() -> void:
	var menu := Login.new()
	add_child_autofree(menu)
	menu._on_connection_failed("dropped")
	assert_true(menu._reconnect_timer.is_stopped())


func test_leave_stops_a_pending_reconnect() -> void:
	var menu := Login.new()
	add_child_autofree(menu)
	menu._schedule_reconnect()
	menu._leave()
	assert_true(menu._reconnect_timer.is_stopped())
