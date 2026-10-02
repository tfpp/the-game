extends GutTest
## The Golden Crown safe zone (features/safe_zone): PvP damage and gunfire are
## refused inside, while slum combat and self-inflicted damage still work.

const FeatureScene := preload("res://features/safe_zone/feature.tscn")
const PlayerScene := preload("res://core/player/player.tscn")
const HandScene := preload("res://features/holdables/hand.tscn")
const GunRigScene := preload("res://features/gun_machine/gun_rig.tscn")

## Slum arrivals and the B1–B5 garage under the casino must stay unprotected.
const SLUM_POINTS: Array[Vector3] = [
	Vector3(-10, 1.2, 595), Vector3(0, 1.2, 918), Vector3(21, -6, -25), Vector3(21, -22, -25)
]
const CROWN_POINTS: Array[Vector3] = [
	Vector3(2, 0.2, 5),  # spawn
	Vector3(0, -1.25, 0),  # gaming pit
	Vector3(0, 0, -17.5),  # elevator
	Vector3(-26, 0, 0),  # petting parlor
	Vector3(-9, 0, 24.5),  # pawn shop
	Vector3(28.7, 0, 29.35),  # kebab shop
	Vector3(-50, 3, -58),  # annex northwest
	Vector3(0, 0, -597),  # lounge
	Vector3(8.75, 0, -1396),  # hotel wing
]

var _combat: Combat


class _MachineStub:
	extends Node
	var spawned: Array[Dictionary] = []

	func spawn_projectile(data: Dictionary) -> void:
		spawned.append(data)


func before_each() -> void:
	add_child_autofree(FeatureScene.instantiate())
	_combat = Combat.new()
	add_child_autofree(_combat)


func _player(peer: int, at: Vector3) -> Player:
	var player := PlayerScene.instantiate() as Player
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	add_child_autofree(player)
	player.set_physics_process(false)
	player.global_position = at
	player.net_position = at
	return player


func test_the_crown_and_its_rooms_are_covered() -> void:
	for point: Vector3 in CROWN_POINTS:
		assert_true(SafeZone.covers(get_tree(), point), "safe at %s" % point)


func test_slums_garages_and_the_shooting_gallery_are_not_covered() -> void:
	for point: Vector3 in SLUM_POINTS + [Vector3(306, 1, -306.5)]:
		assert_false(SafeZone.covers(get_tree(), point), "unsafe at %s" % point)


func test_pvp_damage_is_refused_inside_the_crown() -> void:
	_player(1, Vector3(2, 0.2, 5))
	_player(2, Vector3(4, 0.2, 5))
	_combat.apply_damage(2, 40.0, 1)
	_combat.apply_damage(1, Combat.MAX_HEALTH, 2)
	assert_eq(_combat.health_for(2), Combat.MAX_HEALTH)
	assert_eq(_combat.health_for(1), Combat.MAX_HEALTH)
	assert_false(_combat.is_respawning(1))
	assert_eq(_combat.kills_for(2), 0)


func test_an_attacker_inside_cannot_hurt_someone_outside() -> void:
	_player(1, Vector3(2, 0.2, 5))
	_player(2, SLUM_POINTS[0])
	_combat.apply_damage(2, 40.0, 1)
	assert_eq(_combat.health_for(2), Combat.MAX_HEALTH)


func test_pvp_damage_still_works_in_the_slums() -> void:
	for point: Vector3 in SLUM_POINTS:
		var a := _player(1, point)
		var b := _player(2, point + Vector3(2, 0, 0))
		_combat.apply_damage(2, 10.0, 1)
		a.free()
		b.free()
	assert_eq(_combat.health_for(2), Combat.MAX_HEALTH - 10.0 * SLUM_POINTS.size())


func test_self_inflicted_damage_still_applies_inside() -> void:
	_player(1, Vector3(2, 0.2, 5))
	_combat.apply_damage(1, Combat.MAX_HEALTH, 1)
	assert_true(_combat.is_respawning(1), "/suicide still works in the Crown")


func test_held_guns_do_not_fire_inside_the_crown() -> void:
	_player(1, Vector3(2, 0.2, 5))
	var target := _player(2, Vector3(2, 0.2, -5))
	var hand := HandScene.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	var shots: Array[String] = []
	hand.fired.connect(func(item_id: String) -> void: shots.append(item_id))
	await get_tree().physics_frame
	hand.net_item_id = "pistol"
	hand.request_primary_action()
	assert_eq(shots, [] as Array[String])
	assert_eq(_combat.health_for(target.get_multiplayer_authority()), Combat.MAX_HEALTH)


func test_held_guns_fire_in_the_slums() -> void:
	_player(1, SLUM_POINTS[1])
	var hand := HandScene.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	var shots: Array[String] = []
	hand.fired.connect(func(item_id: String) -> void: shots.append(item_id))
	await get_tree().physics_frame
	hand.net_item_id = "pistol"
	hand.request_primary_action()
	assert_eq(shots, ["pistol"] as Array[String])


func test_gun_machine_guns_do_not_fire_inside_but_do_outside() -> void:
	var player := _player(1, Vector3(2, 0.2, 5))
	var stub := _MachineStub.new()
	stub.add_to_group(&"gun_machine_root")
	add_child_autofree(stub)
	var rig := GunRigScene.instantiate() as GunRig
	rig.peer_id = 1
	add_child_autofree(rig)
	rig.set_process(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	rig.equip(GunGenerator.generate(rng))
	var ammo := rig.net_ammo_in_mag
	rig.request_fire()
	assert_true(stub.spawned.is_empty())
	assert_eq(rig.net_ammo_in_mag, ammo, "no ammo spent")
	player.global_position = SLUM_POINTS[1]
	rig.request_fire()
	assert_false(stub.spawned.is_empty())
