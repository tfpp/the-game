class_name FoodCourt
extends Node3D
## The strip mall dining plaza: booth seating that anyone can sit in.
##
## The server owns `net_seats` (one occupant peer per seat, 0 = free) and validates
## sit/stand requests through the NetworkedEntity component. Movement stays
## client-authoritative, so each client pins its own seated player to the seat, like
## the ferry helm. Other peers see the replicated position and the seated pose that
## `BlockPlayerModel` reads through `is_seated()`.

const BOOTH_SCRIPT := preload("res://features/food_court/booth.gd")
const SEAT_SCRIPT := preload("res://features/food_court/booth_seat.gd")

## Booth centres on the plaza floor, in feature-local coordinates.
const BOOTHS: Array[Vector3] = [
	Vector3(7.5, 0, 22.4),
	Vector3(12.5, 0, 22.4),
	Vector3(17.5, 0, 22.4),
	Vector3(22.5, 0, 22.4),
	Vector3(7.5, 0, 33.6),
	Vector3(12.5, 0, 33.6),
	Vector3(17.5, 0, 33.6),
	Vector3(22.5, 0, 33.6),
]
const SIT_RANGE := 1.8
## Seated players further than this from their seat were moved away (respawn, kill
## plane, noclip); the server frees the seat.
const LEAVE_DISTANCE := 3.0

@export var net_seats := PackedInt32Array():
	set(value):
		net_seats = value
		_seats_changed = true

var seats: Array[Node3D] = []
var _seats_changed := true
var _pinned: Player
var _pinned_index := -1
var _pin_position := Vector3.ZERO
var _stand_requested := false

@onready var entity: NetworkedInteraction = $NetworkedEntity


func _ready() -> void:
	add_to_group(&"seating")
	var root := Node3D.new()
	root.name = "Booths"
	add_child(root)
	for index: int in BOOTHS.size():
		var booth := Node3D.new()
		booth.name = "Booth%d" % index
		booth.set_script(BOOTH_SCRIPT)
		booth.position = BOOTHS[index]
		root.add_child(booth)
		for local: Vector3 in BOOTH_SCRIPT.SEATS:
			var seat := Node3D.new()
			seat.name = "Seat%d" % seats.size()
			seat.set_script(SEAT_SCRIPT)
			seat.position = local
			# Face the table: forward is -Z, so the +Z bench keeps yaw 0.
			seat.rotation.y = 0.0 if local.z > 0.0 else PI
			seat.set("court", self)
			seat.set("index", seats.size())
			booth.add_child(seat)
			seats.append(seat)
	# Static casino anchors exist before the feature loader reaches food_court.
	# Sort paths so every peer assigns identical indices; booth indices stay intact.
	var anchors := get_tree().get_nodes_in_group(&"casino_seats")
	anchors.sort_custom(
		func(a: Node, b: Node) -> bool: return str(a.get_path()) < str(b.get_path())
	)
	for anchor: Node in anchors:
		anchor.set("court", self)
		anchor.set("index", seats.size())
		seats.append(anchor as Node3D)
	var empty := PackedInt32Array()
	empty.resize(seats.size())
	net_seats = empty
	entity.register_action(&"sit", _may_sit, _sit)
	entity.register_action(&"stand", _may_stand, _stand)
	entity.session_reset.connect(_reset_session)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_connect_combat.call_deferred()


## Where a seated player's origin goes: hips on the cushion (see BlockPlayerModel).
func sit_position(index: int) -> Vector3:
	return seats[index].global_position + Vector3(0, BOOTH_SCRIPT.HIP_OFFSET, 0)


## Yaw that faces a seat's player towards its table (forward is -Z).
func sit_yaw(index: int) -> float:
	return seats[index].global_rotation.y


## Floor point at the open end of the seat's bench.
func stand_position(index: int) -> Vector3:
	if bool(seats[index].get("casino_seat")):
		return seats[index].to_global(seats[index].get("exit_offset"))
	var local := seats[index].position
	var booth := seats[index].get_parent() as Node3D
	return booth.to_global(Vector3(signf(local.x) * BOOTH_SCRIPT.STEP_OUT, 0, local.z))


func seat_of(peer: int) -> int:
	return net_seats.find(peer) if peer != 0 else -1


func is_seated(peer: int) -> bool:
	return seat_of(peer) >= 0


## Fixed body heading from authoritative occupancy; view/aim yaw remains independent.
func seated_yaw(peer: int) -> float:
	var index := seat_of(peer)
	return sit_yaw(index) if index >= 0 else NAN


func request_sit(index: int) -> void:
	entity.request_action(&"sit", {"seat": index})


func request_stand() -> void:
	entity.request_action(&"stand")


func _may_sit(peer: int, payload: Dictionary) -> bool:
	for other: Node in get_tree().get_nodes_in_group(&"seating"):
		if other != self and bool(other.call("is_seated", peer)):
			return false
	if payload.size() != 1 or typeof(payload.get("seat")) != TYPE_INT:
		return false
	var index: int = payload["seat"]
	if index < 0 or index >= net_seats.size() or net_seats[index] != 0:
		return false
	var player := entity.player_for_peer(peer)
	return player != null and in_reach(player.net_position, index)


func in_reach(point: Vector3, index: int) -> bool:
	return seats[index].global_position.distance_to(point) <= SIT_RANGE


func _sit(peer: int, payload: Dictionary) -> bool:
	var seats_now := net_seats.duplicate()
	var old := seats_now.find(peer)
	if old >= 0:
		seats_now[old] = 0
	seats_now[int(payload["seat"])] = peer
	net_seats = seats_now
	return true


func _may_stand(peer: int, payload: Dictionary) -> bool:
	return payload.is_empty() and is_seated(peer)


func _stand(peer: int, _payload: Dictionary) -> bool:
	return _free_peer(peer)


func _free_peer(peer: int) -> bool:
	var index := seat_of(peer)
	if index < 0:
		return false
	var seats_now := net_seats.duplicate()
	seats_now[index] = 0
	net_seats = seats_now
	return true


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_release_moved_players()
	_update_local_pin(delta)


func _release_moved_players() -> void:
	for index: int in net_seats.size():
		var peer := net_seats[index]
		if peer == 0:
			continue
		var player := entity.player_for_peer(peer)
		if player == null or player.net_position.distance_to(sit_position(index)) > LEAVE_DISTANCE:
			_free_peer(peer)


func _update_local_pin(delta: float) -> void:
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	var index := seat_of(multiplayer.get_unique_id()) if player != null else -1
	if _seats_changed:
		_seats_changed = false
		_stand_requested = false
	if index < 0:
		_release_pin(true)
		return
	if _pinned != player or _pinned_index != index:
		_release_pin(false)
		_pinned = player
		_pinned_index = index
		player.set_physics_process(false)
		player.yaw = sit_yaw(index)
		player.pitch = 0.0
		_pin_position = player.global_position
	elif player.global_position.distance_to(_pin_position) > 0.5:
		# Something else moved us (respawn, teleport): let go and give up the seat.
		_release_pin(false)
		_ask_to_stand()
		return
	if Controls.gameplay_active():
		var look := Controls.consume_look(delta)
		player.yaw -= look.x
		player.pitch = clampf(player.pitch - look.y, deg_to_rad(-89.0), deg_to_rad(89.0))
		if (
			Input.is_action_just_pressed(&"jump")
			or Controls.consume_jump()
			or Controls.movement().length() > 0.5
		):
			_ask_to_stand()
	_pin(player, sit_position(index))


func _pin(player: Player, at: Vector3) -> void:
	_pin_position = at
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.net_position = at
	player.net_velocity = Vector3.ZERO
	player.net_yaw = player.yaw
	player.net_pitch = player.pitch
	player.reset_physics_interpolation()


func _ask_to_stand() -> void:
	if not _stand_requested:
		_stand_requested = true
		request_stand()


## Standing up steps out past the end of the bench, clear of the table.
func _release_pin(step_out: bool) -> void:
	if is_instance_valid(_pinned):
		# A player something else moved away (respawn, teleport) stays where they are.
		var still_seated := _pinned.global_position.distance_to(_pin_position) < 0.5
		if step_out and still_seated and _pinned_index >= 0:
			var spot := stand_position(_pinned_index)
			spot.y += _pinned.movement.hull_height_m() * 0.5 + 0.02
			_pin(_pinned, spot)
		Controls.clear_input()
		_pinned.set_physics_process(true)
	_pinned = null
	_pinned_index = -1


func _connect_combat() -> void:
	var combat := get_tree().get_first_node_in_group(&"combat")
	if combat != null and combat.has_signal(&"player_died"):
		combat.connect(&"player_died", _on_player_died)


func _on_player_died(victim_peer: int, _attacker_peer: int) -> void:
	if multiplayer.is_server():
		_free_peer(victim_peer)


func _on_peer_disconnected(peer: int) -> void:
	if multiplayer.is_server():
		_free_peer(peer)


func _reset_session(_mode: Network.Mode) -> void:
	var empty := PackedInt32Array()
	empty.resize(seats.size())
	net_seats = empty
