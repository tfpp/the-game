extends GutTest

const SCENE := preload("res://features/horse_betting/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const ACCEPTED := NetworkedEntity.Result.ACCEPTED
const DENIED := NetworkedEntity.Result.DENIED
var race: HorseBetting
var wallet: PlayerMoney
var players: Dictionary = {}


func before_each() -> void:
	wallet = PlayerMoney.new()
	add_child_autofree(wallet)
	wallet.set_process(false)
	wallet.balances = {2: 2000, 3: 2000}
	race = SCENE.instantiate() as HorseBetting
	race.position = Vector3.ZERO
	race.rotation = Vector3.ZERO
	add_child_autofree(race)
	race.set_process(false)
	for peer: int in [2, 3]:
		var player := PLAYER.instantiate() as Player
		player.set_multiplayer_authority(peer)
		player.display_name = "Bettor%d" % peer
		player.position = Vector3(0, 0.9144, 2.4)
		player.net_position = player.position
		player.net_yaw = 0
		add_child_autofree(player)
		player.set_physics_process(false)
		players[peer] = player
	await wait_physics_frames(2)


func bet(peer: int, horse: int = 0, stake: int = 100) -> NetworkedEntity.Result:
	return race.entity._evaluate(
		peer, &"bet", {"horse": horse, "stake": stake, "round": race.ticket_round()}
	)


func test_opening_menu_does_not_start_clock_first_valid_ticket_does() -> void:
	assert_true(race.can_use(players[2]))
	assert_eq(race.state["phase"], "idle")
	assert_eq(bet(2), ACCEPTED)
	assert_eq(race.state["phase"], "betting")
	assert_eq(race.seconds_left, 15)
	race._process(10)
	assert_eq(bet(3, 1), ACCEPTED)
	assert_eq(race.seconds_left, 5)
	assert_eq(int(race.state["round"]), 1)
	race._process(4.99)
	assert_eq(race.state["phase"], "betting")
	race._process(0.01)
	assert_eq(race.state["phase"], "racing")
	assert_eq(race.seconds_left, 0)
	assert_eq(bet(3), DENIED)
	assert_eq(wallet.balances, {2: 2000, 3: 2000}, "no premature charge")


func test_payload_sender_range_balance_and_duplicate_validation() -> void:
	assert_eq(bet(99), DENIED)
	assert_eq(bet(2, -1), DENIED)
	assert_eq(bet(2, 4), DENIED)
	assert_eq(bet(2, 0, 101), DENIED)
	wallet.balances[2] = 99
	assert_eq(bet(2), DENIED)
	wallet.balances[2] = 2000
	assert_eq(race.state["phase"], "idle")
	for payload: Dictionary in [
		{},
		{"horse": "0", "stake": 100, "round": 0},
		{"horse": 0, "stake": 100, "round": 0, "peer": 3},
		{"horse": 0, "stake": 100, "round": -1}
	]:
		assert_eq(race.entity._evaluate(2, &"bet", payload), DENIED)
	(players[2] as Player).net_position = Vector3(0, 1, 20)
	assert_eq(bet(2), DENIED)
	(players[2] as Player).net_position = Vector3(0, 0.9144, 2.4)
	(players[2] as Player).net_yaw = PI
	assert_eq(bet(2), DENIED, "must face terminal")
	(players[2] as Player).net_yaw = 0
	assert_eq(bet(2), ACCEPTED)
	assert_eq(bet(2, 2), DENIED, "one ticket, cannot overwrite")
	assert_eq(race.state["bets"][2]["horse"], 0)


func test_simultaneous_first_tickets_target_same_round_without_resetting_clock() -> void:
	var round_id := race.ticket_round()
	assert_eq(
		race.entity._evaluate(2, &"bet", {"horse": 0, "stake": 100, "round": round_id}), ACCEPTED
	)
	race._process(0.25)
	assert_eq(
		race.entity._evaluate(3, &"bet", {"horse": 1, "stake": 100, "round": round_id}), ACCEPTED
	)
	assert_eq(int(race.state["round"]), round_id)
	assert_eq(race._elapsed, 0.25)
	assert_eq(race.state["bets"].size(), 2)


func test_full_race_settles_winners_losers_and_allows_repeat_play() -> void:
	bet(2, 0, 500)
	bet(3, 1, 1000)
	race._process(15)
	race._durations = [8.0, 10.0, 9.0, 11.0]
	race._process(6)
	assert_eq(race.state["winner"], -1, "no disclosed winner before finish")
	assert_gt(race.progress[0], race.progress[1])
	race._process(6)
	assert_eq(race.state["phase"], "result")
	assert_eq(race.state["winner"], 0)
	assert_eq(wallet.balances[2], 3500, "$5 returns $20 total")
	assert_eq(wallet.balances[3], 1000)
	assert_eq(race.state["results"][2], "Won $20.00")
	assert_eq(race.state["results"][3], "Lost ticket")
	assert_eq(bet(2), DENIED)
	race._process(8)
	assert_eq(race.state["phase"], "idle")
	assert_eq(bet(2, 3), ACCEPTED, "previous bettor can play again")
	assert_eq(int(race.state["round"]), 2)
	assert_eq(race.state["results"], {})
	assert_eq(race.state["bets"].size(), 1)


func test_disconnect_before_lock_removes_ticket_but_walking_away_keeps_it() -> void:
	bet(2)
	bet(3)
	(players[2] as Player).net_position = Vector3(0, 1, 30)
	(players[3] as Player).free()
	race._process(1)
	assert_true(race.state["bets"].has(2))
	assert_false(race.state["bets"].has(3))
	assert_eq(race.seconds_left, 14, "disconnect never restarts window")


func test_insufficient_balance_at_result_voids_without_charge_or_prize() -> void:
	bet(2)
	race._process(15)
	race._durations = [8.0, 10.0, 9.0, 11.0]
	wallet.balances[2] = 50
	race._process(12)
	assert_eq(wallet.balances[2], 50)
	assert_true(str(race.state["results"][2]).begins_with("Void"))


func test_session_reset_clears_clock_tickets_and_progress() -> void:
	bet(2)
	race._process(15)
	race._process(3)
	race._reset(Network.Mode.OFFLINE)
	assert_eq(race.state, HorseBetting.initial_state())
	assert_eq(race.progress, [0.0, 0.0, 0.0, 0.0])
	assert_eq(race.seconds_left, 0)
	assert_true(race._locked.is_empty())


func test_progress_is_monotonic_and_finishes_in_sampled_order() -> void:
	var durations: Array[float] = [8.0, 9.0, 10.0, 11.0]
	var previous: Array[float] = [0.0, 0.0, 0.0, 0.0]
	for tick: int in 121:
		var current := HorseBetting.race_progress(tick / 10.0, durations)
		for horse: int in 4:
			assert_gte(current[horse], previous[horse])
			assert_between(current[horse], 0.0, 1.0)
		previous = current
	assert_eq(previous, [1.0, 1.0, 1.0, 1.0])
	var first := HorseBetting.race_progress(8.0, durations)
	assert_eq(first[0], 1.0)
	assert_lt(first[1], 1.0)


func test_late_join_snapshot_includes_round_tickets_result_clock_and_motion() -> void:
	var config := race.entity.get_node("Sync").replication_config as SceneReplicationConfig
	for path: NodePath in [NodePath(".:state"), NodePath(".:seconds_left"), NodePath(".:progress")]:
		assert_true(config.has_property(path))
		assert_true(config.property_get_spawn(path), "late join gets current snapshot")
	bet(2)
	var late := SCENE.instantiate() as HorseBetting
	late.state = race.state.duplicate(true)
	late.seconds_left = race.seconds_left
	add_child_autofree(late)
	late.set_process(false)
	assert_eq(late.state["bets"][2]["horse"], 0)
	assert_eq(late.seconds_left, 15)
