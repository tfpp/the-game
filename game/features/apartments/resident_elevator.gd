extends RoomDoor
## A resident-keyed express lift. Reuse RoomDoor's preload and server teleport.

@onready var apartments: Apartments = get_parent().get_parent()


func interaction_text() -> String:
	var unit := apartments.unit_for(multiplayer.get_unique_id())
	if unit == 0:
		return "Elevator: speak to the front desk first"
	return (
		"Express elevator: floor %d, unit %s"
		% [Apartments.floor_number(unit), Apartments.unit_label(unit)]
	)


func use() -> void:
	if _select_arrival(multiplayer.get_unique_id()):
		super.use()


@rpc("any_peer", "call_local", "reliable")
func request_enter() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer := sender if sender != 0 else multiplayer.get_unique_id()
	if _select_arrival(peer):
		super.request_enter()


func _select_arrival(peer: int) -> bool:
	var floor_node := apartments.floor_for(peer)
	if floor_node == null:
		return false
	_arrival = floor_node.get_node("Arrival") as Marker3D
	return true
