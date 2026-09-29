extends Node
## Full-world visual/physics check, or real network round trip with a late observer.

var _player: Player
@onready var _feature: Node3D = $Game/Features/hotel_annex
@onready var _hotel: StreamedRoom = $Game/Features/hotel_annex/Hotel
@onready var _entrance: RoomDoor = $Game/Features/hotel_annex/Entrance
@onready var _exit: RoomDoor = $Game/Features/hotel_annex/Hotel/Return


func _ready() -> void:
	$Game/Features/character_memory.queue_free()
	_run.call_deferred()


func _run() -> void:
	var role := str(Network.args.get("hotel-role", "visual"))
	if role == "server":
		await get_tree().create_timer(8).timeout
		assert(not _hotel.is_loaded())
		assert(not (_feature.get_node("Atrium") as StreamedRoom).is_loaded())
		print("SERVER_UNLOADED")
		return
	while _player == null:
		_player = get_tree().get_first_node_in_group(&"local_player") as Player
		await get_tree().process_frame
	_player.set_physics_process(false)
	# Headless has no mouse capture; activate the controller Use path there.
	if DisplayServer.get_name() == "headless":
		Controls.device = Controls.Device.GAMEPAD
	Controls.start()
	_move(Vector3(2, 1, 5))
	await get_tree().create_timer(0.6).timeout
	_entrance.request_enter.rpc_id(1)
	_exit.request_enter.rpc_id(1)
	(_hotel.get_node("AtriumEntrance") as RoomDoor).request_enter.rpc_id(1)
	(_feature.get_node("Atrium/Return") as RoomDoor).request_enter.rpc_id(1)
	await get_tree().create_timer(0.5).timeout
	assert(_player.net_position.is_equal_approx(Vector3(2, 1, 5)))
	print("RANGE_REJECTED")
	if role == "observer":
		await get_tree().create_timer(6).timeout
		assert(_player.net_position.is_equal_approx(Vector3(2, 1, 5)))
		assert(not _hotel.is_loaded())
		print("OBSERVER_UNCHANGED")
		return
	_move((_feature.get_node("CasinoArrival") as Marker3D).global_position, PI)
	await get_tree().create_timer(0.5).timeout
	_check_floor_and_hull()
	if role == "visual":
		var cycle := $Game/Features/day_night
		cycle.set_process(false)
		cycle.call("_apply", 0.5)
		_move(Vector3(5, 1, 25), PI)
		await _capture("entrance")
		_move(Vector3(5, 1, 27), PI)
	_use(_entrance)
	assert(_hotel.is_loaded(), "Collision built before sending RPC")
	await get_tree().create_timer(0.6).timeout
	assert(_player.net_position.distance_to(_hotel.to_global(Vector3(8.75, 1, 2.2))) < 0.02)
	assert(absf(absf(_player.net_yaw) - PI) < 0.01)
	_check_floor_and_hull()
	await _check_radar(true)
	print("HOTEL_ENTERED")
	if role == "driver":
		while get_tree().get_nodes_in_group(&"players").size() < 2:
			await get_tree().process_frame
		await get_tree().create_timer(2).timeout
		await _visit_atrium()
	else:
		_move(_hotel.to_global(Vector3(7.5, 1, 7.5)), 0.9)
		await _capture("room")
		_move(_hotel.to_global(Vector3(6.5, 1, 11)), PI)
		await _capture("hallway")
		_move(_hotel.to_global(Vector3(5, 1, 30)), PI / 2)
		await _capture("junction")
		_move(_hotel.to_global(Vector3(27, 3.5, 13)), -PI / 2)
		await _capture("conservatory")
		_move(_hotel.to_global(Vector3(-14, 1, 14)), PI / 2)
		await _capture("reading-room")
		_move(_hotel.to_global(Vector3(3.4, 1.3, 5)), PI / 2)
		await _capture("windows")
		$Game/Features/day_night.call("_apply", 0.0)
		await _capture("night")
		_move(_hotel.to_global(Vector3(7.5, 1, 7.5)), 0.9)
		await _capture("room-night")
		$Game/Features/flashlight.request_toggle()
		await _capture("flashlight")
		$Game/Features/flashlight.request_toggle()
		_move(_hotel.to_global(Vector3(8.75, 1, 2.2)))
		await _capture("return")
	_use(_exit)
	await get_tree().create_timer(0.6).timeout
	assert(_player.net_position.distance_to(Vector3(5, 1, 27)) < 0.02)
	assert(absf(_player.net_yaw) < 0.01)
	_check_floor_and_hull()
	await get_tree().create_timer(3.1).timeout
	assert(not _hotel.is_loaded())
	await _check_radar(false)
	print("ROUND_TRIP_UNLOADED")
	_use(_entrance)
	await get_tree().create_timer(0.6).timeout
	assert(_hotel.is_loaded() and _hotel.contains(_player.global_position))
	print("REENTRY_PASSED")
	await _check_radar(true)
	if role == "visual":
		get_tree().quit()


func _check_radar(in_hotel: bool) -> void:
	await get_tree().create_timer(1.2).timeout
	var radar: Control = $Game/Features/radar/Map
	if radar._mobile:
		return
	assert(radar._geometry != null and not radar._geometry.floors.is_empty())
	assert(not radar._geometry.walls.is_empty())
	var found_hotel := false
	for point: Vector2 in radar._geometry.floors:
		if point.y < -1300:
			found_hotel = true
	assert(found_hotel == in_hotel, "Radar follows streamed hotel entry, exit and re-entry")


func _visit_atrium() -> void:
	var atrium := _feature.get_node("Atrium") as StreamedRoom
	_move((_hotel.get_node("AtriumArrival") as Marker3D).global_position)
	await get_tree().create_timer(0.6).timeout
	_use(_hotel.get_node("AtriumEntrance") as RoomDoor)
	assert(atrium.is_loaded(), "Atrium collision preloaded")
	await get_tree().create_timer(0.6).timeout
	assert(
		(
			_player.net_position.distance_to(
				(atrium.get_node("Arrival") as Marker3D).global_position
			)
			< 0.02
		)
	)
	_check_floor_and_hull()
	await get_tree().create_timer(3.1).timeout
	assert(not _hotel.is_loaded() and atrium.is_loaded())
	_move((atrium.get_node("Arrival") as Marker3D).global_position)
	await get_tree().create_timer(0.6).timeout
	_use(atrium.get_node("Return") as RoomDoor)
	assert(_hotel.is_loaded(), "Classic collision preloaded on return")
	await get_tree().create_timer(0.6).timeout
	assert(
		(
			_player.net_position.distance_to(
				(_hotel.get_node("AtriumArrival") as Marker3D).global_position
			)
			< 0.02
		)
	)
	_check_floor_and_hull()
	await get_tree().create_timer(3.1).timeout
	assert(not atrium.is_loaded())
	print("ATRIUM_ROUND_TRIP_PASSED")
	_move((_hotel.get_node("Arrival") as Marker3D).global_position)
	await get_tree().create_timer(0.6).timeout


func _use(expected: RoomDoor) -> void:
	var interaction := $Game/Features/interaction
	assert(interaction.call("_find_target") == expected, "Shared Use picks the correct hotel door")
	interaction.call("use")


func _move(at: Vector3, yaw: float = 0.0) -> void:
	_player.global_position = at
	_player.net_position = at
	_player.yaw = yaw
	_player.net_yaw = yaw
	_player.pitch = 0.0
	_player.net_pitch = 0.0
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


func _check_floor_and_hull() -> void:
	var space := _player.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(
		_player.global_position, _player.global_position + Vector3.DOWN * 2
	)
	ray.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(ray)
	assert(not hit.is_empty(), "Floor under arrival")
	assert(absf((hit.position as Vector3).y) < 0.02, "Arrival floor level")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = (_player.get_node("Collider") as CollisionShape3D).shape
	query.transform = _player.global_transform
	query.exclude = [_player.get_rid()]
	assert(space.intersect_shape(query).is_empty(), "Player hull clear of all full-game geometry")


func _capture(label: String) -> void:
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/hotel-" + label + ".png")
