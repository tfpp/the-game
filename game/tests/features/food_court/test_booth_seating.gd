extends GutTest
## Server rules for booth seats, the local seat pin and the replicated seated pose.

const COURT := preload("res://features/food_court/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const MODELS := preload("res://features/player_models/feature.tscn")

var _court: FoodCourt
var _player: Player


func before_each() -> void:
	_court = COURT.instantiate() as FoodCourt
	add_child_autofree(_court)
	_player = _add_player(1)
	# At the open end of the first booth, within reach of both benches' near seats.
	_player.global_position = _court.to_global(FoodCourt.BOOTHS[0] + Vector3(-1.2, 0.92, 0))
	_player.net_position = _player.global_position


func after_each() -> void:
	await get_tree().process_frame


func test_every_booth_has_four_seats_facing_its_table() -> void:
	assert_eq(_court.seats.size(), FoodCourt.BOOTHS.size() * 4)
	for index: int in _court.seats.size():
		var seat := _court.seats[index]
		var table := (seat.get_parent() as Node3D).global_position
		var forward := -seat.global_basis.z
		var toward := signf(table.z - seat.global_position.z)
		assert_gt(forward.dot(Vector3(0, 0, toward)), 0.99)
		assert_almost_eq(seat.global_position.y, 0.45, 0.001, "Seat on the cushion")


func test_nearby_player_sits_and_stands() -> void:
	_court.request_sit(0)
	assert_eq(_court.net_seats[0], 1)
	assert_true(_court.is_seated(1))
	_court.request_sit(2)
	assert_eq(_court.net_seats[0], 0, "Switching seats frees the old one")
	assert_eq(_court.seat_of(1), 2)
	_court.request_stand()
	assert_false(_court.is_seated(1))
	assert_eq(_court.entity._evaluate(1, &"stand", {}), NetworkedEntity.Result.DENIED)


func test_rejects_bad_payloads_distance_unknown_peers_and_taken_seats() -> void:
	var denied := NetworkedEntity.Result.DENIED
	assert_eq(_court.entity._evaluate(1, &"sit", {"seat": "0"}), denied)
	assert_eq(_court.entity._evaluate(1, &"sit", {"seat": 0, "peer": 2}), denied)
	assert_eq(_court.entity._evaluate(1, &"sit", {"seat": 999}), denied)
	assert_eq(_court.entity._evaluate(1, &"sit", {"seat": -1}), denied)
	assert_eq(_court.entity._evaluate(7, &"sit", {"seat": 0}), denied)
	assert_eq(_court.entity._evaluate(1, &"sit", {"seat": 20}), denied, "Too far away")
	var second := _add_player(2)
	second.net_position = _player.net_position
	assert_eq(_court.entity._evaluate(2, &"sit", {"seat": 0}), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_court.entity._evaluate(1, &"sit", {"seat": 0}), denied, "Seat is taken")
	assert_eq(_court.net_seats[0], 2)


func test_disconnect_death_and_moving_away_free_seats() -> void:
	var second := _add_player(2)
	second.net_position = _player.net_position
	_court.entity._evaluate(2, &"sit", {"seat": 1})
	_court._on_peer_disconnected(2)
	assert_false(_court.is_seated(2))
	_court.request_sit(0)
	_court._on_player_died(1, 2)
	assert_false(_court.is_seated(1))
	_court.request_sit(0)
	_player.set_physics_process(false)
	_player.net_position = Vector3(0, 1, 0)
	_court._release_moved_players()
	assert_false(_court.is_seated(1), "Teleported players leave their seat")


func test_local_player_is_pinned_facing_the_table_then_steps_out() -> void:
	_court.request_sit(2)
	_court._physics_process(0.016)
	assert_false(_player.is_physics_processing(), "Seated players don't walk")
	assert_almost_eq(_player.global_position, _court.sit_position(2), Vector3.ONE * 0.001)
	assert_almost_eq(_player.net_position, _court.sit_position(2), Vector3.ONE * 0.001)
	assert_almost_eq(_player.yaw, _court.sit_yaw(2), 0.001)
	_court.request_stand()
	_court._physics_process(0.016)
	assert_true(_player.is_physics_processing())
	var spot := _court.stand_position(2)
	assert_almost_eq(_player.global_position.x, spot.x, 0.001)
	assert_almost_eq(_player.global_position.z, spot.z, 0.001)
	assert_gt(_player.global_position.y, 0.9, "Stands on the floor, not in the bench")


func test_teleported_seated_player_lets_go_and_asks_to_stand() -> void:
	_court.request_sit(0)
	_court._physics_process(0.016)
	_player.global_position = Vector3(2, 0.2, 5)
	_player.net_position = _player.global_position
	_court._physics_process(0.016)
	assert_true(_player.is_physics_processing())
	assert_almost_eq(_player.global_position, Vector3(2, 0.2, 5), Vector3.ONE * 0.001)
	assert_false(_court.is_seated(1))


func test_session_reset_clears_seats() -> void:
	_court.request_sit(0)
	_court._reset_session(Network.Mode.OFFLINE)
	assert_false(_court.is_seated(1))


func test_seat_prompts_follow_occupancy() -> void:
	var seat := _court.seats[0]
	assert_true(seat.call("can_use", _player))
	assert_eq(seat.call("interaction_text"), "Sit in the booth")
	assert_false(_court.seats[1].call("can_use", _player), "Out of reach")
	seat.call("use")
	assert_eq(seat.call("interaction_text"), "Stand up")
	assert_false(_court.seats[2].call("can_use", _player), "Stand up before moving seats")
	_court.net_seats = PackedInt32Array([2]) + _court.net_seats.slice(1)
	assert_false(seat.call("can_use", _player), "Someone else's seat")


func test_late_joiner_sees_remote_diner_seated() -> void:
	var models := MODELS.instantiate()
	add_child_autofree(models)
	var remote := _add_player(2)
	models._process(0.0)
	var model := remote.get_node("Body/Avatar") as BlockPlayerModel
	var seats := _court.net_seats.duplicate()
	seats[3] = 2
	_court.net_seats = seats
	model._process(1.0)
	assert_true(model.seated)
	var leg := model.get_node("Rig/LeftLeg") as Node3D
	var foot := leg.basis * Vector3.DOWN
	assert_lt(foot.z, -0.9, "Legs point forward under the table")
	_court.net_seats = PackedInt32Array(_court.net_seats.slice(0, 3)) + PackedInt32Array([0])
	_court._reset_session(Network.Mode.OFFLINE)
	model._process(1.0)
	assert_false(model.seated)


func _add_player(peer: int) -> Player:
	var player := PLAYER.instantiate() as Player
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	add_child_autofree(player)
	return player
