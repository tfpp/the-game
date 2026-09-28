extends GutTest
## Pure logic for the "/suicide" command (features/suicide/suicide.gd), kept free of
## scene/networking access so it's unit-testable.

const Suicide := preload("res://features/suicide/suicide.gd")


func test_is_suicide_command_matches_both_accepted_spellings() -> void:
	assert_true(Suicide.is_suicide_command("suicide"))
	assert_true(Suicide.is_suicide_command("sucide"))


func test_is_suicide_command_rejects_other_words() -> void:
	assert_false(Suicide.is_suicide_command("dance"))


func test_kill_position_keeps_the_horizontal_position() -> void:
	var pos := Suicide.kill_position(Vector3(1.0, 5.0, -2.0))
	assert_eq(pos.x, 1.0)
	assert_eq(pos.z, -2.0)


func test_kill_position_drops_below_the_kill_plane() -> void:
	var pos := Suicide.kill_position(Vector3.ZERO)
	assert_lt(pos.y, Game.KILL_Y)
