class_name GunMachineTrashCan
extends StaticBody3D
## The trash can next to the machine: discards whatever generated gun you're
## carrying (gun_machine.gd's `discard`), no refund — the only way to get rid of
## one, since firing a GunRig never empties it on its own.

const USE_RANGE := 2.5


func _ready() -> void:
	add_to_group(&"interactables")


func interaction_text() -> String:
	return "Trash your gun"


func can_use(player: Player) -> bool:
	var rig := GunRig.for_peer(player.get_tree(), player.get_multiplayer_authority())
	if rig == null or rig.net_stats.is_empty():
		return false
	return global_position.distance_to(player.net_position) <= USE_RANGE


func use() -> void:
	request_discard.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func request_discard() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender != 0 else multiplayer.get_unique_id()
	var player := _player_for_peer(peer_id)
	if player == null or not can_use(player):
		return
	var machine := get_tree().get_first_node_in_group(&"gun_machine_root")
	if machine != null:
		machine.call("discard", peer_id)


func _player_for_peer(peer_id: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == peer_id:
			return player
	return null
