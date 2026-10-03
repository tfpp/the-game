extends Node
## Real visitor claims a balcony stool; a late visitor sees it and cannot steal it.

var _court: FoodCourt
var _index := -1
var _reply := -1


func _ready() -> void:
	$Game/Features/character_memory.queue_free()
	_court = $Game/Features/food_court as FoodCourt
	_index = _court.seats.find($Game/Room/Casino/MariachiBalcony/Stool_1/Seat)
	_check(_index >= 32, "Casino anchor registration missing")
	if multiplayer.is_server():
		_server()
	else:
		_client()


func _server() -> void:
	while _court.net_seats[_index] == 0:
		await get_tree().process_frame
	var occupant := _court.net_seats[_index]
	print("SEAT_SERVER_OCCUPIED")
	while multiplayer.get_peers().size() < 2:
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	_check(_court.net_seats[_index] == occupant, "Competing request stole seat")
	while _court.net_seats[_index] != 0:
		await get_tree().process_frame
	print("SEAT_SERVER_FREE")


func _client() -> void:
	var player: Player
	while player == null:
		player = get_tree().get_first_node_in_group(&"local_player") as Player
		await get_tree().process_frame
	_court.entity.request_finished.connect(_on_reply)
	var late: bool = Network.args.get("seat-role", "") == "late"
	if late:
		while _court.net_seats[_index] == 0:
			await get_tree().process_frame
		var occupant := _court.net_seats[_index]
		_check(occupant != multiplayer.get_unique_id(), "Late client stole initial seat")
		player.set_physics_process(false)
		player.global_position = _court.sit_position(_index) + Vector3(1, 0, 0)
		player.net_position = player.global_position
		await get_tree().create_timer(0.4).timeout
		_court.request_sit(_index)
		while _reply < 0:
			await get_tree().process_frame
		_check(_reply == NetworkedEntity.Result.DENIED, "Occupied stool request accepted")
		_check(_court.net_seats[_index] == occupant, "Late snapshot lost occupant")
		print("SEAT_LATE_REJECTED")
		while _court.net_seats[_index] != 0:
			await get_tree().process_frame
		print("SEAT_LATE_FREE")
	else:
		player.global_position = _court.sit_position(_index) + Vector3(1, 0, 0)
		player.net_position = player.global_position
		player.set_physics_process(false)
		await get_tree().create_timer(0.4).timeout
		_court.request_sit(_index)
		while not _court.is_seated(multiplayer.get_unique_id()):
			await get_tree().process_frame
		_check(not player.is_physics_processing(), "Owning visitor not pinned")
		print("SEAT_VISITOR_OCCUPIED")
		while multiplayer.get_peers().size() < 2:
			await get_tree().process_frame
		await get_tree().create_timer(2.0).timeout
		_court.request_stand()
		while _court.is_seated(multiplayer.get_unique_id()):
			await get_tree().process_frame
		while not player.is_physics_processing():
			await get_tree().process_frame
		print("SEAT_VISITOR_FREE")


func _on_reply(_action: StringName, result: NetworkedEntity.Result) -> void:
	_reply = result


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		get_tree().quit(1)
