extends GutTest

const PLAYER := preload("res://core/player/player.tscn")
const LADDER := preload("res://features/room_doors/ladder.tscn")
const DOOR := preload("res://features/room_doors/swing_door.tscn")

var _player: Player
var _ladder: ClimbableLadder
var _door: SwingDoor


func before_each() -> void:
	_player = PLAYER.instantiate() as Player
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_door = DOOR.instantiate() as SwingDoor
	add_child_autofree(_door)
	_ladder = LADDER.instantiate() as ClimbableLadder
	add_child_autofree(_ladder)
	_ladder.set_physics_process(false)
	_ladder.access_door = _ladder.get_path_to(_door)


func _move(at: Vector3) -> void:
	_player.global_position = at
	_player.net_position = at


func test_mount_requires_nearby_endpoint_and_open_upper_door() -> void:
	_move(_ladder.top_landing)
	assert_false(_ladder.can_use(_player))
	(_ladder.get_node("TopUse") as NetworkedInteraction).request_use()
	assert_null(_ladder._player)
	_door.net_state = SwingDoor.State.OPEN_IN
	_move(Vector3(20, 1, 20))
	(_ladder.get_node("TopUse") as NetworkedInteraction).request_use()
	assert_null(_ladder._player)
	_move(_ladder.top_landing)
	_ladder.use()
	assert_same(_ladder._player, _player)


func test_climbs_both_directions_and_restores_owner_movement() -> void:
	_move(_ladder.top_landing)
	_door.net_state = SwingDoor.State.OPEN_IN
	_player.set_physics_process(true)
	_ladder.use()
	assert_false(_player.is_physics_processing())
	_ladder._physics_process(0.3)
	assert_eq(_player.net_position, Vector3(0, 1, 0))
	_ladder._climb(-1, 3)
	_ladder._physics_process(0.3)
	assert_eq(_player.net_position, _ladder.bottom_landing)
	assert_true(_player.is_physics_processing())
	assert_null(_ladder._player)
	_door.net_state = SwingDoor.State.CLOSED
	assert_true(_ladder.can_use(_player), "Closing upstairs never strands a player below")
	_ladder.use()
	_ladder._physics_process(0.3)
	_ladder._climb(1, 3)
	_ladder._physics_process(0.3)
	assert_eq(_player.net_position, _ladder.top_landing)
	assert_true(_player.is_physics_processing())
	assert_eq(_player.net_velocity, Vector3.ZERO)


func test_session_change_releases_player() -> void:
	_move(_ladder.bottom_landing)
	_player.set_physics_process(true)
	_ladder.use()
	_ladder._reset(Network.Mode.OFFLINE)
	assert_true(_player.is_physics_processing())
	assert_null(_ladder._player)
