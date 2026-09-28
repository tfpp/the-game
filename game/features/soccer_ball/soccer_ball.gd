class_name SoccerBall
extends CharacterBody3D
## A soccer ball that sits on the floor and behaves the way dust2's does in
## Counter-Strike: walking into it shoves it (`_apply_bumps`), and any gun can kick
## it (`take_hit`, called by features/holdables/hand.gd's hitscan the same way it
## kills a features/frogs/frog.gd or features/penguin/penguin.gd — this only needs
## to sit in the `killable` group, so hand.gd never has to know this feature exists).
##
## Server-authoritative like the rest of shared state (game/AGENTS.md): the server
## integrates gravity, ground/wall bounces and rolling friction in `_physics_process`
## (math lives in ball_physics.gd, unit-tested on its own) and publishes
## `net_position`; other peers only smooth toward it, the same way
## features/holdables/thrown_item.gd replicates a flight arc. Every peer spins the
## visible mesh to match however far the ball actually moved that frame, purely
## cosmetic like the ferry wheel's rock, so it doesn't need to match exactly.
##
## On layer 2 like a frog: hitscans (mask 1 | 2) can hit it, but it never blocks
## player movement (players' mask is 1 only).

const BallPhysics := preload("res://features/soccer_ball/ball_physics.gd")

const REMOTE_SMOOTHING := 16.0

## Replicated (server -> everyone). See the synchronizer config in feature.tscn.
@export var net_position := Vector3.ZERO

@onready var _view: Node3D = $View


func _ready() -> void:
	add_to_group(&"killable")
	floor_snap_length = 0.0
	net_position = global_position
	if not multiplayer.is_server():
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	velocity = BallPhysics.apply_gravity(velocity, delta)
	velocity = BallPhysics.apply_drag(
		velocity,
		delta,
		BallPhysics.GROUND_FRICTION_PER_S if is_on_floor() else BallPhysics.AIR_DRAG_PER_S
	)
	_apply_bumps()
	var pre_move := velocity
	move_and_slide()
	var next := pre_move
	if is_on_floor() and pre_move.y < 0.0:
		next.y = BallPhysics.bounce_off_floor(pre_move).y
	for i in get_slide_collision_count():
		var normal := get_slide_collision(i).get_normal()
		if absf(normal.y) < 0.5:
			next = BallPhysics.reflect_off_wall(next, normal)
	velocity = BallPhysics.settle(next) if is_on_floor() else next
	net_position = global_position


func _process(delta: float) -> void:
	var previous := global_position
	if not multiplayer.is_server():
		var t := 1.0 - exp(-REMOTE_SMOOTHING * delta)
		global_position = global_position.lerp(net_position, t)
	var spin := BallPhysics.rolling_spin(global_position - previous, BallPhysics.RADIUS_M)
	_view.quaternion = (spin * _view.quaternion).normalized()


## Server-only: any nearby player's body shoves the ball (see ball_physics.gd's
## `bump_velocity`). Uses each player's replicated `net_position`/`net_velocity`
## rather than `position`/`velocity`, which are only meaningful on the peer that
## owns a given player (game/AGENTS.md's client-authoritative movement rule).
func _apply_bumps() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player == null:
			continue
		var contact := BallPhysics.RADIUS_M + player.movement.hull_radius_m()
		velocity = BallPhysics.bump_velocity(
			global_position, velocity, player.net_position, player.net_velocity, contact
		)


## Server-only: any weapon's hitscan calls this on a hit (see hand.gd's `_fire`,
## which routes to this instead of features/combat's `apply_damage` because a ball
## has no player peer id). The kick direction is approximated as shooter-to-ball
## since `take_hit` only ever carries the attacker's peer id.
func take_hit(attacker_peer: int) -> void:
	if not multiplayer.is_server():
		return
	var shooter := _player_for_peer(attacker_peer)
	var origin := shooter.net_position if shooter != null else global_position + Vector3.FORWARD
	velocity = BallPhysics.kick_velocity(velocity, origin, global_position)


func _player_for_peer(peer_id: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == peer_id:
			return player
	return null
