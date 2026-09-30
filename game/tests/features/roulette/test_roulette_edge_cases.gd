extends "res://tests/features/roulette/roulette_round_fixture.gd"
## Multiplayer edge cases: rate limits, lost settlement replies, balances that fall
## below the bets, seat collisions and refused seat requests.


func test_chips_the_balance_no_longer_covers_are_returned_at_lock_in() -> void:
	_sit(2)
	_sit(3)
	_table._wheel = FixedWheel.new(1)
	_act(2, &"bet", {"spot": "red", "cents": 100})
	_act(2, &"bet", {"spot": "17", "cents": 500})
	_act(2, &"bet", {"spot": "red", "cents": 100})
	_act(3, &"bet", {"spot": "red", "cents": 500})
	_wallet.balances[2] = 300
	_wallet.balances[3] = 400
	_run(RouletteTable.BETTING_S + 0.1)
	assert_eq(_table.phase(), RouletteTable.PHASE_SPINNING)
	assert_eq(_table.placements_for(2), [["red", 100]], "newest chips that don't fit go back")
	assert_eq(_table.placements_for(3), [], "nothing fits, nothing rides")
	_run(RouletteTable.SPIN_DURATION_S + 0.1)
	assert_eq(_table.state["results"][2]["status"], "won", "the covered chip still plays")
	assert_eq(int(_wallet.balances[2]), 300 - 100 + 200)
	assert_false((_table.state["results"] as Dictionary).has(3))
	assert_eq(int(_wallet.balances[3]), 400)


func test_affordable_keeps_the_oldest_chips_that_fit() -> void:
	var placements := [["a", 100], ["b", 500], ["c", 100], ["d", 5000]]
	assert_eq(RouletteTable.affordable(placements, 650), [["a", 100], ["b", 500]])
	assert_eq(RouletteTable.affordable(placements, 5700), placements)
	assert_eq(RouletteTable.affordable(placements, 50), [])


func test_a_bet_the_wallet_rejects_at_settlement_is_void() -> void:
	_sit(2)
	_table._wheel = FixedWheel.new(1)
	_act(2, &"bet", {"spot": "red", "cents": 500})
	_run(RouletteTable.BETTING_S + 0.1)
	_wallet.balances[2] = 300
	_run(RouletteTable.SPIN_DURATION_S + 0.5)
	assert_eq(_table.state["results"][2]["status"], "void")
	assert_eq(int(_wallet.balances[2]), 300, "a void bet neither charges nor pays")


func test_bet_edits_are_rate_limited_per_player() -> void:
	_sit(2)
	_sit(3)
	_wallet.balances[2] = 100000
	for _chip: int in int(RouletteTable.EDIT_BURST):
		assert_eq(_act(2, &"bet", {"spot": "red", "cents": 100}), RESULT.ACCEPTED)
	assert_eq(_act(2, &"bet", {"spot": "red", "cents": 100}), RESULT.DENIED, "burst spent")
	assert_eq(_act(2, &"undo"), RESULT.DENIED, "every edit shares the allowance")
	assert_eq(_act(3, &"bet", {"spot": "red", "cents": 100}), RESULT.ACCEPTED, "others unaffected")
	_table._clock_s += 1.0 / RouletteTable.EDIT_RATE
	assert_eq(_act(2, &"bet", {"spot": "red", "cents": 100}), RESULT.ACCEPTED, "refills over time")
	assert_eq(_act(2, &"bet", {"spot": "red", "cents": 100}), RESULT.DENIED)
	assert_eq(_act(2, &"leave"), RESULT.ACCEPTED, "leaving is never rate limited")


func test_settlement_keeps_retrying_the_same_operation_until_answered() -> void:
	_wallet.remove_from_group(&"player_money")
	var flaky := FlakyWallet.new()
	add_child_autofree(flaky)
	flaky.set_process(false)
	flaky.balances = {2: 2000}
	_sit(2)
	_table._wheel = FixedWheel.new(1)
	_act(2, &"bet", {"spot": "red", "cents": 500})
	_run(RouletteTable.BETTING_S + RouletteTable.SPIN_DURATION_S + 0.2)
	assert_eq(_table.state["results"][2]["status"], "settling", "no answer is not a void bet")
	await wait_seconds(2.0)
	assert_eq(flaky.ids.size(), 3, "retried after each unanswered call")
	assert_eq(flaky.ids[0], flaky.ids[2], "with the same operation ID")
	assert_eq(_table.state["results"][2]["status"], "won")
	assert_eq(int(flaky.balances[2]), 2000 - 500 + 1000)


func test_a_standing_player_is_moved_off_a_seat_being_taken() -> void:
	var bystander := _players[5] as Player
	bystander.net_position = _table.seat_position(0)
	var moved := _table._clear_seat(0, _players[2] as Player)
	assert_true(moved.has(5))
	var target: Vector3 = moved[5]
	var from_seat := target - _table.seat_position(0)
	from_seat.y = 0.0
	assert_almost_eq(from_seat.length(), RouletteTable.SEAT_NUDGE_M, 0.01)
	assert_lt(_table.to_local(target).z, RouletteTable.SEATS[0].z, "moved away from the table")
	_sit(3)
	(_players[3] as Player).net_position = _table.seat_position(1)
	assert_false(_table._clear_seat(1, _players[2] as Player).has(3), "seated players stay put")


func test_a_refused_seat_request_explains_why() -> void:
	var chat := FakeChat.new()
	add_child_autofree(chat)
	var state := _table.state.duplicate(true)
	state["phase"] = RouletteTable.PHASE_BETTING
	state["seats"] = [2, 3, 4]
	_table.state = state
	_table._on_request_finished(&"use", NetworkedEntity.Result.DENIED)
	assert_eq(chat.lines, ["Roulette table is full"])
	state["phase"] = RouletteTable.PHASE_SPINNING
	_table.state = state
	_table._on_request_finished(&"use", NetworkedEntity.Result.DENIED)
	assert_eq(chat.lines[1], "Roulette: wait for the next round")
	_table._on_request_finished(&"use", NetworkedEntity.Result.ACCEPTED)
	_table._on_request_finished(&"bet", NetworkedEntity.Result.DENIED)
	assert_eq(chat.lines.size(), 2, "only refused seat requests")
