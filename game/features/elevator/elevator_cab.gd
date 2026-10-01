class_name ElevatorCab
extends Node3D
## Stationary cab controller. Fixed structure belongs to the GridMap; only leaves move.
## Optional departures transfer occupants after the door aperture reaches zero.

enum State { CLOSED, OPENING, OPEN, CLOSING }

const ElevatorMath := preload("res://features/elevator/elevator_math.gd")
const DOOR_SLIDE_S := 1.1
const BOARDING_S := 4.5
const CAB_HALF_WIDTH := 1.4
const CAB_HALF_DEPTH := 1.35
const CAB_HEIGHT := 2.9
const DOOR_CLOSED_X := 0.75
const DOOR_MAX_OFFSET := 1.5

@export var destination: NodePath
@export var travel_enabled := false
@export var sign_text := "ELEVATOR"
@export var net_state: State = State.CLOSED
@export var net_aperture := 0.0

var _state_elapsed := 0.0
var _trip_pending := false

@onready var entity: NetworkedEntity = $NetworkedEntity
@onready var car: Node3D = $Car
@onready var _door_left: Node3D = $Car/Doors/LeftLeaf
@onready var _door_right: Node3D = $Car/Doors/RightLeaf


func _ready() -> void:
	($Car/Sign as Label3D).text = sign_text
	entity.session_reset.connect(_reset)
	entity.event_received.connect(_event)
	_update_doors()


func _physics_process(delta: float) -> void:
	if entity.is_authority():
		_server_advance(delta)
	_update_doors()


## Both hall and cab plates use the same authenticated interaction policy.
func request_doors() -> bool:
	if not entity.is_authority():
		return false
	if net_state == State.CLOSED:
		_trip_pending = true
		_open()
		return true
	if net_state == State.OPEN and not doorway_occupied():
		net_state = State.CLOSING
		_trip_pending = true
		_state_elapsed = 0.0
		return true
	return false


## Arrival never moves this cab, and does not schedule a return trip on its own.
func server_arrive() -> void:
	if entity.is_authority():
		_trip_pending = false
		_open()


func _open() -> void:
	net_state = State.OPENING
	_state_elapsed = 0.0
	entity.send_event(&"arrival_bell")


func _server_advance(delta: float) -> void:
	if not entity.is_authority():
		return
	match net_state:
		State.OPENING:
			net_aperture = move_toward(net_aperture, 1.0, delta / DOOR_SLIDE_S)
			if net_aperture >= 1.0:
				net_state = State.OPEN
				_state_elapsed = 0.0
		State.OPEN:
			_state_elapsed += delta
			if _state_elapsed >= BOARDING_S:
				if doorway_occupied():
					_state_elapsed = 0.0
				else:
					net_state = State.CLOSING
		State.CLOSING:
			if doorway_occupied():
				_open()
				return
			net_aperture = move_toward(net_aperture, 0.0, delta / DOOR_SLIDE_S)
			if net_aperture <= 0.0:
				_depart()


func _depart() -> void:
	net_state = State.CLOSED
	_state_elapsed = 0.0
	if not travel_enabled or not _trip_pending or destination.is_empty():
		return
	var arrival := get_node_or_null(destination) as ElevatorCab
	if arrival == null or arrival == self or arrival.net_state != State.CLOSED:
		return
	var occupants := _collect_occupants()
	for player: Player in occupants:
		var offset := ElevatorMath.relative_offset(player.net_position, car.global_transform)
		var yaw := ElevatorMath.relative_yaw(player.net_yaw, car.global_transform)
		player.server_teleport.rpc_id(
			player.get_multiplayer_authority(),
			ElevatorMath.apply_offset(offset, arrival.car.global_transform),
			ElevatorMath.apply_yaw(yaw, arrival.car.global_transform)
		)
	if not occupants.is_empty():
		arrival.server_arrive()


func _collect_occupants() -> Array[Player]:
	var occupants: Array[Player] = []
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null:
			var local := car.to_local(player.net_position)
			if ElevatorMath.is_inside(local, CAB_HALF_WIDTH, CAB_HALF_DEPTH, CAB_HEIGHT):
				occupants.append(player)
	return occupants


func doorway_occupied() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player == null:
			continue
		var local := car.to_local(player.net_position)
		var radius := player.movement.hull_radius_m()
		if (
			absf(local.x) < 1.5 + radius
			and absf(local.z - CAB_HALF_DEPTH) < radius + 0.12
			and local.y > -0.2
			and local.y < CAB_HEIGHT
		):
			return true
	return false


func _update_doors() -> void:
	var offset := ElevatorMath.door_leaf_offset(net_aperture, DOOR_MAX_OFFSET)
	_door_left.position.x = -DOOR_CLOSED_X - offset
	_door_right.position.x = DOOR_CLOSED_X + offset


func _reset(_mode: Network.Mode) -> void:
	net_state = State.CLOSED
	net_aperture = 0.0
	_trip_pending = false
	_state_elapsed = 0.0
	_update_doors()


func _event(event: StringName, _payload: Dictionary) -> void:
	if event == &"arrival_bell":
		GameAudio.play_at(self, &"elevator_ding", global_position)
