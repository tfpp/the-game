extends Node
## Real peers check preload, gravity, top-floor streaming and persistent guest doors.

var _player: Player
var _role := ""
var _stop := ""
var _paused := false
@onready var _hotel: Node3D = $Game/Features/street_hotel
@onready var _street: StreamedRoom = $Game/Features/street_district/Room


func _ready() -> void:
	$Game/Features/character_memory.queue_free()
	_role = str(Network.args.get("hotel-role", "server"))
	_stop = str(Network.args.get("probe-stop", ""))
	_run.call_deferred()


func _process(_delta: float) -> void:
	if _role == "server":
		for room: StreamedRoom in _hotel.floors:
			assert(not room.is_loaded(), "Dedicated server never loads hotel floor geometry")
	if not _paused and FileAccess.file_exists(_stop + ".pause"):
		get_tree().multiplayer_poll = false
		_paused = true
		print("HOTEL_PAUSED")
	if FileAccess.file_exists(_stop):
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		get_tree().quit()


func _run() -> void:
	if _role == "server":
		return
	await _wait(
		func() -> bool:
			_player = get_tree().get_first_node_in_group(&"local_player") as Player
			return _player != null
	)
	_player.set_physics_process(false)
	var first: StreamedRoom = _hotel.floors[0]
	var entrance := _hotel.get_node("StreetEntrance") as RoomDoor
	_move(entrance.global_position + Vector3(1.2, 0, 0))
	await get_tree().create_timer(.8).timeout
	entrance.use()
	assert(first.is_loaded(), "First floor preloaded before request")
	await _wait(func() -> bool: return first.contains(_player.net_position))
	await _stand(first.position.y)
	var guest := first.get_node("GuestDoors/Room102") as SwingDoor
	if _role == "driver":
		_move(first.to_global(Vector3(0, .95, 15)))
		await get_tree().create_timer(.8).timeout
		guest.use()
		await _wait(func() -> bool: return guest.net_state != SwingDoor.State.CLOSED)
		print("HOTEL_DRIVER_ENTERED")
		await _wait(func() -> bool: return FileAccess.file_exists(_stop + ".late"))
		assert(first.is_loaded(), "Another peer changing floors does not unload ours")
	else:
		await _wait(func() -> bool: return guest.net_state != SwingDoor.State.CLOSED)
		var lift := _hotel.lift as ProceduralMovingLift
		_move(lift.cab.global_position + Vector3(0, .95, -.65))
		_player.set_physics_process(true)
		await get_tree().create_timer(.8).timeout
		(lift.cab.get_node("Floor9") as Node3D).call("use")
		print("HOTEL_RIDE_UP_REQUESTED")
		await _wait(
			func() -> bool:
				return lift.net_floor == 9 and lift.net_phase == ProceduralMovingLift.Phase.DOCKED
		)
		assert(lift.contains(_player), "Physical cab carries the late peer")
		print("HOTEL_RIDE_UP_COMPLETE")
		assert(_player.is_on_floor(), "Rider retains floor support in the moving cab")
		var top: StreamedRoom = _hotel.floors[9]
		await _wait(func() -> bool: return top.is_loaded())
		_player.set_physics_process(false)
		_move(top.to_global(Vector3(6, .95, 6.8)))
		await _stand(top.position.y)
		await get_tree().create_timer(3.2).timeout
		assert(not first.is_loaded(), "Departure floor unloaded")
		assert(guest.net_state != SwingDoor.State.CLOSED, "Guest door state survives unload")
		_move(lift.cab.global_position + Vector3(0, .95, -.65))
		_player.set_physics_process(true)
		await get_tree().create_timer(.8).timeout
		(lift.cab.get_node("Floor0") as Node3D).call("use")
		print("HOTEL_RIDE_DOWN_REQUESTED")
		await _wait(
			func() -> bool:
				return lift.net_floor == 0 and lift.net_phase == ProceduralMovingLift.Phase.DOCKED
		)
		assert(lift.contains(_player), "Physical cab carries the late peer back")
		_player.set_physics_process(false)
		await _wait(func() -> bool: return first.is_loaded())
		_move(first.to_global(Vector3(6, .95, 6.8)))
		await _stand(first.position.y)
		assert(guest.net_state != SwingDoor.State.CLOSED, "Shared open door persists on return")
	_move(first.to_global(Vector3(0, 1, 1.8)))
	await get_tree().create_timer(.8).timeout
	(first.get_node("StreetReturn") as RoomDoor).use()
	assert(_street.is_loaded(), "Street floor preloads on return")
	await _wait(func() -> bool: return _street.contains(_player.net_position))
	await _stand(0)
	await get_tree().create_timer(3.2).timeout
	assert(not first.is_loaded())
	print("HOTEL_LATE_PASS" if _role == "late" else "HOTEL_DRIVER_PASS")


func _stand(floor_y: float) -> void:
	_player.set_physics_process(true)
	await get_tree().create_timer(.8).timeout
	assert(_player.is_on_floor(), "Real player stands on destination floor")
	assert(_player.net_position.y > floor_y + .5)
	_player.set_physics_process(false)


func _move(at: Vector3) -> void:
	_player.global_position = at
	_player.net_position = at
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


func _wait(condition: Callable) -> void:
	var deadline := Time.get_ticks_msec() + 90000
	while not condition.call():
		if Time.get_ticks_msec() >= deadline:
			push_error(
				(
					"Street hotel network probe timed out: %s, phase %s, floor %d, height %.2f, player %s"
					% [
						_role,
						_hotel.lift.net_phase,
						_hotel.lift.net_floor,
						_hotel.lift.net_height,
						_player.net_position
					]
				)
			)
			get_tree().quit(1)
			return
		await get_tree().process_frame
