class_name CasinoSecurity
extends Node3D
## Golden Crown security. Bouncers stand watch in the main hall; when someone
## causes trouble (SecurityRules.OFFENCES, reported by the features that refuse
## the act), the nearest free guard comes over, slings the offender over a
## shoulder, carries them to the Crown metro elevator and throws them in. They
## land on a random metro platform through MetroService.deliver().
##
## The server owns every detention and guard; clients never request anything.
## `detentions` replicates to everyone, including late joiners, and every peer
## draws carried and thrown bodies from it and the guards' replicated poses.
## See README.md.

## The server waits this long after loading before probing the hall's floor.
const GRID_DELAY_S := 1.0
## Floor cells probed per physics tick while building (keeps web frames smooth).
const GRID_BUDGET := 96
## Fallback Crown metro threshold, if the connector is missing (casino_gridmap).
const CAB_FALLBACK := Transform3D(Basis(Vector3.UP, PI), Vector3(-12, 0, 19.8))
const REPLANS := 3

## peer -> [guard index, offence id (String), SecurityRules.Phase].
@export var detentions: Dictionary = {}

## Server-only state.
var grid: SecurityGrid
var _grid_wait := GRID_DELAY_S
var _queue: Array[Dictionary] = []
var _timers: Dictionary[int, float] = {}
var _replans: Dictionary[int, int] = {}
var _deliveries: Dictionary[int, Dictionary] = {}
var _rng := RandomNumberGenerator.new()
var _metro_connected: Node
## Presentation on every peer: [phase, seconds in it] and the transform a body
## had when its phase began (the lift's start and the throw's release).
var _seen: Dictionary[int, Array] = {}
var _start: Dictionary[int, Transform3D] = {}
var _posed: Dictionary[int, bool] = {}

@onready var entity: NetworkedEntity = $NetworkedEntity


func _ready() -> void:
	add_to_group(&"casino_security")
	# After avatars (15) have animated, so a whole carried body can be placed.
	process_priority = 16
	_rng.randomize()
	grid = SecurityGrid.new(SecurityRules.HALL)
	for guard: CasinoGuard in guards():
		guard.grid = grid
	entity.session_reset.connect(_reset)
	entity.event_received.connect(_on_event)
	multiplayer.peer_disconnected.connect(_forget)
	_connect.call_deferred()


## Hooks into sibling features once every feature has loaded. Safe to call again.
func _connect() -> void:
	_metro()
	var combat := _combat()
	if combat != null and not combat.player_died.is_connected(_on_player_died):
		combat.player_died.connect(_on_player_died)
	for hook: Array in [
		[&"boxing", &"landed", _on_punch_landed], [&"spray", &"sprayed", _on_sprayed]
	]:
		for node: Node in get_tree().get_nodes_in_group(hook[0]):
			if node.multiplayer != multiplayer or not node.has_signal(hook[1]):
				continue
			if not node.is_connected(hook[1], hook[2]):
				node.connect(hook[1], hook[2])


func _on_player_died(victim: int, _attacker: int) -> void:
	release(victim)


func guards() -> Array[CasinoGuard]:
	var list: Array[CasinoGuard] = []
	for child: Node in $Guards.get_children():
		if child is CasinoGuard:
			list.append(child as CasinoGuard)
	return list


func phase_for(peer: int) -> int:
	var entry: Array = detentions.get(peer, [])
	return int(entry[2]) if entry.size() == 3 else SecurityRules.Phase.NONE


func offence_for(peer: int) -> StringName:
	var entry: Array = detentions.get(peer, [])
	return StringName(str(entry[1])) if entry.size() == 3 else &""


func guard_for(peer: int) -> CasinoGuard:
	var entry: Array = detentions.get(peer, [])
	var list := guards()
	if entry.size() != 3 or int(entry[0]) < 0 or int(entry[0]) >= list.size():
		return null
	return list[int(entry[0])]


## Seconds this peer has been in its current phase, as seen locally.
func phase_elapsed(peer: int) -> float:
	var seen: Array = _seen.get(peer, [])
	return float(seen[1]) if seen.size() == 2 else 0.0


## Server: reports `peer` to the security sharing `caller`'s multiplayer, if any.
## Features that refuse a forbidden act call this (see README.md).
static func report(caller: Node, peer: int, offence: StringName) -> void:
	for node: Node in caller.get_tree().get_nodes_in_group(&"casino_security"):
		if node.multiplayer == caller.multiplayer:
			(node as CasinoSecurity).report_misconduct(peer, offence)


## Server: someone did something the Golden Crown doesn't allow. Returns true when
## security responds (now or as soon as a guard is free). Called by the features
## that detect the act (holdables, gun_machine) and by this feature's own hooks.
func report_misconduct(peer: int, offence: StringName) -> bool:
	if not multiplayer.is_server() or not SecurityRules.is_offence(offence):
		return false
	if detentions.has(peer) or _queued(peer) or not _eligible(peer):
		return false
	_queue.append({"peer": peer, "offence": offence, "waited": 0.0})
	_dispatch_queue()
	return true


func _eligible(peer: int) -> bool:
	var player := _player(peer)
	if player == null or not SecurityRules.in_jurisdiction(player.global_position):
		return false
	var combat := _combat()
	if combat != null and combat.is_respawning(peer):
		return false
	return not _blacked_out(peer)


func _queued(peer: int) -> bool:
	for entry: Dictionary in _queue:
		if int(entry["peer"]) == peer:
			return true
	return false


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not grid.is_ready():
		_grid_wait -= delta
		if _grid_wait <= 0.0:
			grid.build_step(get_world_3d().direct_space_state, GRID_BUDGET, _player_rids())
		return
	advance(delta)


## Server: builds any remaining floor cells now (tests, tools).
func build_grid_now() -> void:
	grid.build_all(get_world_3d().direct_space_state, _player_rids())


## Server: progresses the queue, guards and every detention.
func advance(delta: float) -> void:
	if not multiplayer.is_server():
		return
	for entry: Dictionary in _queue.duplicate():
		entry["waited"] = float(entry["waited"]) + delta
		var peer := int(entry["peer"])
		if float(entry["waited"]) > SecurityRules.QUEUE_TIMEOUT_S or not _eligible(peer):
			_queue.erase(entry)
	_dispatch_queue()
	for guard: CasinoGuard in guards():
		var thrown := guard.net_state == SecurityRules.GuardState.THROWING
		if thrown and guard.net_carrying == 0 and guard.state_elapsed >= SecurityRules.THROW_S:
			_send_home(guard)
	for peer: int in detentions.keys():
		if not _timers.has(peer):
			continue
		_timers[peer] += delta
		var aboard := phase_for(peer) < SecurityRules.Phase.THROWN
		if _player(peer) == null or (aboard and _blacked_out(peer)):
			release(peer)
			continue
		match phase_for(peer):
			SecurityRules.Phase.HELD:
				_advance_held(peer)
			SecurityRules.Phase.CARRIED:
				_advance_carried(peer)
			SecurityRules.Phase.THROWN:
				_advance_thrown(peer, delta)
			SecurityRules.Phase.LANDED:
				if _timers[peer] >= SecurityRules.LANDED_S:
					release(peer)


func _dispatch_queue() -> void:
	if not grid.is_ready():
		return
	for entry: Dictionary in _queue.duplicate():
		var peer := int(entry["peer"])
		var player := _player(peer)
		if player == null:
			_queue.erase(entry)
			continue
		var list := guards()
		var positions: Array[Vector3] = []
		var free: Array[bool] = []
		for guard: CasinoGuard in list:
			positions.append(guard.position)
			free.append(guard.is_free())
		var index := SecurityRules.pick_guard(positions, free, player.global_position)
		if index < 0:
			return
		_queue.erase(entry)
		var route := _route_to(list[index].position, _feet(player))
		if route.is_empty() and not SecurityRules.can_grab(list[index].position, _feet(player)):
			continue
		_detain(peer, index, StringName(entry["offence"]), route)


func _detain(peer: int, index: int, offence: StringName, route: Array[Vector3]) -> void:
	var guard := guards()[index]
	guard.net_carrying = peer
	guard.walk(route, SecurityRules.GuardState.RESPONDING)
	_set_detention(peer, index, offence, SecurityRules.Phase.HELD)
	_replans[peer] = 0
	_say(peer, SecurityRules.callout(offence))


func _advance_held(peer: int) -> void:
	var guard := guard_for(peer)
	var player := _player(peer)
	if guard == null or not SecurityRules.in_jurisdiction(player.global_position):
		release(peer)
		return
	if guard.arrived():
		var feet := _feet(player)
		if SecurityRules.can_grab(guard.position, feet):
			guard.face(feet)
			guard.set_state(SecurityRules.GuardState.LIFTING)
			_stow(peer)
			_set_phase(peer, SecurityRules.Phase.CARRIED)
			_say(peer, SecurityRules.LIFT_LINE)
			entity.send_event(&"thud", {"at": feet})
			return
		_replans[peer] = int(_replans.get(peer, 0)) + 1
		var route := _route_to(guard.position, feet)
		if route.is_empty() or _replans[peer] > REPLANS:
			release(peer)
			return
		guard.walk(route, SecurityRules.GuardState.RESPONDING)
	if _timers[peer] > SecurityRules.RESPOND_TIMEOUT_S:
		release(peer)


func _advance_carried(peer: int) -> void:
	var guard := guard_for(peer)
	if guard == null:
		release(peer)
		return
	var cab := cab_marker()
	var stand := cab * SecurityRules.THROW_STAND
	match guard.net_state:
		SecurityRules.GuardState.LIFTING:
			if _timers[peer] >= SecurityRules.LIFT_S:
				var route := grid.route(guard.position, stand, 0.5, 0.6)
				if route.is_empty() and guard.position.distance_to(stand) > 1.0:
					release(peer)
					return
				guard.walk(route, SecurityRules.GuardState.CARRYING)
		SecurityRules.GuardState.CARRYING:
			if guard.arrived():
				guard.face(cab.origin)
				guard.set_state(SecurityRules.GuardState.DOORS)
				_timers[peer] = 0.0
				var cab_node := _cab()
				if cab_node != null and cab_node.net_state == ElevatorCab.State.CLOSED:
					cab_node.request_doors()
		SecurityRules.GuardState.DOORS:
			var cab_node := _cab()
			var open := cab_node == null or cab_node.net_state == ElevatorCab.State.OPEN
			if open or _timers[peer] >= SecurityRules.DOOR_WAIT_S:
				guard.set_state(SecurityRules.GuardState.THROWING)
				_timers[peer] = 0.0
				_say(peer, SecurityRules.THROW_LINE)
		SecurityRules.GuardState.THROWING:
			if _timers[peer] >= SecurityRules.RELEASE_S:
				# The guard finishes the heave, then walks back (see advance()).
				guard.net_carrying = 0
				_set_phase(peer, SecurityRules.Phase.THROWN)
				_start_delivery(peer)


func _start_delivery(peer: int) -> void:
	var player := _player(peer)
	var metro := _metro()
	# Without a metro the flight still plays, then the offender lands at the doors.
	_deliveries[peer] = {"position": Vector3.ZERO, "yaw": 0.0, "started": false, "waited": 0.0}
	if player == null or metro == null:
		return
	var spot := BoozeRules.wake_spot(
		_rng.randi_range(0, 3),
		_rng.randi_range(0, 1),
		_rng.randf(),
		player.movement.hull_height_m()
	)
	var stations: Array = metro.get("stations")
	var origin := (stations[int(spot["station"])] as Node3D).global_position
	_deliveries[peer] = {
		"position": origin + (spot["local"] as Vector3),
		"yaw": float(spot["yaw"]),
		"started": false,
		"waited": 0.0,
	}


func _advance_thrown(peer: int, delta: float) -> void:
	if not _deliveries.has(peer):
		return
	var trip := _deliveries[peer]
	trip["waited"] = float(trip["waited"]) + delta
	# Let the flight play out before the platform loads in.
	if _timers[peer] < SecurityRules.FLIGHT_S:
		return
	var metro := _metro()
	if metro == null or float(trip["waited"]) > SecurityRules.DELIVERY_TIMEOUT_S:
		if metro != null:
			metro.call("cancel_delivery", peer)
		_deliveries.erase(peer)
		_land_at_doors(peer)
		return
	if not bool(trip["started"]):
		var player := _player(peer)
		trip["started"] = (
			player != null
			and bool(metro.call("deliver", player, trip["position"], float(trip["yaw"])))
		)


## Fallback when the metro can't take someone: put them down outside its doors.
func _land_at_doors(peer: int) -> void:
	var player := _player(peer)
	if player != null:
		var at := cab_marker() * SecurityRules.THROW_STAND
		at.y += player.movement.hull_height_m() * 0.5 + 0.05
		player.server_teleport.rpc_id(peer, at)
	_set_phase(peer, SecurityRules.Phase.LANDED)


func _on_delivered(peer: int) -> void:
	if _deliveries.has(peer):
		_deliveries.erase(peer)
		_set_phase(peer, SecurityRules.Phase.LANDED)


## Server: ends a detention at once (death, disconnect, blackout, timeout). The
## guard, if still busy with this peer, walks back to its post.
func release(peer: int) -> void:
	if not multiplayer.is_server():
		return
	var guard := guard_for(peer)
	if guard != null and guard.net_carrying == peer:
		_send_home(guard)
	if _deliveries.has(peer) and _metro() != null:
		_metro().call("cancel_delivery", peer)
	_deliveries.erase(peer)
	_timers.erase(peer)
	_replans.erase(peer)
	for entry: Dictionary in _queue.duplicate():
		if int(entry["peer"]) == peer:
			_queue.erase(entry)
	if detentions.has(peer):
		var next := detentions.duplicate()
		next.erase(peer)
		detentions = next


## A route to beside an offender standing with their feet at `feet`: close up when
## the floor allows, otherwise within grabbing reach (someone up on a table).
func _route_to(from: Vector3, feet: Vector3) -> Array[Vector3]:
	var drop := SecurityRules.GRAB_DROP
	var route := grid.route(from, feet, SecurityRules.APPROACH, drop)
	if route.is_empty():
		route = grid.route(from, feet, SecurityRules.GRAB_RANGE - 0.1, drop)
	return route


func _send_home(guard: CasinoGuard) -> void:
	guard.net_carrying = 0
	var route: Array[Vector3] = []
	if grid.is_ready():
		route = grid.route(guard.position, guard.post, 0.5, 0.6)
	if route.is_empty():
		route.append(guard.post)
	guard.walk(route, SecurityRules.GuardState.RETURNING)


func _set_detention(peer: int, index: int, offence: StringName, phase: int) -> void:
	var next := detentions.duplicate()
	next[peer] = [index, str(offence), phase]
	detentions = next
	_timers[peer] = 0.0


func _set_phase(peer: int, phase: int) -> void:
	var entry: Array = detentions.get(peer, [])
	if entry.size() == 3:
		_set_detention(peer, int(entry[0]), StringName(str(entry[1])), phase)


## Puts away whatever the offender holds, so nothing floats beside the carry.
func _stow(peer: int) -> void:
	var hand := Hand.for_peer(get_tree(), peer)
	if hand != null and not hand.consumption.active() and not hand.inventory().loading:
		hand.inventory().stow_equipment([-1])
	var rig := GunRig.for_peer(get_tree(), peer)
	if rig != null:
		rig.holster()


func _forget(peer: int) -> void:
	release(peer)
	_seen.erase(peer)
	_start.erase(peer)
	_posed.erase(peer)


func _reset(_mode: Network.Mode) -> void:
	_queue.clear()
	_timers.clear()
	_replans.clear()
	_deliveries.clear()
	detentions = {}
	for guard: CasinoGuard in guards():
		guard.reset_to_post()


func _on_punch_landed(attacker: int, target: Node) -> void:
	var victim := target as Player
	if victim != null and victim.get_multiplayer_authority() != attacker:
		report_misconduct(attacker, &"assault")
	elif target.is_in_group(&"casino_patrons") or target is StationaryPatron:
		report_misconduct(attacker, &"assault")


func _on_sprayed(peer: int, point: Vector3) -> void:
	if SafeZone.covers(get_tree(), point):
		report_misconduct(peer, &"vandalism")


## Server: a line from security for `peer` only (skipped once they have left).
func _say(peer: int, text: String) -> void:
	if peer == multiplayer.get_unique_id() or peer in multiplayer.get_peers():
		entity.send_event(&"say", {"text": text}, peer)


func _on_event(event: StringName, payload: Dictionary) -> void:
	match event:
		&"say":
			Subtitles.say(get_tree(), SecurityRules.SPEAKER, str(payload.get("text", "")))
		&"thud":
			GameAudio.play_at(self, &"hit", payload.get("at", Vector3.ZERO))


func _process(delta: float) -> void:
	if detentions.is_empty() and _posed.is_empty():
		_seen.clear()
		return
	present(delta)


## Every peer: places carried and thrown bodies; stands them back up afterwards.
func present(delta: float) -> void:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player == null or player.multiplayer != multiplayer or player.is_queued_for_deletion():
			continue
		var peer := player.get_multiplayer_authority()
		if not _observe(peer, player):
			var seen: Array = _seen.get(peer, [SecurityRules.Phase.NONE, 0.0])
			_seen[peer] = [seen[0], float(seen[1]) + delta]
		var body := player.get_node_or_null("Body") as Node3D
		if body == null:
			continue
		var target: Variant = body_transform(peer)
		if target == null:
			if _posed.has(peer):
				_posed.erase(peer)
				var yaw := player.yaw if player.is_local() else player.net_yaw
				body.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO)
			continue
		_posed[peer] = true
		body.global_transform = target
		_dangle(body.get_node_or_null("Avatar") as BlockPlayerModel)


## Lets a slung or flying body's arms hang toward the floor (its front faces down)
## instead of reaching past the guard's head. Runs after the avatar has animated.
func _dangle(avatar: BlockPlayerModel) -> void:
	if avatar == null:
		return
	for arm: Node3D in [avatar._left_arm, avatar._right_arm]:
		arm.rotation = Vector3(1.45, 0.0, 0.0)
	for elbow: Node3D in [avatar._left_forearm, avatar._right_forearm]:
		elbow.rotation.x = 0.15
	if avatar.human.visible and avatar.human.skeleton != null:
		avatar.human.pose(avatar, false, false)


## Where `peer`'s body is drawn on this peer right now, or null when it is not
## being carried or thrown. The local view pins the capsule to the same place.
func body_transform(peer: int) -> Variant:
	var phase := phase_for(peer)
	_observe(peer, _player(peer))
	if phase == SecurityRules.Phase.NONE:
		return null
	var guard := guard_for(peer)
	var start: Transform3D = _start.get(peer, Transform3D.IDENTITY)
	if phase == SecurityRules.Phase.CARRIED and guard != null:
		var drawn := guard.drawn_transform()
		if guard.net_state == SecurityRules.GuardState.LIFTING:
			var lift := guard.state_elapsed / SecurityRules.LIFT_S
			return SecurityRules.lifted_body(start, drawn, lift)
		return SecurityRules.carry_body(drawn)
	if phase == SecurityRules.Phase.THROWN:
		var elapsed := phase_elapsed(peer)
		if elapsed >= SecurityRules.FLIGHT_S:
			# Through the doors: gone from view until the platform drop-off.
			return Transform3D(Basis.from_scale(Vector3.ONE * 0.001), cab_marker().origin)
		return SecurityRules.flight_body(start, cab_marker() * SecurityRules.CAB_TARGET, elapsed)
	return null


## Notes a phase change for `peer` on this peer: restarts its clock and captures
## where its body starts from (standing, or the shoulder for a throw). True when
## the phase just changed.
func _observe(peer: int, player: Player) -> bool:
	var phase := phase_for(peer)
	var seen: Array = _seen.get(peer, [SecurityRules.Phase.NONE, 0.0])
	if int(seen[0]) == phase:
		return false
	_seen[peer] = [phase, 0.0]
	var guard := guard_for(peer)
	var body := player.get_node_or_null("Body") as Node3D if player != null else null
	if phase == SecurityRules.Phase.THROWN and guard != null:
		_start[peer] = SecurityRules.carry_body(guard.drawn_transform())
	elif body != null:
		_start[peer] = body.global_transform
	return true


## The Crown metro elevator's threshold (+Z faces the hall).
func cab_marker() -> Transform3D:
	for node: Node in get_tree().get_nodes_in_group(&"metro_access"):
		var access := node as MetroAccess
		if access != null and access.zone_id == "crown" and access.is_inside_tree():
			return access.global_transform
	return CAB_FALLBACK


func _cab() -> ElevatorCab:
	for node: Node in get_tree().get_nodes_in_group(&"metro_access"):
		var access := node as MetroAccess
		if access != null and access.zone_id == "crown" and access.multiplayer == multiplayer:
			return access.source
	return null


func _feet(player: Player) -> Vector3:
	return player.global_position - Vector3.UP * player.movement.hull_height_m() * 0.5


func _player_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var body := node as CollisionObject3D
		if body != null:
			rids.append(body.get_rid())
	return rids


func _blacked_out(peer: int) -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"booze"):
		if node.multiplayer == multiplayer and node.has_method(&"phase_for"):
			return int(node.call(&"phase_for", peer)) != 0
	return false


func _combat() -> Combat:
	var combat := get_tree().get_first_node_in_group(&"combat") as Combat
	return combat if combat != null and combat.multiplayer == multiplayer else null


func _metro() -> Node:
	for node: Node in get_tree().get_nodes_in_group(&"metro_service"):
		if node.multiplayer == multiplayer and node.has_method("deliver"):
			if _metro_connected != node:
				_metro_connected = node
				node.connect(&"delivered", _on_delivered)
			return node
	return null


func _player(peer: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.multiplayer == multiplayer:
			if player.get_multiplayer_authority() == peer and not player.is_queued_for_deletion():
				return player
	return null
