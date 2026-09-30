extends GutTest
## Garage enemies notice crouched players at half their usual distance.

const ENEMY := preload("res://features/garage_enemies/garage_enemy.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const CROUCH := preload("res://features/crouch/feature.tscn")

var _enemy: GarageEnemy
var _player: Player
var _crouch: Crouch


func before_each() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.2, 60)
	shape.shape = box
	shape.position.y = -0.1
	floor_body.add_child(shape)
	add_child_autofree(floor_body)
	_crouch = CROUCH.instantiate() as Crouch
	add_child_autofree(_crouch)
	_enemy = ENEMY.instantiate() as GarageEnemy
	add_child_autofree(_enemy)
	_player = PLAYER.instantiate() as Player
	_player.name = "5"
	_player.set_multiplayer_authority(5)
	add_child_autofree(_player)
	_player.set_physics_process(false)
	await wait_physics_frames(2)
	_enemy.set_physics_process(false)
	_enemy.target_peer = 0


func _distance_between_half_and_full_aggro() -> float:
	return float(_enemy.profile()["aggro"]) * 0.75


func test_crouched_player_goes_unnoticed_between_half_and_full_range() -> void:
	_player.global_position = Vector3(0, 0.95, -_distance_between_half_and_full_aggro())
	_crouch.crouched = {5: true}
	_enemy._sense()
	assert_eq(_enemy.target_peer, 0)
	_crouch.crouched = {}
	_enemy._sense()
	assert_eq(_enemy.target_peer, 5, "standing players are noticed at full range")


func test_enemies_still_see_crouched_players_up_close() -> void:
	var half := float(_enemy.profile()["aggro"]) * Crouch.NOTICE_SCALE
	_player.global_position = Vector3(0, 0.95, -(half - 1.0))
	_crouch.crouched = {5: true}
	_enemy._sense()
	assert_eq(_enemy.target_peer, 5)


func test_crouching_does_not_shake_an_enemy_already_chasing() -> void:
	_player.global_position = Vector3(0, 0.95, -_distance_between_half_and_full_aggro())
	_enemy._sense()
	_crouch.crouched = {5: true}
	_enemy._sense()
	assert_eq(_enemy.target_peer, 5)
