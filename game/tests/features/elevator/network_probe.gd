extends Node3D
## Real WebSocket authority and late-join check; no game feature loader is needed.

const CAB := preload("res://features/elevator/elevator_cab.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _cab: ElevatorCab
var _rider: Player
var _client := false
var _snapshot_checked := false
var _requested := false
var _opened := false
var _elapsed := 0.0
var _accepted := false
var _denied := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 2)
	_client = args[0] == "client"
	var peer := WebSocketMultiplayerPeer.new()
	if _client:
		assert(peer.create_client("ws://127.0.0.1:" + args[1]) == OK)
		multiplayer.connected_to_server.connect(_connected)
	else:
		assert(peer.create_server(int(args[1]), "127.0.0.1") == OK)
		multiplayer.peer_connected.connect(_add_rider)
	multiplayer.multiplayer_peer = peer
	_cab = CAB.instantiate() as ElevatorCab
	_cab.name = "Cab"
	add_child(_cab)
	if not _client:
		# A late peer must see this exact aperture, rather than replaying a full close.
		_cab.set_physics_process(false)
		_cab.net_state = ElevatorCab.State.CLOSING
		_cab.net_aperture = 0.4
	else:
		assert(not _cab.request_doors(), "Clients cannot drive door state directly")
		var hall := _cab.get_node("Car/HallButton/NetworkedEntity") as NetworkedInteraction
		hall.request_finished.connect(_result)


func _connected() -> void:
	_add_rider(multiplayer.get_unique_id())


func _add_rider(peer: int) -> void:
	_rider = PLAYER.instantiate() as Player
	_rider.name = "Rider"
	_rider.set_multiplayer_authority(peer)
	_rider.position = Vector3(2, 0.95, 1.8)
	_rider.net_position = _rider.position
	add_child(_rider)
	_rider.set_physics_process(false)


func _result(_action: StringName, result: NetworkedEntity.Result) -> void:
	_accepted = _accepted or result == NetworkedEntity.Result.ACCEPTED
	_denied = _denied or result == NetworkedEntity.Result.DENIED


@rpc("any_peer", "reliable")
func _snapshot_seen() -> void:
	assert(multiplayer.is_server())
	assert(multiplayer.get_remote_sender_id() == _rider.get_multiplayer_authority())
	_cab.net_state = ElevatorCab.State.CLOSED
	_cab.net_aperture = 0.0
	_cab.set_physics_process(true)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _client and _rider != null:
		var hall := _cab.get_node("Car/HallButton/NetworkedEntity") as NetworkedInteraction
		if not _snapshot_checked and is_equal_approx(_cab.net_aperture, 0.4):
			_snapshot_checked = true
			_cab._update_doors()
			assert(
				is_equal_approx((_cab.get_node("Car/Doors/LeftLeaf") as Node3D).position.x, -1.35)
			)
			hall.request_action(&"use", {"peer": 1})
		if _snapshot_checked and _denied and not _requested:
			_requested = true
			_snapshot_seen.rpc_id(1)
		if _requested and not _accepted and _cab.net_state == ElevatorCab.State.CLOSED:
			hall.request_use()
		if _accepted and _cab.net_state == ElevatorCab.State.OPEN:
			_opened = true
		if _opened and _cab.net_state == ElevatorCab.State.CLOSED:
			assert(not _cab.travel_enabled)
			assert(_cab.global_position.is_equal_approx(Vector3.ZERO))
			assert(_rider.net_position.is_equal_approx(Vector3(2, 0.95, 1.8)))
			print(
				"ELEVATOR_NETWORK PASS: late aperture, rejected forgery, authenticated call, replicated cycle"
			)
			get_tree().quit()
	if _elapsed > 16:
		get_tree().quit(1 if _client else 0)
