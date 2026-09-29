extends GutTest
## Praying at the Kaaba: server validation, stacking blessings and slot luck.

const FEATURE_PATH := "res://features/kaaba/feature.tscn"
const PlayerScene := preload("res://core/player/player.tscn")

var _root: Node3D
var _prayer: KaabaPrayer


func before_each() -> void:
	_root = add_child_autofree((load(FEATURE_PATH) as PackedScene).instantiate() as Node3D)
	_prayer = _root.get_node("Prayer") as KaabaPrayer
	_prayer.set_process(false)


func _player(offset: Vector3) -> Player:
	var player := PlayerScene.instantiate() as Player
	player.set_multiplayer_authority(1)
	add_child_autofree(player)
	player.net_position = _root.global_position + offset
	return player


func test_prayer_is_an_interactable_at_the_kaaba() -> void:
	assert_true(_prayer.is_in_group(&"interactables"))
	assert_true(_prayer.interaction_text().contains("+200% slot luck"))
	assert_eq(_prayer.global_position, _root.global_position)
	assert_true(_prayer.can_use(_player(Vector3(0, 0.9, 3.5))), "beside the south wall")
	assert_false(_prayer.can_use(_player(Vector3(0, 0.9, 9.0))), "too far away")


func test_unknown_player_cannot_pray() -> void:
	_prayer.request_pray()
	assert_true(_prayer.praying.is_empty())


func test_praying_stacks_blessings_up_to_the_cap() -> void:
	var player := _player(Vector3(3.5, 0.9, 0))
	for expected: int in range(1, KaabaPrayer.MAX_BLESSINGS + 1):
		_prayer.request_pray()
		assert_true(_prayer.praying.has(1))
		_prayer.request_pray()
		_prayer._advance(KaabaPrayer.PRAYER_S - 0.1)
		assert_eq(_prayer.blessings_for(1), expected - 1, "not before the prayer ends")
		_prayer._advance(0.2)
		assert_eq(_prayer.blessings_for(1), expected)
		assert_false(_prayer.praying.has(1))
	_prayer.request_pray()
	assert_false(_prayer.praying.has(1), "blessings are full")
	assert_false(player.is_queued_for_deletion())


func test_walking_away_interrupts_the_prayer() -> void:
	var player := _player(Vector3(3.5, 0.9, 0))
	_prayer.request_pray()
	player.net_position = _root.global_position + Vector3(12, 0.9, 0)
	_prayer._advance(KaabaPrayer.PRAYER_S)
	assert_eq(_prayer.blessings_for(1), 0)
	assert_true(_prayer.praying.is_empty())


func test_win_disconnect_and_session_change_clear_blessings() -> void:
	_prayer.blessings = {1: 3, 2: 2}
	_prayer.consume(1)
	assert_eq(_prayer.blessings_for(1), 0)
	_prayer._forget(2)
	assert_eq(_prayer.blessings_for(2), 0)
	_prayer.blessings = {1: 3}
	_prayer._on_mode_changed(Network.Mode.OFFLINE)
	assert_eq(_prayer.blessings_for(1), 0)


func test_blessings_raise_exact_slot_win_chance_by_200_percent_each() -> void:
	for stacks: int in range(6):
		var wins := 0
		var outcomes: Dictionary = {}
		for ticket: int in range(125):
			var reels := SlotSpinCycle.result_for_ticket(ticket, stacks)
			outcomes[str(reels)] = true
			wins += int(SlotSpinCycle.is_win(reels))
			for symbol: int in reels:
				assert_between(symbol, 0, 4)
		assert_eq(wins, 5 + 10 * stacks)
		assert_almost_eq(SlotSpinCycle.win_chance(stacks), float(wins) / 125.0, 0.00001)
		if stacks == 0:
			assert_eq(outcomes.size(), 125, "all original outcomes remain equally likely")
	assert_almost_eq(SlotSpinCycle.win_chance(1), 0.12, 0.00001)
	assert_eq(SlotSpinCycle.win_chance(99), SlotSpinCycle.win_chance(5))


func test_temporary_wallet_uses_blessings() -> void:
	var wallet := PlayerMoney.new()
	add_child_autofree(wallet)
	wallet.set_process(false)
	var wins := 0
	for spin: int in 1000:
		var result: Dictionary = await wallet.spin(1, "id%d" % spin, 1, 5)
		wins += int(int(result.get("payout", 0)) > 0)
	assert_between(wins, 330, 550, "five blessings win 44% of spins")


func test_component_rejects_forgery_unknown_peer_and_vertical_distance() -> void:
	var player := _player(Vector3(3.5, 0.9, 0))
	var entity := _prayer.get_node("NetworkedEntity") as NetworkedInteraction
	assert_eq(entity._evaluate(1, &"use", {"peer": 2}), NetworkedEntity.Result.DENIED)
	assert_eq(entity._evaluate(2, &"use", {}), NetworkedEntity.Result.DENIED)
	player.net_position.y += 20
	assert_eq(entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_true(_prayer.praying.is_empty())


func test_simultaneous_players_and_death_cancel_only_their_own_prayer() -> void:
	_player(Vector3(3.5, 0.9, 0))
	var other := _player(Vector3(-3.5, 0.9, 0))
	other.set_multiplayer_authority(2)
	var entity := _prayer.get_node("NetworkedEntity") as NetworkedInteraction
	assert_eq(entity._evaluate(1, &"use", {}), NetworkedEntity.Result.ACCEPTED)
	assert_eq(entity._evaluate(2, &"use", {}), NetworkedEntity.Result.ACCEPTED)
	_prayer._advance(3.0)
	_prayer._on_death(1, 2)
	_prayer._advance(3.0)
	assert_eq(_prayer.blessings_for(1), 0)
	assert_eq(_prayer.blessings_for(2), 1)
	assert_true(_prayer.praying.is_empty())


func test_replication_includes_current_prayers_and_blessings_for_late_joiners() -> void:
	var sync := _prayer.get_node("NetworkedEntity/Sync") as MultiplayerSynchronizer
	assert_eq(sync.get_multiplayer_authority(), 1)
	assert_same(sync.get_node(sync.root_path), _prayer)
	for property: NodePath in [NodePath(".:blessings"), NodePath(".:praying")]:
		assert_true(sync.replication_config.property_get_spawn(property))
		assert_eq(sync.replication_config.property_get_replication_mode(property), 2)


func test_chant_is_a_few_seconds_of_audio() -> void:
	var chant := KaabaChant.takbir()
	assert_between(KaabaChant.duration_s(), 5.0, KaabaChant.duration_s())
	assert_eq(chant.data.size(), int(KaabaChant.duration_s() * KaabaChant.MIX_RATE) * 2)
	assert_ne(chant.data.count(0), chant.data.size(), "not silent")
