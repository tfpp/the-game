extends Node
## Exercise real authenticated peers against the production room and portal paths.

var _player: Player
var _role := ""
var _stop := ""
var _result := -1
var _paused := false
var _seen_visitor := false
@onready var _feature: Node3D = $Game/Features/hotel_props
@onready var _room: StreamedRoom = $Game/Features/hotel_props/Room
@onready var _entrance: RoomDoor = $Game/Features/hotel_props/Entrance
@onready var _exit: RoomDoor = $Game/Features/hotel_props/Room/Return


func _ready() -> void:
	$Game/Features/character_memory.queue_free()
	_role = str(Network.args.get("hotel-props-role", "server"))
	_stop = str(Network.args.get("probe-stop", ""))
	for door: RoomDoor in [_entrance, _exit]:
		(door.get_node("NetworkedEntity") as NetworkedInteraction).request_finished.connect(
			func(_action: StringName, result: NetworkedEntity.Result) -> void: _result = result
		)
	_run.call_deferred()


func _process(_delta: float) -> void:
	if _role == "server":
		assert(not _room.is_loaded(), "Dedicated server must not instantiate the interior")
		for player: Player in $Game.get_players():
			if _room.contains(player.net_position) and not _seen_visitor:
				_seen_visitor = true
				print("HOTEL_SERVER_VISITOR")
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
	assert(not _room.is_loaded(), "A new peer starts outside the showroom")
	_move(Vector3(2, 1, 5))
	await get_tree().create_timer(0.8).timeout
	_result = -1
	var entity := _entrance.get_node("NetworkedEntity") as NetworkedInteraction
	entity.request_use()
	await _wait(func() -> bool: return _result >= 0)
	assert(_result == NetworkedEntity.Result.DENIED)
	assert(_player.net_position.is_equal_approx(Vector3(2, 1, 5)))
	_move((_feature.get_node("CasinoArrival") as Marker3D).global_position)
	await get_tree().create_timer(0.8).timeout
	_result = -1
	entity.request_action(&"use", {"peer_id": 1})
	await _wait(func() -> bool: return _result >= 0)
	assert(_result == NetworkedEntity.Result.DENIED)
	_entrance.use()
	assert(_room.is_loaded(), "Floor preloaded synchronously before request")
	await _wait(
		func() -> bool:
			return (
				_player.net_position.distance_to(
					(_room.get_node("Arrival") as Marker3D).global_position
				)
				< 0.02
			)
	)
	assert(_room.get_node("Content/Props").get_child_count() == 50)
	if _role == "driver":
		print("HOTEL_DRIVER_ENTERED")
		await _wait(func() -> bool: return FileAccess.file_exists(_stop + ".late"))
	await _return_to_dev_room()
	if _role == "late":
		print("HOTEL_LATE_PASS")
	else:
		print("HOTEL_DRIVER_PASS")


func _return_to_dev_room() -> void:
	_move(_exit.global_position - Vector3(0, 0, 1.5))
	await get_tree().create_timer(0.8).timeout
	_exit.use()
	await _wait(
		func() -> bool:
			return (
				_player.net_position.distance_to(
					(_feature.get_node("CasinoArrival") as Marker3D).global_position
				)
				< 0.02
			)
	)
	await get_tree().create_timer(3.2).timeout
	assert(not _room.is_loaded(), "Showroom unloaded after return")


func _move(at: Vector3) -> void:
	_player.global_position = at
	_player.net_position = at
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


func _wait(condition: Callable) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while not condition.call():
		if Time.get_ticks_msec() >= deadline:
			push_error("Hotel props network probe timed out: " + _role)
			get_tree().quit(1)
			return
		await get_tree().process_frame
