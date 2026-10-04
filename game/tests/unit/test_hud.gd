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


func test_voice_text_names_speakers_compactly() -> void:
	assert_eq(Hud.voice_text(PackedStringArray()), "VOICE")
	assert_eq(Hud.voice_text(PackedStringArray(["You", "Ana"])), "VOICE · You, Ana")
	assert_eq(Hud.voice_text(PackedStringArray(["A", "B", "C", "D", "E"])), "VOICE · A, B, C +2")


func test_status_counts_nearby_players_within_voice_range() -> void:
	var others: Array[Vector3] = [Vector3(3, 0, 0), Vector3(0, 0, 25), Vector3(0, 19, 0)]
	assert_eq(Hud.count_nearby(Vector3.ZERO, others, Hud.NEARBY_RADIUS), 2)
	assert_eq(Hud.status_text(2, 5, "online"), "2 nearby · 5 players · online")
