extends GutTest
## Crouch state: server validation, the local player's speed/eyes/capsule, the
## ceiling check and cleanup on respawn and disconnect.

const PLAYER := preload("res://core/player/player.tscn")
const CROUCH := preload("res://features/crouch/feature.tscn")
const MODELS := preload("res://features/player_models/feature.tscn")

var _player: Player
var _crouch: Crouch


func before_each() -> void:
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_crouch = CROUCH.instantiate() as Crouch
	add_child_autofree(_crouch)
	_crouch._physics_process(0.0)


func after_each() -> void:
	await get_tree().process_frame


func _floor(y: float) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 0.2, 4)
	shape.shape = box
	body.add_child(shape)
	body.position.y = y
	add_child_autofree(body)


func test_server_validates_payload_and_player() -> void:
	for payload: Dictionary in [{}, {"crouched": 1}, {"crouched": true, "peer": 2}]:
		assert_eq(_crouch.entity._evaluate(1, &"crouch", payload), NetworkedEntity.Result.DENIED)
	assert_eq(
		_crouch.entity._evaluate(77, &"crouch", {"crouched": true}), NetworkedEntity.Result.DENIED
	)
	assert_eq(
		_crouch.entity._evaluate(1, &"crouch", {"crouched": true}), NetworkedEntity.Result.ACCEPTED
	)
	assert_eq(_crouch.crouched, {1: true})
	_crouch.entity._evaluate(1, &"crouch", {"crouched": false})
	assert_true(_crouch.crouched.is_empty())


func test_remote_state_comes_from_replication() -> void:
	assert_false(_crouch.is_crouching(2))
	_crouch.crouched = {2: true}
	assert_true(_crouch.is_crouching(2))
	_crouch._remove_peer(2)
	assert_false(_crouch.is_crouching(2))


func test_crouching_slows_lowers_eyes_and_publishes() -> void:
	var speed := _player.movement.max_speed
	var eye := _player.movement.eye_height
	assert_true(_crouch.set_crouched(true))
	assert_true(_crouch.is_crouching(1))
	assert_true(_crouch.crouched.get(1, false), "server state replicated")
	assert_almost_eq(_player.movement.max_speed, speed * Crouch.SPEED_SCALE, 0.001)
	for i: int in 60:
		_crouch._physics_process(1.0 / 60.0)
	assert_almost_eq(_player.movement.eye_height, Crouch.EYE_HEIGHT, 0.1)
	assert_true(_crouch.set_crouched(false))
	assert_almost_eq(_player.movement.max_speed, speed, 0.001)
	for i: int in 60:
		_crouch._physics_process(1.0 / 60.0)
	assert_almost_eq(_player.movement.eye_height, eye, 0.1)
	assert_false(_crouch.crouched.has(1))


func test_crouching_does_not_modify_the_shared_default_config() -> void:
	var fresh := PLAYER.instantiate() as Player
	var shared_speed := fresh.movement.max_speed
	_crouch.set_crouched(true)
	assert_eq(fresh.movement.max_speed, shared_speed)
	fresh.free()


func test_respawned_player_starts_standing() -> void:
	_crouch.set_crouched(true)
	_player.remove_from_group(&"local_player")
	var next := PLAYER.instantiate() as Player
	next.name = "1b"
	add_child_autofree(next)
	next.set_physics_process(false)
	var speed := next.movement.max_speed
	_crouch._physics_process(0.0)
	assert_false(_crouch.is_crouching(1))
	assert_false(_crouch.crouched.has(1))
	assert_eq(next.movement.max_speed, speed)


func test_capsule_shrinks_from_the_feet_and_ceiling_blocks_standing() -> void:
	var models := MODELS.instantiate() as PlayerModels
	add_child_autofree(models)
	models.set_process(false)
	var collider := _player.get_node("Collider") as CollisionShape3D
	_player.global_position = Vector3(0, 0.9144, 0)
	models._process(0)
	var standing := (collider.shape as CapsuleShape3D).height
	var feet := collider.global_position.y - standing * 0.5
	_crouch.set_crouched(true)
	models._process(0)
	var capsule := collider.shape as CapsuleShape3D
	assert_almost_eq(capsule.height, standing * Crouch.HEIGHT_SCALE, 0.001)
	assert_almost_eq(collider.global_position.y - capsule.height * 0.5, feet, 0.001)
	# A ceiling just above the crouched head keeps the player crouched.
	_floor(feet + capsule.height + 0.15)
	await wait_physics_frames(2)
	assert_true(Crouch.blocked_overhead(_player))
	assert_false(_crouch.set_crouched(false))
	assert_true(_crouch.is_crouching(1))


func test_open_space_allows_standing() -> void:
	_player.global_position = Vector3(10, 0.9144, 0)
	_crouch.set_crouched(true)
	await wait_physics_frames(1)
	assert_false(Crouch.blocked_overhead(_player))
	assert_true(_crouch.set_crouched(false))
