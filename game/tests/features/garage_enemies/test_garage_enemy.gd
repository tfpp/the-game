extends GutTest
## Server-side behavior on a bare floor: sensing, attacks through features/combat,
## hits, death, respawn and session reset.

const ENEMY := preload("res://features/garage_enemies/garage_enemy.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const COMBAT := preload("res://features/combat/feature.tscn")

var _enemy: GarageEnemy
var _player: Player
var _combat: Node


func before_each() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.2, 60)
	shape.shape = box
	shape.position.y = -0.1
	floor_body.add_child(shape)
	add_child_autofree(floor_body)
	_combat = COMBAT.instantiate()
	add_child_autofree(_combat)
	_enemy = ENEMY.instantiate() as GarageEnemy
	_enemy.position = Vector3(0, 0, 0)
	add_child_autofree(_enemy)
	_player = PLAYER.instantiate() as Player
	_player.name = "5"
	_player.set_multiplayer_authority(5)
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_place(Vector3(0, 0.95, -6))
	await wait_physics_frames(2)


func _place(at: Vector3) -> void:
	_player.global_position = at
	_player.net_position = at


func _health() -> float:
	return float(_combat.call("health_for", 5))


func test_senses_player_on_its_floor_and_walks_towards_them() -> void:
	_enemy._sense()
	assert_eq(_enemy.target_peer, 5)
	var start := _enemy.global_position.distance_to(_player.global_position)
	for i: int in 20:
		_enemy._physics_process(0.05)
	assert_lt(_enemy.global_position.distance_to(_player.global_position), start)
	var facing := Vector3.FORWARD.rotated(Vector3.UP, _enemy.net_yaw)
	assert_lt(facing.z, -0.9, "faces the player at -Z")


func test_ignores_players_on_another_floor() -> void:
	_place(Vector3(0, 3.3 + 0.95, -3))
	_enemy._sense()
	assert_eq(_enemy.target_peer, 0)


func test_melee_winds_up_then_damages_through_combat() -> void:
	_place(Vector3(0, 0.95, -1.0))
	_enemy._sense()
	assert_true(_enemy.net_windup)
	assert_eq(_health(), 100.0, "the wind-up gives players time to react")
	_enemy._physics_process(1.0)
	assert_false(_enemy.net_windup)
	assert_eq(_health(), 100.0 - float(_enemy.profile()["damage"]))
	assert_eq(int(_combat.call("kills_for", 5)), 0)


func test_player_who_escapes_during_windup_is_not_hit() -> void:
	_place(Vector3(0, 0.95, -1.0))
	_enemy._sense()
	_place(Vector3(0, 0.95, -9.0))
	_enemy._strike()
	assert_eq(_health(), 100.0)


func test_tiers_take_their_number_of_hits_then_respawn_at_home() -> void:
	_enemy.queue_free()
	_enemy = ENEMY.instantiate() as GarageEnemy
	_enemy.tier = GarageEnemyTiers.Tier.STALKER
	_enemy.position = Vector3(3, 0, 0)
	add_child_autofree(_enemy)
	_enemy.take_hit(5)
	assert_true(_enemy.net_alive)
	assert_eq(_enemy.target_peer, 5, "being shot draws aggro")
	_enemy.take_hit(5)
	assert_false(_enemy.net_alive)
	_enemy.take_hit(5)
	_enemy.position = Vector3(9, 0, 9)
	_enemy._physics_process(float(_enemy.profile()["respawn"]) + 0.1)
	assert_true(_enemy.net_alive)
	assert_eq(_enemy.position, Vector3(3, 0, 0))
	assert_eq(_enemy.health, int(_enemy.profile()["hits"]))


func test_session_reset_restores_every_enemy() -> void:
	_enemy.take_hit(5)
	assert_false(_enemy.net_alive)
	_enemy.entity.session_reset.emit(Network.Mode.OFFLINE)
	assert_true(_enemy.net_alive)
	assert_eq(_enemy.target_peer, 0)


func test_walls_block_line_of_sight() -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 3, 0.3)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0, 1.5, -3)
	add_child_autofree(wall)
	await wait_physics_frames(2)
	assert_false(_enemy.can_see(_player))
	_enemy._sense()
	assert_eq(_enemy.target_peer, 0)
