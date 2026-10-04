extends Node3D
## The existing chat RPC supplies the authenticated sender; no client-selected player/path.

const ARRIVALS := {
	"dev": "dev_room/Room/Arrival",
	"casino": "dev_room/CasinoArrival",
	"lounge": "room_doors/Lounge/FromLobby",
	"cellar": "room_doors/Cellar/FromLounge",
	"hotel": "hotel_annex/Hotel/Arrival",
	"apartments": "apartments/Lobby/EntranceArrival",
	"props": "hotel_props/Room/Arrival",
	"garage": "procedural_rooms/Garage/Arrival",
	"street": "street_district/Room/Arrival",
}
const DEVELOPMENT: Array[String] = ["props", "garage", "street"]
const HELP := "!warp dev | casino | lounge | cellar | hotel | apartments | props | garage | street"

var _next_warp: Dictionary[int, int] = {}
var _entity: NetworkedEntity


func _ready() -> void:
	add_to_group(&"chat_commands")
	_entity = NetworkedEntity.new()
	_entity.name = "WarpEvents"
	add_child(_entity)
	_entity.event_received.connect(_preload_room)
	Network.mode_changed.connect(_reset)
	multiplayer.peer_disconnected.connect(_forget_peer)


func handle_chat_command(peer: int, command: String) -> void:
	if not multiplayer.is_server() or (command != "warp" and not command.begins_with("warp ")):
		return
	var player := _player(peer)
	if player == null or Time.get_ticks_msec() < _next_warp.get(peer, 0):
		return
	var words := command.split(" ", false)
	if words.size() != 2 or not ARRIVALS.has(words[1]):
		_notice(peer, HELP)
		return
	var place := words[1]
	if DEVELOPMENT.has(place) and not DevGate.cheats_enabled(get_tree()):
		_notice(peer, "That development destination requires sv_cheats 1.")
		return
	var arrival := get_parent().get_node_or_null(NodePath(ARRIVALS[place])) as Marker3D
	if arrival == null:
		_notice(peer, "That room is unavailable.")
		return
	_next_warp[peer] = Time.get_ticks_msec() + 1000
	var zones := ZoneInstances.for_node(self)
	if zones != null and arrival is SlumArrivalPoint:
		if not zones.enter_development_zone(player, arrival as SlumArrivalPoint):
			_notice(peer, "That room is unavailable.")
		return
	var ancestor: Node = arrival.get_parent()
	while ancestor != null:
		if ancestor is StreamedRoom:
			# Reliable owner event precedes teleport, so the landing floor already exists.
			_entity.send_event(&"preload", {"room": ancestor.get_path()}, peer)
			break
		ancestor = ancestor.get_parent()
	var runs := get_tree().get_first_node_in_group(&"slum_runs") as SlumRuns
	if runs != null:
		runs.finish(peer)
	player.server_teleport.rpc_id(peer, arrival.global_position, arrival.global_basis.get_euler().y)


func _preload_room(event: StringName, payload: Dictionary) -> void:
	if event != &"preload":
		return
	var room := get_node_or_null(payload.get("room", NodePath(""))) as StreamedRoom
	if room != null:
		room.load_room(RoomDoor.ARRIVAL_HOLD_MSEC)


func _player(peer: int) -> Player:
	for player: Player in get_tree().get_nodes_in_group(&"players"):
		if player.multiplayer == multiplayer and player.get_multiplayer_authority() == peer:
			return player
	return null


func _notice(peer: int, text: String) -> void:
	var chat := get_tree().get_first_node_in_group(&"chat_box")
	if chat != null:
		chat.send_notice(peer, text)


func _forget_peer(peer: int) -> void:
	_next_warp.erase(peer)


func _reset(_mode: Network.Mode) -> void:
	_next_warp.clear()
