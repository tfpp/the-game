extends GutTest
const TABLE := preload("res://features/table_games/table.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var wallet: PlayerMoney
var table: CrownGameTable
var players: Array[Player] = []


func before_each() -> void:
	wallet = PlayerMoney.new()
	add_child_autofree(wallet)
	wallet.set_process(false)
	wallet.balances = {1: 2000, 2: 2000, 3: 2000}
	table = TABLE.instantiate() as CrownGameTable
	add_child_autofree(table)
	table.set_process(false)
	for peer: int in [1, 2, 3]:
		var player := PLAYER.instantiate() as Player
		player.set_multiplayer_authority(peer)
		player.position = Vector3((peer - 2) * .7, .9144, 2)
		player.net_position = player.position
		player.display_name = "Player%d" % peer
		add_child_autofree(player)
		player.set_physics_process(false)
		players.append(player)


func after_each() -> void:
	players.clear()


func test_wallet_reserves_blocks_other_spending_and_settles_once() -> void:
	assert_true(wallet.reserve_table(1, "round", 500))
	assert_false(wallet.reserve_table(1, "other", 100))
	var refused := await wallet.charge(1, "charge", 100)
	assert_true(refused.has("error"))
	assert_eq(wallet.balances[1], 2000)
	var result := await wallet.settle_table(1, 0, "round", 100, 250)
	assert_eq(result["balance"], 2150)
	result = await wallet.settle_table(1, 0, "round", 100, 250)
	assert_true(result.has("rejected"))
	assert_eq(wallet.balances[1], 2150)


func test_blackjack_validation_timeout_and_late_snapshot() -> void:
	assert_true(table._join(players[0]))
	assert_true(table._join(players[1]))
	table._start()
	assert_eq(table.state["players"].size(), 2)
	assert_false(table._may_move(3, {"move": "hit", "hold": 0}))
	assert_false(table._may_move(1, {"move": "hit", "hold": 0, "peer": 2}))
	assert_false(table._may_move(1, {"move": "draw", "hold": 0}))
	for i: int in 3:
		if table.state["phase"] == "playing":
			table._process(30)
	assert_eq(table.state["phase"], "result")
	assert_gte(table.state["dealer"].size(), 2)
	var late := TABLE.instantiate() as CrownGameTable
	late.state = table.state.duplicate(true)
	add_child_autofree(late)
	late.set_process(false)
	assert_eq(late.state, table.state)
	assert_true(late.private_hand.is_empty())


func test_holdem_private_cards_turns_and_pot_conservation() -> void:
	table.game = "poker"
	for player: Player in players:
		assert_true(table._join(player))
	table._start()
	for entry: Dictionary in table.state["players"].values():
		assert_false(entry.has("cards"), "Hole cards are never in the initial public snapshot")
	assert_false(table._may_move(2, {"move": "check", "hold": 0}))
	var steps := 0
	while table.state["phase"] == "playing" and steps < 30:
		var peer := int(table.state["turn"])
		assert_true(table._may_move(peer, {"move": "check", "hold": 0}))
		table._move(peer, {"move": "check", "hold": 0})
		steps += 1
	assert_eq(table.state["phase"], "result")
	assert_eq(table.state["board"].size(), 5)
	assert_eq(int(wallet.balances[1]) + int(wallet.balances[2]) + int(wallet.balances[3]), 6000)


func test_holdem_raise_cap_and_fold_winner() -> void:
	table.game = "poker"
	assert_true(table._join(players[0]))
	assert_true(table._join(players[1]))
	table._start()
	table._move(1, {"move": "bet", "hold": 0})
	assert_true(table.moves(2).has("raise"))
	table._move(2, {"move": "raise", "hold": 0})
	assert_false(table.moves(1).has("raise"))
	table._move(1, {"move": "fold", "hold": 0})
	assert_eq(table.state["phase"], "result")
	assert_eq(wallet.balances[1], 1850)
	assert_eq(wallet.balances[2], 2150)


func test_draw_keeps_held_cards_and_refuses_invalid_masks() -> void:
	table.game = "video_poker"
	assert_true(table._join(players[0]))
	assert_false(table._join(players[1]), "Cabinet has a single operator")
	table._start()
	var hand: Array = table._hands[1].duplicate()
	assert_false(table._may_move(1, {"move": "draw", "hold": 32}))
	assert_false(table._may_move(1, {"move": "draw", "hold": -1}))
	table._move(1, {"move": "draw", "hold": 5})
	assert_eq(table._hands[1][0], hand[0])
	assert_eq(table._hands[1][2], hand[2])
	assert_ne(table._hands[1][1], hand[1])
	assert_eq(table.state["phase"], "result")


func test_cancel_releases_money_and_range_facing_are_validated() -> void:
	await get_tree().physics_frame
	assert_true(table.can_use(players[0]))
	players[0].net_yaw = PI
	assert_false(table.can_use(players[0]))
	players[0].net_yaw = 0
	assert_true(table._join(players[0]))
	assert_true(table._leave(1, {}))
	assert_true(wallet.reserve_table(1, "other", 100))
	wallet.release_table(1, "other")
	players[0].net_position.z = 20
	assert_false(table.can_use(players[0]))


func test_reservation_bounds_account_binding_and_disconnect_retention() -> void:
	assert_true(wallet.reserve_table(2, "round", 500))
	var result := await wallet.settle_table(2, 99, "round", 100, 0)
	assert_true(result.has("rejected"))
	result = await wallet.settle_table(2, 0, "round", 600, 0)
	assert_true(result.has("rejected"))
	wallet._process(6)
	assert_true(wallet.balances.has(2), "A disconnected reserved wallet is kept until settlement")
	result = await wallet.settle_table(2, 0, "round", 100, 0)
	assert_eq(result["balance"], 1900)
	wallet._process(6)
	assert_false(wallet.balances.has(2), "The disconnected settled wallet can be removed")


func test_ui_can_open_close_and_hold_controls_exist() -> void:
	table.game = "video_poker"
	assert_true(table._join(players[0]))
	table._start()
	table.open_screen()
	assert_true(is_instance_valid(table._screen))
	assert_eq(table._screen.get("_hold_buttons").size(), 5)
	table._screen.call("close")
	await get_tree().process_frame
	assert_false(is_instance_valid(table._screen))


func test_void_losing_wager_is_removed_from_poker_pot() -> void:
	var next := {"players": {1: {"payout": 151}, 2: {"payout": 150}}, "winners": [1, 2]}
	table._remove_void_stake(next, 100)
	assert_eq(next["players"][1]["payout"], 101)
	assert_eq(next["players"][2]["payout"], 100)


class RetryWallet:
	extends PlayerMoney
	var requests: Array[Dictionary] = []

	func _request(account: int, action: String, id: String, extra: Dictionary = {}) -> Dictionary:
		requests.append(
			{"account": account, "action": action, "id": id, "extra": extra.duplicate()}
		)
		return {"error": "Reply lost"} if requests.size() == 1 else {"balance": 2150}


func test_account_retry_retains_reservation_and_immutable_operation() -> void:
	var retry := RetryWallet.new()
	add_child_autofree(retry)
	retry.set_process(false)
	retry.balances = {1: 2000}
	var previous: Variant = Network.peer_accounts.get(1)
	Network.peer_accounts[1] = {"account_id": 7}
	assert_true(retry.reserve_table(1, "immutable-round", 500))
	var result := await retry.settle_table(1, 7, "immutable-round", 100, 250)
	assert_true(result.has("error"))
	assert_false(retry.reserve_table(1, "other", 100))
	assert_eq(retry.balances[1], 2000)
	result = await retry.settle_table(1, 7, "immutable-round", 100, 250)
	assert_eq(result["balance"], 2150)
	assert_eq(retry.requests.size(), 2)
	assert_eq(retry.requests[0], retry.requests[1])
	assert_eq(retry.requests[0]["action"], "roulette")
	if previous == null:
		Network.peer_accounts.erase(1)
	else:
		Network.peer_accounts[1] = previous


func test_upstream_account_debits_respect_reservations_but_refunds_can_arrive() -> void:
	assert_true(wallet.reserve_table(1, "table", 500))
	var debit := await wallet.adjust_account(1, 0, "a".repeat(64), -100, "Another wager")
	assert_true(debit.has("error"))
	assert_eq(wallet.balances[1], 2000)
	var refund := await wallet.adjust_account(1, 0, "b".repeat(64), 100, "Refund")
	assert_eq(refund["balance"], 2100)
	assert_true(wallet._table_holds.has(1))
	var settled := await wallet.settle_table(1, 0, "table", 500, 0)
	assert_eq(settled["balance"], 1600)
