class_name Penguin
extends AnimatableBody3D
## A decorative penguin that waddles in a slow circle around its spawn point forever
## — until she's shot, at which point she explodes and waddles back a few seconds
## later.
##
## Server-authoritative like the rest of shared state (see game/AGENTS.md): the server
## (or the offline peer, which is its own server) advances the patrol angle in
## `_physics_process` and publishes `net_position`/`net_yaw`/`net_alive`, which Sync
## (MultiplayerSynchronizer) replicates to every client. Non-authoritative peers only
## smooth toward the replicated values. The cosmetic side-to-side rock and the
## explosion debris run locally on every peer since they don't need to match exactly.
## The patrol math itself lives in penguin_waddle.gd so it's unit-testable on its own.
##
## Killable by any weapon: a physics body (not just a visual Node3D) so
## features/holdables/hand.gd's hitscan can hit her, in the `killable` group so
## `_fire` knows to call `take_hit` instead of features/combat's `apply_damage`,
## which is keyed by player peer id and doesn't apply here.
##
## Reacts to a nearby player wearing the "penguin" body model (see
## features/player_models) by waving a flipper and hopping in place. That reaction
## is purely cosmetic, computed independently by every peer each `_process` frame
## from data everyone already has (PlayerModels' replicated body_types, other
## players' replicated positions), so it needs no RPC of its own — same reasoning
## as the waddle rock and the explosion above.

const REMOTE_SMOOTHING := 12.0
const RESPAWN_DELAY_S := 4.0

## Replicated state (server -> everyone). See the synchronizer config in feature.tscn.
@export var net_position := Vector3.ZERO
@export var net_yaw := 0.0
@export var net_alive := true

var _home := Vector3.ZERO
var _angle := 0.0
var _elapsed := 0.0
var _respawn_timer := 0.0

@onready var _body: Node3D = $Body
@onready var _collider: CollisionShape3D = $Collider
@onready var _wave_flipper: Node3D = $Body/Torso/RightFlipper


func _ready() -> void:
	_home = position
	net_position = position
	add_to_group(&"killable")
	if not multiplayer.is_server():
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not net_alive:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		return
	_angle += (
		PenguinWaddle.angular_speed(PenguinWaddle.PATROL_RADIUS, PenguinWaddle.WALK_SPEED) * delta
	)
	position = PenguinWaddle.position_on_circle(_home, PenguinWaddle.PATROL_RADIUS, _angle)
	net_position = position
	net_yaw = PenguinWaddle.facing_yaw(_angle)


func _process(delta: float) -> void:
	_elapsed += delta
	if not multiplayer.is_server():
		var t := 1.0 - exp(-REMOTE_SMOOTHING * delta)
		position = position.lerp(net_position, t)
	_body.visible = net_alive
	_collider.disabled = not net_alive
	if not net_alive:
		return
	_body.rotation.y = net_yaw
	_body.rotation.z = PenguinWaddle.waddle_rock(
		_elapsed, PenguinWaddle.WADDLE_FREQUENCY, PenguinWaddle.WADDLE_AMPLITUDE
	)
	var reacting := _reacting_to_nearby_penguin_player()
	_body.position.y = (
		PenguinWaddle.react_bounce(
			_elapsed, PenguinWaddle.BOUNCE_FREQUENCY, PenguinWaddle.BOUNCE_HEIGHT
		)
		if reacting
		else 0.0
	)
	_wave_flipper.rotation.z = (
		(
			deg_to_rad(70.0)
			+ PenguinWaddle.wave_angle(
				_elapsed, PenguinWaddle.WAVE_FREQUENCY, PenguinWaddle.WAVE_AMPLITUDE
			)
		)
		if reacting
		else 0.0
	)


## True while any player currently wearing the "penguin" body model (see
## features/player_models/player_models.gd) stands within `REACT_RADIUS`. Reads
## only replicated state (body_types, player positions), so every peer computes
## the same cosmetic reaction independently without an RPC.
func _reacting_to_nearby_penguin_player() -> bool:
	var models := get_tree().get_first_node_in_group(&"player_models") as PlayerModels
	if models == null:
		return false
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player == null:
			continue
		if models.type_for(player.get_multiplayer_authority()) != "penguin":
			continue
		if global_position.distance_to(player.global_position) <= PenguinWaddle.REACT_RADIUS:
			return true
	return false


## Server-only: any weapon's hitscan calls this on a hit (see hand.gd's `_fire`,
## which routes to this instead of features/combat's `apply_damage` because she has
## no player peer id). One hit is always fatal, regardless of the weapon's damage
## value, so "killable with any weapon" holds even for the weakest gun.
func take_hit(_attacker_peer: int) -> void:
	if not multiplayer.is_server() or not net_alive:
		return
	net_alive = false
	_respawn_timer = RESPAWN_DELAY_S
	_explode.rpc()


func _respawn() -> void:
	net_alive = true
	_angle = 0.0
	position = _home
	net_position = _home
	net_yaw = 0.0


## Cosmetic only — every peer plays its own explosion locally, same as the waddle
## rock, so it doesn't need to be pixel-synced.
@rpc("authority", "call_local", "reliable")
func _explode() -> void:
	MeshExplosion.spawn(self, _body)
