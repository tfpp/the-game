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
const TALK_RANGE := 2.5
const SPEECH_S := 4.0

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
## Server-only, Mamdani: last fare time (seconds) per account key.
var _fare_claims: Dictionary[String, float] = {}
var _talk: NetworkedInteraction
var _speech: Label3D
var _speech_timer := 0.0

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
	if is_essential():
		_setup_talk()


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
	if _speech != null and _speech.visible:
		_speech_timer -= delta
		_speech.visible = _speech_timer > 0.0


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
## Mamdani is essential: he's knocked out instead and gets up where he fell.
func take_hit(_attacker_peer: int) -> void:
	if not multiplayer.is_server() or not net_alive:
		return
	if is_essential():
		_knock_out()
		return
	net_alive = false
	net_ragdoll = false
	_respawn_timer = RESPAWN_DELAY_S
	_explode.rpc()


## Mamdani (PatronModel.MAMDANI_LOOK) never dies.
func is_essential() -> bool:
	return look == PatronModel.MAMDANI_LOOK


func _knock_out() -> void:
	if not net_ragdoll:
		net_fall_dir = Basis(Vector3.UP, net_yaw) * Vector3.BACK
		if _return_to == null:
			_return_to = position
	net_ragdoll = true
	_daze = 0.0
	_ragdoll_timer = maxf(_ragdoll_timer, PatronMath.KNOCKOUT_S)
	_flinch_from.rpc(net_fall_dir)


func _setup_talk() -> void:
	add_to_group(&"interactables")
	_talk = NetworkedInteraction.new()
	_talk.name = "Talk"
	_talk.interaction_range = TALK_RANGE
	add_child(_talk)
	_talk.register_use(can_use, _give_fare)
	_talk.event_received.connect(_on_talk_event)
	_speech = Label3D.new()
	_speech.name = "Speech"
	_speech.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_speech.font_size = 36
	_speech.outline_size = 10
	_speech.pixel_size = 0.004
	_speech.modulate = Color(1.0, 0.95, 0.6)
	_speech.position = Vector3(0, 2.35, 0)
	_speech.visible = false
	add_child(_speech)


func can_use(player: Player) -> bool:
	return is_essential() and net_alive and not net_ragdoll and _talk.in_range(player)


func interaction_text() -> String:
	return "Talk to %s (subway fare)" % PatronModel.MAMDANI_NAME


func use() -> void:
	_talk.request_use()


## Server-only, called by the Talk entity after range and state checks. Pays
## subway fare through the shared wallet once an hour per account.
func _give_fare(player: Player) -> bool:
	var peer := player.get_multiplayer_authority()
	var key := _claim_key(peer)
	var now := _now_s()
	var wait := PatronMath.fare_wait_s(_fare_claims.get(key, -1.0), now)
	net_yaw = PatronMath.facing_yaw(player.global_position - position)
	_stagger = STAGGER_S * 2.0
	if wait > 0.0:
		_say(peer, "I already covered your fare. Come back in %s." % PatronMath.wait_text(wait))
		return true
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	if wallet == null:
		return false
	_fare_claims[key] = now
	_say(peer, "Fare-free buses and the subway on me! +%s" % _fare_text())
	_pay_fare(wallet, peer, key)
	return true


func _pay_fare(wallet: PlayerMoney, peer: int, key: String) -> void:
	var id := Crypto.new().generate_random_bytes(32).hex_encode()
	var result: Dictionary = await wallet.credit_coin(peer, id)
	if result.has("error"):
		_fare_claims.erase(key)
		_say(peer, "My wallet's stuck, try again in a moment.")


static func _fare_text() -> String:
	return PlayerMoney.format_money(PlayerMoney.COIN_CREDIT_CENTS)


## Accounts keep their cooldown across reconnects; guests fall back to the peer.
static func _claim_key(peer: int) -> String:
	var account: Dictionary = Network.peer_accounts.get(peer, {})
	var id := int(account.get("account_id", 0))
	return "account:%d" % id if id > 0 else "peer:%d" % peer


func _now_s() -> float:
	return Time.get_ticks_msec() / 1000.0


func _say(peer: int, text: String) -> void:
	_talk.send_event(&"say", {"text": text}, peer)


func _on_talk_event(event: StringName, payload: Dictionary) -> void:
	if event != &"say" or _speech == null:
		return
	_speech.text = str(payload.get("text", ""))
	_speech.visible = true
	_speech_timer = SPEECH_S


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
