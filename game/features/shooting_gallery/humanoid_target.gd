class_name HumanoidTarget
extends AnimatableBody3D
## A standing shooting-gallery dummy: killable by any weapon, gibs with gore, and
## pops back up a few seconds later. Modeled closely on
## features/penguin/penguin.gd, but at a fixed spot rather than patrolling — a
## gallery target should always be where you last saw it, not wander off.
##
## Killable by any weapon: a physics body (not just a visual Node3D) so
## features/holdables/hand.gd's hitscan and features/gun_machine/projectile.gd's
## ray query can both hit it, in the `killable` group so they route to `take_hit`
## instead of features/combat's `apply_damage`, which is keyed by player peer id
## and doesn't apply here.

const RESPAWN_DELAY_S := 3.0

## Boxing (features/boxing calls `take_punch`). Punch strengths add up as "daze",
## which wears off over time; reaching 1.0 knocks the dummy down into a ragdoll.
const KNOCKDOWN_DAZE := 1.0
const DAZE_RECOVERY_PER_S := 0.35
## A downed dummy gets back up this long after the last punch it took.
const RAGDOLL_S := 4.0
## Punches at least this strong (power punches) send a downed dummy sliding.
const KNOCK_AWAY_MIN_STRENGTH := 0.5
## Slide speed per unit of strength and floor friction: a full power punch slides
## a downed dummy about 2.6 m, a weak one about 0.7 m.
const KNOCK_AWAY_SPEED := 6.5
const SLIDE_FRICTION := 8.0
const FALL_SPEED := 4.0
const GET_UP_SPEED := 1.5
## Lifts the toppled body so its torso rests on the floor rather than through it.
const LYING_LIFT := 0.13

## Replicated (server -> everyone). See the synchronizer config in
## humanoid_target.tscn. Position never changes once spawned, so this is the only
## networked state — like features/penguin/penguin.gd's `net_alive`.
@export var net_alive := true
## Replicated: knocked down by punches, and which horizontal world direction its
## head fell toward. `position` is replicated too, since punches slide it around.
@export var net_ragdoll := false
@export var net_fall_dir := Vector3.FORWARD

## Set by shooting_gallery.gd's spawn data, identically on every peer, before this
## node enters the tree — the same way features/frogs/frog.gd's `body_color` arrives.
var jumpsuit_color := Color(0.55, 0.35, 0.15)

var _respawn_timer := 0.0
var _daze := 0.0
var _ragdoll_timer := 0.0
var _slide_velocity := Vector3.ZERO
var _home := Vector3.ZERO
## Local visual state: 0 standing, 1 lying flat; plus a short flinch after a punch.
var _fallen := 0.0
var _flinch := 0.0
var _flinch_dir := Vector3.FORWARD
var _collider_rest := Transform3D.IDENTITY

@onready var _body: HumanoidTargetModel = $Body
@onready var _collider: CollisionShape3D = $Collider


func _ready() -> void:
	add_to_group(&"killable")
	add_to_group(&"shooting_gallery_targets")
	_body.build(jumpsuit_color)
	_home = position
	# Punches move it from script (and clients get the replicated position), so the
	# node transform must be the source of truth rather than the physics state.
	sync_to_physics = false
	_collider_rest = _collider.transform
	if not multiplayer.is_server():
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	if net_alive:
		_daze = maxf(_daze - DAZE_RECOVERY_PER_S * delta, 0.0)
		if net_ragdoll:
			_slide(delta)
			_ragdoll_timer -= delta
			if _ragdoll_timer <= 0.0:
				net_ragdoll = false
		return
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		net_alive = true
		net_ragdoll = false
		_slide_velocity = Vector3.ZERO
		_daze = 0.0
		position = _home


func _process(delta: float) -> void:
	_body.visible = net_alive
	_collider.disabled = not net_alive
	var goal := 1.0 if net_ragdoll and net_alive else 0.0
	_fallen = move_toward(_fallen, goal, (FALL_SPEED if goal > _fallen else GET_UP_SPEED) * delta)
	_flinch = maxf(_flinch - delta * 4.0, 0.0)
	var to_local := global_basis.inverse()
	var pose := Transform3D(
		(
			fall_basis(to_local * net_fall_dir, _fallen)
			* fall_basis(to_local * _flinch_dir, _flinch * 0.2)
		),
		Vector3.UP * LYING_LIFT * _fallen
	)
	_body.transform = pose
	_collider.transform = pose * _collider_rest


## Server-only: a punch from features/boxing. `strength` is 0..1 (a jab is 0.25,
## a fully charged power punch 1.0) and `direction` the horizontal way it pushes.
## Enough punches (or one hard one) knock the dummy down; power punches on a
## downed dummy knock it a short way across the floor.
func take_punch(_attacker_peer: int, strength: float, direction: Vector3) -> void:
	if not multiplayer.is_server() or not net_alive:
		return
	var push := Vector3(direction.x, 0.0, direction.z).normalized()
	if push.is_zero_approx():
		push = -global_basis.z
	if net_ragdoll:
		_ragdoll_timer = RAGDOLL_S
		if strength >= KNOCK_AWAY_MIN_STRENGTH:
			_slide_velocity = push * KNOCK_AWAY_SPEED * strength
	else:
		_daze += strength
		if _daze >= KNOCKDOWN_DAZE:
			_daze = 0.0
			net_ragdoll = true
			net_fall_dir = push
			_ragdoll_timer = RAGDOLL_S
	_flinch_from.rpc(push)


func is_knocked_down() -> bool:
	return net_ragdoll


## Moves a downed dummy along its knock-away slide, stopping at walls and cover.
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
	var speed := maxf(_slide_velocity.length() - SLIDE_FRICTION * delta, 0.0)
	_slide_velocity = _slide_velocity.normalized() * speed


## Cosmetic only: a quick recoil away from the punch on every peer.
@rpc("authority", "call_local", "reliable")
func _flinch_from(direction: Vector3) -> void:
	_flinch = 1.0
	_flinch_dir = direction


## Server-only: any weapon kills a dummy outright, regardless of its damage value —
## the same "killable with any weapon" contract features/penguin/penguin.gd's
## `take_hit` documents.
func take_hit(_attacker_peer: int) -> void:
	if not multiplayer.is_server() or not net_alive:
		return
	net_alive = false
	_respawn_timer = RESPAWN_DELAY_S
	_explode.rpc()


## Cosmetic only — every peer plays its own gore locally, like
## features/penguin/penguin.gd's `_explode`.
@rpc("authority", "call_local", "reliable")
func _explode() -> void:
	MeshExplosion.spawn(self, _body)
	GoreSplatter.spawn(self, _body)


## Tips an upright (+Y) body over its feet so its head points along `fall_dir`
## once `amount` reaches 1. `fall_dir` is horizontal, in the body's parent space.
static func fall_basis(fall_dir: Vector3, amount: float) -> Basis:
	var flat := Vector3(fall_dir.x, 0.0, fall_dir.z)
	if flat.length_squared() < 0.0001 or amount <= 0.0:
		return Basis.IDENTITY
	var axis := Vector3.UP.cross(flat.normalized()).normalized()
	return Basis(axis, PI * 0.5 * clampf(amount, 0.0, 1.0))
