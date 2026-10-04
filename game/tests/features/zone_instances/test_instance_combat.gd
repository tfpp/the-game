extends GutTest
## Membership is a combat boundary even when player poses temporarily overlap.

const ZONES := preload("res://features/zone_instances/feature.tscn")
const COMBAT := preload("res://features/combat/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const PROJECTILE := preload("res://features/gun_machine/projectile.tscn")
const ENEMY := preload("res://features/garage_enemies/garage_enemy.tscn")


func _player(peer: int) -> Player:
	var player := PLAYER.instantiate() as Player
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	add_child_autofree(player)
	player.set_physics_process(false)
	return player


func test_damage_and_splash_do_not_cross_instance_membership() -> void:
	var zones := ZONES.instantiate() as ZoneInstances
	add_child_autofree(zones)
	var combat := COMBAT.instantiate() as Combat
	add_child_autofree(combat)
	combat.set_process(false)
	var arrival := Marker3D.new()
	add_child_autofree(arrival)
	var id := zones.registry.create([1, 2] as Array[int], arrival)
	zones.registry.create([3] as Array[int], arrival)
	var host := _player(1)
	_player(2)
	_player(3)
	combat.apply_damage(3, 40.0, 1)
	combat.apply_damage(1, 40.0, 3)
	assert_eq(combat.health_for(3), 100.0)
	assert_eq(combat.health_for(1), 100.0, "Hosting player has no cross-group damage privilege")
	combat.apply_damage(2, 20.0, 1)
	assert_eq(combat.health_for(2), 80.0)
	var round := PROJECTILE.instantiate() as Projectile
	round.instance_id = id
	round.shooter_peer = 1
	round.damage = 20.0
	add_child_autofree(round)
	round.set_physics_process(false)
	round._splash({"explosion_radius": 4.0, "splash_force": 0.0}, 0)
	assert_eq(combat.health_for(3), 100.0, "Overlapping outsider cannot take splash damage")
	assert_lt(combat.health_for(2), 80.0, "Same-instance bystander takes splash damage")
	zones.registry.leave(1)
	var before := host.net_position
	round._apply_splash_force(host, 0.0, 4.0, 10.0)
	assert_eq(host.net_position, before, "A returning player cannot be pushed by an old run")
	combat.apply_damage(2, 10.0, 1)
	assert_eq(combat.health_for(2), 60.0, "Hub player cannot damage someone still in the run")
	zones.registry.leave(2)
	combat.apply_damage(2, 10.0, 1)
	assert_eq(combat.health_for(2), 50.0, "Unprotected shared-world combat still works")


func test_enemy_targets_only_current_members_even_when_outsiders_overlap() -> void:
	var scope := ZoneScope.new()
	scope.members = [2]
	scope.position = Vector3(0, 0, -25000)
	add_child_autofree(scope)
	var enemy := ENEMY.instantiate() as GarageEnemy
	scope.add_child(enemy)
	enemy.set_physics_process(false)
	var member := _player(2)
	member.position = scope.to_global(Vector3(0, .95, 2))
	member.net_position = member.position
	var outsider := _player(3)
	outsider.position = scope.to_global(Vector3(.5, .95, 0))
	outsider.net_position = outsider.position
	var host := _player(1)
	host.position = scope.to_global(Vector3(-.5, .95, 0))
	host.net_position = host.position
	await wait_physics_frames(2)
	assert_same(enemy._find_target(), member)
	assert_null(enemy._player(3), "An overlapping outsider cannot become an attack target")
	assert_null(enemy._player(1), "The host has no gameplay membership exception")
	enemy.take_hit(3)
	enemy.take_hit(1)
	assert_eq(enemy.health, 1, "Outsiders cannot damage the private enemy")
	scope.replace_members([])
	assert_null(enemy._find_target())
	assert_null(enemy._player(2), "A returning member is no longer a valid target")
	enemy.take_hit(2)
	assert_eq(enemy.health, 1, "A departed member cannot hit their old instance")
