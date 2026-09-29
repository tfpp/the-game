extends GutTest
## Praying at the Kaaba: server validation, stacking blessings and slot rerolls.

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


func test_blessings_raise_the_slot_win_chance() -> void:
	assert_almost_eq(SlotSpinCycle.win_chance(0), 0.04, 0.0001)
	assert_gt(SlotSpinCycle.win_chance(5), SlotSpinCycle.win_chance(1))
	var cycle := SlotSpinCycle.new()
	var plain := 0
	var blessed := 0
	for spin: int in 2000:
		plain += int(SlotSpinCycle.is_win(cycle.next_result()))
		blessed += int(SlotSpinCycle.is_win(cycle.blessed_result(5)))
	assert_gt(blessed, plain * 2, "five blessings win far more often")


func test_temporary_wallet_uses_blessings_as_rerolls() -> void:
	var wallet := PlayerMoney.new()
	add_child_autofree(wallet)
	wallet.set_process(false)
	var wins := 0
	for spin: int in 200:
		var result: Dictionary = await wallet.spin(1, "id%d" % spin, 1, 30)
		wins += int(int(result.get("payout", 0)) > 0)
	assert_gt(wins, 100, "30 rerolls win most spins (~71%)")


func test_chant_is_a_few_seconds_of_audio() -> void:
	var chant := KaabaChant.takbir()
	assert_between(KaabaChant.duration_s(), 5.0, KaabaChant.duration_s())
	assert_eq(chant.data.size(), int(KaabaChant.duration_s() * KaabaChant.MIX_RATE) * 2)
	assert_ne(chant.data.count(0), chant.data.size(), "not silent")


func test_remote_peer_validation_and_completion_effect() -> void:
	var player := _player(Vector3(3.5, 0.9, 0))
	player.set_multiplayer_authority(42)
	assert_false(_prayer.entity._validate_use(7, {}), "cannot borrow another peer")
	assert_false(_prayer.entity._validate_use(42, {"peer": 7}), "no identity payload")
	assert_true(_prayer.entity._validate_use(42, {}))
	watch_signals(_prayer.entity)
	_prayer.entity._apply_use(42, {})
	_prayer._advance(KaabaPrayer.PRAYER_S)
	assert_eq(_prayer.blessings_for(42), 1)
	assert_eq(_prayer.blessings_for(1), 0)
	assert_signal_emitted(_prayer.entity, "event_received")
	var args: Array = get_signal_parameters(_prayer.entity, "event_received")
	assert_eq(args[0], &"completed")
	var eye := player.movement.eye_height_m() - player.movement.hull_height_m() * 0.5
	assert_eq(args[1]["position"], player.net_position + Vector3(0, eye, -0.9))


func test_blessed_spin_event_and_effect_cleanup() -> void:
	watch_signals(_prayer.entity)
	_prayer.show_blessed_spin(Vector3(1, 2, 3))
	assert_signal_emitted_with_parameters(
		_prayer.entity, "event_received", [&"gamble", {"position": Vector3(1, 2, 3)}]
	)
	var effect := BlessingEffect.new()
	add_child_autofree(effect)
	effect.build(true)
	assert_eq(effect.get_child_count(), 1, "one lightweight crescent-and-star mesh")
	effect._process(BlessingEffect.LIFETIME)
	assert_true(effect.is_queued_for_deletion())


func test_replication_includes_blessings_and_prayer_for_late_joiners() -> void:
	assert_has(_prayer.entity.replicated_properties, NodePath(".:blessings"))
	assert_has(_prayer.entity.replicated_properties, NodePath(".:praying"))
