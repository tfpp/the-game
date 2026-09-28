class_name RoomDoor
extends GarageDoor
## A GarageDoor whose destination may be inside a StreamedRoom. The server-side
## teleport is unchanged; the client just builds the destination room before
## asking, so the player never lands on missing floor.

## How long the destination stays built while the teleport RPC is in flight.
const ARRIVAL_HOLD_MSEC := 3000


func destination_room() -> StreamedRoom:
	var node := _arrival.get_parent()
	while node != null:
		if node is StreamedRoom:
			return node as StreamedRoom
		node = node.get_parent()
	return null


func use() -> void:
	var room := destination_room()
	if room != null:
		room.load_room(ARRIVAL_HOLD_MSEC)
	super.use()
