class_name DevElevator
extends CSGBox3D
## Debug-only pad selects a registered slum. In the game, ZoneInstances validates
## cheats and waits for a private map to be ready before moving the player.
## Standalone pad fixtures without that service retain the authored-marker warp.

const SlumDestinations := preload("res://features/dev_elevator/slum_destinations.gd")

const USE_RANGE_M := 2.5


func _ready() -> void:
	add_to_group(&"interactables")


func interaction_text() -> String:
	return "[DEV] Warp to slum map"


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
	var arrival := SlumDestinations.pick(get_tree(), multiplayer)
	if arrival == null:
		return
	var zones := ZoneInstances.for_node(self)
	if zones != null:
		zones.enter_development_zone(player, arrival)
		return
	var arrival_yaw := arrival.global_transform.basis.get_euler().y
	player.server_teleport.rpc_id(
		player.get_multiplayer_authority(), arrival.global_position, arrival_yaw
	)


func _player_for_peer(peer_id: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if (
			player != null
			and player.multiplayer == multiplayer
			and player.get_multiplayer_authority() == peer_id
		):
			return player
	return null
