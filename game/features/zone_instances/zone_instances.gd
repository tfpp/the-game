class_name ZoneInstances
extends Node
## Server-owned registry of slum zone instances (see README.md). Shared zones such as
## the Crown are not tracked. Members leave on disconnect; callers report returns
## and deaths through `leave()`.

const GROUP := &"zone_instances"
const GARAGE_INSTANCE := preload("res://features/zone_instances/garage_instance.tscn")
const ALLEY_INSTANCE := preload("res://features/zone_instances/alley_instance.tscn")
const INSTANCE_ORIGIN := Vector3(0, 0, 12000)

@export var net_peer_instances: Dictionary = {}
var registry := ZoneRegistry.new()
var _scopes: Dictionary[int, ZoneScope] = {}
var _spawner: MultiplayerSpawner
var _transfers: Dictionary[int, Dictionary] = {}
var _membership: NetworkedEntity


static func for_node(caller: Node) -> ZoneInstances:
	for service: Node in caller.get_tree().get_nodes_in_group(&"zone_instances"):
		if service is ZoneInstances and service.multiplayer == caller.multiplayer:
			return service as ZoneInstances
	return null


## Use a permanent endpoint so a delayed readiness request remains valid when
## an instance is removed before its client acknowledgement reaches the server.
func report_loaded(instance_id: int) -> void:
	_membership.request_action(&"loaded", {"instance": instance_id})


func _may_acknowledge(peer: int, payload: Dictionary) -> bool:
	if payload.size() != 1 or not payload.get("instance") is int:
		return false
	var id := int(payload["instance"])
	return registry.instance_of(peer) == id and scope_for(id) is SlumInstance


func _acknowledge(peer: int, payload: Dictionary) -> bool:
	var instance := scope_for(int(payload["instance"])) as SlumInstance
	if instance == null:
		return false
	if peer not in instance.ready_peers:
		instance.ready_peers.append(peer)
	return true


func can_observe_player(owner: int, observer: int) -> bool:
	return (
		observer == MultiplayerPeer.TARGET_PEER_SERVER
		or observer == owner
		or shares_instance(owner, observer)
	)


## Gameplay membership has no server visibility exception: even a hosting player
## may only damage players in their own shared hub or private excursion.
func shares_instance(first: int, second: int) -> bool:
	return int(net_peer_instances.get(first, -1)) == int(net_peer_instances.get(second, -1))


func can_observe_zone(instance_id: int, observer: int) -> bool:
	return (
		observer == MultiplayerPeer.TARGET_PEER_SERVER
		or int(net_peer_instances.get(observer, -1)) == instance_id
	)


func instance_at_position(point: Vector3) -> int:
	for id: int in _scopes:
		var scope := scope_for(id) as SlumInstance
		if scope == null:
			continue
		var bounds := AABB(Vector3(-28, -2, -28), Vector3(56, 24, 56))
		if scope.destination == SlumInstance.Destination.GARAGE:
			bounds = AABB(Vector3(-38, -2, -16), Vector3(76, 28, 100))
		if bounds.has_point(scope.to_local(point)):
			return id
	return -1


func _process(_delta: float) -> void:
	var local_peer := multiplayer.get_unique_id()
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player == null or player.multiplayer != multiplayer or player.is_local():
			continue
		var relevant := can_observe_player(player.get_multiplayer_authority(), local_peer)
		player.visible = relevant
		var collider := player.get_node("Collider") as CollisionShape3D
		if collider.disabled == relevant:
			collider.set_deferred("disabled", not relevant)


func _publish_memberships() -> void:
	var snapshot: Dictionary = {}
	for id: int in registry.instance_ids():
		for peer: int in registry.members(id):
			snapshot[peer] = id
	net_peer_instances = snapshot
	for group: StringName in [&"holdables_root", &"gun_machine_root", &"combat"]:
		for owner: Node in get_tree().get_nodes_in_group(group):
			if owner.multiplayer == multiplayer:
				ZoneScope.refresh_visibility(owner)


func _physics_process(_delta: float) -> void:
	var transport := multiplayer.multiplayer_peer
	if (
		transport == null
		or transport.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED
	):
		return
	if not multiplayer.is_server():
		return
	for peer: int in _transfers.keys():
		var trip: Dictionary = _transfers[peer]
		if Time.get_ticks_msec() > int(trip["expires"]):
			_erase_transfer(peer)
			if not bool(trip["return"]):
				registry.leave(peer)
			var source := trip["source"] as ElevatorCab
			if is_instance_valid(source):
				source.server_arrive()
			continue
		if Time.get_ticks_msec() < int(trip["after"]):
			continue
		var instance := scope_for(int(trip["instance"])) as SlumInstance
		if not bool(trip["return"]) and (instance == null or peer not in instance.ready_peers):
			continue
		var player := trip["player"] as Player
		if is_instance_valid(player):
			if bool(trip["return"]):
				for loader: Node in get_tree().get_nodes_in_group(&"room_visibility"):
					if loader.multiplayer == multiplayer:
						(loader as RoomVisibility).preload_at.rpc_id(peer, trip["position"])
			player.server_teleport.rpc_id(peer, trip["position"], trip["yaw"])
			var receiving := trip["arrival"] as ElevatorCab
			if is_instance_valid(receiving):
				receiving.server_arrive()
			if bool(trip["return"]):
				registry.leave(peer)
		_erase_transfer(peer)


func _erase_transfer(peer: int) -> void:
	var trip: Dictionary = _transfers.get(peer, {})
	_transfers.erase(peer)
	for key: String in ["source", "arrival"]:
		var cab := trip.get(key) as ElevatorCab
		if not is_instance_valid(cab):
			continue
		var still_pending := false
		for pending: Dictionary in _transfers.values():
			if pending.get("source") == cab or pending.get("arrival") == cab:
				still_pending = true
				break
		if not still_pending:
			cab.server_end_ride()


## Called only by a server cab after its validated door cycle has fully closed.
# gdlint: disable=max-returns
func depart_cab(cab: ElevatorCab, occupants: Array[Player]) -> void:
	if (
		not multiplayer.is_server()
		or occupants.is_empty()
		or occupants.size() > ElevatorCab.MAX_RIDERS
	):
		return
	var peers: Array[int] = []
	for player: Player in occupants:
		var peer := player.get_multiplayer_authority()
		if _transfers.has(peer):
			return
		peers.append(peer)
	var arrival_cab: ElevatorCab
	var instance: SlumInstance
	var returning := cab.excursion_role == ElevatorCab.ExcursionRole.RETURN
	if returning:
		var ancestor: Node = cab
		while ancestor != null and not ancestor is SlumInstance:
			ancestor = ancestor.get_parent()
		instance = ancestor as SlumInstance
		if instance == null:
			return
		for peer: int in peers:
			if registry.instance_of(peer) != instance.instance_id:
				return
		for node: Node in get_tree().get_nodes_in_group(&"crown_excursion_cabs"):
			if node.multiplayer == multiplayer:
				arrival_cab = node as ElevatorCab
				break
		if (
			arrival_cab == null
			or arrival_cab.net_state != ElevatorCab.State.CLOSED
			or arrival_cab.net_riding
		):
			return
	else:
		var destination := SlumDestinations.pick(get_tree(), multiplayer)
		if destination == null:
			return
		instance = create_excursion(peers, destination, _destination_kind(destination), randi())
		if instance == null:
			return
		arrival_cab = instance.return_cab
	cab.server_begin_ride(arrival_cab.home_floor)
	arrival_cab.server_begin_ride(arrival_cab.home_floor, cab.home_floor)
	for player: Player in occupants:
		var offset := ElevatorMath.relative_offset(player.net_position, cab.car.global_transform)
		var yaw := ElevatorMath.relative_yaw(player.net_yaw, cab.car.global_transform)
		_schedule_transfer(
			player,
			cab,
			arrival_cab,
			instance.instance_id,
			returning,
			ElevatorMath.apply_offset(offset, arrival_cab.car.global_transform),
			ElevatorMath.apply_yaw(yaw, arrival_cab.car.global_transform)
		)


func _destination_kind(arrival: SlumArrivalPoint) -> SlumInstance.Destination:
	return (
		SlumInstance.Destination.ALLEYS
		if "Alley" in arrival.slum_name
		else SlumInstance.Destination.GARAGE
	)


## Trusted developer pad call after sender/range validation. Uses normal readiness.
func enter_development_zone(player: Player, arrival: SlumArrivalPoint) -> bool:
	if (
		not multiplayer.is_server()
		or not DevGate.cheats_enabled(get_tree())
		or player == null
		or arrival == null
		or player.multiplayer != multiplayer
		or _transfers.has(player.get_multiplayer_authority())
	):
		return false
	var run := create_excursion(
		[player.get_multiplayer_authority()] as Array[int],
		arrival,
		_destination_kind(arrival),
		randi()
	)
	if run == null:
		return false
	var cab := run.return_cab
	cab.server_begin_ride(cab.home_floor)
	_schedule_transfer(
		player,
		null,
		cab,
		run.instance_id,
		false,
		run.entry_position(),
		wrapf(cab.car.global_basis.get_euler().y + PI, -PI, PI)
	)
	return true


func _schedule_transfer(
	player: Player,
	source: ElevatorCab,
	arrival: ElevatorCab,
	instance_id: int,
	returning: bool,
	position: Vector3,
	yaw: float
) -> void:
	_transfers[player.get_multiplayer_authority()] = {
		"player": player,
		"position": position,
		"yaw": yaw,
		"after": Time.get_ticks_msec() + 1000,
		"expires": Time.get_ticks_msec() + 10000,
		"source": source,
		"arrival": arrival,
		"instance": instance_id,
		"return": returning
	}


func _ready() -> void:
	add_to_group(GROUP)
	_membership = NetworkedEntity.new()
	_membership.name = "Membership"
	_membership.replicated_properties = [NodePath(".:net_peer_instances")]
	add_child(_membership)
	_membership.register_action(&"loaded", _may_acknowledge, _acknowledge)
	var instances := Node3D.new()
	instances.name = "Instances"
	add_child(instances)
	_spawner = MultiplayerSpawner.new()
	_spawner.name = "InstanceSpawner"
	_spawner.spawn_path = NodePath("../Instances")
	_spawner.spawn_function = _spawn_instance
	add_child(_spawner)
	registry.membership_changed.connect(_on_membership_changed)
	registry.instance_freed.connect(_on_instance_freed)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Network.mode_changed.connect(_on_mode_changed)


## The scene's registry, or `fallback` when the feature is not loaded (unit tests
## that build a single feature).
static func registry_for(tree: SceneTree, fallback: ZoneRegistry) -> ZoneRegistry:
	var node := tree.get_first_node_in_group(GROUP) as ZoneInstances
	return node.registry if node != null else fallback


## Bind the spawned root before it enters the tree. The registry remains the
## source of truth, including immediate revocation on return/death/disconnect.
func bind_scope(instance_id: int, scope: ZoneScope) -> bool:
	if not multiplayer.is_server() or scope == null or not registry.has_instance(instance_id):
		return false
	if _scopes.has(instance_id) and is_instance_valid(_scopes[instance_id]):
		return false
	scope.instance_id = instance_id
	scope.replace_members(registry.members(instance_id))
	_scopes[instance_id] = scope
	return true


func scope_for(instance_id: int) -> ZoneScope:
	var scope: ZoneScope = _scopes.get(instance_id)
	return scope if is_instance_valid(scope) else null


## Trusted server API; callers supply the riders collected from the actual cab.
func create_excursion(
	peers: Array[int], arrival: Node3D, destination: SlumInstance.Destination, seed_value: int
) -> SlumInstance:
	if not multiplayer.is_server() or peers.is_empty() or arrival == null:
		return null
	var id := registry.create(peers, arrival)
	var data := {
		"id": id,
		"members": registry.members(id),
		"destination": destination,
		"seed": seed_value,
		"enemies":
		GarageRunPlan.enemies(seed_value) if destination == SlumInstance.Destination.GARAGE else [],
		"position": INSTANCE_ORIGIN + registry.offset_of(id)
	}
	var instance := _spawner.spawn(data) as SlumInstance
	if instance == null:
		for peer: int in peers:
			registry.leave(peer)
	return instance


func _spawn_instance(data: Variant) -> Node:
	var info := data as Dictionary
	var scene := GARAGE_INSTANCE if int(info["destination"]) == 0 else ALLEY_INSTANCE
	var instance := scene.instantiate() as SlumInstance
	instance.name = "Run%d" % int(info["id"])
	instance.instance_id = int(info["id"])
	instance.members.assign(info["members"])
	instance.destination = int(info["destination"]) as SlumInstance.Destination
	instance.layout_seed = int(info["seed"])
	instance.enemy_plan.assign(info["enemies"])
	instance.position = info["position"]
	if multiplayer.is_server():
		bind_scope(instance.instance_id, instance)
	return instance


func _on_membership_changed(instance_id: int) -> void:
	_publish_memberships()
	for peer: int in _transfers.keys():
		if (
			int(_transfers[peer]["instance"]) == instance_id
			and peer not in registry.members(instance_id)
		):
			_erase_transfer(peer)
	var scope := scope_for(instance_id)
	if scope != null:
		scope.replace_members(registry.members(instance_id))


func _on_instance_freed(instance_id: int) -> void:
	_publish_memberships()
	for group: StringName in [&"holdables_root", &"gun_machine_root"]:
		for owner: Node in get_tree().get_nodes_in_group(group):
			if owner.multiplayer == multiplayer and owner.has_method("clear_instance_items"):
				owner.call("clear_instance_items", instance_id)
	for peer: int in _transfers.keys():
		if int(_transfers[peer]["instance"]) == instance_id:
			_erase_transfer(peer)
	var scope := scope_for(instance_id)
	_scopes.erase(instance_id)
	if scope != null:
		# Revoke before deferred destruction, so no last-frame request can commit.
		scope.replace_members([])
		scope.queue_free()


func _on_peer_disconnected(peer_id: int) -> void:
	_erase_transfer(peer_id)
	if multiplayer.is_server():
		registry.leave(peer_id)


func _on_mode_changed(_mode: Network.Mode) -> void:
	net_peer_instances = {}
	_transfers.clear()
	registry.clear()
	_scopes.clear()
	for instance: Node in get_node("Instances").get_children():
		instance.queue_free()
