extends Node3D

@onready var apartments: Apartments = get_parent().get_parent()


func _ready() -> void:
	add_to_group(&"interactables")


func can_use(player: Player) -> bool:
	return global_position.distance_to(player.net_position) <= 2.5


func interaction_text() -> String:
	var unit := apartments.unit_for(multiplayer.get_unique_id())
	if unit == 0:
		return 'Talk to receptionist: "A free apartment, please."'
	return (
		'"Welcome! Unit %s, floor %d. Take the elevator."'
		% [Apartments.unit_label(unit), Apartments.floor_number(unit)]
	)


func use() -> void:
	request_room.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func request_room() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	apartments.claim(sender if sender != 0 else multiplayer.get_unique_id())
