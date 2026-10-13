class_name Leaderboard
extends Node
## Server-owned leaderboard history. Wallets and combat remain authoritative for
## money and kill increments; this feature remembers their historical scores.
##
## `Player.jumped` (core/player/player.gd) only ever fires for the local peer's own
## player (puppets skip physics entirely), so each client reports its own jumps to
## the server with `request_record_jump`, the same any_peer-RPC-validated-by-the-
## server pattern `features/player_models` uses for body type requests.

## peer_id -> int, replicated (server -> everyone) like features/money's `balances`.
@export var jumps: Dictionary = {}

## Public display snapshots only; account IDs never replicate to clients.
@export var entries: Array[Dictionary] = []
var save_path := "user://leaderboard.json"
## The local player currently wired to `_on_local_jump`.
var _jump_listener: Player
var _history: Dictionary = {}
var _connections: Dictionary = {}
var _loaded := false
var _dirty := false
var _save_elapsed := 0.0
var _guest_serial := 0
var _kill_baselines: Dictionary = {}


func _ready() -> void:
	add_to_group(&"leaderboard")
	Network.mode_changed.connect(_reset)
	multiplayer.peer_disconnected.connect(_disconnected)
	save_path = str(Network.args.get("leaderboard-save-path", save_path))


func _process(delta: float) -> void:
	capture_players()
	if multiplayer.is_server():
		for peer: int in _connections:
			var key: String = _connections[peer]["key"]
			if key.begins_with("guest:"):
				_history[key]["online_seconds"] = float(_history[key]["online_seconds"]) + delta
	_save_elapsed += delta
	if _save_elapsed >= 5.0:
		_save_elapsed = 0.0
		_save()
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	if is_instance_valid(_jump_listener) and _jump_listener == player:
		return
	if is_instance_valid(_jump_listener) and _jump_listener.jumped.is_connected(_on_local_jump):
		_jump_listener.jumped.disconnect(_on_local_jump)
	_jump_listener = player
	if player != null:
		player.jumped.connect(_on_local_jump)


func jumps_for(peer_id: int) -> int:
	return int(jumps.get(peer_id, 0))


## Clients request their own jump be counted; the server validates the sender.
@rpc("any_peer", "call_local", "reliable")
func request_record_jump() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender != 0 else multiplayer.get_unique_id()
	if _player_for(peer_id) == null:
		return
	var next := jumps.duplicate()
	next[peer_id] = jumps_for(peer_id) + 1
	jumps = next


func _on_local_jump() -> void:
	request_record_jump.rpc_id(1)


func _reset(_mode: Network.Mode) -> void:
	_save()
	jumps = {}
	entries = []
	_history = {}
	_connections = {}
	_kill_baselines = {}
	_loaded = false
	_dirty = false
	if is_instance_valid(_jump_listener) and _jump_listener.jumped.is_connected(_on_local_jump):
		_jump_listener.jumped.disconnect(_on_local_jump)
	_jump_listener = null


func _player_for(peer: int) -> Player:
	for player: Player in get_tree().get_nodes_in_group(&"players"):
		if player.get_multiplayer_authority() == peer:
			return player
	return null


## Called by the server each frame and before opening its local panel.
func capture_players() -> void:
	if not multiplayer.is_server():
		return
	_ensure_loaded()
	var present := {}
	for player: Player in get_tree().get_nodes_in_group(&"players"):
		if player.is_queued_for_deletion():
			continue
		var peer := player.get_multiplayer_authority()
		present[peer] = true
		if not _connections.has(peer):
			var account: Dictionary = Network.peer_accounts.get(peer, {})
			var account_id := int(account.get("account_id", 0))
			_guest_serial += 1
			var key := str(account_id) if account_id > 0 else "guest:%d" % _guest_serial
			_connections[peer] = {
				"key": key, "jumps": 0, "kills": int(_kill_baselines.get(peer, 0))
			}
			if not _history.has(key):
				_history[key] = {
					"name": "",
					"money": 0,
					"jumps": 0,
					"kills": 0,
					"online_seconds": 0.0,
					"portrait": {}
				}
				_dirty = true
		var record: Dictionary = _history[_connections[peer]["key"]]
		var display_name := Network.peer_name(peer)
		if display_name.is_empty():
			display_name = LeaderboardPanel.player_label(player.display_name, peer)
		if record["name"] != display_name:
			record["name"] = display_name
			_dirty = true
		_sample(peer)
	for peer: int in _connections.keys():
		if not present.has(peer):
			_disconnected(peer)
	_publish()


func _sample(peer: int) -> void:
	var connection: Dictionary = _connections[peer]
	var record: Dictionary = _history[connection["key"]]
	var money := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	if money != null and money.balances.has(peer):
		var balance := int(money.balances[peer])
		if int(record["money"]) != balance:
			record["money"] = balance
			_dirty = true
	if money != null and not str(connection["key"]).begins_with("guest:"):
		var seconds := money.playtime_for(peer)
		if seconds >= 0:
			if seconds != int(record["online_seconds"]):
				record["online_seconds"] = seconds
				_dirty = true
	var combat := get_tree().get_first_node_in_group(&"combat") as Combat
	var counts := {"jumps": jumps_for(peer), "kills": combat.kills_for(peer) if combat else 0}
	for stat: String in counts:
		var count := int(counts[stat])
		var increase := maxi(0, count - int(connection[stat]))
		record[stat] = int(record[stat]) + increase
		connection[stat] = count
		_dirty = _dirty or increase > 0


func _publish() -> void:
	var peers := {}
	for peer: int in _connections:
		peers[_connections[peer]["key"]] = peer
	var next: Array[Dictionary] = []
	for key: String in _history:
		var row: Dictionary = _history[key].duplicate()
		row.erase("online_seconds")
		row.erase("portrait")
		row["peer"] = int(peers.get(key, 0))
		next.append(row)
	if entries != next:
		entries = next


func _disconnected(peer: int) -> void:
	if not multiplayer.is_server() or not _connections.has(peer):
		return
	_sample(peer)
	_capture_portrait(peer)
	_kill_baselines[peer] = _connections[peer]["kills"]
	_connections.erase(peer)
	# Peer IDs may be reused; jump counts belong to a connection, not an identity.
	jumps = jumps.duplicate()
	jumps.erase(peer)
	_publish()
	_save()


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if Network.mode != Network.Mode.SERVER or not FileAccess.file_exists(save_path):
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return
	var data: Dictionary = parser.data
	for key: String in data:
		var value: Variant = data[key]
		if not key.is_valid_int() or int(key) <= 0 or not value is Dictionary:
			continue
		if not value.get("name") is String:
			continue
		var valid := true
		for stat: String in ["money", "jumps", "kills"]:
			var count: Variant = value.get(stat)
			if not (count is int or count is float):
				valid = false
			elif not is_finite(float(count)) or float(count) < 0:
				valid = false
		if valid:
			_history[key] = {
				"name": value["name"],
				"money": int(value["money"]),
				"jumps": int(value["jumps"]),
				"kills": int(value["kills"]),
				"online_seconds": 0.0,
				"portrait": {}
			}
			var seconds: Variant = value.get("online_seconds", 0)
			if (seconds is int or seconds is float) and is_finite(float(seconds)):
				_history[key]["online_seconds"] = maxf(0.0, float(seconds))
			var portrait: Variant = value.get("portrait", {})
			if portrait is Dictionary and OnlineStatue.valid_portrait(portrait):
				_history[key]["portrait"] = portrait


## Server-only display snapshot; no account identifiers or client-authored scores.
## Ties retain historical insertion order, like the existing panel rankings.
func longest_online() -> Dictionary:
	if not multiplayer.is_server():
		return {}
	capture_players()
	for peer: int in _connections:
		_capture_portrait(peer)
	var best := {}
	for record: Dictionary in _history.values():
		if best.is_empty() or int(record["online_seconds"]) > int(best["seconds"]):
			best = {
				"name": record["name"],
				"seconds": int(record["online_seconds"]),
				"portrait": record["portrait"].duplicate(true)
			}
	return best


func _capture_portrait(peer: int) -> void:
	var record: Dictionary = _history[_connections[peer]["key"]]
	var portrait := OnlineStatue.portrait_for(get_tree(), peer)
	if record["portrait"] != portrait:
		record["portrait"] = portrait
		_dirty = true


func _save() -> void:
	if not _dirty or not multiplayer.is_server():
		return
	var persistent := {}
	for key: String in _history:
		if key.is_valid_int() and int(key) > 0:
			persistent[key] = _history[key]
	if persistent.is_empty():
		return
	var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if file == null:
		push_warning("Cannot save leaderboard history")
		return
	file.store_string(JSON.stringify(persistent))
	file.close()
	if DirAccess.rename_absolute(save_path + ".tmp", save_path) == OK:
		_dirty = false
	else:
		push_warning("Cannot replace leaderboard history")


func _exit_tree() -> void:
	_save()
