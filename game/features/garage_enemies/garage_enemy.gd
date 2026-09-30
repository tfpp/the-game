class_name GarageEnemy
extends CharacterBody3D
## A hostile garage scavenger. The server senses players, chases, winds up and
## deals damage through features/combat; clients only smooth the replicated
## position and play the broadcast attack, hurt and death effects.
##
## In the `killable` group like the frogs: every weapon calls `take_hit()`, and
## each tier needs its own number of hits. Enemies sit on physics layer 2 so
## hitscans and projectiles hit them without them blocking player movement.

const REMOTE_SMOOTHING := 14.0
const SENSE_INTERVAL_S := 0.2
const GRAVITY := 18.0
const EYE_HEIGHT := 1.4
## Players farther than this from home aren't sensed at all, so idle enemies
## cost almost nothing while nobody is in the garage.
const WAKE_RADIUS := 30.0
## Cameras farther than this skip posing the rig; the enemy is barely visible.
const ANIMATE_RADIUS := 45.0

@export var tier := GarageEnemyTiers.Tier.LURKER

## Replicated through NetworkedEntity (see garage_enemy.tscn).
@export var net_position := Vector3.ZERO
@export var net_yaw := 0.0
@export var net_alive := true
@export var net_windup := false

var health := 1
var target_peer := 0

var _info: Dictionary
var _home := Vector3.ZERO
var _sense_timer := 0.0
var _cooldown := 0.0
var _windup_timer := 0.0
var _respawn_timer := 0.0
var _target_position := Vector3.INF
var _target_speed := 0.0
var _remote_ready := false

@onready var entity: NetworkedEntity = $NetworkedEntity
@onready var _model: GarageEnemyModel = $Model
@onready var _collider: CollisionShape3D = $Collider


func _ready() -> void:
	_info = GarageEnemyTiers.profile(tier)
	_home = position
	net_position = position
	health = int(_info["hits"])
	_model.equip(tier, absi(String(name).hash()))
	_collider.shape = _collider.shape.duplicate()
	var capsule := _collider.shape as CapsuleShape3D
	capsule.height = 1.7 * float(_info["scale"])
	_collider.position.y = capsule.height * 0.5
	add_to_group(&"killable")
	add_to_group(&"garage_enemies")
	entity.event_received.connect(_on_event)
	entity.session_reset.connect(func(_mode: Network.Mode) -> void: reset_to_home())
	if not multiplayer.is_server():
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		set_physics_process(false)


func profile() -> Dictionary:
	return _info


func home() -> Vector3:
	return _home


func _physics_process(delta: float) -> void:
	if not net_alive:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			reset_to_home()
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_sense_timer -= delta
	if _sense_timer <= 0.0:
		_sense_timer = SENSE_INTERVAL_S
		_sense()
	if net_windup:
		_windup_timer -= delta
		if _windup_timer <= 0.0:
			_strike()
	_move(delta)
	net_position = position


## Server-only. Picks up the target again every sense tick, so a player who
## leaves the floor, hides or dies simply stops being chased.
func _sense() -> void:
	var player := _find_target()
	if player == null:
		target_peer = 0
		_target_position = Vector3.INF
		net_windup = false
		return
	var point := player.global_position
	if _target_position != Vector3.INF and target_peer == player.get_multiplayer_authority():
		_target_speed = GarageEnemyTiers.flat_distance(point, _target_position) / SENSE_INTERVAL_S
	target_peer = player.get_multiplayer_authority()
	_target_position = point
	var distance := GarageEnemyTiers.flat_distance(global_position, point)
	if not net_windup and _cooldown <= 0.0 and distance <= float(_info["range"]):
		net_windup = true
		_windup_timer = float(_info["windup"])
		entity.send_event(&"windup")


func _find_target() -> Player:
	var players: Array[Player] = []
	var points: Array[Vector3] = []
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player == null or not player.is_inside_tree():
			continue
		var point := player.global_position
		if global_position.distance_to(point) > WAKE_RADIUS:
			continue
		# Don't follow anyone beyond the leash, so enemies hold their floor area.
		var from_home := GarageEnemyTiers.flat_distance(_global_home(), point)
		if from_home > float(_info["leash"]):
			continue
		if not can_see(player):
			continue
		# Keep chasing the current target (or whoever just shot us) past the
		# aggro radius while they stay visible, on this floor and inside the leash.
		if player.get_multiplayer_authority() == target_peer:
			if GarageEnemyTiers.same_floor(global_position, point):
				return player
		# Crouching players are noticed at half the usual distance (features/crouch).
		var aggro := GarageEnemyTiers.notice_radius(float(_info["aggro"]), _crouching(player))
		if GarageEnemyTiers.flat_distance(global_position, point) > aggro:
			continue
		players.append(player)
		points.append(point)
	var index := GarageEnemyTiers.nearest(global_position, points, float(_info["aggro"]))
	return players[index] if index >= 0 else null


func _crouching(player: Player) -> bool:
	var crouch := get_tree().get_first_node_in_group(&"crouching")
	return crouch != null and bool(crouch.call("is_crouching", player.get_multiplayer_authority()))


func can_see(player: Player) -> bool:
	var from := global_position + Vector3.UP * EYE_HEIGHT * float(_info["scale"])
	var query := PhysicsRayQueryParameters3D.create(from, player.global_position + Vector3.UP * 0.4)
	query.collision_mask = 1
	query.exclude = [get_rid(), player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _move(delta: float) -> void:
	var goal := _global_home()
	var chasing := _target_position != Vector3.INF
	if chasing:
		goal = _target_position
	var to_goal := goal - global_position
	to_goal.y = 0.0
	var distance := to_goal.length()
	var advance := GarageEnemyTiers.wants_to_advance(tier, distance) if chasing else distance > 0.3
	var speed := float(_info["speed"]) * (1.0 if chasing else 0.6)
	if net_windup:
		speed *= 0.3
	var planar := to_goal.normalized() * speed if advance and distance > 0.01 else Vector3.ZERO
	velocity.x = planar.x
	velocity.z = planar.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	if distance > 0.01 and (advance or chasing):
		net_yaw = GarageEnemyTiers.facing_yaw(_parent_direction(to_goal))


## Server-only: the wind-up finished. Melee needs the target still in reach; a
## gunman's shot needs a clear line and is less likely to land on a fast target.
func _strike() -> void:
	net_windup = false
	_cooldown = float(_info["cooldown"])
	var player := _player(target_peer)
	if player == null or not can_see(player):
		return
	var point := player.global_position
	var reach := float(_info["range"]) * 1.25
	if GarageEnemyTiers.flat_distance(global_position, point) > reach:
		return
	var hit := true
	if _info["ranged"]:
		hit = randf() < GarageEnemyTiers.hit_chance(_target_speed)
	entity.send_event(&"attack", {"to": point, "hit": hit})
	if hit:
		var combat := get_tree().get_first_node_in_group(&"combat")
		if combat != null:
			# The victim is also the "attacker", so dying to an enemy never awards
			# another player a kill.
			var peer := player.get_multiplayer_authority()
			combat.call("apply_damage", peer, float(_info["damage"]), peer)


## Server-only: any weapon's hit. Being shot turns the enemy towards its attacker.
func take_hit(attacker_peer: int) -> void:
	if not multiplayer.is_server() or not net_alive:
		return
	health -= 1
	var attacker := _player(attacker_peer)
	if attacker != null and GarageEnemyTiers.same_floor(global_position, attacker.global_position):
		target_peer = attacker_peer
		_target_position = attacker.global_position
	if health > 0:
		entity.send_event(&"hurt")
		return
	entity.send_event(&"die")
	net_alive = false
	net_windup = false
	target_peer = 0
	_target_position = Vector3.INF
	_respawn_timer = float(_info["respawn"])


func reset_to_home() -> void:
	if not multiplayer.is_server():
		return
	position = _home
	net_position = _home
	velocity = Vector3.ZERO
	net_yaw = 0.0
	net_alive = true
	net_windup = false
	health = int(_info["hits"])
	target_peer = 0
	_target_position = Vector3.INF
	_cooldown = 0.0


func _process(delta: float) -> void:
	var before := position
	if not multiplayer.is_server():
		if not _remote_ready:
			position = net_position
			_remote_ready = true
		position = position.lerp(net_position, 1.0 - exp(-REMOTE_SMOOTHING * delta))
		if net_position.distance_to(position) > 4.0:
			position = net_position
	_model.visible = net_alive
	_collider.disabled = not net_alive
	if not net_alive:
		return
	_model.rotation.y = lerp_angle(_model.rotation.y, net_yaw, minf(delta * 10.0, 1.0))
	if not _near_camera():
		return
	var speed := Vector2(position.x - before.x, position.z - before.z).length() / maxf(delta, 0.001)
	if multiplayer.is_server():
		speed = Vector2(velocity.x, velocity.z).length()
	_model.animate(delta, speed, net_windup)


func _on_event(event: StringName, payload: Dictionary) -> void:
	match event:
		&"windup":
			GameAudio.play_at(self, &"equip", global_position)
		&"hurt":
			_model.flash()
			GameAudio.play_at(self, &"hit", global_position)
		&"die":
			MeshExplosion.spawn(self, _model)
		&"attack":
			_model.strike()
			_play_attack(payload)


func _play_attack(payload: Dictionary) -> void:
	var to: Variant = payload.get("to")
	if not to is Vector3:
		return
	if not _info["ranged"]:
		GameAudio.play_at(self, &"impact", global_position)
		return
	GameAudio.play_at(self, &"pistol", global_position)
	var from := global_position + Vector3.UP * EYE_HEIGHT * float(_info["scale"])
	var tracer := EnemyTracer.create(from, to as Vector3, bool(payload.get("hit", false)))
	add_child(tracer)


func _global_home() -> Vector3:
	var parent := get_parent() as Node3D
	return parent.to_global(_home) if parent != null else _home


func _player(peer: int) -> Player:
	if peer == 0:
		return null
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == peer:
			return player
	return null


## Turns a global direction into the parent's space, so `net_yaw` (applied to the
## model locally) faces the right way under a rotated parent like the basement.
func _parent_direction(direction: Vector3) -> Vector3:
	var parent := get_parent() as Node3D
	return parent.global_basis.inverse() * direction if parent != null else direction


## Only pose the skinned rig for cameras close enough to see it.
func _near_camera() -> bool:
	var camera := get_viewport().get_camera_3d()
	return camera == null or camera.global_position.distance_to(global_position) < ANIMATE_RADIUS
