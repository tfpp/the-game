extends GutTest
## Server-authoritative boarding/departure for the elevator (features/elevator/elevator_cab.gd).
## Runs single-process like test_combat.gd, so peer 1 is the server and `.rpc_id()`
## calls resolve locally; state transitions are driven directly instead of waiting out
## real seconds, the same way test_coin_pickup.gd pokes `_on_cooldown_finished()`.

const FeatureScene := preload("res://features/elevator/feature.tscn")
const PlayerScene := preload("res://core/player/player.tscn")

var _root: Node3D
var _casino_cab: ElevatorCab
var _garage_cab: ElevatorCab


func before_each() -> void:
	_root = FeatureScene.instantiate() as Node3D
	add_child_autofree(_root)
	_casino_cab = _root.get_node("CasinoCab") as ElevatorCab
	_garage_cab = _root.get_node("GarageZone/GarageCab") as ElevatorCab


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
	_player_at(_casino_cab.global_position + Vector3(0, 0.9, 0))
	_casino_cab.request_call()
	assert_eq(_casino_cab.net_state, ElevatorCab.State.OPENING)


func test_calling_a_busy_cab_does_nothing() -> void:
	_player_at(_casino_cab.global_position + Vector3(0, 0.9, 0))
	_casino_cab.request_call()
	_casino_cab.request_call()
	_casino_cab._server_advance(ElevatorCab.DOOR_SLIDE_S + 0.01)
	assert_eq(_casino_cab.net_state, ElevatorCab.State.OPEN)


func test_full_cycle_teleports_the_occupant_to_the_other_cab_and_opens_it() -> void:
	var player := _player_at(_casino_cab.global_position + Vector3(0, 0.9, 0))
	_board_and_depart(_casino_cab)

	assert_eq(_casino_cab.net_state, ElevatorCab.State.CLOSED)
	assert_eq(_garage_cab.net_state, ElevatorCab.State.OPENING)
	var expected := _garage_cab.global_position + Vector3(0, 0.9, 0)
	assert_true(
		player.global_position.is_equal_approx(expected),
		"expected %s, got %s" % [expected, player.global_position]
	)


func test_the_trip_reverses_from_the_garage_back_to_the_casino() -> void:
	var player := _player_at(_garage_cab.global_position + Vector3(0.3, 0.9, 0))
	_board_and_depart(_garage_cab)

	assert_eq(_garage_cab.net_state, ElevatorCab.State.CLOSED)
	assert_eq(_casino_cab.net_state, ElevatorCab.State.OPENING)
	var expected := ElevatorMath.apply_offset(
		ElevatorMath.relative_offset(
			_garage_cab.global_position + Vector3(0.3, 0.9, 0), _garage_cab.global_transform
		),
		_casino_cab.global_transform
	)
	assert_true(player.global_position.is_equal_approx(expected))


func test_full_cycle_preserves_the_occupants_facing_relative_to_the_cab() -> void:
	var player := _player_at(_casino_cab.global_position + Vector3(0, 0.9, 0))
	# Facing exactly the way the casino cab itself faces.
	player.yaw = _casino_cab.global_transform.basis.get_euler().y
	player.net_yaw = player.yaw
	_board_and_depart(_casino_cab)

	# Lands facing exactly the way the garage cab faces, even though the casino cab is
	# rotated 90 degrees relative to it (the garage runs east-west under the casino).
	assert_almost_eq(player.yaw, _garage_cab.global_transform.basis.get_euler().y, 0.0001)
	assert_almost_eq(player.net_yaw, _garage_cab.global_transform.basis.get_euler().y, 0.0001)


func test_a_player_left_outside_the_cab_does_not_depart() -> void:
	var bystander := _player_at(_casino_cab.global_position + Vector3(4, 0.9, 0))
	var start := bystander.global_position
	_board_and_depart(_casino_cab)
	assert_true(bystander.global_position.is_equal_approx(start))
	assert_eq(_garage_cab.net_state, ElevatorCab.State.CLOSED)


func test_departing_with_nobody_inside_just_recloses() -> void:
	_casino_cab.request_call()
	_casino_cab._server_advance(ElevatorCab.DOOR_SLIDE_S + 0.01)
	_casino_cab._server_advance(ElevatorCab.BOARDING_S + 0.01)
	_casino_cab._server_advance(ElevatorCab.DOOR_SLIDE_S + 0.01)
	assert_eq(_casino_cab.net_state, ElevatorCab.State.CLOSED)
	assert_eq(_garage_cab.net_state, ElevatorCab.State.CLOSED)


func test_can_use_requires_being_near_and_idle() -> void:
	var near := _player_at(_casino_cab.global_position)
	var far := _player_at(_casino_cab.global_position + Vector3(10, 0, 0))
	assert_true(_casino_cab.can_use(near))
	assert_false(_casino_cab.can_use(far))
	_casino_cab.request_call()
	assert_false(_casino_cab.can_use(near))


func test_everyone_inside_arrives_together_in_the_same_arrangement() -> void:
	var offsets: Array[Vector3] = [Vector3(-0.9, 0, -0.8), Vector3(0.8, 0, 0.9)]
	var riders: Array[Player] = []
	for offset: Vector3 in offsets:
		riders.append(_player_at(_casino_cab.to_global(offset)))
	_board_and_depart(_casino_cab)
	for index: int in riders.size():
		var expected := _garage_cab.to_global(offsets[index])
		assert_true(
			riders[index].global_position.is_equal_approx(expected),
			"expected %s, got %s" % [expected, riders[index].global_position]
		)
