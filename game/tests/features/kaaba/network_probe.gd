extends Node
## Minimal real-peer probe: production prayer scene and production player lookup.

var _role := ""
var _events := 0
var _saw_praying := false
var _saw_blessing := false
var _requested := false
var _port := 0

@onready var _prayer: KaabaPrayer = $Kaaba/Prayer


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--prayer-role="):
			_role = arg.get_slice("=", 1)
		if arg.begins_with("--prayer-port="):
			_port = int(arg.get_slice("=", 1))
	_prayer.get_node("NetworkedEntity").event_received.connect(_event)
	var peer := ENetMultiplayerPeer.new()
	if _role == "server":
		assert(peer.create_server(_port) == OK)
		multiplayer.peer_connected.connect(_add_player)
		multiplayer.peer_disconnected.connect(_remove_player)
	else:
		assert(peer.create_client("127.0.0.1", _port) == OK)
	multiplayer.multiplayer_peer = peer
	print("PROBE_READY ", _role)


func _add_player(id: int) -> void:
	var player := preload("res://core/player/player.tscn").instantiate() as Player
	player.get_node("Sync").free()
	player.name = str(id)
	player.set_multiplayer_authority(id)
	add_child(player)
	player.set_physics_process(false)
	player.net_position = _prayer.global_position + Vector3(3.5, 0.9, 0)


func _remove_player(id: int) -> void:
	get_node(str(id)).queue_free()
	assert(not _prayer.praying.has(id) and _prayer.blessings_for(id) == 0)
	print("DISCONNECT_CLEAN")


func _event(event: StringName, _payload: Dictionary) -> void:
	if event == &"prayer":
		_events += 1
		print("CHANT_EVENT")


func _process(_delta: float) -> void:
	if _role == "server":
		return
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if _role == "driver" and not _requested:
		_requested = true
		_request.call_deferred()
	if not _prayer.praying.is_empty() and not _saw_praying:
		_saw_praying = true
		print("PRAYING_REPLICATED")
	if not _prayer.blessings.is_empty() and not _saw_blessing:
		_saw_blessing = true
		assert(int(_prayer.blessings.values()[0]) == 1)
		assert(_prayer.praying.is_empty())
		assert(_events == (0 if _role.begins_with("late") else 1))
		# Client-side public mutation must be powerless.
		_prayer.consume(int(_prayer.blessings.keys()[0]))
		assert(not _prayer.blessings.is_empty())
		print("BLESSING_REPLICATED")
	if _saw_blessing and _prayer.blessings.is_empty():
		print("CLEANUP_REPLICATED")
		set_process(false)


func _request() -> void:
	await get_tree().create_timer(0.5).timeout
	var entity := _prayer.get_node("NetworkedEntity") as NetworkedInteraction
	entity.request_action(&"use", {"peer": 1})
	await get_tree().create_timer(0.3).timeout
	assert(_prayer.praying.is_empty())
	print("FORGED_REJECTED")
	_prayer.use()
	_prayer.use()
