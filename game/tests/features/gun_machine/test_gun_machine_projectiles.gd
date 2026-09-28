extends GutTest
## End-to-end coverage of the fire -> projectile -> hit pipeline: equips a real rig
## inside a real feature.tscn instance (so `spawn_projectile` goes through the real
## MultiplayerSpawner, not a stub), fires at a target player, and steps physics
## until the shot lands.

const FeatureScene := preload("res://features/gun_machine/feature.tscn")
const GunRigScene := preload("res://features/gun_machine/gun_rig.tscn")
const PlayerScene := preload("res://core/player/player.tscn")

const RIFLE_STATS := {
	"ammo_type": 1,  # GunGenerator.AmmoType.RIFLE
	"barrel_count": 1,
	"fire_rate": 5.0,
	"magazine_size": 10,
	"damage": 15.0,
	"total_ammo": 50,
	"projectile_speed": 60.0,
	"spread_degrees": 0.0,
	"display_name": "Test Rifle",
}

const ROCKET_STATS := {
	"ammo_type": 3,  # GunGenerator.AmmoType.ROCKET
	"barrel_count": 1,
	"fire_rate": 0.5,
	"magazine_size": 2,
	"damage": 80.0,
	"total_ammo": 6,
	"projectile_speed": 40.0,
	"spread_degrees": 0.0,
	"display_name": "Test Rocket",
}


## Minimal stand-in for a non-player killable (features/frogs, features/penguin,
## features/shooting_gallery): just enough of their `killable` contract for
## projectile.gd's `_apply_killable_hit` to route a hit to it.
class KillableStub:
	extends StaticBody3D

	var hits: Array[int] = []

	func _ready() -> void:
		add_to_group(&"killable")
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3.ONE
		shape.shape = box
		add_child(shape)

	func take_hit(attacker_peer: int) -> void:
		hits.append(attacker_peer)


func _shooter_and_target() -> Array[Player]:
	var shooter := PlayerScene.instantiate() as Player
	shooter.name = "1"
	shooter.set_multiplayer_authority(1)
	add_child_autofree(shooter)
	var target := PlayerScene.instantiate() as Player
	target.name = "2"
	target.set_multiplayer_authority(2)
	target.position = Vector3(0, 0, -10)
	target.net_position = target.position
	add_child_autofree(target)
	return [shooter, target]


func test_a_fired_rifle_round_flies_forward_and_damages_whoever_it_hits() -> void:
	add_child_autofree(Combat.new())
	var players := _shooter_and_target()
	var shooter := players[0]
	var rig := GunRigScene.instantiate() as GunRig
	rig.peer_id = 1
	add_child_autofree(rig)
	var feature := FeatureScene.instantiate() as GunMachine
	add_child_autofree(feature)
	await get_tree().physics_frame
	rig.equip(RIFLE_STATS)
	shooter.net_yaw = 0.0
	shooter.net_pitch = 0.0
	rig.request_fire()
	assert_eq(rig.net_ammo_in_mag, 9)

	var combat := get_tree().get_first_node_in_group(&"combat") as Combat
	var hit := false
	for _tick: int in 120:
		await get_tree().physics_frame
		if combat.health_for(2) < Combat.MAX_HEALTH:
			hit = true
			break
	assert_true(hit, "the round should have crossed the 10m gap and hit the target")
	assert_almost_eq(combat.health_for(2), Combat.MAX_HEALTH - 15.0, 0.01)


func test_a_direct_rocket_hit_also_splashes_a_nearby_bystander() -> void:
	add_child_autofree(Combat.new())
	var players := _shooter_and_target()
	var shooter := players[0]
	var target := players[1]
	var bystander := PlayerScene.instantiate() as Player
	bystander.name = "3"
	bystander.set_multiplayer_authority(3)
	bystander.position = target.position + Vector3(2, 0, 0)
	bystander.net_position = bystander.position
	add_child_autofree(bystander)
	var rig := GunRigScene.instantiate() as GunRig
	rig.peer_id = 1
	add_child_autofree(rig)
	var feature := FeatureScene.instantiate() as GunMachine
	add_child_autofree(feature)
	await get_tree().physics_frame
	rig.equip(ROCKET_STATS)
	shooter.net_yaw = 0.0
	shooter.net_pitch = 0.0
	rig.request_fire()

	var combat := get_tree().get_first_node_in_group(&"combat") as Combat
	var hit := false
	for _tick: int in 120:
		await get_tree().physics_frame
		if combat.health_for(2) < Combat.MAX_HEALTH:
			hit = true
			break
	assert_true(hit, "the rocket should have crossed the 10m gap and hit the target")
	assert_almost_eq(combat.health_for(2), Combat.MAX_HEALTH - 80.0, 0.5)
	# The exact impact point (and so the exact splash falloff) depends on incidental
	# collider geometry, not gun_machine's concern — just check splash happened, and
	# that the direct hit still did more damage than the splash.
	assert_lt(combat.health_for(3), Combat.MAX_HEALTH, "the bystander should take splash damage")
	assert_lt(
		combat.health_for(2), combat.health_for(3), "a direct hit should hurt more than splash"
	)


func test_a_fired_rifle_round_kills_a_killable_npc_on_layer_2() -> void:
	var shooter := PlayerScene.instantiate() as Player
	shooter.name = "1"
	shooter.set_multiplayer_authority(1)
	add_child_autofree(shooter)
	var target := KillableStub.new()
	target.collision_layer = 2
	target.position = Vector3(0, 0, -10)
	add_child_autofree(target)
	var rig := GunRigScene.instantiate() as GunRig
	rig.peer_id = 1
	add_child_autofree(rig)
	var feature := FeatureScene.instantiate() as GunMachine
	add_child_autofree(feature)
	await get_tree().physics_frame
	rig.equip(RIFLE_STATS)
	shooter.net_yaw = 0.0
	shooter.net_pitch = 0.0
	rig.request_fire()

	var hit := false
	for _tick: int in 120:
		await get_tree().physics_frame
		if not target.hits.is_empty():
			hit = true
			break
	assert_true(hit, "the round should have crossed the 10m gap and hit the killable target")
	assert_eq(target.hits, [1])
