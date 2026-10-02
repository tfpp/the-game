extends GutTest
## Rider limit: five riders keep the doors open and light the replicated weight lamps.

const CAB := preload("res://features/elevator/elevator_cab.tscn")
const PLAYER := preload("res://core/player/player.tscn")

var _cab: ElevatorCab
var _riders: Array[Player] = []


func before_each() -> void:
	_riders.clear()
	_cab = CAB.instantiate() as ElevatorCab
	add_child_autofree(_cab)
	_cab.set_physics_process(false)


func _board(count: int) -> void:
	for index: int in count:
		var player := PLAYER.instantiate() as Player
		player.set_multiplayer_authority(1)
		var offset := Vector3(-0.9 + 0.45 * index, 0.95, -0.5)
		player.position = _cab.car.to_global(offset)
		player.net_position = player.position
		add_child_autofree(player)
		player.set_physics_process(false)
		_riders.append(player)


func _lamp_energy(path: String) -> float:
	var lens := _cab.get_node(path) as MeshInstance3D
	return (lens.material_override as StandardMaterial3D).emission_energy_multiplier


func _open_and_wait() -> void:
	assert_true(_cab.request_doors())
	_cab._server_advance(ElevatorCab.DOOR_SLIDE_S)
	_cab._server_advance(ElevatorCab.BOARDING_S)


func test_four_riders_close_normally_with_lamps_dark() -> void:
	_board(4)
	assert_eq(_cab.rider_count(), 4)
	_open_and_wait()
	assert_false(_cab.net_overloaded)
	assert_eq(_cab.net_state, ElevatorCab.State.CLOSING)
	_cab._update_lamps()
	assert_eq(_lamp_energy("Car/HallLamp/Lens"), 0.0)


func test_five_riders_hold_doors_and_light_both_lamps() -> void:
	_board(5)
	_open_and_wait()
	assert_true(_cab.net_overloaded)
	assert_eq(_cab.net_state, ElevatorCab.State.OPEN)
	assert_false(_cab.request_doors(), "Close button refuses while overloaded")
	var hall := _cab.get_node("Car/HallButton")
	assert_string_contains(hall.interaction_text(), "Over capacity")
	_cab._update_lamps()
	assert_gt(_lamp_energy("Car/HallLamp/Lens"), 0.0)
	assert_gt(_lamp_energy("Car/CabLamp/Lens"), 0.0)


func test_rider_leaving_clears_the_lamp_and_lets_doors_close() -> void:
	_board(5)
	_open_and_wait()
	_riders[4].net_position = _cab.car.to_global(Vector3(0, 0.95, 4))
	_cab._server_advance(ElevatorCab.BOARDING_S)
	assert_false(_cab.net_overloaded)
	assert_eq(_cab.net_state, ElevatorCab.State.CLOSING)
	_cab._server_advance(ElevatorCab.DOOR_SLIDE_S)
	assert_eq(_cab.net_state, ElevatorCab.State.CLOSED)
	_cab._update_lamps()
	assert_eq(_lamp_energy("Car/CabLamp/Lens"), 0.0)


func test_boarding_a_fifth_rider_reopens_closing_doors() -> void:
	_board(4)
	_open_and_wait()
	assert_eq(_cab.net_state, ElevatorCab.State.CLOSING)
	_board(1)
	_cab._server_advance(0.1)
	assert_eq(_cab.net_state, ElevatorCab.State.OPENING)


func test_overload_flag_is_in_the_late_join_snapshot_and_resets() -> void:
	var sync := _cab.entity.get_node("Sync") as MultiplayerSynchronizer
	assert_true(sync.replication_config.property_get_spawn(NodePath(".:net_overloaded")))
	_cab.net_overloaded = true
	_cab.entity._on_session_changed(Network.Mode.OFFLINE)
	assert_false(_cab.net_overloaded)
