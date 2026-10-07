class_name MetroService
extends Node3D
## Shared loop authority. World travel is only between compact stationary rooms.

@export var net_time := 0.0
@export var net_cycle := 0
@export var net_passengers: Dictionary = {}
var stations: Array[MetroZone] = []
var rides: Array[MetroZone] = []
var accesses: Array[MetroAccess] = []
var transfers: MetroTransfers
var _collision: Array[Node3D] = []
var _structure: Array[Node3D] = []
var _collision_doors: Array[AnimationPlayer] = []
var _ready_links := false
var _view_time := 0.0
var _received_time := -1.0
var _items_departed := false
## Peer -> cycle in which the metro sent them off a departing train.
var _shielded: Dictionary[int, int] = {}
@onready var entity: NetworkedEntity = $NetworkedEntity


static func for_node(caller: Node) -> MetroService:
	for node: Node in caller.get_tree().get_nodes_in_group(&"metro_service"):
		if node.multiplayer == caller.multiplayer:
			return node as MetroService
	return null


func _ready() -> void:
	add_to_group(&"metro_service")
	for i: int in 4:
		stations.append(get_node("Station%d" % i) as MetroZone)
	for i: int in MetroRules.SERVICES:
		rides.append(get_node("Ride%d" % i) as MetroZone)
	transfers = MetroTransfers.new()
	transfers.name = "Transfers"
	add_child(transfers)
	entity.session_reset.connect(_reset)
	entity.event_received.connect(_on_event)
	multiplayer.peer_disconnected.connect(_remove_peer)
	call_deferred("_register_accesses")
	call_deferred("_connect_combat")
	_sync_server_collision()


func _connect_combat() -> void:
	var combat := get_tree().get_first_node_in_group(&"combat") as Combat
	if combat != null and combat.multiplayer == multiplayer:
		combat.player_died.connect(_on_death)


func _register_accesses() -> void:
	if _ready_links:
		return
	_ready_links = true
	for node: Node in get_tree().get_nodes_in_group(&"metro_access"):
		var access := node as MetroAccess
		if access.multiplayer != multiplayer:
			continue
		register_access(access)


func register_access(access: MetroAccess) -> bool:
	if access in accesses:
		return true
	if (
		access.zone_id.is_empty()
		or access.station < 0
		or access.station >= 4
		or access.slot < 0
		or access.slot > 10
	):
		return false
	for other: MetroAccess in accesses:
		if (
			other.zone_id == access.zone_id
			or (other.station == access.station and other.slot == access.slot)
		):
			push_error("Duplicate metro connector: " + access.zone_id)
			return false
	accesses.append(access)
	access.tree_exiting.connect(_unregister_access.bind(access))
	var kit := load("res://features/metro/access_elevator.tscn") as PackedScene
	access.source = kit.instantiate() as MetroElevator
	access.source.name = "MetroElevator"
	_configure_cab(access.source, access, true)
	access.add_child(access.source)
	access.destination = kit.instantiate() as MetroElevator
	access.destination.name = "Exit_" + access.zone_id
	_configure_cab(access.destination, access, false)
	access.destination.position = Vector3(6.4, 1.2, (access.slot - 2.5) * 8)
	access.destination.rotation.y = -PI / 2
	stations[access.station].add_child(access.destination)
	access.destination.attach_shaft()
	access.source.partner = access.destination
	access.destination.partner = access.source
	var gps := GpsDestination.new()
	gps.set_script(load("res://features/metro/metro_destination.gd"))
	gps.name = "MetroDestination"
	gps.label = "Metro · " + access.label
	gps.hint = "Elevator to " + MetroRules.NAMES[access.station]
	gps.dev_only = access.access_policy == "developer"
	gps.position = Vector3(0, 0.1, 1)
	access.add_child(gps)
	return true


func _unregister_access(access: MetroAccess) -> void:
	accesses.erase(access)
	if is_instance_valid(access.destination):
		access.destination.queue_free()
	if transfers != null:
		for peer: int in transfers.pending.keys():
			var trip := transfers.pending[peer]
			if trip["source"] == access.source or trip["cab"] == access.source:
				transfers.cancel(peer)


func _configure_cab(cab: MetroElevator, access: MetroAccess, outbound: bool) -> void:
	cab.metro = self
	cab.access = access
	cab.outbound = outbound
	cab.excursion_role = ElevatorCab.ExcursionRole.NONE
	cab.sign_text = "METRO" if outbound else access.label.to_upper()
	cab.home_floor = "M" if not outbound else "G"


func player(peer: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if node.multiplayer == multiplayer and node.get_multiplayer_authority() == peer:
			return node as Player
	return null


func alive(rider: Player) -> bool:
	if not is_instance_valid(rider):
		return false
	var instances := ZoneInstances.for_node(self)
	if (
		instances != null
		and instances.registry.instance_of(rider.get_multiplayer_authority()) != -1
	):
		return false
	for node: Node in get_tree().get_nodes_in_group(&"combat"):
		if (
			node.multiplayer == multiplayer
			and (node as Combat).is_respawning(rider.get_multiplayer_authority())
		):
			return false
	return true


func depart_elevator(cab: MetroElevator, riders: Array[Player]) -> void:
	if not multiplayer.is_server() or riders.is_empty() or riders.size() > ElevatorCab.MAX_RIDERS:
		return
	if cab.net_state != ElevatorCab.State.CLOSED or cab.net_riding:
		return
	var target := cab.partner
	if (
		target == null
		or target.net_state != ElevatorCab.State.CLOSED
		or target.net_riding
		or not target._collect_occupants().is_empty()
	):
		cab.server_arrive()
		return
	for rider: Player in riders:
		if not alive(rider) or transfers.pending.has(rider.get_multiplayer_authority()):
			cab.server_arrive()
			return
		if not cab.outbound and not cab.access.allowed(rider):
			cab.server_arrive()
			return
	cab.server_begin_ride(target.home_floor)
	target.server_begin_ride(target.home_floor)
	for rider: Player in riders:
		transfers.prepare(
			rider, cab.car.global_position, target.car.global_position, 1.0, "lift", -1, cab, target
		)


func display_time() -> float:
	return net_time if multiplayer.is_server() else _view_time


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		if net_time != _received_time:
			_received_time = net_time
			_view_time = net_time
		else:
			_view_time = minf(_view_time + delta, minf(net_time + 0.25, MetroRules.PERIOD))


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	var previous := net_time
	net_time += delta
	if (
		previous < MetroRules.OPEN + MetroRules.DWELL
		and net_time >= MetroRules.OPEN + MetroRules.DWELL
	):
		_begin_boarding_transfer()
	if not _items_departed and net_time >= MetroRules.DEPART:
		_items_departed = true
		_clear_unboarded()
		for index: int in MetroRules.SERVICES:
			_move_items(train_origin(index, net_cycle), rides[index].position)
	if previous < MetroRules.PERIOD - 3 and net_time >= MetroRules.PERIOD - 3:
		_begin_arrival_transfer()
	_check_train_impacts(previous, net_time)
	if net_time >= MetroRules.PERIOD:
		for index: int in MetroRules.SERVICES:
			_move_items(rides[index].position, train_origin(index, net_cycle + 1))
		net_time = fmod(net_time, MetroRules.PERIOD)
		net_cycle += 1
		_items_departed = false
	_update_collision()


func _check_train_impacts(previous: float, current: float) -> void:
	if not multiplayer.is_server() or current <= MetroRules.DEPART:
		return
	var combat: Combat
	for node: Node in get_tree().get_nodes_in_group(&"combat"):
		if node.multiplayer == multiplayer:
			combat = node as Combat
			break
	if combat == null:
		return
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var rider := node as Player
		if rider == null or rider.multiplayer != multiplayer or not alive(rider):
			continue
		var peer := rider.get_multiplayer_authority()
		for station: MetroZone in stations:
			if not station.contains(rider.net_position):
				continue
			for track_index: int in 2:
				var point := (
					rider.net_position
					- station.global_position
					- MetroRules.track_offset(track_index)
				)
				if _protected(peer, point, station, rider.movement.hull_radius_m(), track_index):
					continue
				point.z *= 1 if track_index == 0 else -1
				if MetroRules.train_hits(
					point,
					rider.movement.hull_radius_m(),
					rider.movement.hull_height_m(),
					previous,
					current
				):
					combat.apply_damage(peer, Combat.MAX_HEALTH, peer)
					if combat.is_respawning(peer):
						entity.send_event(&"struck", {"peer": peer, "at": rider.net_position})
					break
			break


func _protected(
	peer: int, point: Vector3, station: MetroZone, radius: float, track_index: int = 0
) -> bool:
	var trip: Dictionary = transfers.pending.get(peer, {})
	# A validated rider awaiting floor readiness still belongs to the cabin.
	# Stepping out of that cabin forfeits protection.
	if (
		trip.get("kind", "") == "depart"
		and trip.get("origin") == station.position + MetroRules.track_offset(track_index)
		and MetroRules.aboard(point, radius)
	):
		return true
	# Movement is client-authoritative: after the metro teleports someone off a
	# departing train, the server sees their old seat until the owner reports back.
	return (
		MetroRules.in_car(point)
		and (net_passengers.has(peer) or _shielded.get(peer, -1) == net_cycle)
	)


## Protect a rider the metro is moving off the departing train this cycle.
func shield_from_train(peer: int) -> void:
	_shielded[peer] = net_cycle


func _on_event(event: StringName, payload: Dictionary) -> void:
	if event != &"struck":
		return
	# The victim hears the flatline in their ears; bystanders hear it on the tracks.
	var at: Vector3 = payload.get("at", Vector3.INF)
	if int(payload.get("peer", 0)) == multiplayer.get_unique_id():
		GameAudio.play_ui(self, &"metro_flatline")
	else:
		GameAudio.play_at(self, &"metro_flatline", at)


func _begin_boarding_transfer() -> void:
	for service_id: int in MetroRules.SERVICES:
		var origin := train_origin(service_id, net_cycle)
		for node: Node in get_tree().get_nodes_in_group(&"players"):
			var rider := node as Player
			if rider == null or rider.multiplayer != multiplayer or not alive(rider):
				continue
			var point := rider.net_position - origin
			if MetroRules.aboard(point, rider.movement.hull_radius_m()):
				transfers.prepare(
					rider,
					origin,
					rides[service_id].position,
					MetroRules.CLOSE,
					"depart",
					service_id
				)
			elif (
				MetroRules.car_at(point) >= 0
				and point.y > 1.2
				and point.y < 3.5
				and absf(point.x) < 1.95
			):
				rider.server_teleport.rpc_id(
					rider.get_multiplayer_authority(),
					origin + MetroRules.platform_recovery(point, MetroRules.track(service_id))
				)


func _begin_arrival_transfer() -> void:
	for peer: int in net_passengers.keys():
		var service_id := int(net_passengers[peer])
		var rider := player(peer)
		if alive(rider):
			transfers.prepare(
				rider,
				rides[service_id].position,
				train_origin(service_id, net_cycle + 1),
				3.0,
				"arrive",
				service_id
			)
		else:
			remove_passenger(peer)


func _clear_unboarded() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var rider := node as Player
		if rider == null or rider.multiplayer != multiplayer or not alive(rider):
			continue
		# An owner may already be on the ride while the server still sees their
		# old cabin pose. Never follow a successful transfer with a platform eject.
		var peer := rider.get_multiplayer_authority()
		if transfers.pending.has(peer) or net_passengers.has(peer):
			continue
		for station: MetroZone in stations:
			for track_index: int in 2:
				var origin := station.position + MetroRules.track_offset(track_index)
				var point := rider.net_position - origin
				if MetroRules.in_car(point):
					shield_from_train(peer)
					rider.server_teleport.rpc_id(
						peer, origin + MetroRules.platform_recovery(point, track_index)
					)


func add_passenger(peer: int, service_id: int) -> void:
	var snapshot := net_passengers.duplicate()
	snapshot[peer] = service_id
	net_passengers = snapshot


func remove_passenger(peer: int) -> void:
	if not net_passengers.has(peer):
		return
	var snapshot := net_passengers.duplicate()
	snapshot.erase(peer)
	net_passengers = snapshot


func _remove_peer(peer: int) -> void:
	transfers.cancel(peer)
	remove_passenger(peer)
	_shielded.erase(peer)


func _on_death(peer: int, _attacker: int) -> void:
	if multiplayer.is_server():
		_remove_peer(peer)


func _move_items(origin: Vector3, target: Vector3) -> void:
	for owner: Node in get_tree().get_nodes_in_group(&"holdables_root"):
		if owner.multiplayer != multiplayer:
			continue
		var items := owner.get_node_or_null("Thrown")
		if items == null:
			continue
		for item: ThrownItem in items.get_children():
			if item.instance_id == -1 and MetroRules.inside_item(item.net_position - origin):
				item.transfer_by(target - origin)


## Both station tracks share an island, but each has its own ride and manifest.
func train_origin(service_id: int, cycle: int) -> Vector3:
	return (
		stations[MetroRules.station(service_id, cycle)].position
		+ MetroRules.track_offset(MetroRules.track(service_id))
	)


func collision_height(station_index: int, track_index: int = 0) -> float:
	if station_index < 0 or net_time < MetroRules.DEPART:
		return 0.0
	var origin := stations[station_index].position + MetroRules.track_offset(track_index)
	# Slow loading must not remove the floor underneath a validated rider.
	if transfers.support_needed(origin):
		return 0.0
	return -200.0


func _sync_server_collision() -> void:
	for node: Node3D in _collision + _structure:
		node.queue_free()
	_collision.clear()
	_collision_doors.clear()
	_structure.clear()
	if not multiplayer.is_server():
		return
	var scene := load("res://features/metro/train_collision.tscn") as PackedScene
	for track_index: int in 2:
		for zone: MetroZone in stations:
			_add_collision(scene, zone, track_index)
	for zone: MetroZone in rides:
		_add_collision(scene, zone, 0)
	for zone: MetroZone in stations:
		var structure := (
			(load("res://features/metro/station_collision.tscn") as PackedScene).instantiate()
			as Node3D
		)
		zone.add_child(structure)
		_structure.append(structure)
	_update_collision()


func _add_collision(scene: PackedScene, zone: MetroZone, track_index: int) -> void:
	var body := scene.instantiate() as Node3D
	body.name = "ServerCollision" if track_index == 0 else "ReverseCollision"
	body.position = MetroRules.track_offset(track_index)
	body.set_meta("station", zone.station_index)
	body.set_meta("track", track_index)
	zone.add_child(body)
	_collision.append(body)
	_collision_doors.append(body.get_node("Doors") as AnimationPlayer)


func _update_collision() -> void:
	for index: int in _collision.size():
		var body := _collision[index]
		var station_index := int(body.get_meta("station"))
		var track_index := int(body.get_meta("track"))
		var height := collision_height(station_index, track_index)
		if body.position.y != height:
			body.position.y = height
		var amount := MetroRules.aperture(net_time) if station_index >= 0 else 0.0
		if body.get_meta("aperture", -1.0) != amount:
			var animation := _collision_doors[index]
			animation.play("open_right" if track_index == 0 else "open_left")
			animation.seek(amount * 1.2, true)
			animation.pause()
			body.set_meta("aperture", amount)


func gps_links() -> Array[Dictionary]:
	var links: Array[Dictionary] = []
	for access: MetroAccess in accesses:
		if access.access_policy == "developer" and not DevGate.cheats_enabled(get_tree()):
			continue
		if (
			access.access_policy == "vip"
			and not access.allowed(player(multiplayer.get_unique_id()))
		):
			continue
		links.append(
			{
				"from": access.source.global_position + access.source.global_basis.z,
				"to": access.destination.car.global_position,
				"label": "Take the metro elevator"
			}
		)
		links.append(
			{
				"from": access.destination.global_position + access.destination.global_basis.z,
				"to": access.source.car.global_position,
				"label": "Exit to " + access.label
			}
		)
	for index: int in MetroRules.SERVICES:
		var station_index := index % 4
		var next := MetroRules.station(index, 1)
		var platform := (
			MetroRules.track_offset(MetroRules.track(index))
			+ MetroRules.platform_recovery(Vector3.ZERO, MetroRules.track(index))
		)
		platform.y = 1.2
		links.append(
			{
				"from": stations[station_index].position + platform,
				"to": stations[next].position + platform,
				"label": "Wait for the train to " + MetroRules.NAMES[next]
			}
		)
		var arrival := MetroRules.station(
			index, net_cycle + (1 if net_time >= MetroRules.DEPART else 0)
		)
		links.append(
			{
				"from": rides[index].position + Vector3(0, 1.2, 2.5),
				"to": stations[arrival].position + platform,
				"label": "Ride to " + MetroRules.NAMES[arrival]
			}
		)
	return links


func _reset(_mode: Network.Mode) -> void:
	net_time = 0
	net_cycle = 0
	net_passengers = {}
	_shielded.clear()
	_items_departed = false
	_received_time = -1
	_view_time = 0
	for zone: MetroZone in stations + rides:
		zone.unload_room()
	_sync_server_collision.call_deferred()
