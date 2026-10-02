class_name Game
extends Node3D
## Root gameplay scene. Server-authoritative orchestration:
## the server spawns/despawns one Player per peer via MultiplayerSpawner and
## enforces world rules (e.g. respawning players who fall out of the world).
## Peers only count as connected once their join ticket checks out (see Network), so
## `peer_connected` means "authenticated" and carries the account's display name.

const PLAYER_SCENE := preload("res://core/player/player.tscn")
const KILL_Y := -50.0
## The default font for every Control and Label3D without one of its own (see
## assets/fonts/README.md). Set here rather than as the project's custom font, which
## Godot loads at startup, before a fresh checkout's first import has created it.
const DEFAULT_FONT_PATH := "res://assets/fonts/inter/Inter-Regular.ttf"

@onready var _features: Node3D = $Features
@onready var _players: Node3D = $Players
@onready var _spawner: MultiplayerSpawner = $PlayerSpawner
@onready var _spawn_point: Marker3D = $Room/Spawn


func _enter_tree() -> void:
	# Before any child (HUD, world signs, features) draws text.
	ThemeDB.fallback_font = load(DEFAULT_FONT_PATH)


func _ready() -> void:
	# Before networking starts, so every peer has the same feature nodes (and their
	# spawners, synchronizers and RPC targets) before any replication arrives.
	FeatureLoader.load_features(_features)
	_spawner.spawn_function = _spawn_player
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Network.mode_changed.connect(_on_mode_changed)
	if Network.has_flag("debug-roster"):
		_start_roster_log()
	Network.start_from_environment()


func _physics_process(_delta: float) -> void:
	if not Network.is_authoritative():
		return
	for player: Player in get_players():
		if player.net_position.y < KILL_Y:
			player.server_teleport.rpc_id(player.get_multiplayer_authority(), _spawn_position())


func get_players() -> Array[Player]:
	var result: Array[Player] = []
	for child: Node in _players.get_children():
		if child is Player:
			result.append(child as Player)
	return result


func _on_mode_changed(mode: Network.Mode) -> void:
	_clear_players()
	if mode == Network.Mode.OFFLINE:
		# Offline: this process is the server and the only player (peer 1).
		_spawner.spawn({"peer": multiplayer.get_unique_id(), "position": _spawn_position()})


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var display_name := Network.peer_name(peer_id)
	print("Peer %d (%s) connected, spawning player" % [peer_id, display_name])
	_spawner.spawn({"peer": peer_id, "position": _spawn_position(), "name": display_name})


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	print("Peer %d disconnected" % peer_id)
	var node := _players.get_node_or_null(str(peer_id))
	if node:
		node.queue_free()


## Runs on every peer (spawn_function), so authority is set identically everywhere.
func _spawn_player(data: Variant) -> Node:
	var info := data as Dictionary
	var peer_id: int = info["peer"]
	var player := PLAYER_SCENE.instantiate() as Player
	player.name = str(peer_id)
	player.position = info["position"]
	player.net_position = info["position"]
	player.display_name = str(info.get("name", ""))
	player.set_multiplayer_authority(peer_id)
	return player


func _spawn_position() -> Vector3:
	var jitter := Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0))
	var feature_spawn := get_tree().get_first_node_in_group(&"player_spawn") as Marker3D
	var origin := (
		feature_spawn.global_position if feature_spawn != null else _spawn_point.global_position
	)
	return origin + jitter


## Debug aid (`-- --debug-roster`): prints who this peer sees, once per second.
## Used by scripts/net_smoke.sh to verify replication.
func _start_roster_log() -> void:
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(
		func() -> void:
			var names: Array[String] = []
			for player: Player in get_players():
				names.append("%s%s" % [player.name, "*" if player.is_local() else ""])
			print("ROSTER peer=%d players=%s" % [multiplayer.get_unique_id(), ",".join(names)])
	)
	add_child(timer)


func _clear_players() -> void:
	for child: Node in _players.get_children():
		_players.remove_child(child)
		child.queue_free()
