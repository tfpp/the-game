extends GutTest
## Server-side round flow: seats, bets, lock-in, spin, settlement and release.
## Requests go through the real NetworkedInteraction evaluation with fake peers.

const TableScene := preload("res://features/roulette/table.tscn")
const PlayerScene := preload("res://core/player/player.tscn")
const RESULT := NetworkedEntity.Result

var _table: RouletteTable
var _wallet: PlayerMoney
var _players: Dictionary = {}


func before_each() -> void:
	_wallet = PlayerMoney.new()
	add_child_autofree(_wallet)
	_wallet.set_process(false)
	_wallet.balances = {2: 2000, 3: 2000, 4: 2000, 5: 2000}
	_table = TableScene.instantiate() as RouletteTable
	add_child_autofree(_table)
	_table.set_process(false)
	_players.clear()
	for peer: int in [2, 3, 4, 5]:
		var player := PlayerScene.instantiate() as Player
		player.set_multiplayer_authority(peer)
		player.display_name = "P%d" % peer
		player.position = Vector3((peer - 3) * 0.9, 0.9144, -2.4)
		player.net_position = player.position
		player.net_yaw = PI
		add_child_autofree(player)
		_players[peer] = player
	await get_tree().physics_frame


func _use(peer: int) -> NetworkedEntity.Result:
	return _table.entity._evaluate(peer, &"use", {})


func _act(peer: int, action: StringName, payload: Dictionary = {}) -> NetworkedEntity.Result:
	return _table.entity._evaluate(peer, action, payload)


func _sit(peer: int) -> void:
	assert_eq(_use(peer), RESULT.ACCEPTED, "peer %d sits" % peer)
	var player := _players[peer] as Player
	player.net_position = _table.seat_position(_table.seat_of(peer))
	player.global_position = player.net_position


func _run(seconds: float) -> void:
	var step := 0.25
	var elapsed := 0.0
	while elapsed < seconds:
		_table._process(step)
		elapsed += step


func test_first_player_opens_a_thirty_second_round_and_takes_a_seat() -> void:
	assert_eq(_table.phase(), RouletteTable.PHASE_IDLE)
	_sit(2)
	assert_eq(_table.phase(), RouletteTable.PHASE_BETTING)
	assert_eq(_table.seat_of(2), 0)
	assert_eq(_table.state["names"][0], "P2")
	assert_eq(_table.net_seconds_left, 30)
	_run(15.0)
	assert_eq(_table.phase(), RouletteTable.PHASE_BETTING, "joining does not restart the clock")
	_sit(3)
	assert_eq(_table.seat_of(3), 1)
	assert_eq(_table.net_seconds_left, 15)


func test_only_three_players_fit_and_nobody_sits_twice() -> void:
	_sit(2)
	assert_eq(_use(2), RESULT.DENIED)
	_sit(3)
	_sit(4)
	assert_eq(_use(5), RESULT.DENIED, "the table is full")
	assert_eq(_table.state["seats"], [2, 3, 4])


func test_seats_are_fixed_locations_facing_the_table() -> void:
	var seen := {}
	for seat: int in RouletteTable.SEAT_COUNT:
		var position := _table.seat_position(seat)
		assert_lt(position.z, -0.62 - 0.4, "seat %d is clear of the table edge" % seat)
		seen[position] = true
	assert_eq(seen.size(), RouletteTable.SEAT_COUNT)
	var facing := Basis.from_euler(Vector3(0, _table.seat_yaw(), 0)) * Vector3.FORWARD
	assert_almost_eq(facing, Vector3.BACK, Vector3.ONE * 0.001, "players face +Z, the layout")


func test_bets_must_be_seated_valid_chips_and_within_the_balance() -> void:
	assert_eq(_act(2, &"bet", {"spot": "red", "cents": 100}), RESULT.DENIED, "not seated")
	_sit(2)
	assert_eq(_act(2, &"bet", {"spot": "red", "cents": 100}), RESULT.ACCEPTED)
	assert_eq(_act(2, &"bet", {"spot": "17", "cents": 500}), RESULT.ACCEPTED)
	assert_eq(_act(2, &"bet", {"spot": "red", "cents": 250}), RESULT.DENIED, "not a chip")
	assert_eq(_act(2, &"bet", {"spot": "purple", "cents": 100}), RESULT.DENIED)
	assert_eq(_act(2, &"bet", {"spot": "red"}), RESULT.DENIED)
	assert_eq(_act(2, &"bet", {"spot": "red", "cents": "100"}), RESULT.DENIED)
	assert_eq(_act(2, &"bet", {"spot": "red", "cents": 100, "peer": 3}), RESULT.DENIED)
	# $20 wallet: $6 is down, so $14 remains; a $50 chip does not fit.
	assert_eq(_act(2, &"bet", {"spot": "black", "cents": 5000}), RESULT.DENIED)
	for _chip: int in 14:
		assert_eq(_act(2, &"bet", {"spot": "black", "cents": 100}), RESULT.ACCEPTED)
	assert_eq(_act(2, &"bet", {"spot": "black", "cents": 100}), RESULT.DENIED, "balance used up")
	assert_eq(RouletteBets.total(_table.placements_for(2)), 2000)


func test_any_chip_combination_up_to_a_large_balance() -> void:
	_wallet.balances[2] = 3165600
	_sit(2)
	for cents: int in RouletteBets.DENOMINATIONS:
		assert_eq(_act(2, &"bet", {"spot": "dozen1", "cents": cents}), RESULT.ACCEPTED)
	assert_eq(RouletteBets.by_spot(_table.placements_for(2)), {"dozen1": 3165600})


func test_undo_remove_and_clear_edit_only_your_own_bets() -> void:
	_sit(2)
	_sit(3)
	_act(2, &"bet", {"spot": "red", "cents": 100})
	_act(2, &"bet", {"spot": "17", "cents": 500})
	_act(2, &"bet", {"spot": "red", "cents": 500})
	_act(3, &"bet", {"spot": "red", "cents": 100})
	assert_eq(_act(2, &"undo"), RESULT.ACCEPTED)
	assert_eq(_table.placements_for(2), [["red", 100], ["17", 500]])
	assert_eq(_act(2, &"remove", {"spot": "red"}), RESULT.ACCEPTED)
	assert_eq(_table.placements_for(2), [["17", 500]])
	assert_eq(_act(2, &"remove", {"spot": "black"}), RESULT.DENIED)
	assert_eq(_act(2, &"clear"), RESULT.ACCEPTED)
	assert_eq(_table.placements_for(2), [])
	assert_eq(_table.placements_for(3), [["red", 100]], "other players keep their chips")


func test_leaving_before_the_spin_cancels_bets_and_frees_the_seat() -> void:
	_sit(2)
	_sit(3)
	_act(2, &"bet", {"spot": "red", "cents": 100})
	assert_eq(_act(2, &"leave"), RESULT.ACCEPTED)
	assert_eq(_table.seat_of(2), -1)
	assert_eq(_table.placements_for(2), [])
	assert_eq(_table.phase(), RouletteTable.PHASE_BETTING)
	assert_eq(_act(3, &"leave"), RESULT.ACCEPTED)
	assert_eq(_table.phase(), RouletteTable.PHASE_IDLE, "an empty table closes the round")
	assert_eq(int(_wallet.balances[2]), 2000, "cancelled bets never cost anything")


func test_round_without_bets_releases_everyone_without_spinning() -> void:
	_sit(2)
	_run(RouletteTable.BETTING_S + 0.5)
	assert_eq(_table.phase(), RouletteTable.PHASE_IDLE)
	assert_eq(int(_table.state["spin"]), 0)
	assert_eq(_table.seat_of(2), -1)
	assert_eq(_table.state["message"], "No bets placed")


func test_full_round_locks_bets_spins_settles_and_releases() -> void:
	_sit(2)
	_sit(3)
	_sit(4)
	_table._wheel = FixedWheel.new(17)
	_act(2, &"bet", {"spot": "17", "cents": 100})
	_act(2, &"bet", {"spot": "red", "cents": 500})
	_act(3, &"bet", {"spot": "black", "cents": 500})
	_run(RouletteTable.BETTING_S + 0.1)
	assert_eq(_table.phase(), RouletteTable.PHASE_SPINNING)
	assert_true(_table.state["spinning"])
	assert_eq(_act(2, &"bet", {"spot": "black", "cents": 100}), RESULT.DENIED, "no more bets")
	assert_eq(_act(2, &"leave"), RESULT.DENIED, "bets are riding")
	assert_eq(_act(4, &"leave"), RESULT.ACCEPTED, "a seat with no bets may stand up")
	assert_eq(_use(5), RESULT.DENIED, "nobody joins mid-spin")
	assert_eq(int(_wallet.balances[2]), 2000, "nothing settles before the ball lands")
	_run(RouletteTable.SPIN_DURATION_S + 0.1)
	assert_eq(_table.phase(), RouletteTable.PHASE_RESULT)
	assert_eq(int(_table.state["number"]), 17)
	assert_eq(_table.state["color"], "black")
	# Peer 2: 17 straight pays 36 x $1, red loses $5. Peer 3: black pays 2 x $5.
	assert_eq(int(_wallet.balances[2]), 2000 - 600 + 3600)
	assert_eq(int(_wallet.balances[3]), 2000 - 500 + 1000)
	assert_eq(int(_wallet.balances[4]), 2000)
	var results := _table.state["results"] as Dictionary
	assert_eq(results[2], {"wager": 600, "payout": 3600, "status": "won"})
	assert_eq(results[3]["status"], "won")
	assert_false(results.has(4))
	assert_eq(_table.seat_of(2), 0, "players stay seated to see the result")
	_run(RouletteTable.RESULT_S + 0.1)
	assert_eq(_table.phase(), RouletteTable.PHASE_IDLE)
	assert_eq(_table.state["seats"], [0, 0, 0], "everyone is released")
	assert_eq(_table.state["bets"], {})
	_sit(5)
	assert_eq(int(_table.state["round"]), 2, "the next player opens a new round")
	assert_eq(_table.state["results"], {})


func test_a_bet_the_wallet_can_no_longer_cover_is_void() -> void:
	_sit(2)
	_table._wheel = FixedWheel.new(1)
	_act(2, &"bet", {"spot": "red", "cents": 500})
	_wallet.balances[2] = 300
	_run(RouletteTable.BETTING_S + RouletteTable.SPIN_DURATION_S + 0.5)
	assert_eq(_table.state["results"][2]["status"], "void")
	assert_eq(int(_wallet.balances[2]), 300, "a void bet neither charges nor pays")


func test_players_who_leave_their_seat_or_disconnect_lose_it() -> void:
	_sit(2)
	_sit(3)
	_act(2, &"bet", {"spot": "red", "cents": 100})
	_table._process(0.1)
	(_players[2] as Player).net_position += Vector3(0, 0, -3)
	_table._process(0.1)
	assert_eq(_table.seat_of(2), -1, "walked away")
	assert_eq(_table.placements_for(2), [])
	(_players[3] as Player).free()
	_table._process(0.1)
	assert_eq(_table.seat_of(3), -1, "disconnected")
	assert_eq(_table.phase(), RouletteTable.PHASE_IDLE)


func test_a_player_still_walking_to_the_seat_keeps_it() -> void:
	assert_eq(_use(2), RESULT.ACCEPTED)
	_table._process(0.1)
	assert_eq(_table.seat_of(2), 0, "the teleport has not arrived yet")


func test_session_change_clears_the_round() -> void:
	_sit(2)
	_act(2, &"bet", {"spot": "red", "cents": 100})
	_table._on_mode_changed(Network.Mode.OFFLINE)
	assert_eq(_table.state, RouletteTable.initial_state())
	assert_eq(_table.net_seconds_left, 0)


func test_table_has_a_dealer_across_from_the_seats() -> void:
	var dealer := _table.get_node("Dealer") as Node3D
	assert_not_null(dealer)
	assert_gt(dealer.position.z, 0.62, "behind the far edge of the table")
	assert_lt(_table.seat_position(0).z, 0.0)


func test_seated_players_spectate_and_open_the_bet_view_on_request() -> void:
	var view := _table.get_node("View") as RouletteTableView
	var local := _players[2] as Player
	local.set_multiplayer_authority(multiplayer.get_unique_id())
	local.add_to_group(&"local_player")
	_wallet.balances[multiplayer.get_unique_id()] = 2000
	var state := _table.state.duplicate(true)
	state["phase"] = RouletteTable.PHASE_BETTING
	state["seats"] = [multiplayer.get_unique_id(), 0, 0]
	_table.state = state
	view._process(0.0)
	assert_not_null(view.seat_view, "sitting starts the seat view")
	assert_null(view.screen, "the overhead view waits for the bet key")
	assert_false(view.seat_view.is_in_group(&"modal_ui"), "the player can still look around")
	assert_false(local.is_physics_processing(), "but cannot walk away")
	assert_true(InputMap.has_action(RouletteSeatView.ACTION))
	view.seat_view.open_bets()
	assert_not_null(view.screen)
	assert_false(view.seat_view.visible, "the seat panel hides under the bet view")
	view.screen.close()
	assert_null(view.screen, "Esc / the bet key returns to the seat")
	assert_true(view.seat_view.visible)
	assert_false(local.is_physics_processing())
	view.open_betting()
	assert_true(view.screen.is_in_group(&"modal_ui"), "the bet view blocks movement")
	assert_true(view.screen.camera.current, "overview camera")
	var center := view.screen.camera.unproject_position(
		_table.to_global(RouletteBets.pixel_to_local(RouletteBets.anchor("14")))
	)
	assert_eq(view.screen.spot_at_screen(center), "14", "clicks map onto the layout")
	state = _table.state.duplicate(true)
	state["bets"] = {multiplayer.get_unique_id(): [["14", 500], ["14", 100]]}
	_table.state = state
	view._process(0.0)
	assert_eq(view.chips.get_child_count(), 2, "chips are drawn on the felt")
	var top := view.chips.get_child(1) as MeshInstance3D
	assert_eq(top.mesh, view.chip_meshes[RouletteBets.DENOMINATIONS.find(100)])
	assert_gt(top.position.y, (view.chips.get_child(0) as Node3D).position.y, "last chip on top")
	state = _table.state.duplicate(true)
	var many: Array = []
	for _chip: int in RouletteTableView.MAX_STACK + 3:
		many.append(["14", 500])
	many.append(["14", 100])
	state["bets"] = {multiplayer.get_unique_id(): many}
	_table.state = state
	view._process(0.0)
	assert_eq(view.chips.get_child_count(), RouletteTableView.MAX_STACK, "tall stacks are capped")
	var last := view.chips.get_child(RouletteTableView.MAX_STACK - 1) as MeshInstance3D
	assert_eq(last.mesh, view.chip_meshes[0], "the newest chip stays on top past the cap")
	var wheel := _table.to_global(Vector3(-0.98, 0.9, 0))
	var layout := _table.to_global(RouletteBets.pixel_to_local(RouletteBets.anchor("14")))
	var screen := view.screen
	state = _table.state.duplicate(true)
	state["phase"] = RouletteTable.PHASE_SPINNING
	_table.state = state
	assert_true(screen.watching_wheel())
	for _frame: int in 90:
		screen.pan(1.0 / 30.0)
	var look := -screen.camera.global_basis.z
	assert_gt(look.dot((wheel - screen.camera.global_position).normalized()), 0.99, "on the wheel")
	state = _table.state.duplicate(true)
	state["phase"] = RouletteTable.PHASE_RESULT
	_table.state = state
	screen.pan(1.0)
	assert_true(screen.watching_wheel(), "holds on the wheel while the ball settles")
	for _frame: int in 90:
		screen.pan(1.0 / 30.0)
	assert_false(screen.watching_wheel())
	look = -screen.camera.global_basis.z
	assert_lt(
		look.dot((wheel - screen.camera.global_position).normalized()), 0.9, "back over the layout"
	)
	assert_eq(screen.spot_at_screen(screen.camera.unproject_position(layout)), "14")
	_table.state = RouletteTable.initial_state()
	view._process(0.0)
	assert_null(view.seat_view)
	assert_true(local.is_physics_processing(), "released players can move again")
	assert_not_null(view.screen, "the result stays up after release")
	assert_false(view.screen.seated())
	assert_true(view.screen.is_in_group(&"modal_ui"))
	view.screen._continue()
	assert_null(view.screen, "continuing returns to the game")
	Controls.pause()


func test_standing_up_from_the_seat_view_leaves_the_table() -> void:
	var view := _table.get_node("View") as RouletteTableView
	var local := _players[2] as Player
	local.set_multiplayer_authority(multiplayer.get_unique_id())
	local.add_to_group(&"local_player")
	var state := _table.state.duplicate(true)
	state["phase"] = RouletteTable.PHASE_BETTING
	state["seats"] = [multiplayer.get_unique_id(), 0, 0]
	_table.state = state
	view._process(0.0)
	assert_true(view.seat_view._hint.text.contains("leave table"))
	state = _table.state.duplicate(true)
	state["phase"] = RouletteTable.PHASE_SPINNING
	_table._locked[multiplayer.get_unique_id()] = {}
	_table.state = state
	view._process(0.0)
	assert_true(view.seat_view._hint.text.contains("riding"), "no standing up mid-spin")
	assert_true(view.seat_view._leave_button.disabled)
	_table.state = RouletteTable.initial_state()
	view._process(0.0)
	assert_null(view.seat_view)
	assert_null(view.screen, "released straight back to the game from the seat")


class FixedWheel:
	extends RouletteWheel
	var _number := 0

	func _init(number: int) -> void:
		_number = number

	func next_result() -> int:
		return _number
