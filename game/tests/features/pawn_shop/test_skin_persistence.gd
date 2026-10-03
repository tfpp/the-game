extends GutTest
## Fake account transport exercises the real PlayerMoney.cosmetics interface.
## SQLite/HMAC/restart/concurrency are covered independently by the API tests.

const SCENE := preload("res://features/pawn_shop/skin_crates.tscn")
var _skins: PrawnSkins
var _wallet: AccountWallet
var _player: Player
var _accounts := {}


class AccountWallet:
	extends PlayerMoney
	var document := PrawnSkinCatalog.empty_document()
	var revision := 0
	var balance := 2000
	var operations: Dictionary = {}
	var lose_response := false
	var fail_load := false

	func _request(_account: int, action: String, id: String, extra: Dictionary = {}) -> Dictionary:
		if action == "cosmetics_load":
			if fail_load:
				return {"error": "Unavailable"}
			return {"document": document.duplicate(true), "revision": revision, "balance": balance}
		if not operations.has(id):
			if extra["revision"] != revision:
				return {"error": "Collection changed", "rejected": true}
			balance += int(extra["delta"])
			document = extra["document"].duplicate(true)
			revision += 1
			operations[id] = extra.duplicate(true)
		if lose_response:
			return {"error": "Response lost"}
		return {"document": document.duplicate(true), "revision": revision, "balance": balance}


func before_each() -> void:
	_accounts = Network.peer_accounts.duplicate(true)
	Network.peer_accounts[1] = {"account_id": 37}
	_wallet = AccountWallet.new()
	add_child_autofree(_wallet)
	_wallet.set_process(false)
	_player = preload("res://core/player/player.tscn").instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.net_position = Vector3(0, .95, 1.2)
	_attach()


func after_each() -> void:
	Network.peer_accounts = _accounts


func _attach() -> void:
	_skins = SCENE.instantiate() as PrawnSkins
	add_child_autofree(_skins)
	_skins.set_process(false)
	_skins.odds = [10000, 0, 0, 0, 0]
	_skins._peers[1] = "account:37"
	_skins._players[1] = _player.get_instance_id()
	_skins._load(1, "account:37")


func test_reconnect_load_restores_equipment_skins_and_unopened_crates() -> void:
	_request("buy", "harbour")
	_request("open", "harbour")
	_request("equip", "brine")
	_request("buy", "night")
	assert_eq(_wallet.balance, 500)
	assert_eq(_wallet.balances[1], 500, "Existing wallet owns replicated balance")
	_skins.free()
	_attach()
	var saved: Dictionary = _skins._collections["account:37"]["document"]
	assert_eq(saved["skins"], {"brine": 1})
	assert_eq(saved["crates"], {"night": 1})
	assert_eq(_skins.net_equipped[1], {"pistol": "brine"})
	assert_eq(_request("unequip", "pistol"), NetworkedEntity.Result.ACCEPTED)
	assert_true(_wallet.document["equipped"].is_empty())


func test_lost_open_response_and_reconnect_retry_cannot_roll_or_deliver_twice() -> void:
	_request("buy", "harbour")
	_wallet.lose_response = true
	_request("open", "harbour")
	assert_eq(_wallet.document["skins"], {"brine": 1}, "Already committed in storage")
	assert_eq(_wallet.revision, 2)
	assert_true(_skins._pending.has("account:37"))
	var plan: Dictionary = _skins._pending["account:37"].duplicate(true)
	# A reconnect loads current state but keeps the unresolved ID for safe retry.
	_skins._load(1, "account:37")
	_skins.odds = [0, 0, 0, 0, 10000]
	_wallet.lose_response = false
	assert_eq(_request("retry", ""), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_wallet.document["skins"], {"brine": 1})
	assert_eq(_wallet.revision, 2)
	assert_eq(_wallet.balance, 1500)
	assert_eq(_wallet.operations[plan["id"]]["document"], plan["document"])


func test_api_load_outage_never_overwrites_an_existing_collection() -> void:
	_request("buy", "night")
	_wallet.fail_load = true
	_skins.free()
	_attach()
	assert_false(_skins._collections.has("account:37"))
	assert_eq(_request("buy", "harbour"), NetworkedEntity.Result.DENIED)
	assert_eq(_wallet.document["crates"], {"night": 1})
	_wallet.fail_load = false
	assert_eq(_request("refresh", ""), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_skins._collections["account:37"]["document"]["crates"], {"night": 1})


func test_server_session_reset_recovers_a_committed_lost_reply_from_storage() -> void:
	_wallet.lose_response = true
	_request("buy", "harbour")
	assert_eq(_wallet.balance, 1500)
	_skins.entity.session_reset.emit(Network.Mode.OFFLINE)
	_wallet.lose_response = false
	_skins._peers[1] = "account:37"
	_skins._players[1] = _player.get_instance_id()
	_skins._load(1, "account:37")
	assert_eq(_skins._collections["account:37"]["document"]["crates"], {"harbour": 1})
	assert_eq(_wallet.balance, 1500)
	assert_true(_skins._pending.is_empty())


func test_initial_load_waits_for_existing_wallet_operation() -> void:
	_skins.free()
	_wallet._busy[1] = true
	_skins = SCENE.instantiate() as PrawnSkins
	add_child_autofree(_skins)
	_skins.set_process(false)
	_skins._peers[1] = "account:37"
	_skins._players[1] = _player.get_instance_id()
	_skins._load(1, "account:37")
	assert_true(_skins._busy.has("account:37"))
	assert_false(_skins._collections.has("account:37"))
	_wallet._busy.erase(1)
	await wait_process_frames(2)
	assert_true(_skins._collections.has("account:37"))
	assert_false(_skins._busy.has("account:37"))


func _request(action: String, id: String) -> NetworkedEntity.Result:
	var record: Dictionary = _skins._collections.get("account:37", {})
	return (
		_skins
		. entity
		. _evaluate(
			1,
			&"operate",
			{
				"action": action,
				"id": id,
				"revision": int(record.get("revision", -1)),
			}
		)
	)
