extends GutTest

const SKINS := preload("res://features/pawn_shop/skin_crates.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const HAND := preload("res://features/holdables/hand.tscn")

var _skins: PrawnSkins
var _player: Player
var _wallet: PlayerMoney


class SlowWallet:
	extends PlayerMoney
	signal complete
	var calls: Array[Dictionary] = []
	var unavailable := false

	func cosmetics(
		_peer: int, id: String, revision: int, document: Dictionary, delta: int, load: bool = false
	) -> Dictionary:
		if load:
			return {"revision": 0, "document": PrawnSkinCatalog.empty_document(), "balance": 2000}
		calls.append({"id": id, "document": document.duplicate(true), "delta": delta})
		await complete
		if unavailable:
			return {"error": "Storage unavailable"}
		return {"revision": revision + 1, "document": document, "balance": 2000 + delta}


func before_each() -> void:
	_wallet = PlayerMoney.new()
	add_child_autofree(_wallet)
	_wallet.set_process(false)
	_wallet.balances = {1: 2000}
	_skins = SKINS.instantiate() as PrawnSkins
	add_child_autofree(_skins)
	_skins.set_process(false)
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.net_position = Vector3(0, .95, 1.2)
	_skins._players[1] = _player.get_instance_id()
	_skins._peers[1] = "temporary:1"
	_skins._load(1, "temporary:1")


func test_offline_buy_open_equip_exchange_unequip_share_the_wallet() -> void:
	_skins.odds = [10000, 0, 0, 0, 0]
	for index: int in 2:
		assert_eq(_request("buy", "harbour"), NetworkedEntity.Result.ACCEPTED)
		assert_eq(_request("open", "harbour"), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_wallet.balances[1], 1000)
	assert_eq(_document()["skins"]["brine"], 2)
	assert_eq(_request("equip", "brine"), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_skins.net_equipped, {1: {"pistol": "brine"}})
	assert_eq(_request("exchange", "brine"), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_wallet.balances[1], 1050)
	assert_eq(_document()["skins"]["brine"], 1)
	assert_eq(_request("exchange", "brine"), NetworkedEntity.Result.DENIED)
	assert_eq(_skins.net_equipped[1], {"pistol": "brine"})
	assert_eq(_request("unequip", "pistol"), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_skins.net_equipped[1], {})


func test_forged_unknown_far_stale_and_empty_requests_are_denied() -> void:
	assert_eq(_request("buy", "harbour", 99), NetworkedEntity.Result.DENIED)
	assert_eq(
		_skins.entity._evaluate(
			1, &"operate", {"action": "buy", "id": "harbour", "revision": 0, "price": 0}
		),
		NetworkedEntity.Result.DENIED
	)
	for pair: Array in [
		["buy", "bad"],
		["equip", "brine"],
		["open", "harbour"],
		["exchange", "brine"],
		["unequip", "generated"]
	]:
		assert_eq(_request(pair[0], pair[1]), NetworkedEntity.Result.DENIED)
	_player.net_position = Vector3(0, 1, 50)
	assert_eq(_request("buy", "harbour"), NetworkedEntity.Result.DENIED)
	_player.net_position = Vector3(0, .95, 1.2)
	assert_eq(_request("buy", "harbour"), NetworkedEntity.Result.ACCEPTED)
	assert_eq(
		_skins.entity._evaluate(1, &"operate", {"action": "buy", "id": "harbour", "revision": 0}),
		NetworkedEntity.Result.DENIED,
		"Replay cannot buy another crate"
	)
	assert_eq(_wallet.balances[1], 1500)


func test_insufficient_money_preserves_collection_and_reports_reason() -> void:
	_wallet.balances = {1: 499}
	watch_signals(_skins.entity)
	_request("buy", "harbour")
	assert_eq(_wallet.balances[1], 499)
	assert_eq(_document(), PrawnSkinCatalog.empty_document())
	assert_true(_skins._pending.is_empty())
	var signals: Variant = get_signal_parameters(_skins.entity, "event_received", 2)
	assert_string_contains(str(signals), "afford")


func test_bad_odds_block_spending_and_rewards() -> void:
	_skins.odds = [6000, 2500, 1000, 400, 99]
	assert_eq(_request("buy", "harbour"), NetworkedEntity.Result.DENIED)
	assert_eq(_wallet.balances[1], 2000)


func test_lost_response_locks_and_retries_the_exact_operation_without_rerolling() -> void:
	var slow := _slow_wallet()
	assert_eq(_request("buy", "harbour"), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_request("buy", "harbour"), NetworkedEntity.Result.DENIED)
	assert_eq(slow.calls.size(), 1)
	slow.unavailable = true
	slow.complete.emit()
	assert_eq(_request("buy", "night"), NetworkedEntity.Result.DENIED)
	assert_eq(_request("refresh", ""), NetworkedEntity.Result.DENIED)
	assert_eq(_request("retry", ""), NetworkedEntity.Result.ACCEPTED)
	assert_eq(slow.calls[0], slow.calls[1], "Same ID, charge and saved document")
	slow.unavailable = false
	slow.complete.emit()
	assert_eq(_document()["crates"]["harbour"], 1)
	assert_true(_skins._pending.is_empty())


func test_pending_open_does_not_remove_crate_until_reward_is_saved() -> void:
	_request("buy", "harbour")
	var slow := _slow_wallet()
	_request("open", "harbour")
	assert_eq(_document()["crates"]["harbour"], 1)
	assert_true(_document()["skins"].is_empty())
	assert_eq(_request("open", "harbour"), NetworkedEntity.Result.DENIED)
	var result: Dictionary = slow.calls[0]["document"]
	slow.complete.emit()
	assert_eq(_document(), PrawnSkinCatalog.clean(result))
	assert_eq(_document()["skins"].values(), [1])


func test_reset_ignores_stale_callbacks_and_clears_temporary_equipment() -> void:
	var slow := _slow_wallet()
	_request("buy", "harbour")
	_skins.entity.session_reset.emit(Network.Mode.OFFLINE)
	slow.complete.emit()
	assert_true(_skins._collections.is_empty())
	assert_true(_skins.net_equipped.is_empty())
	assert_true(_skins._pending.is_empty())


func test_respawn_and_new_hand_receive_same_equipped_cosmetic() -> void:
	_skins.odds = [10000, 0, 0, 0, 0]
	_request("buy", "harbour")
	_request("open", "harbour")
	_request("equip", "brine")
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	hand.net_item_id = "pistol"
	await wait_process_frames(2)
	_skins._apply_appearance()
	assert_eq(hand.held_view().get_meta("prawn_skin"), "brine")
	# A late equipment snapshot is the only required gameplay appearance state.
	assert_true(NodePath(".:net_equipped") in _skins.entity.replicated_properties)
	_request("unequip", "pistol")
	_skins._apply_appearance()
	assert_eq(hand.held_view().get_meta("prawn_skin"), "")
	assert_eq(hand.net_item_id, "pistol")


func test_temporary_wallet_receipt_cannot_be_repurposed_or_undo_other_income() -> void:
	var document := PrawnSkinCatalog.empty_document()
	document["crates"]["harbour"] = 1
	var id := "a".repeat(64)
	var result: Dictionary = await _wallet.cosmetics(1, id, 0, document, -500)
	assert_eq(result["balance"], 1500)
	_wallet.balances[1] += 500
	result = await _wallet.cosmetics(1, id, 0, document, -500)
	assert_eq(result["balance"], 2000, "Retry preserves income since the original purchase")
	assert_eq(_wallet.balances[1], 2000)
	for change: Dictionary in [
		{"peer": 77, "revision": 0, "document": document, "delta": -500},
		{"peer": 1, "revision": 1, "document": document, "delta": -500},
		{"peer": 1, "revision": 0, "document": document, "delta": -501},
		{"peer": 1, "revision": 0, "document": {}, "delta": -500},
	]:
		result = await _wallet.cosmetics(
			change["peer"], id, change["revision"], change["document"], change["delta"]
		)
		assert_true(result.get("rejected", false))
	assert_eq(_wallet.balances[1], 2000)
	# The original public wallet callers still spend/pay the very same balance.
	await _wallet.charge(1, "b".repeat(64), 100)
	assert_eq(_wallet.balances[1], 1900)
	await _wallet.sell_loot(1, "c".repeat(64), 100, "Ordinary loot")
	assert_eq(_wallet.balances[1], 2000)


func _request(action: String, id: String, peer: int = 1) -> NetworkedEntity.Result:
	var key := _skins._key(peer)
	var record: Dictionary = _skins._collections.get(key, {})
	return (
		_skins
		. entity
		. _evaluate(
			peer,
			&"operate",
			{
				"action": action,
				"id": id,
				"revision": int(record.get("revision", -1)),
			}
		)
	)


func _document() -> Dictionary:
	return _skins._collections["temporary:1"]["document"]


func _slow_wallet() -> SlowWallet:
	_wallet.free()
	var slow := SlowWallet.new()
	add_child_autofree(slow)
	slow.set_process(false)
	_wallet = slow
	return slow
