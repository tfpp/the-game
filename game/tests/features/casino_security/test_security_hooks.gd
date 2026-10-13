extends GutTest
## How the trouble is noticed: features that refuse or witness an act in the
## Golden Crown report it (held guns, gun-machine guns, punches and kicks, spray
## paint, hitting a guard). Their original behaviour is unchanged.

const SAFE_ZONE := preload("res://features/safe_zone/feature.tscn")
const SECURITY := preload("res://features/casino_security/feature.tscn")
const BOXING := preload("res://features/boxing/feature.tscn")
const SPRAY := preload("res://features/spray/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const HAND := preload("res://features/holdables/hand.tscn")
const GUN_RIG := preload("res://features/gun_machine/gun_rig.tscn")

var _security: CasinoSecurity
var _combat: Combat


class MachineStub:
	extends Node
	var spawned: Array[Dictionary] = []

	func spawn_projectile(data: Dictionary) -> void:
		spawned.append(data)


## A punchable body in the given group (a roaming patron, or a toy ball).
class PunchStub:
	extends StaticBody3D
	var punches := 0

	func _init(group: StringName) -> void:
		add_to_group(group)
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.8, 2.0, 0.8)
		collider.shape = shape
		add_child(collider)

	func take_punch(_attacker: int, _strength: float, _direction: Vector3) -> void:
		punches += 1

	func take_hit(_attacker: int) -> void:
		punches += 1


func before_each() -> void:
	add_child_autofree(SAFE_ZONE.instantiate())
	_combat = Combat.new()
	add_child_autofree(_combat)
	_security = SECURITY.instantiate() as CasinoSecurity
	add_child_autofree(_security)
	_security.set_physics_process(false)


func after_each() -> void:
	await get_tree().process_frame


func _player(peer: int, at: Vector3) -> Player:
	var player := PLAYER.instantiate() as Player
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	add_child_autofree(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.global_position = at
	player.net_position = at
	return player


## The grid is not needed to record an offence; it queues until guards can walk.
func _reported(peer: int) -> StringName:
	if _security.detentions.has(peer):
		return _security.offence_for(peer)
	for entry: Dictionary in _security._queue:
		if int(entry["peer"]) == peer:
			return StringName(entry["offence"])
	return &""


func test_trying_to_fire_a_held_gun_in_the_crown_calls_security() -> void:
	_player(1, Vector3(2, 0.92, 5))
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	var shots: Array[String] = []
	hand.fired.connect(func(id: String) -> void: shots.append(id))
	await get_tree().physics_frame
	hand.net_item_id = "pistol"
	hand.inventory().collect("ammo:pistol:1")
	hand.request_primary_action()
	assert_eq(shots, [] as Array[String], "still no shot in the safe zone")
	assert_eq(hand.inventory().ammo_for("pistol"), 1, "and no ammo spent")
	assert_eq(_reported(1), &"firearm")


func test_non_weapons_and_guns_outside_the_crown_are_not_reported() -> void:
	var player := _player(1, Vector3(2, 0.92, 5))
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	await get_tree().physics_frame
	hand.net_item_id = "banana"
	hand.request_primary_action()
	assert_eq(_reported(1), &"", "eating a banana is fine")
	player.global_position = Vector3(0, 1.2, 918)
	player.net_position = player.global_position
	hand.net_item_id = "pistol"
	hand.inventory().collect("ammo:pistol:1")
	hand.request_primary_action()
	assert_eq(_reported(1), &"", "the slums are not security's business")


func test_gun_machine_guns_are_reported_too() -> void:
	_player(1, Vector3(2, 0.92, 5))
	var stub := MachineStub.new()
	stub.add_to_group(&"gun_machine_root")
	add_child_autofree(stub)
	var rig := GUN_RIG.instantiate() as GunRig
	rig.peer_id = 1
	add_child_autofree(rig)
	rig.set_process(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	rig.equip(GunGenerator.generate(rng))
	var ammo := rig.net_ammo_in_mag
	rig.request_fire()
	assert_true(stub.spawned.is_empty())
	assert_eq(rig.net_ammo_in_mag, ammo)
	assert_eq(_reported(1), &"firearm")


func _boxing() -> Boxing:
	var boxing := BOXING.instantiate() as Boxing
	add_child_autofree(boxing)
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	_security._connect()
	return boxing


func test_punching_a_guest_is_assault_but_kicking_a_ball_is_not() -> void:
	var attacker := _player(1, Vector3(2, 0.92, 5))
	attacker.net_yaw = 0.0
	var victim := _player(2, Vector3(2, 0.92, 4))
	var boxing := _boxing()
	var landed: Array[Node] = []
	boxing.landed.connect(func(_peer: int, target: Node) -> void: landed.append(target))
	await wait_physics_frames(2)
	var ball := PunchStub.new(&"killable")
	add_child_autofree(ball)
	victim.global_position = Vector3(2, 0.92, 9)
	ball.global_position = Vector3(2, 0.9, 4)
	await wait_physics_frames(2)
	assert_eq(boxing.punch(1, 1.0), ball)
	assert_eq(landed, [ball] as Array[Node])
	assert_eq(_reported(1), &"", "toys are fair game")
	ball.global_position = Vector3(30, 0, 30)
	victim.global_position = Vector3(2, 0.92, 4)
	await wait_physics_frames(2)
	boxing._ready_at_ms.clear()
	assert_eq(boxing.punch(1, 0.1), victim)
	assert_eq(_combat.health_for(2), Combat.MAX_HEALTH, "the Crown still blocks the damage")
	assert_eq(_reported(1), &"assault")


func test_punching_a_patron_is_assault() -> void:
	_player(1, Vector3(2, 0.92, 5))
	var boxing := _boxing()
	var patron := PunchStub.new(&"casino_patrons")
	add_child_autofree(patron)
	patron.global_position = Vector3(2, 0.9, 4)
	await wait_physics_frames(2)
	assert_eq(boxing.punch(1, 0.1), patron)
	assert_eq(patron.punches, 1, "the patron still flinches")
	assert_eq(_reported(1), &"assault")


func test_punching_a_guard_is_picking_a_fight_with_security() -> void:
	var guard := _security.guards()[0]
	_player(1, guard.position + Vector3(0, 0.92, 1.0))
	var boxing := _boxing()
	await wait_physics_frames(2)
	assert_eq(boxing.punch(1, 1.0), guard)
	assert_eq(_reported(1), &"security")
	assert_eq(guard.net_state, SecurityRules.GuardState.POSTED, "doesn't even flinch off post")


func test_spray_painting_the_crown_is_vandalism() -> void:
	_player(1, Vector3(2, 0.92, 5))
	var spray := SPRAY.instantiate() as Spray
	add_child_autofree(spray)
	_security._connect()
	var sprayed: Array[Vector3] = []
	spray.sprayed.connect(func(_peer: int, point: Vector3) -> void: sprayed.append(point))
	spray.request_spray(Vector3(2, 1.5, 3), Vector3.BACK)
	assert_eq(sprayed, [Vector3(2, 1.5, 3)] as Array[Vector3])
	assert_eq(spray.get_child_count(), 1, "the decal is still placed")
	assert_eq(_reported(1), &"vandalism")
