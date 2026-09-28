extends GutTest
## HUD corner text.

const Hud := preload("res://ui/hud.gd")


func test_release_text_is_a_v_tag() -> void:
	assert_eq(Hud.release_text("0.3.0"), "v0.3.0")


func test_player_count_text_pluralizes() -> void:
	assert_eq(Hud.player_count_text(0), "0 players")
	assert_eq(Hud.player_count_text(1), "1 player")
	assert_eq(Hud.player_count_text(12), "12 players")


## The release workflow bumps the version, so check its shape, not a literal.
func test_release_version_is_set() -> void:
	var version := Network.game_version()
	var semver := RegEx.create_from_string("^\\d+\\.\\d+\\.\\d+$")
	assert_not_null(semver.search(version), "%s is X.Y.Z" % version)
	assert_ne(version, "0.0.0")
