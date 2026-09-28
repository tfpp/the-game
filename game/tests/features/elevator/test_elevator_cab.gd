extends GutTest
## Server-authoritative boarding/departure for the elevator (features/elevator/elevator_cab.gd).
## Runs single-process like test_combat.gd, so peer 1 is the server and `.rpc_id()`
## calls resolve locally; state transitions are driven directly instead of waiting out
## real seconds, the same way test_coin_pickup.gd pokes `_on_cooldown_finished()`.

const FeatureScene := preload("res://features/elevator/feature.tscn")
const PlayerScene := preload("res://core/player/player.tscn")

var _root: Node3D
var _lobby_cab: ElevatorCab
var _room_cab: ElevatorCab


func before_each() -> void:
	_root = FeatureScene.instantiate() as Node3D
	add_child_autofree(_root)
	_lobby_cab = _root.get_node("LobbyCab") as ElevatorCab
	_room_cab = _root.get_node("RoomCab") as ElevatorCab


## `_root` and every player are direct children of the test scene root with no
## transform of their own, so local `position` doubles as world position here.
func _player_at(global_pos: Vector3) -> Player:
	var player := PlayerScene.instantiate() as Player
	player.set_multiplayer_authority(1)
	player.position = global_pos
	player.net_position = global_pos
	add_child_autofree(player)
	return player


func _board_and_depart(cab: ElevatorCab) -> void:
	cab.request_call()
	cab._server_advance(ElevatorCab.DOOR_SLIDE_S + 0.01)
	cab._server_advance(ElevatorCab.BOARDING_S + 0.01)
	cab._server_advance(ElevatorCab.DOOR_SLIDE_S + 0.01)


func test_calling_an_idle_cab_starts_it_opening() -> void:
	_player_at(_lobby_cab.global_position + Vector3(0, 0.9, 0))
	_lobby_cab.request_call()
	assert_eq(_lobby_cab.net_state, ElevatorCab.State.OPENING)


func test_calling_a_busy_cab_does_nothing() -> void:
	_player_at(_lobby_cab.global_position + Vector3(0, 0.9, 0))
	_lobby_cab.request_call()
	_lobby_cab.request_call()
	_lobby_cab._server_advance(ElevatorCab.DOOR_SLIDE_S + 0.01)
	assert_eq(_lobby_cab.net_state, ElevatorCab.State.OPEN)


func test_full_cycle_teleports_the_occupant_to_the_other_cab_and_opens_it() -> void:
	var player := _player_at(_lobby_cab.global_position + Vector3(0, 0.9, 0))
	_board_and_depart(_lobby_cab)

	assert_eq(_lobby_cab.net_state, ElevatorCab.State.CLOSED)
	assert_eq(_room_cab.net_state, ElevatorCab.State.OPENING)
	var expected := _room_cab.global_position + Vector3(0, 0.9, 0)
	assert_true(
		player.global_position.is_equal_approx(expected),
		"expected %s, got %s" % [expected, player.global_position]
	)


func test_the_trip_reverses_from_the_room_back_to_the_lobby() -> void:
	var player := _player_at(_room_cab.global_position + Vector3(0.3, 0.9, 0))
	_board_and_depart(_room_cab)

	assert_eq(_room_cab.net_state, ElevatorCab.State.CLOSED)
	assert_eq(_lobby_cab.net_state, ElevatorCab.State.OPENING)
	var expected := ElevatorMath.apply_offset(
		ElevatorMath.relative_offset(
			_room_cab.global_position + Vector3(0.3, 0.9, 0), _room_cab.global_transform
		),
		_lobby_cab.global_transform
	)
	assert_true(player.global_position.is_equal_approx(expected))


func test_a_player_left_outside_the_cab_does_not_depart() -> void:
	var bystander := _player_at(_lobby_cab.global_position + Vector3(4, 0.9, 0))
	var start := bystander.global_position
	_board_and_depart(_lobby_cab)
	assert_true(bystander.global_position.is_equal_approx(start))
	assert_eq(_room_cab.net_state, ElevatorCab.State.CLOSED)


func test_departing_with_nobody_inside_just_recloses() -> void:
	_lobby_cab.request_call()
	_lobby_cab._server_advance(ElevatorCab.DOOR_SLIDE_S + 0.01)
	_lobby_cab._server_advance(ElevatorCab.BOARDING_S + 0.01)
	_lobby_cab._server_advance(ElevatorCab.DOOR_SLIDE_S + 0.01)
	assert_eq(_lobby_cab.net_state, ElevatorCab.State.CLOSED)
	assert_eq(_room_cab.net_state, ElevatorCab.State.CLOSED)


func test_can_use_requires_being_near_and_idle() -> void:
	var near := _player_at(_lobby_cab.global_position)
	var far := _player_at(_lobby_cab.global_position + Vector3(10, 0, 0))
	assert_true(_lobby_cab.can_use(near))
	assert_false(_lobby_cab.can_use(far))
	_lobby_cab.request_call()
	assert_false(_lobby_cab.can_use(near))
