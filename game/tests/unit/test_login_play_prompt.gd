extends GutTest
## First load shows a small "Click to play" prompt instead of the full Esc menu
## (Phase 1 task D2); after the player has played, a lost pointer lock opens the menu.

const Login := preload("res://ui/login/login_screen.gd")

var _menu: CanvasLayer


func before_each() -> void:
	_menu = Login.new()
	add_child_autofree(_menu)


func after_each() -> void:
	Controls.pause()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_first_idle_shows_the_play_prompt_not_the_menu() -> void:
	_menu._idle_timeout()
	assert_false(_menu.visible, "The full menu stays closed on first load")
	assert_false(_menu.is_in_group(&"modal_ui"))
	assert_true(_menu._play_layer.visible)
	assert_string_ends_with(_menu._play_prompt.text, "to play")


func test_prompt_shows_while_the_menu_layer_is_hidden() -> void:
	_menu._idle_timeout()
	assert_true(_menu._play_prompt.is_visible_in_tree())


func test_pressing_the_prompt_starts_play_and_hides_it() -> void:
	_menu._idle_timeout()
	_menu._play_prompt.pressed.emit()
	assert_false(_menu._play_layer.visible)
	assert_true(Controls.playing)


func test_after_playing_a_lost_lock_opens_the_menu() -> void:
	_menu._has_played = true
	_menu._idle_timeout()
	assert_true(_menu.visible)
	assert_false(_menu._play_layer.visible)


func test_opening_the_menu_hides_the_prompt() -> void:
	_menu._idle_timeout()
	_menu.open_menu()
	assert_false(_menu._play_layer.visible)
