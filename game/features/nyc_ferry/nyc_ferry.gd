extends AnimatableBody3D
## A small ferry that cruises back and forth between two docks in the room, carrying
## whoever is standing on deck. A player can take the wheel to drive it manually.
##
## Server-authoritative: the server owns `_distance` (progress from dock A toward dock
## B) and writes the resulting position; `sync_to_physics` (default on for
## AnimatableBody3D) propagates that motion to any CharacterBody3D standing on it, on
## every peer, since each peer runs the same physics world. Non-server peers just play
## back the replicated `net_position` instead of computing it themselves.
##
## With nobody driving, `_distance` follows `NycFerryPath`'s timeline. Taking the wheel
## (the Use interaction) freezes the timeline and steers `_distance` directly from the
## driver's move_forward/move_back input, sent to the server as `_throttle`. Letting go
## converts the current distance and direction back into an equivalent elapsed time
## (`NycFerryPath.elapsed_for_distance`) so the schedule resumes without a jump.

const ROUTE_LENGTH_M := 30.0
const SPEED_MPS := 3.0
const DOCK_WAIT_S := 3.0
const USE_RANGE_M := 4.0

## Replicated state (server -> everyone). See the synchronizer config in feature.tscn.
@export var net_position := Vector3.ZERO
## 0 when nobody is driving, otherwise the driver's peer id.
@export var driver_peer_id := 0

var _dock_a := Vector3.ZERO
var _dock_b := Vector3.ZERO
var _elapsed := 0.0
var _distance := 0.0
var _direction := 1
var _throttle := 0.0
var _last_sent_throttle := 0.0


func _ready() -> void:
	add_to_group(&"interactables")
	_dock_a = global_position
	_dock_b = _dock_a + Vector3(0.0, 0.0, ROUTE_LENGTH_M)
	net_position = _dock_a
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Network.mode_changed.connect(_on_mode_changed)


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		if driver_peer_id != 0:
			_advance_manual(delta)
		else:
			_advance_auto(delta)
		global_position = _dock_a.lerp(_dock_b, _distance / ROUTE_LENGTH_M)
		net_position = global_position
	else:
		global_position = net_position


func _process(_delta: float) -> void:
	if driver_peer_id == 0 or driver_peer_id != multiplayer.get_unique_id():
		return
	var throttle := _local_throttle_input()
	if not is_equal_approx(throttle, _last_sent_throttle):
		_last_sent_throttle = throttle
		submit_throttle.rpc_id(1, throttle)


func interaction_text() -> String:
	return "Let go of the wheel" if driver_peer_id != 0 else "Take the wheel"


func can_use(player: Player) -> bool:
	if driver_peer_id == player.get_multiplayer_authority():
		return true
	if driver_peer_id != 0:
		return false
	return player.net_position.distance_to(_helm_position()) <= USE_RANGE_M


func use() -> void:
	request_toggle_drive.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func request_toggle_drive() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender != 0 else multiplayer.get_unique_id()
	if driver_peer_id == peer_id:
		_stop_driving()
		return
	if driver_peer_id != 0:
		return
	var player := _player_for_peer(peer_id)
	if player == null or not can_use(player):
		return
	driver_peer_id = peer_id
	_throttle = 0.0


@rpc("any_peer", "call_local", "reliable")
func submit_throttle(throttle: float) -> void:
	if not multiplayer.is_server() or driver_peer_id == 0:
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender != 0 else multiplayer.get_unique_id()
	if peer_id != driver_peer_id:
		return
	_throttle = clampf(throttle, -1.0, 1.0)


func _stop_driving() -> void:
	driver_peer_id = 0
	_throttle = 0.0
	_last_sent_throttle = 0.0
	_elapsed = NycFerryPath.elapsed_for_distance(
		_distance, _direction, ROUTE_LENGTH_M, SPEED_MPS, DOCK_WAIT_S
	)


func _advance_auto(delta: float) -> void:
	_elapsed += delta
	var next := NycFerryPath.distance_along_route(_elapsed, ROUTE_LENGTH_M, SPEED_MPS, DOCK_WAIT_S)
	if not is_equal_approx(next, _distance):
		_direction = 1 if next > _distance else -1
	_distance = next


func _advance_manual(delta: float) -> void:
	if _throttle == 0.0:
		return
	_distance = clampf(_distance + _throttle * SPEED_MPS * delta, 0.0, ROUTE_LENGTH_M)
	_direction = 1 if _throttle > 0.0 else -1


func _local_throttle_input() -> float:
	if not Controls.gameplay_active():
		return 0.0
	var throttle := 0.0
	if Input.is_action_pressed(&"move_forward"):
		throttle += 1.0
	if Input.is_action_pressed(&"move_back"):
		throttle -= 1.0
	return throttle


func _helm_position() -> Vector3:
	return to_global(Vector3(0, 1.0, -0.2))


func _player_for_peer(peer_id: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == peer_id:
			return player
	return null


func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server() and driver_peer_id == peer_id:
		_stop_driving()


func _on_mode_changed(_mode: Network.Mode) -> void:
	# Do not carry a driver claim from a previous offline/online session.
	driver_peer_id = 0
	_throttle = 0.0
	_last_sent_throttle = 0.0
	_elapsed = 0.0
	_distance = 0.0
	_direction = 1
	global_position = _dock_a
	net_position = _dock_a
