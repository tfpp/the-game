extends GutTest

const FEATURE := preload("res://features/casino_patrons/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _feature: Node3D
var _trump: CasinoPatron
var _mayor: CasinoPatron
var _wallet: PlayerMoney
var _player: Player


class DelayedWallet:
	extends PlayerMoney
	signal settle
	var calls := 0

	func charge(peer: int, id: String, amount_cents: int) -> Dictionary:
		calls += 1
		await settle
		return await super.charge(peer, id, amount_cents)


func before_each() -> void:
	_feature = FEATURE.instantiate()
	add_child_autofree(_feature)
	_mayor = _feature._spawn_patron({"index": PatronModel.MAMDANI_LOOK})
	_trump = _feature._spawn_patron({"index": PatronModel.TRUMP_LOOK})
	_feature.get_node("Patrons").add_child(_mayor)
	_feature.get_node("Patrons").add_child(_trump)
	_mayor.set_physics_process(false)
	_trump.set_physics_process(false)
	_wallet = PlayerMoney.new()
	add_child_autofree(_wallet)
	_wallet.set_process(false)
	_wallet.balances = {1: 25000, 2: 30000}
	_player = PLAYER.instantiate()
	_player.name = "1"
	_player.set_multiplayer_authority(1)
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.net_position = _trump.global_position + Vector3(1, 0, 0)
	_player.global_position = _player.net_position


func test_model_and_spawn_are_distinct_and_repeatable() -> void:
	assert_eq((_trump.get_node("Body/NameTag") as Label3D).text, "Donald Trump")
	assert_not_null(_trump.find_child("SweptFringe", true, false))
	assert_null(_trump.find_child("Beard", true, false))
	var copy := _feature._spawn_patron({"index": PatronModel.TRUMP_LOOK}) as CasinoPatron
	assert_eq(copy.position, _trump.position)
	assert_eq(copy.name, _trump.name)
	assert_eq(copy.look, PatronModel.TRUMP_LOOK)
	copy.free()


func test_follows_stops_and_turns_with_the_mayor() -> void:
	_player.remove_from_group(&"players")
	_mayor.position.z = -5.0
	for step: int in 180:
		_trump._physics_process(1.0 / 30.0)
	assert_almost_eq(_trump.position.z, -6.5, 0.01)
	assert_almost_eq(_trump.net_position.z, _trump.position.z, 0.001)
	assert_almost_eq((Basis(Vector3.UP, _trump.net_yaw) * Vector3.FORWARD).z, 1.0, 0.01)
	var stopped := _trump.position
	_trump._physics_process(1.0)
	assert_eq(_trump.position, stopped)
	_mayor.position.z = -11.0
	for step: int in 180:
		_trump._physics_process(1.0 / 30.0)
	assert_almost_eq(_trump.position.z, -9.5, 0.01)
	assert_almost_eq((Basis(Vector3.UP, _trump.net_yaw) * Vector3.FORWARD).z, -1.0, 0.01)


func test_use_charges_exactly_100_and_rejects_immediate_duplicate() -> void:
	_trump.use()
	await wait_frames(2)
	assert_eq(int(_wallet.balances[1]), 15000)
	assert_eq(int(_wallet.balances[2]), 30000, "only requester pays")
	_trump.use()
	await wait_frames(2)
	assert_eq(int(_wallet.balances[1]), 15000)
	assert_eq((_trump.get_node("Speech") as Label3D).text, "Paid $100.")


func test_insufficient_funds_leave_wallet_intact() -> void:
	_wallet.balances[1] = 9999
	_trump.use()
	await wait_frames(2)
	assert_eq(int(_wallet.balances[1]), 9999)
	assert_string_contains((_trump.get_node("Speech") as Label3D).text, "afford")


func test_rejects_unknown_peer_payload_range_and_downed_state() -> void:
	var talk := _trump.get_node("Talk") as NetworkedInteraction
	assert_eq(talk._evaluate(77, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_eq(talk._evaluate(1, &"use", {"peer": 2}), NetworkedEntity.Result.DENIED)
	_player.net_position += Vector3(10, 0, 0)
	assert_eq(talk._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	_player.net_position = _trump.position
	_trump.net_ragdoll = true
	assert_eq(talk._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	_trump.net_ragdoll = false
	_trump.take_hit(1)
	assert_eq(talk._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_eq(int(_wallet.balances[1]), 25000)
	_trump._physics_process(CasinoPatron.RESPAWN_DELAY_S)
	assert_true(_trump.net_alive)
	assert_true(_trump.can_use(_player))


func test_two_players_pay_their_own_wallet_and_missing_mayor_is_safe() -> void:
	var second := PLAYER.instantiate() as Player
	second.name = "2"
	second.set_multiplayer_authority(2)
	add_child_autofree(second)
	second.set_physics_process(false)
	second.net_position = _trump.position
	var talk := _trump.get_node("Talk") as NetworkedInteraction
	assert_eq(talk._evaluate(1, &"use", {}), NetworkedEntity.Result.ACCEPTED)
	await wait_seconds(0.55)
	assert_eq(talk._evaluate(2, &"use", {}), NetworkedEntity.Result.ACCEPTED)
	assert_eq(int(_wallet.balances[1]), 15000)
	assert_eq(int(_wallet.balances[2]), 20000)
	_mayor.free()
	var at := _trump.position
	_trump._physics_process(1.0)
	assert_eq(_trump.position, at)


func test_pending_charge_blocks_duplicate_and_disconnect_drops_reply() -> void:
	_wallet.free()
	var delayed := DelayedWallet.new()
	add_child_autofree(delayed)
	delayed.set_process(false)
	delayed.balances = {1: 25000}
	assert_true(_trump._apply_talk(_player))
	assert_false(_trump._apply_talk(_player), "one outstanding charge per player")
	assert_eq(delayed.calls, 1)
	_player.free()
	delayed.settle.emit()
	await wait_frames(2)
	assert_eq(int(delayed.balances[1]), 15000, "accepted charge completes once")
	assert_false((_trump.get_node("Speech") as Label3D).visible)


func test_talking_plays_accordion_emote_for_everyone() -> void:
	var shoulder := _trump.find_child("ShoulderR", true, false) as Node3D
	_trump._process(0.016)
	var rest := shoulder.rotation
	_trump.use()
	await wait_frames(2)
	assert_gt(_trump._accordion_left, 0.0, "accepted talk broadcasts the emote")
	_trump._process(1.0)
	assert_gt(shoulder.rotation.x, rest.x + 0.5, "arms raised to squeeze the bellows")
	_trump._process(5.0)
	assert_eq(_trump._accordion_left, 0.0)
	assert_almost_eq(shoulder.rotation.x, rest.x, 0.01, "arms return to rest")


func test_accordion_weight_eases_in_and_out() -> void:
	var script: GDScript = _trump.get_script()
	assert_eq(script.accordion_weight(script.ACCORDION_S), 0.0)
	assert_eq(script.accordion_weight(script.ACCORDION_S / 2.0), 1.0)
	assert_eq(script.accordion_weight(0.0), 0.0)
