extends GutTest
## Skips the sign-in "ready" screen for a returning, already-authenticated player.

const LoginScreen := preload("res://ui/login/login_screen.gd")


func test_auto_plays_when_already_signed_in() -> void:
	assert_true(LoginScreen.should_auto_play(true, "", false))


func test_does_not_auto_play_without_being_asked() -> void:
	assert_false(LoginScreen.should_auto_play(false, "", false))


func test_does_not_auto_play_with_a_message_to_show() -> void:
	assert_false(LoginScreen.should_auto_play(true, "Connection failed.", false))


func test_does_not_auto_play_on_a_version_mismatch() -> void:
	assert_false(LoginScreen.should_auto_play(true, "", true))
