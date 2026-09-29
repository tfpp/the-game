class_name SlumGate
extends CSGBox3D
## The public Golden Crown exit. The first player opens a shared run on a
## randomly selected slum map; later players join that same map.

const USE_RANGE_M := 2.5


func _ready() -> void:
	add_to_group(&"interactables")


func interaction_text() -> String:
	return "Leave the Crown for the slums"


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
	var runs := get_parent() as SlumRuns
	var arrival := runs.choose_arrival()
	if arrival == null:
		return
	runs.begin(peer_id, arrival)
	player.server_teleport.rpc_id(
		peer_id, arrival.global_position, arrival.global_transform.basis.get_euler().y
	)


func _player_for_peer(peer_id: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == peer_id:
			return player
	return null
