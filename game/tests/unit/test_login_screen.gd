extends GutTest
## Login screen behavior (ui/login/login_screen.gd):
## - Skips the sign-in "ready" screen for a returning, already-authenticated player.
## - Idle-menu detection. Regression for #14: opening the chat box also popped the pause
##   menu open on top of it, because both read as "not playing" through
##   Controls.gameplay_active()'s modal_ui check.

const Login := preload("res://ui/login/login_screen.gd")


func test_auto_plays_when_already_signed_in() -> void:
	assert_true(Login.should_auto_play(true, "", false))


func test_does_not_auto_play_without_being_asked() -> void:
	assert_false(Login.should_auto_play(false, "", false))


func test_does_not_auto_play_with_a_message_to_show() -> void:
	assert_false(Login.should_auto_play(true, "Connection failed.", false))


func test_does_not_auto_play_on_a_version_mismatch() -> void:
	assert_false(Login.should_auto_play(true, "", true))


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
