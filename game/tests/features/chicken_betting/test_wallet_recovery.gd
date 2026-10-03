extends GutTest

const SCENE := preload("res://features/chicken_betting/feature.tscn")
var feature: Node3D
var book: ChickenBettingBook
var wallet: AccountWallet


class AccountWallet:
	extends PlayerMoney
	var calls: Array[Array] = []
	var receipts: Dictionary = {}
	var stored := 2000
	var fail_next := false
	var delay_reply := false
	var fail_action := ""

	func _request(account: int, action: String, id: String, extra: Dictionary = {}) -> Dictionary:
		calls.append([account, action, id, extra.get("amount_cents", 0)])
		if not receipts.has(id):
			stored += int(extra["amount_cents"]) * (-1 if action == "charge" else 1)
			receipts[id] = true
		if delay_reply:
			delay_reply = false
			await get_tree().process_frame
		if fail_next or fail_action == action:
			fail_next = false
			fail_action = ""
			return {"error": "Lost reply"}
		return {"balance": stored}


func before_each() -> void:
	wallet = AccountWallet.new()
	add_child_autofree(wallet)
	wallet.set_process(false)
	feature = SCENE.instantiate() as Node3D
	add_child_autofree(feature)
	book = feature.get_node("Room/Book") as ChickenBettingBook
	book.set_process(false)
	book._journal.path = "user://chicken-recovery-test.cfg"
	book._journal.entries = {}
	DirAccess.remove_absolute(book._journal.path)


func after_each() -> void:
	Network.peer_accounts = {}
	DirAccess.remove_absolute(book._journal.path)


func _ticket(credit: int = 100) -> Dictionary:
	return {
		"peer": 2, "account": 77, "id": "a".repeat(64), "stake": 100, "credit": credit, "side": 0
	}


func test_captured_account_credit_after_disconnect_uses_existing_signed_sale_contract() -> void:
	var result := await wallet.adjust_account(2, 77, "b".repeat(64), 100, "Refund")
	assert_eq(result["balance"], 2100)
	assert_eq(wallet.calls, [[77, "sell", "b".repeat(64), 100]])
	assert_false(wallet.balances.has(2), "never credits an unrelated temporary peer")


func test_current_account_debits_and_credits_update_its_existing_wallet() -> void:
	Network.peer_accounts = {2: {"account_id": 77}}
	wallet.balances = {2: 2000}
	await wallet.adjust_account(2, 77, "c".repeat(64), -500, "")
	assert_eq(wallet.balances[2], 1500)
	await wallet.adjust_account(2, 77, "d".repeat(64), 900, "Winner")
	assert_eq(wallet.balances[2], 2400)


func test_unknown_committed_debit_recovers_with_same_id_and_refunds_once() -> void:
	var ticket := _ticket()
	assert_true(book._journal.store(ticket["id"], ticket))
	wallet.fail_next = true
	var result := await wallet.adjust_account(2, 77, ticket["id"], -100, "")
	assert_false(result.has("balance"))
	assert_eq(wallet.stored, 1900, "API committed despite lost response")
	var loaded := ChickenBetJournal.new()
	loaded.path = book._journal.path
	loaded.load_entries()
	assert_eq(loaded.entries[ticket["id"]], ticket)
	book._recover(loaded.entries[ticket["id"]])
	assert_eq(wallet.stored, 2000)
	assert_true(book._journal.entries.is_empty())
	assert_eq(wallet.calls[0][2], wallet.calls[1][2], "replay original debit")
	assert_eq(str(wallet.calls[2][2]).length(), 64, "API requires 64-character IDs")
	# A stale journal surviving deletion must not pay twice.
	book._recover(ticket)
	assert_eq(wallet.stored, 2000)


func test_finished_intent_recovers_fixed_payout_not_refund() -> void:
	var ticket := _ticket(350)
	book._journal.store(ticket["id"], ticket)
	book._recover(ticket)
	assert_eq(wallet.stored, 2250)
	assert_eq(wallet.calls[1][3], 350)


func test_temporary_adjustments_are_idempotent_and_preserve_other_spending() -> void:
	var temporary := PlayerMoney.new()
	wallet.remove_from_group(&"player_money")
	add_child_autofree(temporary)
	temporary.set_process(false)
	temporary.balances = {2: 2000}
	var id := "e".repeat(64)
	await temporary.adjust_account(2, 0, id, -100, "")
	await temporary.adjust_account(2, 0, id, -100, "")
	assert_eq(temporary.balances[2], 1900)
	temporary.balances[2] = 1500
	await temporary.adjust_account(2, 0, "f".repeat(64), 100, "Refund")
	await temporary.adjust_account(2, 0, "f".repeat(64), 100, "Refund")
	assert_eq(temporary.balances[2], 1600)
	var changed := await temporary.adjust_account(2, 0, id, -200, "")
	assert_true(changed.has("rejected"))
	assert_eq(temporary.balances[2], 1600)


func test_disconnect_during_pending_charge_refunds_the_captured_account() -> void:
	Network.peer_accounts = {2: {"account_id": 77}}
	wallet.balances = {2: 2000}
	book.config = ChickenFightConfig.new()
	book.config.odds_samples = 64
	book._prepare()
	var player := preload("res://core/player/player.tscn").instantiate() as Player
	player.set_multiplayer_authority(2)
	player.position = book.global_position + Vector3(0, 0.9144, 1.5)
	player.net_position = player.position
	add_child_autofree(player)
	player.set_physics_process(false)
	await wait_physics_frames(2)
	wallet.delay_reply = true
	assert_eq(
		book.entity._evaluate(2, &"bet", {"side": 0, "stake": 100, "match": 1}),
		NetworkedEntity.Result.ACCEPTED
	)
	assert_eq(wallet.stored, 1900)
	player.free()
	Network.peer_accounts = {}
	book._process(0.3)
	await wait_process_frames(3)
	assert_eq(wallet.stored, 2000)
	assert_eq(wallet.calls[1][0], 77)
	assert_eq(wallet.calls[1][1], "sell")
	assert_true(book._tickets.is_empty())
	assert_true(book._journal.entries.is_empty())


func test_lost_credit_reply_replays_the_same_return_id_without_double_payment() -> void:
	var ticket := _ticket()
	book._journal.store(ticket["id"], ticket)
	wallet.fail_action = "sell"
	book._recover(ticket)
	assert_eq(wallet.stored, 2000, "credit committed but reply was lost")
	assert_false(book._journal.entries.is_empty())
	await wait_seconds(0.6)
	assert_eq(wallet.stored, 2000)
	assert_eq(wallet.calls[1][2], wallet.calls[2][2])
	assert_true(book._journal.entries.is_empty())


func test_journal_write_failure_refuses_to_record_an_unsafe_debit() -> void:
	book._journal.path = "/nonexistent-chicken-dir/book.cfg"
	assert_false(book._journal.store("bad", _ticket()))
	assert_true(book._journal.entries.is_empty())
