extends Node3D
## Exercise placement, saved furniture and a physical ride with assertions disabled.

const HOTEL := preload("res://features/street_hotel/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _failed := false


func _ready() -> void:
	_check(not OS.is_debug_build(), "Use an exported release")
	var hotel := HOTEL.instantiate() as Node3D
	add_child(hotel)
	var first: StreamedRoom = hotel.floors[0]
	first.load_room(3000)
	var lift := hotel.lift as ProceduralMovingLift
	_check(lift.gates.size() == 10, "All ten landing gates exist")
	_check(lift.stop_label(9) == "10", "Configured labels survive export")
	var player := PLAYER.instantiate() as Player
	player.position = lift.cab.global_position + Vector3(0, .95, -.65)
	player.net_position = player.position
	add_child(player)
	for tick: int in range(8):
		await get_tree().physics_frame
	_check(player.is_on_floor(), "Cab supports the rider")
	var requested := lift.request_floor(9)
	_check(requested, "Floor ten request executes outside assertions")
	for tick: int in range(2200):
		if lift.net_floor == 9 and lift.net_phase == ProceduralMovingLift.Phase.DOCKED:
			break
		await get_tree().physics_frame
	_check(lift.net_floor == 9, "Physical cab reaches floor ten")
	_check(lift.contains(player), "Cab carries the actual player")
	_check(player.net_position.y > 38.3, "Rider reaches the correct storey")
	var top: StreamedRoom = hotel.floors[9]
	_check(top.is_loaded(), "Destination landing loads before exit")
	if top.is_loaded():
		var positions: Dictionary[Vector3, bool] = {}
		for batch: MultiMeshInstance3D in (
			top.get_node("Content/FloorLayout/BatchedFurniture").get_children()
		):
			var buffer := batch.multimesh.buffer
			_check(
				buffer.size() == batch.multimesh.instance_count * 16,
				"Furniture buffers survive export"
			)
			for index: int in batch.multimesh.instance_count:
				var offset := index * 16
				var point := Vector3(buffer[offset + 3], buffer[offset + 7], buffer[offset + 11])
				positions[batch.position + point] = true
		_check(positions.size() > 200, "Furniture remains distributed through the rooms")
	if not _failed:
		print(
			"HOTEL_RELEASE_PASS: ten stops, physical rider, streamed landing, distributed furniture"
		)
	get_tree().quit(1 if _failed else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		push_error("HOTEL_RELEASE_FAIL: " + message)
