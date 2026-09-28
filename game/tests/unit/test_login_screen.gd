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
