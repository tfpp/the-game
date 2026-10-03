extends GutTest

const SCENE := preload("res://features/chicken_betting/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const ACCEPTED := NetworkedEntity.Result.ACCEPTED
const DENIED := NetworkedEntity.Result.DENIED

var feature: Node3D
var book: ChickenBettingBook
var wallet: PlayerMoney
var players: Dictionary


func before_each() -> void:
	wallet = PlayerMoney.new()
	add_child_autofree(wallet)
	wallet.set_process(false)
	wallet.balances = {2: 20000, 3: 20000}
	feature = SCENE.instantiate() as Node3D
	add_child_autofree(feature)
	book = feature.get_node("Room/Book") as ChickenBettingBook
	book.set_process(false)
	book.config = ChickenFightConfig.new()
	book.config.odds_samples = 64
	book._journal.path = "user://chicken-test.cfg"
	book._prepare()
	players = {}
	for peer: int in [2, 3]:
		var player := PLAYER.instantiate() as Player
		player.set_multiplayer_authority(peer)
		player.display_name = "Bettor%d" % peer
		player.position = book.global_position + Vector3(0, 0.9144, 1.5)
		player.net_position = player.position
		add_child_autofree(player)
		player.set_physics_process(false)
		players[peer] = player
	await wait_physics_frames(2)


func bet(peer: int, side: int = 0, stake: int = 100) -> NetworkedEntity.Result:
	return book.entity._evaluate(
		peer, &"bet", {"side": side, "stake": stake, "match": int(book.state["match"])}
	)


func test_upfront_debit_duplicate_limits_balance_range_and_schema() -> void:
	assert_eq(bet(99), DENIED)
	assert_eq(bet(2, 2), DENIED)
	assert_eq(bet(2, 0, 99), DENIED)
	assert_eq(bet(2, 0, 10001), DENIED)
	wallet.balances[2] = 99
	assert_eq(bet(2), DENIED)
	wallet.balances[2] = 20000
	for payload: Dictionary in [
		{},
		{"side": "0", "stake": 100, "match": 1},
		{"side": 0, "stake": 100, "match": -1},
		{"side": 0, "stake": 100, "match": 1, "peer": 3}
	]:
		assert_eq(book.entity._evaluate(2, &"bet", payload), DENIED)
	(players[2] as Player).net_position += Vector3(0, 0, 10)
	assert_eq(bet(2), DENIED)
	(players[2] as Player).net_position = (players[2] as Player).position
	(players[2] as Player).net_yaw = PI
	assert_eq(bet(2), DENIED, "must face the book")
	(players[2] as Player).net_yaw = 0
	assert_eq(bet(2, 0, 500), ACCEPTED)
	assert_eq(wallet.balances[2], 19500)
	assert_eq(bet(2, 1), DENIED)
	assert_eq(wallet.balances[2], 19500)


func test_one_shared_window_and_exact_winning_return_and_loss() -> void:
	var match_id := int(book.state["match"])
	assert_eq(bet(2, 0, 500), ACCEPTED)
	book._process(3)
	assert_eq(bet(3, 1, 1000), ACCEPTED)
	assert_eq(int(book.state["match"]), match_id)
	assert_eq(book._elapsed, 3.0)
	book._process(7)
	assert_eq(book.state["phase"], "fighting")
	assert_eq(bet(2), DENIED)
	var next := book.state.duplicate(true)
	next["winner"] = 0
	next["health"] = [30, 0]
	book.state = next
	book._finish()
	var payout := ChickenFightSimulation.payout(500, book.state["odds"][0])
	assert_eq(wallet.balances[2], 19500 + payout)
	assert_eq(wallet.balances[3], 19000)
	assert_true(str(book.state["bets"][2]["result"]).contains("Balance"))
	assert_true(str(book.state["bets"][3]["result"]).begins_with("Lost"))
	assert_true(book._tickets.is_empty())
	book._process(book.config.result_seconds)
	assert_eq(book.state["phase"], "idle")
	assert_eq(book.state["birds"], [], "chickens despawn after match")


func test_cancel_and_room_exit_refund_once_without_restarting_other_ticket() -> void:
	bet(2, 0, 500)
	bet(3, 1, 1000)
	book._process(2)
	assert_eq(book.entity._evaluate(99, &"cancel", {}), DENIED)
	assert_eq(book.entity._evaluate(2, &"cancel", {"peer": 3}), DENIED)
	assert_eq(book.entity._evaluate(2, &"cancel", {}), ACCEPTED)
	assert_eq(wallet.balances[2], 20000)
	assert_eq(book.entity._evaluate(2, &"cancel", {}), DENIED)
	assert_eq(book._elapsed, 2.0)
	book._process(8)
	(players[3] as Player).net_position = Vector3.ZERO
	book._process(0.3)
	assert_eq(wallet.balances[3], 20000)
	assert_true(book._tickets.is_empty())
	assert_true(str(book.state["bets"][3]["result"]).begins_with("Refunded"))


func test_round_health_attack_and_knockout_are_the_same_snapshot() -> void:
	bet(2)
	book._process(10)
	var previous: Array = book.state["health"].duplicate()
	var rounds := 0
	while book.state["phase"] == "fighting" and rounds < 100:
		book._process(book.config.round_seconds)
		var attack: Dictionary = book.state["attack"]
		var attacker := int(attack["attacker"])
		assert_eq(book.state["health"][attacker], previous[attacker])
		assert_eq(book.state["health"], attack["health"])
		previous = book.state["health"].duplicate()
		rounds += 1
	assert_eq(book.state["phase"], "result")
	assert_gte(int(book.state["winner"]), 0)
	assert_eq(int(book.state["health"][1 - int(book.state["winner"])]), 0)


func test_late_join_snapshot_preserves_stats_odds_round_health_and_tickets() -> void:
	bet(2)
	book._process(10)
	book._process(0.8)
	var sync := book.entity.get_node("Sync") as MultiplayerSynchronizer
	var path := NodePath(".:state")
	assert_true(sync.replication_config.has_property(path))
	assert_true(sync.replication_config.property_get_spawn(path))
	var late := SCENE.instantiate() as Node3D
	add_child_autofree(late)
	var late_book := late.get_node("Room/Book") as ChickenBettingBook
	late_book.set_process(false)
	late_book.state = book.state.duplicate(true)
	assert_eq(late_book.state, book.state)
	assert_eq(late_book.state["bets"][2]["stake"], 100)
	assert_eq(late_book.state["round"], 1)


func test_wallet_delay_holds_start_but_never_reopens_the_betting_deadline() -> void:
	bet(2)
	book._tickets[2]["paid"] = false
	book._process(10)
	assert_eq(book.state["phase"], "betting", "wait for wallet without simulating")
	assert_eq(book.state["seconds"], 0)
	assert_eq(bet(3), DENIED, "eligible late bettor cannot extend the window")
	book._tickets[2]["paid"] = true
	book._process(0.1)
	assert_eq(book.state["phase"], "fighting")


func test_temporary_disconnect_does_not_credit_a_replacement_player() -> void:
	bet(2)
	(players[2] as Player).free()
	var replacement := PLAYER.instantiate() as Player
	replacement.set_multiplayer_authority(2)
	add_child_autofree(replacement)
	replacement.set_physics_process(false)
	wallet.balances[2] = 50000
	book._process(0.3)
	assert_eq(wallet.balances[2], 50000)
	assert_false(book._tickets.has(2))
