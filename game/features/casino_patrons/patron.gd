class_name CasinoPatron
extends AnimatableBody3D
## A casino patron who strolls a loop of the gaming floor. Punches from
## features/boxing daze them and, once the daze adds up, knock them into a limp
## ragdoll; any weapon gibs them. The server walks them and replicates their
## state; every peer animates its own copy.
##
## Knockdown rules and tuning match features/shooting_gallery/humanoid_target.gd
## so punching feels the same everywhere.

const REMOTE_SMOOTHING := 12.0
const RESPAWN_DELAY_S := 6.0
## How long a patron stands still, facing whoever hit them, after a jab.
const STAGGER_S := 0.9
## A punch shoves a standing patron back at this speed times sqrt(strength).
const STAGGER_PUSH_SPEED := 4.5
const FALL_SPEED := 4.0
const GET_UP_SPEED := 1.5
const LYING_LIFT := 0.14
const STRIDE_PER_M := 4.2

## Replicated (server -> everyone), see patron.tscn's synchronizer.
@export var net_position := Vector3.ZERO
@export var net_yaw := 0.0
@export var net_alive := true
@export var net_ragdoll := false
@export var net_fall_dir := Vector3.FORWARD

## Set from spawn data on every peer before entering the tree.
var look := 0
var route: Array[Vector3] = []

var _waypoint := 0
var _pause := 0.0
var _stagger := 0.0
## How long the patron has waited for a player in its way.
var _waited := 0.0
var _daze := 0.0
var _ragdoll_timer := 0.0
var _respawn_timer := 0.0
var _slide_velocity := Vector3.ZERO
## Where the patron was pushed off its route from; it walks back there first.
var _return_to: Variant = null

# Local animation state.
var _fallen := 0.0
var _flinch := 0.0
var _flinch_dir := Vector3.FORWARD
var _phase := 0.0
var _walk := 0.0
var _idle := 0.0
var _last_position := Vector3.ZERO
var _collider_rest := Transform3D.IDENTITY

@onready var _body: PatronModel = $Body
@onready var _collider: CollisionShape3D = $Collider


func _ready() -> void:
	add_to_group(&"killable")
	add_to_group(&"casino_patrons")
	_body.build(look)
	sync_to_physics = false
	_collider_rest = _collider.transform
	if multiplayer.is_server():
		net_position = position
		_waypoint = PatronMath.next_waypoint(0, route.size())
	else:
		set_physics_process(false)
		position = net_position
	_last_position = position
	_idle = look * 1.7


func _physics_process(delta: float) -> void:
	if not net_alive:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		return
	_daze = maxf(_daze - HumanoidTarget.DAZE_RECOVERY_PER_S * delta, 0.0)
	_slide(delta)
	if net_ragdoll:
		_ragdoll_timer -= delta
		if _ragdoll_timer <= 0.0:
			net_ragdoll = false
			_stagger = STAGGER_S
	elif _stagger > 0.0:
		_stagger -= delta
	elif _pause > 0.0:
		_pause -= delta
	else:
		_walk_on(delta)
	net_position = position


func _walk_on(delta: float) -> void:
	if route.is_empty():
		return
	var goal: Vector3 = _return_to if _return_to != null else route[_waypoint]
	var to_goal := goal - position
	to_goal.y = 0.0
	if to_goal.length() < 0.05:
		if _return_to != null:
			_return_to = null
		else:
			_waypoint = PatronMath.next_waypoint(_waypoint, route.size())
			_pause = randf_range(PatronMath.PAUSE_MIN_S, PatronMath.PAUSE_MAX_S)
		return
	var heading := to_goal.normalized()
	net_yaw = PatronMath.facing_yaw(heading)
	if not _player_in_the_way(heading):
		_waited = 0.0
	elif _waited < PatronMath.MAX_WAIT_S:
		_waited += delta
		return
	position = position.move_toward(
		Vector3(goal.x, position.y, goal.z), PatronMath.WALK_SPEED * delta
	)


func _player_in_the_way(heading: Vector3) -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Node3D
		if player != null and PatronMath.is_in_the_way(position, heading, player.global_position):
			return true
	return false


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		position = position.lerp(net_position, 1.0 - exp(-REMOTE_SMOOTHING * delta))
	_body.visible = net_alive
	_collider.disabled = not net_alive
	var moved := Vector3(position.x - _last_position.x, 0.0, position.z - _last_position.z).length()
	_last_position = position
	var goal := 1.0 if net_ragdoll and net_alive else 0.0
	_fallen = move_toward(_fallen, goal, (FALL_SPEED if goal > _fallen else GET_UP_SPEED) * delta)
	_flinch = maxf(_flinch - delta * 3.0, 0.0)
	var walking := 1.0 if delta > 0.0 and moved / delta > 0.3 and goal == 0.0 else 0.0
	_walk = move_toward(_walk, walking, delta * 5.0)
	_phase = fmod(_phase + moved * STRIDE_PER_M, TAU)
	_idle += delta
	var yaw := Basis(Vector3.UP, net_yaw)
	var pose := Transform3D(
		(
			HumanoidTarget.fall_basis(net_fall_dir, _fallen)
			* HumanoidTarget.fall_basis(_flinch_dir, _flinch * 0.15)
			* yaw
		),
		Vector3.UP * LYING_LIFT * _fallen
	)
	_body.transform = pose
	_body.pose(_phase, _walk, _fallen, _flinch, _idle)
	_collider.transform = pose * _collider_rest


## Server-only: a punch from features/boxing. `strength` is 0..1, `direction`
## the horizontal way it pushes.
func take_punch(_attacker_peer: int, strength: float, direction: Vector3) -> void:
	if not multiplayer.is_server() or not net_alive:
		return
	var push := Vector3(direction.x, 0.0, direction.z).normalized()
	if push.is_zero_approx():
		push = Basis(Vector3.UP, net_yaw) * Vector3.BACK
	if _return_to == null:
		_return_to = position
	if net_ragdoll:
		_ragdoll_timer = HumanoidTarget.RAGDOLL_S
		if strength >= HumanoidTarget.KNOCK_AWAY_MIN_STRENGTH:
			_slide_velocity = push * HumanoidTarget.KNOCK_AWAY_SPEED * strength
	else:
		_daze += strength
		net_yaw = PatronMath.facing_yaw(-push)
		if _daze >= HumanoidTarget.KNOCKDOWN_DAZE:
			_daze = 0.0
			net_ragdoll = true
			net_fall_dir = push
			_ragdoll_timer = HumanoidTarget.RAGDOLL_S
			_slide_velocity = push * STAGGER_PUSH_SPEED * sqrt(strength)
		else:
			_stagger = STAGGER_S
			_slide_velocity = push * STAGGER_PUSH_SPEED * sqrt(strength)
	_flinch_from.rpc(push)


func is_knocked_down() -> bool:
	return net_ragdoll


## Server-only: any weapon gibs a patron; they walk back in a few seconds later.
func take_hit(_attacker_peer: int) -> void:
	if not multiplayer.is_server() or not net_alive:
		return
	net_alive = false
	net_ragdoll = false
	_respawn_timer = RESPAWN_DELAY_S
	_explode.rpc()


func _respawn() -> void:
	net_alive = true
	_daze = 0.0
	_stagger = 0.0
	_slide_velocity = Vector3.ZERO
	_return_to = null
	if not route.is_empty():
		position = route[0]
		_waypoint = PatronMath.next_waypoint(0, route.size())
	net_position = position


## Moves the patron along a knock-back, stopping at walls and furniture.
func _slide(delta: float) -> void:
	if _slide_velocity.is_zero_approx():
		return
	var step := _slide_velocity * delta
	var from := global_position + Vector3.UP * 0.3
	var query := PhysicsRayQueryParameters3D.create(
		from, from + step + step.normalized() * 0.4, 1, [get_rid()]
	)
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		_slide_velocity = Vector3.ZERO
		return
	global_position += step
	var speed := maxf(_slide_velocity.length() - HumanoidTarget.SLIDE_FRICTION * delta, 0.0)
	_slide_velocity = _slide_velocity.normalized() * speed


@rpc("authority", "call_local", "reliable")
func _flinch_from(direction: Vector3) -> void:
	_flinch = 1.0
	_flinch_dir = direction


@rpc("authority", "call_local", "reliable")
func _explode() -> void:
	MeshExplosion.spawn(self, _body)
	GoreSplatter.spawn(self, _body)
