extends Node
## Local test only: a late client must receive the already-open door state.

const DOOR := preload("res://features/procedural_rooms/sliding_door.tscn")
var _door: ProceduralSlidingDoor
var _client := false
var _elapsed := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		get_tree().quit(1)
		return
	var peer := WebSocketMultiplayerPeer.new()
	_client = args[0] == "client"
	var error := (
		peer.create_client("ws://127.0.0.1:" + args[1])
		if _client
		else peer.create_server(int(args[1]), "127.0.0.1")
	)
	if error != OK:
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	_door = DOOR.instantiate() as ProceduralSlidingDoor
	_door.name = "PersistentDoor"
	# Server establishes an open state before the late client exists.
	_door.net_open = not _client
	add_child(_door)
	if _client:
		var result := _door.entity._evaluate(1, &"use", {})
		if result != NetworkedEntity.Result.DENIED:
			get_tree().quit(1)
			return
		print("DOOR_AUTHORITY PASS: client-side state mutation rejected")


func _process(delta: float) -> void:
	_elapsed += delta
	if _client and _door.net_open:
		print("DOOR_LATE_JOIN PASS: server's pre-existing open state replicated")
		get_tree().quit()
	elif _elapsed > 6.0:
		get_tree().quit(1 if _client else 0)
