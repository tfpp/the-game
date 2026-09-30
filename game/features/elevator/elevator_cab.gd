class_name ElevatorCab
extends Node3D
## One elevator cab built into a wall, dressed in the painted service-elevator models
## from features/procedural_rooms. `feature.tscn` instances this scene twice — a casino
## cab in the south lobby wall and a garage cab on B1 — each pointing at the other
## through `destination`. The cab never moves: press the call button, its doors open,
## board within the boarding window, the doors close with a ding, and everyone who was
## inside reappears inside the other cab in the same relative arrangement, facing the
## same way relative to the cab (see `ElevatorMath.relative_offset`/`apply_offset` and
## `relative_yaw`/`apply_yaw`), whose doors then open to reveal them.
##
## Server-authoritative: `net_state` is the only replicated property (see the
## synchronizer in elevator_cab.tscn). The server alone drives `_state_elapsed` and
## decides who boarded; every peer, including the server, separately drives its own
## `_visual_elapsed` purely to animate the doors and cue the ding the instant it
## observes `net_state` change, the same way remote players are smoothed locally
## instead of over the network.

enum State { CLOSED, OPENING, OPEN, CLOSING }

const ElevatorMath := preload("res://features/elevator/elevator_math.gd")

const DOOR_SLIDE_S := 1.1
const BOARDING_S := 4.5
const CALL_RANGE_M := 3.2
## Boarding footprint around the cab origin: the model's 3 m wide interior, from the
## back wall up to the door leaves at local z 1.35.
const CAB_HALF_WIDTH := 1.4
const CAB_HALF_DEPTH := 1.35
const CAB_HEIGHT := 2.9
## Door leaves (elevator_door_model.tscn) meet at x ±0.75 and retract into the wall.
const DOOR_CLOSED_X := 0.75
const DOOR_MAX_OFFSET := 1.5

## Sibling cab occupants are sent to when this cab departs.
@export var destination: NodePath
## Finish on the surrounding wall block, matching the wall the cab is built into.
@export var shell_material: Material
## Text over the doors, seen from outside.
@export_multiline var sign_text := "ELEVATOR"
## Height of the surrounding wall block, up to the ceiling it tucks under.
@export var shell_height := 7.98

## Replicated state (server -> everyone). See the synchronizer config in elevator_cab.tscn.
@export var net_state: State = State.CLOSED

var _state_elapsed := 0.0
var _visual_state: State = State.CLOSED
var _visual_elapsed := 0.0

@onready var _door_left: Node3D = $Doors/LeftLeaf
@onready var _door_right: Node3D = $Doors/RightLeaf
@onready var _destination_cab: Node3D = get_node_or_null(destination) as Node3D


func _ready() -> void:
	add_to_group(&"interactables")
	($Sign as Label3D).text = sign_text
	var block := $Shell/Block as CSGBox3D
	block.size.y = shell_height
	block.position.y = shell_height * 0.5
	if shell_material != null:
		for part: Node in $Shell.get_children():
			(part as CSGPrimitive3D).material = shell_material


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_server_advance(delta)


func _process(delta: float) -> void:
	if net_state != _visual_state:
		_visual_state = net_state
		_visual_elapsed = 0.0
		if net_state == State.OPENING:
			GameAudio.play_at(self, &"elevator_ding", global_position)
	else:
		_visual_elapsed += delta
	_update_doors()


func interaction_text() -> String:
	return "Call elevator" if net_state == State.CLOSED else "Elevator busy"


func can_use(player: Player) -> bool:
	return (
		net_state == State.CLOSED
		and global_position.distance_to(player.net_position) <= CALL_RANGE_M
	)


func use() -> void:
	request_call.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func request_call() -> void:
	if not multiplayer.is_server() or net_state != State.CLOSED:
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender != 0 else multiplayer.get_unique_id()
	var player := _player_for_peer(peer_id)
	if player == null or not can_use(player):
		return
	_open()


## Called by the departing cab on the server when it delivers occupants here. Reopens
## this cab to reveal them, unless it's already mid-cycle from its own call.
func server_arrive() -> void:
	if not multiplayer.is_server():
		return
	if net_state == State.CLOSED or net_state == State.CLOSING:
		_open()


func _open() -> void:
	net_state = State.OPENING
	_state_elapsed = 0.0


func _server_advance(delta: float) -> void:
	if net_state == State.CLOSED:
		return
	_state_elapsed += delta
	match net_state:
		State.OPENING:
			if _state_elapsed >= DOOR_SLIDE_S:
				net_state = State.OPEN
				_state_elapsed = 0.0
		State.OPEN:
			if _state_elapsed >= BOARDING_S:
				net_state = State.CLOSING
				_state_elapsed = 0.0
		State.CLOSING:
			if _state_elapsed >= DOOR_SLIDE_S:
				_depart()


func _depart() -> void:
	var occupants := _collect_occupants()
	net_state = State.CLOSED
	_state_elapsed = 0.0
	if occupants.is_empty() or _destination_cab == null:
		return
	var origin_transform := global_transform
	var destination_transform := _destination_cab.global_transform
	for player in occupants:
		var offset := ElevatorMath.relative_offset(player.net_position, origin_transform)
		var arrival := ElevatorMath.apply_offset(offset, destination_transform)
		var yaw_offset := ElevatorMath.relative_yaw(player.net_yaw, origin_transform)
		var arrival_yaw := ElevatorMath.apply_yaw(yaw_offset, destination_transform)
		player.server_teleport.rpc_id(player.get_multiplayer_authority(), arrival, arrival_yaw)
	_destination_cab.call(&"server_arrive")


func _collect_occupants() -> Array[Player]:
	var occupants: Array[Player] = []
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player == null:
			continue
		var local := ElevatorMath.relative_offset(player.net_position, global_transform)
		if ElevatorMath.is_inside(local, CAB_HALF_WIDTH, CAB_HALF_DEPTH, CAB_HEIGHT):
			occupants.append(player)
	return occupants


func _player_for_peer(peer_id: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == peer_id:
			return player
	return null


func _update_doors() -> void:
	var t := 0.0
	match _visual_state:
		State.OPENING:
			t = ElevatorMath.door_fraction(_visual_elapsed, DOOR_SLIDE_S, true)
		State.OPEN:
			t = 1.0
		State.CLOSING:
			t = ElevatorMath.door_fraction(_visual_elapsed, DOOR_SLIDE_S, false)
		State.CLOSED:
			t = 0.0
	var offset := ElevatorMath.door_leaf_offset(t, DOOR_MAX_OFFSET)
	_door_left.position.x = -DOOR_CLOSED_X - offset
	_door_right.position.x = DOOR_CLOSED_X + offset
