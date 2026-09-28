class_name TeleportPortal
extends StaticBody3D
## A "Use" interactable that instantly moves whoever presses E to `destination`,
## facing `destination_yaw` — features/shooting_gallery's entrance and exit arches.
## Reuses the same server_teleport RPC features/elevator/elevator_cab.gd and
## features/combat/combat.gd use to move a player from server code (see
## game/AGENTS.md's multiplayer rules), just without an elevator's door animation.

const USE_RANGE_M := 3.0

@export var label := "Enter"
@export var destination := Vector3.ZERO
@export var destination_yaw := 0.0


func _ready() -> void:
	add_to_group(&"interactables")


func interaction_text() -> String:
	return label


func can_use(player: Player) -> bool:
	return global_position.distance_to(player.net_position) <= USE_RANGE_M


func use() -> void:
	request_teleport.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func request_teleport() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender != 0 else multiplayer.get_unique_id()
	var player := _player_for_peer(peer_id)
	if player == null or not can_use(player):
		return
	player.server_teleport.rpc_id(peer_id, destination, destination_yaw)


func _player_for_peer(peer_id: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == peer_id:
			return player
	return null
