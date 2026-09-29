class_name Bird
extends AnimatableBody3D
## A friendly wandering bird that flies continuously between the active player, other
## players, and NPCs on the casino floor.
##
## Server-authoritative: the server selects destinations, calculates flight arcs,
## and publishes `net_position`, `net_yaw`, `net_pitch`, `net_roll`, `net_flying`,
## and `net_alive`. Clients interpolate the puppet and animate wing flapping locally.
##
## Killable by any weapon: like the penguin and frogs, a hit triggers an explosion
## effect, hides the bird, and schedules a respawn.

enum State {
	STATE_FLYING,
	STATE_PERCHED,
}

const RESPAWN_DELAY_S := 4.0

## Replicated state (server -> clients). See synchronizer config in feature.tscn.
@export var net_position := Vector3.ZERO
@export var net_yaw := 0.0
@export var net_pitch := 0.0
@export var net_roll := 0.0
@export var net_flying := true
@export var net_alive := true

var _state: State = State.STATE_FLYING
var _flight_progress := 0.0
var _flight_start := Vector3.ZERO
var _arc := 1.0
var _target: Node3D = null
var _perch_seed := 0.0
var _rest_timer := 0.0
var _respawn_timer := 0.0
var _elapsed := 0.0
var _fallback_perch_idx := 0

@onready var _body: Node3D = $Body
@onready var _collider: CollisionShape3D = $Collider
@onready var _left_wing: Node3D = $Body/WingLeft
@onready var _right_wing: Node3D = $Body/WingRight
@onready var _audio: AudioStreamPlayer3D = $Audio


func _ready() -> void:
	sync_to_physics = false
	add_to_group(&"killable")
	add_to_group(&"birds")
	_audio.stream = BirdChirp.stream()
	if multiplayer.is_server():
		net_position = global_position
		_flight_start = global_position
		_pick_and_start_flight()
	else:
		set_physics_process(false)
		global_position = net_position


func _physics_process(delta: float) -> void:
	if not net_alive:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		return

	if _state == State.STATE_FLYING:
		_step_flying(delta)
	elif _state == State.STATE_PERCHED:
		_step_perched(delta)

	net_position = global_position


func _step_flying(delta: float) -> void:
	if _target != null and is_instance_valid(_target):
		var alive_val: Variant = _target.get("net_alive")
		if alive_val != null and not bool(alive_val):
			_target = null

	if _target == null or not is_instance_valid(_target):
		var next := BirdFlight.select_next_target(null, _get_players(), _get_npcs(), randf())
		if next != null:
			_target = next
			_flight_start = global_position
			_flight_progress = 0.0

	var destination := _current_destination()
	var horiz_dist := (
		Vector2(destination.x - _flight_start.x, destination.z - _flight_start.z).length()
	)
	_arc = BirdFlight.arc_height(horiz_dist)
	var total_dist := maxf(_flight_start.distance_to(destination), 0.5)
	_flight_progress += (BirdFlight.CRUISE_SPEED / total_dist) * delta

	if _flight_progress >= 1.0:
		_flight_progress = 1.0
		global_position = destination
		_state = State.STATE_PERCHED
		net_flying = false
		_rest_timer = randf_range(BirdFlight.REST_MIN_S, BirdFlight.REST_MAX_S)
	else:
		var new_pos := BirdFlight.flight_position(
			_flight_start, destination, _flight_progress, _arc
		)
		var vel := BirdFlight.flight_velocity(_flight_start, destination, _flight_progress, _arc)
		global_position = new_pos
		var angles := BirdFlight.facing_angles(vel)
		var prev_yaw := net_yaw
		net_yaw = angles.x
		net_pitch = angles.y
		net_roll = BirdFlight.bank_angle(angles.x - prev_yaw, delta)


func _step_perched(delta: float) -> void:
	if _target != null and is_instance_valid(_target):
		var alive_val: Variant = _target.get("net_alive")
		if alive_val != null and not bool(alive_val):
			_pick_and_start_flight()
			return
		global_position = _current_destination()
	_rest_timer -= delta
	if _rest_timer <= 0.0:
		_pick_and_start_flight()


func _process(delta: float) -> void:
	_elapsed += delta
	if not multiplayer.is_server():
		var t := 1.0 - exp(-BirdFlight.REMOTE_SMOOTHING * delta)
		global_position = global_position.lerp(net_position, t)

	_body.visible = net_alive
	_collider.disabled = not net_alive
	if not net_alive:
		return

	_body.rotation.y = net_yaw
	_body.rotation.x = net_pitch
	_body.rotation.z = net_roll

	var wing_z := BirdFlight.wing_angle(_elapsed, net_flying)
	_left_wing.rotation.z = wing_z
	_right_wing.rotation.z = -wing_z


func _current_destination() -> Vector3:
	if _target != null and is_instance_valid(_target):
		return _target.global_position + BirdFlight.perch_offset(_target, _perch_seed)
	return BirdFlight.DEFAULT_PERCHES[_fallback_perch_idx % BirdFlight.DEFAULT_PERCHES.size()]


func _pick_and_start_flight() -> void:
	var players := _get_players()
	var npcs := _get_npcs()
	var next := BirdFlight.select_next_target(_target, players, npcs, randf())
	if next == null:
		_fallback_perch_idx = (_fallback_perch_idx + 1) % BirdFlight.DEFAULT_PERCHES.size()
	_target = next
	_flight_start = global_position
	_flight_progress = 0.0
	_state = State.STATE_FLYING
	net_flying = true
	_perch_seed = randf()
	_chirp.rpc()


func _get_players() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var p := node as Node3D
		if p != null and is_instance_valid(p):
			result.append(p)
	return result


func _get_npcs() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for group_name: StringName in [&"casino_patrons", &"npcs", &"frogs", &"gnomes"]:
		for node: Node in get_tree().get_nodes_in_group(group_name):
			var n := node as Node3D
			if n != null and is_instance_valid(n) and not result.has(n):
				result.append(n)
	return result


func take_hit(_attacker_peer: int) -> void:
	if not multiplayer.is_server() or not net_alive:
		return
	net_alive = false
	_respawn_timer = RESPAWN_DELAY_S
	_explode.rpc()


func _respawn() -> void:
	net_alive = true
	_flight_start = global_position
	_state = State.STATE_FLYING
	_flight_progress = 0.0
	_target = null
	_pick_and_start_flight()


@rpc("authority", "call_local", "reliable")
func _explode() -> void:
	MeshExplosion.spawn(self, _body)


@rpc("authority", "call_local", "unreliable")
func _chirp() -> void:
	if _audio != null and not _audio.playing:
		_audio.play()
