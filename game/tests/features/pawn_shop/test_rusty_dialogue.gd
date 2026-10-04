extends GutTest

const RUSTY := preload("res://features/pawn_shop/rusty_hogg.tscn")
const DIALOGUE := preload("res://features/pawn_shop/rusty_hogg.gd")
const PLAYER := preload("res://core/player/player.tscn")
const REAL_TIME := preload("res://tests/fixtures/real_time.gd")

var _rusty: StationaryPatron
var _talk: NetworkedInteraction
var _player: Player
var _subtitles: Subtitles


func before_each() -> void:
	_rusty = RUSTY.instantiate() as StationaryPatron
	add_child_autofree(_rusty)
	_rusty.set_physics_process(false)
	_talk = _rusty.get_node("Talk") as NetworkedInteraction
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.net_position = Vector3(1.5, 0.95, 0)
	_subtitles = Subtitles.new()
	add_child_autofree(_subtitles)
	_subtitles.set_process(false)


func test_use_shows_one_requested_or_extra_line_as_a_private_subtitle() -> void:
	assert_eq(_rusty.call("interaction_text"), "Trade with Rusty Hogg")
	assert_true(_rusty.is_in_group(&"interactables"))
	assert_true(_rusty.call("can_use", _player))
	_rusty.call("use")
	assert_true(_subtitles.is_showing())
	assert_true(DIALOGUE.LINES.has(_subtitles.current_text().trim_prefix("Rusty Hogg: ")))
	assert_eq(_talk._evaluate(1, &"use", {}), NetworkedEntity.Result.COOLDOWN)


func test_rejects_unknown_sender_payload_distance_and_dead_state() -> void:
	assert_eq(_talk._evaluate(77, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_eq(_talk._evaluate(1, &"use", {"peer": 1}), NetworkedEntity.Result.DENIED)
	_player.net_position = Vector3(5, 0, 0)
	assert_eq(_talk._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	_player.net_position = Vector3(1.5, 0.95, 0)
	_rusty.take_hit(1)
	assert_eq(_talk._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_false(_subtitles.is_showing())
	_rusty._physics_process(StationaryPatron.RESPAWN_DELAY_S)
	assert_eq(_talk._evaluate(1, &"use", {}), NetworkedEntity.Result.ACCEPTED)
	assert_true(_subtitles.is_showing(), "inherited respawn restores conversation")


func test_non_authority_cannot_choose_dialogue() -> void:
	_talk.set_multiplayer_authority(2)
	assert_eq(_talk._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_false(_subtitles.is_showing())


func test_every_requested_line_is_available_with_extra_quips() -> void:
	for line: String in [
		"Don't tell the IRS",
		"Vivienne is hotter than my cousin",
		"Don't point that thing at me",
		"Uncle Sam doesn't have to know about this",
		"No ID? No problem!",
		"Those sissy liberals can't take that away from you!",
	]:
		assert_has(DIALOGUE.LINES, line)
	assert_eq(DIALOGUE.LINES.size(), 12)


func test_successive_replies_do_not_repeat() -> void:
	var previous := ""
	for _index: int in 4:
		assert_eq(_talk._evaluate(1, &"use", {}), NetworkedEntity.Result.ACCEPTED)
		var current := _subtitles.current_text()
		assert_ne(current, previous)
		previous = current
		await REAL_TIME.wait(get_tree(), 0.51)


func test_late_dead_snapshot_is_silent_and_talk_returns_after_reset() -> void:
	var late := RUSTY.instantiate() as StationaryPatron
	late.net_alive = false
	add_child_autofree(late)
	late.set_physics_process(false)
	var talk := late.get_node("Talk") as NetworkedInteraction
	assert_false(late._body.visible)
	assert_eq(talk._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_false(_subtitles.is_showing(), "old conversations are not snapshot state")
	late._entity._on_session_changed(Network.Mode.OFFLINE)
	talk._on_session_changed(Network.Mode.OFFLINE)
	assert_true(late.net_alive)
	assert_eq(talk._evaluate(1, &"use", {}), NetworkedEntity.Result.ACCEPTED)
