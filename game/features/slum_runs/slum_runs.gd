class_name SlumRuns
extends Node3D
## The server's current shared excursion. Everyone who enters while a run is
## active lands on the same map, so they can search, ambush and escape together.

const SlumDestinations := preload("res://features/dev_elevator/slum_destinations.gd")

var _active_peers: Dictionary = {}
var _arrival: SlumArrivalPoint


func _ready() -> void:
	add_to_group(&"slum_runs")
	var combat := get_tree().get_first_node_in_group(&"combat") as Combat
	if combat != null:
		combat.player_died.connect(_on_player_died)
	multiplayer.peer_disconnected.connect(finish)
	Network.mode_changed.connect(_on_mode_changed)


func choose_arrival() -> SlumArrivalPoint:
	return _arrival if _arrival != null else SlumDestinations.pick(get_tree())


func begin(peer_id: int, arrival: SlumArrivalPoint) -> void:
	if not multiplayer.is_server() or arrival == null:
		return
	if _active_peers.is_empty():
		LootContainer.reset_all(get_tree())
		_arrival = arrival
	_active_peers[peer_id] = true


func finish(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_active_peers.erase(peer_id)
	if _active_peers.is_empty():
		_arrival = null


func is_active(peer_id: int) -> bool:
	return _active_peers.has(peer_id)


func _on_player_died(victim_peer: int, _attacker_peer: int) -> void:
	if not multiplayer.is_server() or not is_active(victim_peer):
		return
	var hand := Hand.for_peer(get_tree(), victim_peer)
	var player := _player_for_peer(victim_peer)
	if hand != null and player != null:
		hand.inventory().drop_valuables(player.net_position)
	finish(victim_peer)


func _on_mode_changed(_mode: Network.Mode) -> void:
	_active_peers.clear()
	_arrival = null


func _player_for_peer(peer_id: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == peer_id:
			return player
	return null
