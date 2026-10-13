class_name CasinoGuard
extends AnimatableBody3D
## One Golden Crown bouncer. The server walks it along routes from
## CasinoSecurity's walkable grid and sets its state; every peer animates its own
## copy from the replicated position, facing and state. Players pass through it
## (layer 2, like patrons), but punches and kicks land, and count against you.

const REMOTE_SMOOTHING := 10.0
## Head-turn and pose updates stop beyond this distance from the camera.
const POSE_RANGE := 40.0
## A guard standing watch with its arms crossed re-poses this often (seconds).
const IDLE_POSE_S := 0.1

## Where the guard stands watch, and which way it faces there (set in the scene).
@export var post := Vector3.ZERO
@export var post_yaw := 0.0
@export var look := 0

## Replicated (server -> everyone), see guard.tscn's NetworkedEntity.
@export var net_position := Vector3.ZERO
@export var net_yaw := 0.0
@export var net_state: SecurityRules.GuardState = SecurityRules.GuardState.POSTED
## The peer being carried or thrown (0 when none).
@export var net_carrying := 0

## Server: the remaining route, and the floor height source.
var path: Array[Vector3] = []
var grid: SecurityGrid
## Seconds in the current state, as seen on this peer.
var state_elapsed := 0.0
var _seen_state := -1
var _walk := 0.0
var _idle := 0.0
var _last_position := Vector3.ZERO
var _flinch := 0.0
var _pose_delta := 0.0

@onready var body: GuardModel = $Body
@onready var entity: NetworkedEntity = $NetworkedEntity


func _ready() -> void:
	add_to_group(&"casino_guards")
	sync_to_physics = false
	body.build_guard(look)
	_idle = look * 2.3
	entity.event_received.connect(_on_event)
	entity.session_reset.connect(func(_mode: Network.Mode) -> void: reset_to_post())
	if multiplayer.is_server():
		reset_to_post()
	else:
		position = net_position
		rotation.y = net_yaw
	_last_position = position


## Server: back at the post, arms crossed, carrying nobody.
func reset_to_post() -> void:
	path.clear()
	position = post
	net_position = post
	net_yaw = post_yaw
	net_carrying = 0
	set_state(SecurityRules.GuardState.POSTED)


func set_state(state: SecurityRules.GuardState) -> void:
	net_state = state


func is_free() -> bool:
	return (
		net_state == SecurityRules.GuardState.POSTED
		or net_state == SecurityRules.GuardState.RETURNING
	)


## Server: walks `route` in `state`. An empty route means already there.
func walk(route: Array[Vector3], state: SecurityRules.GuardState) -> void:
	path = route.duplicate()
	set_state(state)


func arrived() -> bool:
	return path.is_empty()


## Server: turns to face a point.
func face(point: Vector3) -> void:
	var to := point - position
	to.y = 0.0
	if to.length() > 0.05:
		net_yaw = SecurityRules.facing_yaw(to.normalized())


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	var speed := SecurityRules.speed_for(net_state)
	if speed > 0.0 and not path.is_empty():
		var budget := speed * delta
		while budget > 0.0 and not path.is_empty():
			var goal := path[0]
			var to := Vector3(goal.x - position.x, 0.0, goal.z - position.z)
			var distance := to.length()
			if distance <= budget:
				position = Vector3(goal.x, position.y, goal.z)
				path.remove_at(0)
				budget -= distance
			else:
				position += to / distance * budget
				net_yaw = SecurityRules.facing_yaw(to / distance)
				budget = 0.0
		var floor_y := grid.floor_at(position, position.y) if grid != null else position.y
		position.y = move_toward(position.y, floor_y, delta * 3.0)
	if net_state == SecurityRules.GuardState.RETURNING and path.is_empty():
		position = post
		net_yaw = post_yaw
		set_state(SecurityRules.GuardState.POSTED)
	net_position = position


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		var t := 1.0 - exp(-REMOTE_SMOOTHING * delta)
		position = position.lerp(net_position, t)
		rotation.y = lerp_angle(rotation.y, net_yaw, t)
	else:
		rotation.y = lerp_angle(rotation.y, net_yaw, 1.0 - exp(-REMOTE_SMOOTHING * delta))
	if int(net_state) != _seen_state:
		_seen_state = int(net_state)
		state_elapsed = 0.0
	else:
		state_elapsed += delta
	var moved := Vector3(position.x - _last_position.x, 0.0, position.z - _last_position.z).length()
	_last_position = position
	var walking := 1.0 if delta > 0.0 and moved / delta > 0.3 else 0.0
	_walk = move_toward(_walk, walking, delta * 5.0)
	_idle += delta
	_flinch = maxf(_flinch - delta * 3.0, 0.0)
	if Network.mode == Network.Mode.SERVER and DisplayServer.get_name() == "headless":
		return
	if not _near_camera():
		return
	_pose_delta += delta
	var settled := (
		net_state == SecurityRules.GuardState.POSTED
		and state_elapsed > 1.0
		and _walk <= 0.0
		and _flinch <= 0.0
	)
	if settled and _pose_delta < IDLE_POSE_S:
		return
	var weights := SecurityRules.guard_pose(net_state, state_elapsed)
	body.rotation.x = -_flinch * 0.12
	body.pose_guard(_pose_delta, _walk, _idle, weights["arms"], weights["carry"], weights["throw"])
	_pose_delta = 0.0


## World transform of the guard as drawn on this peer (smoothed).
func drawn_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, rotation.y), position)


## Server-only: a punch or kick from features/boxing. It barely registers on a
## bouncer, but security takes it personally.
func take_punch(attacker_peer: int, _strength: float, _direction: Vector3) -> void:
	if not multiplayer.is_server():
		return
	entity.send_event(&"flinch")
	CasinoSecurity.report(self, attacker_peer, &"security")


func _on_event(event: StringName, _payload: Dictionary) -> void:
	if event == &"flinch":
		_flinch = 1.0


func _near_camera() -> bool:
	if not visible:
		return false
	var camera := get_viewport().get_camera_3d()
	return camera == null or camera.global_position.distance_to(global_position) < POSE_RANGE
