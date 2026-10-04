class_name OperationsVan
extends Node3D
## Static shared endpoint. Only the authenticated requester sees the map/transition.

const TRAVEL_SECONDS := 2.0
const ZONE_NAMES: Array[String] = [
	"The Golden Crown",
	"Basement Garage · B1",
	"Street District",
	"Gun Shop · Rusty Hogg's",
	"Crown Strip Mall"
]
const ZONE_HINTS: Array[String] = [
	"Casino, shops and friends",
	"Five floors · hostile enemies",
	"Streets, alleys and searchable containers",
	"Guns and pawn counter",
	"Kebabs, poke bowls and Wendy's · outdoor dining"
]

@export var arrivals: Array[NodePath] = []
@export var panel_path: NodePath
## Garage travel is developer-only and enters a ready private instance.
@export var dev_routes := PackedInt32Array([1])

var _pending: Dictionary[int, Dictionary] = {}
@onready var entity: NetworkedInteraction = $NetworkedEntity
@onready var panel: VanTravelPanel = get_node(panel_path)


func _ready() -> void:
	add_to_group(&"interactables")
	entity.register_use(can_use, _open_map)
	entity.register_action(&"travel", _validate_trip, _begin_trip)
	entity.event_received.connect(_event)
	entity.request_finished.connect(_result)
	entity.session_reset.connect(_reset)
	multiplayer.peer_disconnected.connect(_cancel_peer)
	var combat := get_tree().get_first_node_in_group(&"combat") as Combat
	if combat != null:
		combat.player_died.connect(_on_death)


func interaction_text() -> String:
	return "Van · open travel map"


func can_use(player: Player) -> bool:
	return entity.in_range(player) and _available(player.get_multiplayer_authority())


func use() -> void:
	entity.request_use()


func arrival(zone: int) -> Marker3D:
	if zone < 0 or zone >= arrivals.size():
		return null
	if zone in dev_routes and not DevGate.cheats_enabled(get_tree()):
		return null
	return get_node_or_null(arrivals[zone]) as Marker3D


func request_trip(zone: int) -> void:
	entity.request_action(&"travel", {"zone": zone})


func _available(peer: int) -> bool:
	var combat := get_tree().get_first_node_in_group(&"combat") as Combat
	return not _pending.has(peer) and (combat == null or not combat.is_respawning(peer))


func _open_map(player: Player) -> bool:
	entity.send_event(&"map", {}, player.get_multiplayer_authority())
	return true


func _validate_trip(peer: int, payload: Dictionary) -> bool:
	var player := entity.player_for_peer(peer)
	return (
		payload.size() == 1
		and payload.get("zone") is int
		and arrival(int(payload["zone"])) != null
		and entity.in_range(player)
		and _available(peer)
	)


func _begin_trip(peer: int, payload: Dictionary) -> bool:
	_pending[peer] = {"zone": int(payload["zone"]), "remaining": TRAVEL_SECONDS}
	entity.send_event(&"depart", {"zone": int(payload["zone"])}, peer)
	return true


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	for peer: int in _pending.keys():
		var trip: Dictionary = _pending[peer]
		var player := entity.player_for_peer(peer)
		if not entity.in_range(player):
			_cancel_peer(peer)
			continue
		trip["remaining"] = float(trip["remaining"]) - delta
		if float(trip["remaining"]) > 0:
			continue
		_pending.erase(peer)
		var target := arrival(int(trip["zone"]))
		if target == null:
			entity.send_event(&"cancel", {}, peer)
			continue
		var zones := ZoneInstances.for_node(self)
		if zones != null and target is SlumArrivalPoint:
			if zones.enter_development_zone(player, target as SlumArrivalPoint):
				var run := zones.scope_for(zones.registry.instance_of(peer)) as SlumInstance
				entity.send_event(&"destination", {"position": run.entry_position()}, peer)
			else:
				entity.send_event(&"cancel", {}, peer)
			continue
		var runs := get_tree().get_first_node_in_group(&"slum_runs") as SlumRuns
		if runs != null:
			runs.finish(peer)
		player.server_teleport.rpc_id(
			peer, target.global_position, target.global_basis.get_euler().y
		)


func _event(event: StringName, payload: Dictionary) -> void:
	match event:
		&"map":
			panel.open_map(self)
		&"depart":
			var zone := int(payload["zone"])
			var target := arrival(zone)
			if target == null:
				return
			var ancestor := target.get_parent()
			while ancestor != null:
				if ancestor is StreamedRoom:
					(ancestor as StreamedRoom).load_room(6000)
					break
				ancestor = ancestor.get_parent()
			panel.depart(self, zone, target.global_position)
			GameAudio.play_ui(self, &"van_departure")
		&"cancel":
			panel.close()
		&"destination":
			panel.update_destination(payload["position"])


func _result(action: StringName, result: NetworkedEntity.Result) -> void:
	if action == &"travel" and result != NetworkedEntity.Result.ACCEPTED:
		panel.reject_trip()


func _cancel_peer(peer: int) -> void:
	var existed := _pending.erase(peer)
	if existed and (peer == multiplayer.get_unique_id() or multiplayer.get_peers().has(peer)):
		entity.send_event(&"cancel", {}, peer)


func _on_death(peer: int, _attacker: int) -> void:
	if multiplayer.is_server():
		_pending.erase(peer)
	if peer == multiplayer.get_unique_id():
		panel.close(false)


func _reset(_mode: Network.Mode) -> void:
	_pending.clear()
	panel.close(false)
