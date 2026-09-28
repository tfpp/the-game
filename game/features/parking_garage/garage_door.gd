class_name GarageDoor
extends CSGBox3D
## A one-way step-through link to a `Marker3D` named by `destination`. Unlike
## the elevator (features/elevator/elevator_cab.gd) there is no cab or boarding
## window to keep in sync, so the server just teleports the requester straight
## to the marker the instant it validates the request.

const USE_RANGE_M := 2.5

@export var destination: NodePath
@export var door_label: String = "Enter"

@onready var _arrival: Marker3D = get_node(destination)


func _ready() -> void:
	add_to_group(&"interactables")


func interaction_text() -> String:
	return door_label


func can_use(player: Player) -> bool:
	return global_position.distance_to(player.net_position) <= USE_RANGE_M


func use() -> void:
	request_enter.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func request_enter() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender != 0 else multiplayer.get_unique_id()
	var player := _player_for_peer(peer_id)
	if player == null or not can_use(player):
		return
	var arrival_yaw := _arrival.global_transform.basis.get_euler().y
	player.server_teleport.rpc_id(
		player.get_multiplayer_authority(), _arrival.global_position, arrival_yaw
	)


func _player_for_peer(peer_id: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == peer_id:
			return player
	return null
