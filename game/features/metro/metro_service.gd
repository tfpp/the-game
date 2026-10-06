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
var _ready_links := false
var _view_time := 0.0
var _received_time := -1.0
var _items_departed := false
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
		rides.append(get_node("Ride%d" % i) as MetroZone)
	transfers = MetroTransfers.new()
	transfers.name = "Transfers"
	add_child(transfers)
	entity.session_reset.connect(_reset)
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
	access.destination.position = Vector3(17.5, 1.2, (access.slot - 2.5) * 8)
	access.destination.rotation.y = -PI / 2
	stations[access.station].add_child(access.destination)
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
		for index: int in 4:
			_move_items(
				stations[MetroRules.station(index, net_cycle)].position, rides[index].position
			)
	if previous < MetroRules.PERIOD - 3 and net_time >= MetroRules.PERIOD - 3:
		_begin_arrival_transfer()
	_check_train_impacts(previous, net_time)
	if net_time >= MetroRules.PERIOD:
		for index: int in 4:
			_move_items(
				rides[index].position, stations[MetroRules.station(index, net_cycle + 1)].position
			)
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
			var point := rider.net_position - station.global_position
			var trip: Dictionary = transfers.pending.get(peer, {})
			# A validated rider awaiting floor readiness still belongs to the cabin.
			# Stepping out of that cabin forfeits protection.
			if (
				trip.get("kind", "") == "depart"
				and trip.get("origin") == station.position
				and MetroRules.aboard(point, rider.movement.hull_radius_m())
			):
				continue
			if MetroRules.train_hits(
				point,
				rider.movement.hull_radius_m(),
				rider.movement.hull_height_m(),
				previous,
				current
			):
				combat.apply_damage(peer, Combat.MAX_HEALTH, peer)
				break


func _begin_boarding_transfer() -> void:
	for service_id: int in 4:
		var source := stations[MetroRules.station(service_id, net_cycle)]
		for node: Node in get_tree().get_nodes_in_group(&"players"):
			var rider := node as Player
			if rider == null or rider.multiplayer != multiplayer or not alive(rider):
				continue
			var point := rider.net_position - source.position
			if MetroRules.aboard(point, rider.movement.hull_radius_m()):
				transfers.prepare(
					rider,
					source.position,
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
					source.position + MetroRules.platform_recovery(point)
				)


func _begin_arrival_transfer() -> void:
	for peer: int in net_passengers.keys():
		var service_id := int(net_passengers[peer])
		var rider := player(peer)
		if alive(rider):
			transfers.prepare(
				rider,
				rides[service_id].position,
				stations[MetroRules.station(service_id, net_cycle + 1)].position,
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
		if transfers.pending.has(rider.get_multiplayer_authority()):
			continue
		for station: MetroZone in stations:
			var point := rider.net_position - station.position
			if (
				MetroRules.car_at(point) >= 0
				and absf(point.x) < 1.95
				and point.y > 1.2
				and point.y < 3.5
			):
				rider.server_teleport.rpc_id(
					rider.get_multiplayer_authority(),
					station.position + MetroRules.platform_recovery(point)
				)


func add_passenger(peer: int, service_id: int) -> void:
	var snapshot := net_passengers.duplicate()
	snapshot[peer] = service_id
	net_passengers = snapshot


func remove_passenger(peer: int) -> void:
	var snapshot := net_passengers.duplicate()
	snapshot.erase(peer)
	net_passengers = snapshot


func _remove_peer(peer: int) -> void:
	transfers.cancel(peer)
	remove_passenger(peer)


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


func _sync_server_collision() -> void:
	for node: Node3D in _collision + _structure:
		node.queue_free()
	_collision.clear()
	_structure.clear()
	if not multiplayer.is_server():
		return
	var scene := load("res://features/metro/train_collision.tscn") as PackedScene
	for zone: MetroZone in stations + rides:
		var body := scene.instantiate() as Node3D
		body.name = "ServerCollision"
		zone.add_child(body)
		_collision.append(body)
		if zone.station_index >= 0:
			var structure := (
				(load("res://features/metro/station_collision.tscn") as PackedScene).instantiate()
				as Node3D
			)
			zone.add_child(structure)
			_structure.append(structure)
	_update_collision()


func _update_collision() -> void:
	for index: int in _collision.size():
		var body := _collision[index]
		var height := MetroRules.collision_y(net_time) if index < 4 else 0.0
		if body.position.y != height:
			body.position.y = height
		var animation := body.get_node("Doors") as AnimationPlayer
		var amount := MetroRules.aperture(net_time) if index < 4 else 0.0
		if body.get_meta("aperture", -1.0) != amount:
			animation.play("open_right")
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
	for index: int in 4:
		links.append(
			{
				"from": stations[index].position + Vector3(3, 1.2, 0),
				"to": stations[(index + 1) % 4].position + Vector3(3, 1.2, 0),
				"label": "Wait for the train to " + MetroRules.NAMES[(index + 1) % 4]
			}
		)
		var arrival := MetroRules.station(
			index, net_cycle + (1 if net_time >= MetroRules.DEPART else 0)
		)
		links.append(
			{
				"from": rides[index].position + Vector3(0, 1.2, 2.5),
				"to": stations[arrival].position + Vector3(3, 1.2, 0),
				"label": "Ride to " + MetroRules.NAMES[arrival]
			}
		)
	return links


func _reset(_mode: Network.Mode) -> void:
	net_time = 0
	net_cycle = 0
	net_passengers = {}
	_items_departed = false
	_received_time = -1
	_view_time = 0
	for zone: MetroZone in stations + rides:
		zone.unload_room()
	_sync_server_collision.call_deferred()
