extends GutTest
## The DJ booth: server-validated party start, timers, recharge, late joins and the beat.

const FEATURE := preload("res://features/disco_party/feature.tscn")
const PlayerScene := preload("res://core/player/player.tscn")

var _party: DiscoParty


func before_each() -> void:
	_party = FEATURE.instantiate() as DiscoParty
	add_child_autofree(_party)
	_party.set_process(false)


func _player(offset: Vector3, display_name := "Ace") -> Player:
	var player := PlayerScene.instantiate() as Player
	player.set_multiplayer_authority(1)
	player.display_name = display_name
	add_child_autofree(player)
	player.net_position = _party.global_position + offset
	return player


func test_booth_is_an_idle_interactable() -> void:
	assert_true(_party.is_in_group(&"interactables"))
	assert_false(_party.is_partying())
	assert_true(_party.interaction_text().contains("disco party"))
	assert_true(_party.can_use(_player(Vector3(0, 0.9, 1.5))))
	assert_false(_party.can_use(_player(Vector3(0, 0.9, 6.0))), "too far from the booth")


func test_nearby_player_starts_a_party_for_everyone() -> void:
	_player(Vector3(0, 0.9, 1.2), "Ace")
	_party.use()
	assert_true(_party.is_partying())
	assert_eq(_party.net_seconds_left, int(DiscoParty.PARTY_S))
	assert_eq(_party.net_dj, "Ace")
	_party._present(0.1)
	assert_true((_party.get_node("Beams") as Node3D).visible)
	assert_true((_party.get_node("Light") as OmniLight3D).visible)


func test_unknown_or_distant_player_cannot_start_it() -> void:
	_party.use()
	assert_false(_party.is_partying(), "no player for the sender")
	_player(Vector3(5, 0.9, 0))
	_party.use()
	assert_false(_party.is_partying(), "out of range")


func test_party_runs_out_then_recharges_before_the_next_one() -> void:
	_player(Vector3(0, 0.9, 1.2))
	_party.use()
	_party.advance(10.2)
	assert_eq(_party.net_seconds_left, 20)
	_party.use()
	assert_eq(_party.net_seconds_left, 20, "a second press does not restart it")
	_party.advance(DiscoParty.PARTY_S)
	assert_false(_party.is_partying())
	assert_eq(_party.net_dj, "")
	assert_eq(_party.net_recharge_left, int(DiscoParty.RECHARGE_S))
	_party.use()
	assert_false(_party.is_partying(), "still recharging")
	_party.advance(DiscoParty.RECHARGE_S)
	assert_eq(_party.net_recharge_left, 0)
	_party.use()
	assert_true(_party.is_partying())


func test_session_change_ends_the_party() -> void:
	_player(Vector3(0, 0.9, 1.2))
	_party.use()
	_party._reset(Network.Mode.OFFLINE)
	assert_false(_party.is_partying())
	assert_eq(_party.net_recharge_left, 0)


func test_late_joiner_sees_replicated_party_state() -> void:
	var late := FEATURE.instantiate() as DiscoParty
	late.net_seconds_left = 12
	late.net_dj = "Ace"
	add_child_autofree(late)
	late.set_process(false)
	late._present(0.0)
	assert_true(late.is_partying())
	assert_true((late.get_node("Beams") as Node3D).visible)
	assert_eq((late.get_node("Sign") as Label3D).text, "ACE IS ON THE DECKS\n12s")
	var fields: Array = (late.get_node("NetworkedEntity") as NetworkedEntity).replicated_properties
	for field: String in ["net_seconds_left", "net_recharge_left", "net_dj"]:
		assert_true(fields.has(NodePath(".:" + field)), field)


func test_sign_text_for_each_state() -> void:
	assert_eq(DiscoParty.sign_text(0, 0, ""), "DISCO PARTY\nPRESS USE")
	assert_eq(DiscoParty.sign_text(0, 9, ""), "DISCO RECHARGING\n9s")
	assert_eq(DiscoParty.sign_text(5, 0, "zed"), "ZED IS ON THE DECKS\n5s")


func test_beat_is_one_seamless_looping_bar() -> void:
	var stream := DiscoBeat.build()
	assert_eq(stream.mix_rate, DiscoBeat.MIX_RATE)
	assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(stream.loop_end, DiscoBeat.bar_frames())
	assert_eq(stream.data.size(), DiscoBeat.bar_frames() * 2)
	assert_almost_eq(stream.get_length(), 2.0, 0.01)
	var loudest := 0
	for i: int in range(0, stream.data.size(), 64):
		loudest = maxi(loudest, absi(stream.data.decode_s16(i)))
	assert_gt(loudest, 8000, "the bar is audible")
