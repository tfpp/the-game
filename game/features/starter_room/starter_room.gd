extends Node3D
## Join/respawn floor protection before a delayed server room-assignment packet arrives.

@onready var room: StreamedRoom = $Room


func _ready() -> void:
	process_physics_priority = -100


func _physics_process(_delta: float) -> void:
	if Network.mode == Network.Mode.SERVER or room.is_loaded():
		return
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	if player != null and room.contains(player.net_position):
		room.load_room(RoomDoor.ARRIVAL_HOLD_MSEC)
