extends Node
## Real WebSocket clients exercise the inherited RoomDoor RPC and dynamic floor spawn.

@onready var _home: Apartments = $Game/Features/apartments


func _ready() -> void:
	$Game/Features/character_memory.queue_free()
	if Network.args.has("apartment-role"):
		_run()


func _run() -> void:
	var player: Player
	while player == null:
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group(&"local_player") as Player
	player.set_physics_process(false)
	var peer := multiplayer.get_unique_id()
	var desk := _home.get_node("Lobby/Desk")
	var lift := _home.get_node("Lobby/Elevator") as RoomDoor
	if Network.args["apartment-role"] == "observer":
		while _home.assignments.is_empty() or _home.floors.get_child_count() == 0:
			await get_tree().process_frame
		_check(_home.unit_for(peer) == 0, "observer starts without a reservation")
		_check(
			not (_home.floors.get_child(0) as StreamedRoom).is_loaded(), "late floor stays unloaded"
		)
		desk.request_room.rpc_id(1)
		await get_tree().create_timer(0.4).timeout
		_check(_home.unit_for(peer) == 0, "remote desk request rejected")
		print("LATE_OK")
	else:
		_move(player, (_home.get_node("Entrance") as Node3D).global_position + Vector3(0, 0, -1))
		await get_tree().create_timer(0.3).timeout
		(_home.get_node("Entrance") as RoomDoor).use()
		await get_tree().create_timer(0.4).timeout
		_check((_home.get_node("Lobby") as StreamedRoom).contains(player.net_position), "entrance")
	_move(player, (desk as Node3D).global_position + Vector3(0, 0, 1.5))
	await get_tree().create_timer(0.3).timeout
	desk.use()
	while _home.floor_for(peer) == null:
		await get_tree().process_frame
	print("CLAIMED")
	var unit := _home.unit_for(peer)
	desk.use()
	await get_tree().create_timer(0.2).timeout
	_check(_home.unit_for(peer) == unit, "repeat claim")
	_move(player, lift.global_position + Vector3(0, 0, 1.5))
	await get_tree().create_timer(0.3).timeout
	lift.use()
	var floor_node := _home.floor_for(peer)
	_check(floor_node.is_loaded(), "floor preloaded synchronously")
	await get_tree().create_timer(0.5).timeout
	_check(floor_node.contains(player.net_position), "arrived on assigned floor")
	var back := floor_node.get_node("Elevator") as RoomDoor
	back.use()
	await get_tree().create_timer(0.5).timeout
	_check((_home.get_node("Lobby") as StreamedRoom).contains(player.net_position), "return lift")
	await get_tree().create_timer(3.2).timeout
	_check(not floor_node.is_loaded(), "floor unloaded after leaving")
	print("APARTMENT_DONE")


func _move(player: Player, point: Vector3) -> void:
	player.position = point
	player.net_position = point


func _check(ok: bool, message: String) -> void:
	if not ok:
		push_error("Apartment probe: " + message)
		get_tree().quit(1)
