extends Node
## Remembers where a signed-in player was standing and puts them back there the next time
## they connect from the same account, instead of the usual random spawn jitter.
##
## Server-authoritative: state is only ever read or written when `multiplayer.is_server()`
## (dedicated server, or the single local peer offline). Offline play has no account, so
## `Network.peer_name` is empty there and nothing is saved or restored.
##
## Positions persist to `user://` so they also survive a server restart, best-effort;
## nothing else about the request needs `api/` or `game/core/` changes.

const SAVE_PATH := "user://character_state.json"

var _store := CharacterStateStore.new()
var _loaded := false
## peer_id -> true once this connection's restore has been attempted, so a reconnect
## with the same peer id (it won't happen, but keeps this simple) isn't restored twice.
var _restored_peers := {}

@onready var _timer: Timer = $Timer


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_timer.timeout.connect(_on_tick)


func _on_tick() -> void:
	if not multiplayer.is_server():
		return
	_ensure_loaded()
	var dirty := false
	for player: Player in get_tree().get_nodes_in_group(&"players"):
		var peer_id := int(player.name)
		var key := CharacterStateStore.normalize_key(Network.peer_name(peer_id))
		if key.is_empty():
			continue
		if not _restored_peers.has(peer_id):
			_restored_peers[peer_id] = true
			if _store.has_position(key):
				var pos := _store.get_position(key)
				player.server_teleport.rpc_id(peer_id, pos)
				print("Restoring %s to %s" % [key, pos])
			continue  # let the teleport replicate back before saving over it
		_store.set_position(key, player.net_position)
		dirty = true
	if dirty:
		_save()


func _on_peer_disconnected(peer_id: int) -> void:
	_restored_peers.erase(peer_id)


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		_store.from_json(file.get_as_text())


func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(_store.to_json())
