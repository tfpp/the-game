class_name ElevatorCab
extends Node3D
## Stationary cab controller. Fixed structure belongs to the GridMap; only leaves move.
## Optional departures transfer occupants after the door aperture reaches zero.

enum State { CLOSED, OPENING, OPEN, CLOSING }
enum ExcursionRole { NONE, CROWN, RETURN }

const ElevatorMath := preload("res://features/elevator/elevator_math.gd")
const DOOR_SLIDE_S := 1.1
const BOARDING_S := 4.5
const CAB_HALF_WIDTH := 1.4
const CAB_HALF_DEPTH := 1.35
const CAB_HEIGHT := 2.9
const DOOR_CLOSED_X := 0.75
const DOOR_MAX_OFFSET := 1.5
## More riders than this keep the doors open and light the weight lamps.
const MAX_RIDERS := 4
const LAMP_ON_ENERGY := 4.0

@export var destination: NodePath
@export var travel_enabled := false
@export var excursion_role: ExcursionRole = ExcursionRole.NONE
@export var sign_text := "ELEVATOR"
@export var home_floor := "C"
@export var net_state: State = State.CLOSED
@export var net_aperture := 0.0
@export var net_overloaded := false
@export var net_riding := false
@export var net_floor := "C"

var _state_elapsed := 0.0
var _trip_pending := false
var _ride_elapsed := 0.0
var _ride_start_floor := "C"
var _ride_target_floor := "B1"
var _ride_hum: AudioStreamPlayer3D
var _shake_camera: Camera3D
var _shake_offset := Vector2.ZERO
var _shake_elapsed := 0.0

@onready var entity: NetworkedEntity = $NetworkedEntity
@onready var car: Node3D = $Car
@onready var _door_left: Node3D = $Car/Doors/LeftLeaf
@onready var _door_right: Node3D = $Car/Doors/RightLeaf
@onready var _lamp: StandardMaterial3D = (
	($Car/HallLamp/Lens as MeshInstance3D).material_override as StandardMaterial3D
)


func _ready() -> void:
	if excursion_role == ExcursionRole.CROWN:
		add_to_group(&"crown_excursion_cabs")
	net_floor = home_floor
	($Car/Sign as SignBoard).text = sign_text
	entity.session_reset.connect(_reset)
	entity.event_received.connect(_event)
	_ride_hum = AudioStreamPlayer3D.new()
	_ride_hum.name = "RideHum"
	_ride_hum.stream = ProceduralAudio.hum_loop(80.0, 1911)
	_ride_hum.bus = GameAudio.BUS
	_ride_hum.volume_db = -25.0
	_ride_hum.max_distance = 12.0
	car.add_child(_ride_hum)
	_update_doors()
	_update_lamps()
	_update_ride()


func _physics_process(delta: float) -> void:
	if entity.is_authority():
		_server_advance(delta)
		if net_riding:
			_ride_elapsed += delta
			net_floor = (
				_ride_start_floor
				if _ride_elapsed < .35
				else ("-" if _ride_elapsed < .65 else _ride_target_floor)
			)
	_update_doors()
	_update_lamps()
	_update_ride()


func _process(delta: float) -> void:
	_clear_shake()
	if not net_riding:
		_shake_elapsed = 0.0
		return
	_shake_elapsed += delta
	for player: Player in _collect_occupants():
		if player.multiplayer != multiplayer or not player.is_local():
			continue
		var camera := player.get_node_or_null("Camera") as Camera3D
		if camera == null or not camera.current:
			continue
		_shake_camera = camera
		_shake_offset = Vector2(
			sin(_shake_elapsed * 37.0) * .004, sin(_shake_elapsed * 49.0) * .006
		)
		camera.h_offset += _shake_offset.x
		camera.v_offset += _shake_offset.y
		break


func _clear_shake() -> void:
	if is_instance_valid(_shake_camera):
		_shake_camera.h_offset -= _shake_offset.x
		_shake_camera.v_offset -= _shake_offset.y
	_shake_camera = null
	_shake_offset = Vector2.ZERO


func _exit_tree() -> void:
	_clear_shake()


## Accepted excursion transfers own this state until arrival or cancellation.
func server_begin_ride(target_floor: String = "B1", start_floor: String = "") -> void:
	if entity.is_authority():
		net_riding = true
		_ride_elapsed = 0.0
		_ride_start_floor = home_floor if start_floor.is_empty() else start_floor
		_ride_target_floor = target_floor
		net_floor = _ride_start_floor


func server_end_ride() -> void:
	if entity.is_authority():
		net_riding = false
		net_floor = home_floor
		_clear_shake()


func _update_ride() -> void:
	if net_riding and not _ride_hum.playing:
		_ride_hum.play()
	elif not net_riding and _ride_hum.playing:
		_ride_hum.stop()
	for path: NodePath in [NodePath("Car/Indicator"), NodePath("Car/CabIndicator")]:
		var indicator := get_node(path) as SignBoard
		if indicator.text != net_floor:
			indicator.text = net_floor


## Both hall and cab plates use the same authenticated interaction policy.
func request_doors() -> bool:
	if not entity.is_authority() or net_riding:
		return false
	if net_state == State.CLOSED:
		_trip_pending = true
		_open()
		return true
	if net_state == State.OPEN and not doorway_occupied() and not net_overloaded:
		net_state = State.CLOSING
		_trip_pending = true
		_state_elapsed = 0.0
		return true
	return false


## Arrival never moves this cab, and does not schedule a return trip on its own.
func server_arrive() -> void:
	if entity.is_authority():
		server_end_ride()
		_trip_pending = false
		_open()


func _open() -> void:
	net_state = State.OPENING
	_state_elapsed = 0.0
	entity.send_event(&"arrival_bell")


func _server_advance(delta: float) -> void:
	if not entity.is_authority():
		return
	net_overloaded = _collect_occupants().size() > MAX_RIDERS
	match net_state:
		State.OPENING:
			net_aperture = move_toward(net_aperture, 1.0, delta / DOOR_SLIDE_S)
			if net_aperture >= 1.0:
				net_state = State.OPEN
				_state_elapsed = 0.0
		State.OPEN:
			_state_elapsed += delta
			if _state_elapsed >= BOARDING_S:
				if doorway_occupied() or net_overloaded:
					_state_elapsed = 0.0
				else:
					net_state = State.CLOSING
		State.CLOSING:
			if doorway_occupied() or net_overloaded:
				_open()
				return
			net_aperture = move_toward(net_aperture, 0.0, delta / DOOR_SLIDE_S)
			if net_aperture <= 0.0:
				_depart()


func _depart() -> void:
	net_state = State.CLOSED
	_state_elapsed = 0.0
	if excursion_role != ExcursionRole.NONE and _trip_pending:
		for node: Node in get_tree().get_nodes_in_group(&"zone_instances"):
			if node.multiplayer == multiplayer:
				node.call("depart_cab", self, _collect_occupants())
				break
		return
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
		if player != null and player.multiplayer == multiplayer:
			var local := car.to_local(player.net_position)
			if ElevatorMath.is_inside(local, CAB_HALF_WIDTH, CAB_HALF_DEPTH, CAB_HEIGHT):
				occupants.append(player)
	return occupants


func doorway_occupied() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player == null or player.multiplayer != multiplayer:
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
	var left := _door_left.position
	var right := _door_right.position
	left.x = -DOOR_CLOSED_X - offset
	right.x = DOOR_CLOSED_X + offset
	if _door_left.position != left:
		_door_left.position = left
	if _door_right.position != right:
		_door_right.position = right


func _reset(_mode: Network.Mode) -> void:
	net_state = State.CLOSED
	net_aperture = 0.0
	net_overloaded = false
	net_riding = false
	net_floor = home_floor
	_clear_shake()
	_trip_pending = false
	_state_elapsed = 0.0
	_update_doors()
	_update_lamps()
	_update_ride()


func _event(event: StringName, _payload: Dictionary) -> void:
	if event == &"arrival_bell":
		GameAudio.play_at(self, &"elevator_ding", global_position)


## Riders whose replicated position is inside the cab, as the server counts them.
func rider_count() -> int:
	return _collect_occupants().size()


func _update_lamps() -> void:
	_lamp.emission_energy_multiplier = LAMP_ON_ENERGY if net_overloaded else 0.0
