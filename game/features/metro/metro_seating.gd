class_name MetroSeating
extends FoodCourt
## Persistent metro seats reuse booth authority and the shared avatar/pinning contract.
## Standing before the loading handshake preserves the metro's aisle-only boarding.

const SEAT := preload("res://features/metro/metro_seat.gd")
const CUSHION_Y := 1.68
var zone: MetroZone


func _ready() -> void:
	zone = get_parent() as MetroZone
	add_to_group(&"seating")
	for point: Vector3 in layout():
		var seat := Node3D.new()
		seat.name = "Seat%d" % seats.size()
		seat.set_script(SEAT)
		seat.set("court", self)
		seat.set("index", seats.size())
		seat.position = point
		# Avatar forward is -Z: the lengthwise buckets face into the aisle.
		seat.rotation.y = signf(point.x) * PI / 2
		add_child(seat)
		seats.append(seat)
	var empty := PackedInt32Array()
	empty.resize(seats.size())
	net_seats = empty
	entity.register_action(&"sit", _may_sit, _sit)
	entity.register_action(&"stand", _may_stand, _stand)
	entity.session_reset.connect(_reset_session)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_connect_combat.call_deferred()


static func layout() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for car: int in 5:
		for side: float in [-1.0, 1.0]:
			for bay: float in [-5.0, 0.0, 5.0]:
				for offset: float in [-0.37, 0.37]:
					# Two sleeping residents use the other two left-hand buckets.
					if side < 0 and bay != 0 and offset > 0:
						continue
					points.append(
						Vector3(side, CUSHION_Y, MetroRules.car_center(car) + bay + offset)
					)
	return points


func available() -> bool:
	var t := zone.service().net_time
	if zone.station_index >= 0:
		return t < MetroRules.OPEN + MetroRules.DWELL - 2
	return t < MetroRules.PERIOD - 4


func _may_sit(peer: int, payload: Dictionary) -> bool:
	var rider := zone.service().player(peer)
	return (
		available()
		and zone.service().alive(rider)
		and MetroRules.aboard(rider.net_position - zone.global_position)
		and not zone.service().transfers.pending.has(peer)
		and super._may_sit(peer, payload)
	)


func sit_position(index: int) -> Vector3:
	return seats[index].global_position + Vector3.UP * BOOTH_SCRIPT.HIP_OFFSET


func stand_position(index: int) -> Vector3:
	# Aisle floor is y=1.2. Keep z away from grab poles and boarding doors.
	return to_global(Vector3(0, 1.2, seats[index].position.z))


func _physics_process(delta: float) -> void:
	if multiplayer.is_server() and not available():
		for peer: int in net_seats:
			if peer != 0:
				_free_peer(peer)
	super._physics_process(delta)


func _exit_tree() -> void:
	# Scene shutdown can remove Player before the permanent metro anchors.
	if is_instance_valid(_pinned) and not _pinned.is_inside_tree():
		_pinned = null
	_release_pin(false)
