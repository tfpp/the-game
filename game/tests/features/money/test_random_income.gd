extends GutTest

const PlayerScene := preload("res://core/player/player.tscn")


class JackpotWallet:
	extends PlayerMoney
	var rolls := 0

	func _roll_income(_units: int) -> int:
		rolls += 1
		return 100_000_000_000


class FakeChat:
	extends Node
	var notices: Array = []

	func send_notice(peer: int, message: String) -> void:
		notices.append([peer, message])


func test_decade_prizes_match_api_and_have_no_billion_ceiling() -> void:
	for row: Array in [
		[0, 0, 30000, 100],
		[8, 0, 30000, 900],
		[4, 0, 25500, 425],
		[4, 0, 27750, 462],
		[0, 9, 30000, 100_000_000_000],
		[0, 10, 30000, 1_000_000_000_000]
	]:
		var left := [int(row[1])]
		var draw := func(bound: int) -> int:
			if bound == 9:
				return int(row[0])
			if left[0] > 0:
				left[0] -= 1
				return 0
			return 1
		assert_eq(IncomeRoll.sample(int(row[2]), draw), int(row[3]))


func test_repeated_promotions_stop_only_at_integer_boundary() -> void:
	var draw := func(_bound: int) -> int: return 0
	assert_eq(IncomeRoll.sample(30000, draw), 1_000_000_000_000_000_000)


func test_minute_jackpot_logs_and_stays_additive_to_purchases() -> void:
	var wallet := JackpotWallet.new()
	add_child_autofree(wallet)
	wallet.set_process(false)
	var chat := FakeChat.new()
	chat.add_to_group(&"chat_box")
	add_child_autofree(chat)
	var player := PlayerScene.instantiate() as Player
	player.set_multiplayer_authority(1)
	add_child_autofree(player)
	player.set_process(false)
	wallet._process(59.0)
	assert_eq(wallet.rolls, 0)
	await wallet.charge(1, "purchase", 100)
	wallet._process(1.0)
	assert_eq(wallet.rolls, 1)
	assert_eq(int(wallet.balances[1]), 100_000_001_900)
	assert_eq(chat.notices, [[1, "+$1,000,000,000.00: Income for time connected"]])
	wallet._process(120.0)
	assert_eq(wallet.rolls, 3)
	assert_eq(int(wallet.balances[1]), 300_000_001_900)
	wallet._reset(Network.Mode.OFFLINE)
	assert_true(wallet._temporary_seconds.is_empty())
	assert_true(wallet._temporary_income_units.is_empty())


func test_api_large_balances_preserve_integer_cents() -> void:
	for cents: int in [100_000_000_000, 100_000_000_000_000_001, IncomeRoll.MAX_CENTS]:
		var parsed: Dictionary = PlayerMoney.parse_response('{"balance": %d}' % cents)
		assert_eq(typeof(parsed["balance"]), TYPE_INT)
		assert_eq(int(parsed["balance"]), cents)
	assert_null(PlayerMoney.parse_response("invalid"))
	assert_eq(
		PlayerMoney.parse_response('{"error":"Wallet unavailable"}'),
		{"error": "Wallet unavailable"}
	)


func test_wallet_storage_boundary_never_wraps_negative() -> void:
	var wallet := JackpotWallet.new()
	add_child_autofree(wallet)
	wallet.set_process(false)
	var player := PlayerScene.instantiate() as Player
	player.set_multiplayer_authority(1)
	add_child_autofree(player)
	player.set_process(false)
	wallet.balances = {1: IncomeRoll.MAX_CENTS - 50}
	wallet._process(60.0)
	assert_eq(int(wallet.balances[1]), IncomeRoll.MAX_CENTS)
	wallet._process(60.0)
	assert_eq(int(wallet.balances[1]), IncomeRoll.MAX_CENTS)
