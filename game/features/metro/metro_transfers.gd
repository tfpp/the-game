class_name MetroTransfers
extends Node
## Readiness handshake shared by metro lifts and scheduled trains. No client coordinates.

var pending: Dictionary[int, Dictionary] = {}
var metro: MetroService
var entity: NetworkedEntity
var _serial := 0
var _time := 0.0


func _ready() -> void:
	metro = get_parent() as MetroService
	entity = NetworkedEntity.new()
	entity.name = "NetworkedEntity"
	add_child(entity)
	entity.register_action(&"ready", _may_ready, _ready_received)
	entity.event_received.connect(_event)
	entity.session_reset.connect(_reset)
	multiplayer.peer_disconnected.connect(cancel)


func prepare(
	player: Player,
	origin: Vector3,
	target: Vector3,
	delay: float,
	kind: String,
	service_id: int = -1,
	source_cab: MetroElevator = null,
	target_cab: MetroElevator = null
) -> bool:
	var peer := player.get_multiplayer_authority()
	if not multiplayer.is_server() or pending.has(peer) or not metro.alive(player):
		return false
	_serial += 1
	var offset := player.net_position - origin
	var position := target + offset
	var yaw := player.net_yaw
	if source_cab != null:
		offset = source_cab.car.to_local(player.net_position)
		position = target_cab.car.to_global(offset)
		yaw = ElevatorMath.apply_yaw(
			ElevatorMath.relative_yaw(yaw, source_cab.car.global_transform),
			target_cab.car.global_transform
		)
	pending[peer] = {
		"token": _serial,
		"ready": false,
		"after": _time + delay,
		"expires": _time + delay + (2.0 if kind == "depart" else 7.0),
		"origin": origin,
		"target": target,
		"position": position,
		"yaw": yaw,
		"kind": kind,
		"service": service_id,
		"source": source_cab,
		"cab": target_cab
	}
	var floor_y := target_cab.car.global_position.y if target_cab != null else target.y + 1.2
	if kind == "recover":
		floor_y = position.y - 0.95
	entity.send_event(
		&"prepare", {"token": _serial, "position": position, "floor_y": floor_y}, peer
	)
	return true


func _may_ready(peer: int, payload: Dictionary) -> bool:
	return (
		payload.size() == 1
		and payload.get("token") is int
		and pending.has(peer)
		and payload["token"] == pending[peer]["token"]
		and _time <= pending[peer]["expires"]
	)


func _ready_received(peer: int, _payload: Dictionary) -> bool:
	pending[peer]["ready"] = true
	return true


func _event(event: StringName, payload: Dictionary) -> void:
	if event == &"prepare":
		_load_destination(payload)


func _load_destination(payload: Dictionary) -> void:
	var position: Vector3 = payload["position"]
	var room := StreamedRoom.for_position(self, position)
	if room != null:
		room.load_room(10000)
	# Arrival geometry can still be pulling into the station. Keep waiting for its
	# actual floor, never acknowledge only that a PackedScene was instantiated.
	for frame: int in 420:
		await get_tree().physics_frame
		if not is_inside_tree() or (room != null and not room.is_loaded()):
			return
		if frame < 3:
			continue
		var local := metro.player(multiplayer.get_unique_id())
		if local == null:
			return
		var ray := PhysicsRayQueryParameters3D.create(position, position + Vector3.DOWN * 3, 1)
		var hit := local.get_world_3d().direct_space_state.intersect_ray(ray)
		# Include seats and jumping passengers, but reject the lower track bed.
		var floor_y: float = payload["floor_y"]
		if not hit.is_empty() and (hit["position"] as Vector3).y >= floor_y - 0.05:
			entity.request_action(&"ready", {"token": payload["token"]})
			return


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_time += delta
	for peer: int in pending.keys():
		if not pending.has(peer):
			continue
		var trip := pending[peer]
		var rider := metro.player(peer)
		if not metro.alive(rider):
			cancel(peer)
			metro.remove_passenger(peer)
			continue
		if _time > float(trip["expires"]):
			cancel(peer)
			_recover(rider, trip)
			continue
		if not trip["ready"] or _time < float(trip["after"]):
			continue
		var source := trip["source"] as MetroElevator
		if source != null:
			if not _group_ready(source):
				continue
			_complete_lift(source)
		else:
			_complete_train(rider, trip)
			cancel(peer)


func _group_ready(source: MetroElevator) -> bool:
	for trip: Dictionary in pending.values():
		if trip["source"] == source and (not trip["ready"] or _time < trip["after"]):
			return false
	return true


func _complete_lift(source: MetroElevator) -> void:
	var peers: Array[int] = []
	var valid := true
	for peer: int in pending:
		var trip := pending[peer]
		if trip["source"] != source:
			continue
		peers.append(peer)
		var rider := metro.player(peer)
		valid = valid and metro.alive(rider) and rider in source._collect_occupants()
		if not source.outbound:
			valid = valid and source.access.allowed(rider)
	for peer: int in peers:
		var trip := pending[peer]
		var rider := metro.player(peer)
		if valid:
			if source.outbound:
				source.access.leave_destination(rider)
			else:
				var button := (
					source.get_node("Car/CabButton/NetworkedEntity") as NetworkedInteraction
				)
				source.access.enter_destination(rider, button)
			rider.server_teleport.rpc_id(peer, trip["position"], trip["yaw"])
			(trip["cab"] as MetroElevator).server_arrive()
		else:
			source.server_arrive()
		cancel(peer)


func _complete_train(rider: Player, trip: Dictionary) -> void:
	var peer := rider.get_multiplayer_authority()
	if trip["kind"] == "recover":
		if metro.rides[int(trip["service"])].contains(rider.net_position):
			rider.server_teleport.rpc_id(peer, trip["position"])
		metro.remove_passenger(peer)
		return
	var offset := rider.net_position - (trip["origin"] as Vector3)
	if not MetroRules.inside_item(offset) or absf(offset.x) > 1.1:
		if (
			trip["kind"] == "depart"
			and MetroRules.car_at(offset) >= 0
			and absf(offset.x) < 1.95
			and offset.y > -1
			and offset.y < 3.5
		):
			rider.server_teleport.rpc_id(
				peer, (trip["origin"] as Vector3) + MetroRules.platform_recovery(offset)
			)
		metro.remove_passenger(peer)
		return
	if trip["kind"] == "arrive" and metro.net_time >= MetroRules.OPEN + MetroRules.DWELL:
		# A very slow arrival misses the parked train, never its supporting platform.
		offset = MetroRules.platform_recovery(offset)
	rider.server_teleport.rpc_id(peer, (trip["target"] as Vector3) + offset, rider.net_yaw)
	if trip["kind"] == "depart":
		metro.add_passenger(peer, int(trip["service"]))
	else:
		metro.remove_passenger(peer)


func _recover(rider: Player, trip: Dictionary) -> void:
	if trip["source"] != null:
		(trip["source"] as MetroElevator).server_arrive()
		return
	var peer := rider.get_multiplayer_authority()
	if trip["kind"] == "depart":
		# The departure platform is already loaded around this player.
		var offset := rider.net_position - (trip["origin"] as Vector3)
		if (
			MetroRules.car_at(offset) >= 0
			and absf(offset.x) < 1.95
			and offset.y > -1
			and offset.y < 3.5
		):
			rider.server_teleport.rpc_id(
				peer, (trip["origin"] as Vector3) + MetroRules.platform_recovery(offset)
			)
		metro.remove_passenger(peer)
		return
	# Keep a slow client safely in the fixed carriage and retry a platform arrival.
	# One pending token per peer bounds retries; even recovery requires readiness.
	var position: Vector3 = (
		trip["position"]
		if trip["kind"] == "recover"
		else (trip["target"] as Vector3) + Vector3(3.3, 2.15, 0)
	)
	prepare(rider, rider.net_position, position, 0, "recover", int(trip["service"]))


func cancel(peer: int) -> void:
	var trip: Dictionary = pending.get(peer, {})
	pending.erase(peer)
	for key: String in ["source", "cab"]:
		var cab := trip.get(key) as MetroElevator
		if not is_instance_valid(cab):
			continue
		var still_pending := false
		for other: Dictionary in pending.values():
			if other["source"] == cab or other["cab"] == cab:
				still_pending = true
		if not still_pending:
			cab.server_end_ride()


func _reset(_mode: Network.Mode) -> void:
	for peer: int in pending.keys():
		cancel(peer)
	_time = 0
