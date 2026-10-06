extends GutTest

const THROWN := preload("res://features/holdables/thrown_item.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const HAND := preload("res://features/holdables/hand.tscn")
var _ball: ThrownItem


func before_each() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	_ball = THROWN.instantiate() as ThrownItem
	_ball.item_id = "ball"
	_ball.from = Vector3(0, 1, 0)
	_ball.to = Vector3(4, 0, 0)
	add_child_autofree(_ball)


func _box(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	body.position = at
	add_child_autofree(body)


func test_ball_bounces_on_actual_floor_and_persists_after_settling() -> void:
	var bounced := false
	for frame in range(240):
		await wait_physics_frames(1)
		if _ball.net_landed and _ball.velocity.y > 1.0:
			bounced = true
	assert_true(bounced, "Floor contact must produce an upward bounce")
	assert_true(_ball.net_landed)
	assert_almost_eq(_ball.position.y, 0.0, 0.02, "Sphere and view sit above the floor")
	assert_almost_eq(_ball.velocity.length(), 0.0, 0.05)
	assert_true(_ball.is_in_group(&"interactables"))
	assert_true(_ball.visible)
	await wait_physics_frames(240)
	assert_false(_ball.is_queued_for_deletion(), "No timer deletes a settled ball")


func test_ball_hits_wall_instead_of_passing_through_it() -> void:
	_box(Vector3(1.5, 2, 0), Vector3(0.1, 4, 10))
	var bounced := false
	for frame in range(45):
		await wait_physics_frames(1)
		assert_lt(_ball.position.x + 0.122, 1.48)
		if _ball.velocity.x < -1.0:
			bounced = true
	assert_true(bounced, "The wall sends the ball back toward the thrower")


func test_ball_hits_ceiling_and_stays_in_the_room() -> void:
	_box(Vector3(0, 2, 0), Vector3(40, 0.1, 40))
	_ball.velocity = Vector3(0, 12, 0)
	await wait_physics_frames(30)
	assert_lt(_ball.position.y + 0.244, 1.98)
	assert_true(_ball.net_landed, "A ceiling hit falls back onto the floor")


func test_ball_lost_below_the_map_returns_to_release_point() -> void:
	_ball.position = _ball.from + Vector3.DOWN * 51
	_ball.velocity = Vector3.DOWN
	_ball._physics_process(1.0 / 64.0)
	assert_eq(_ball.net_position, _ball.from)
	assert_eq(_ball.position, _ball.from)


func test_transfer_preserves_ball_momentum_and_recovery_origin() -> void:
	_ball.set_physics_process(false)
	var before := _ball.velocity
	var origin := _ball.from
	var offset := Vector3(600, 0, -2000)
	_ball.transfer_by(offset)
	assert_eq(_ball.velocity, before)
	assert_eq(_ball.from, origin + offset)
	assert_eq(_ball.position, _ball.net_position)
	assert_eq(_ball._last_visual_position, _ball.position)


func test_ball_rolls_the_visible_model_and_does_not_block_players() -> void:
	var view := _ball.get_node("Mount") as Node3D
	var before := view.quaternion
	await wait_physics_frames(20)
	assert_ne(view.quaternion, before)
	var player := PLAYER.instantiate() as Player
	add_child_autofree(player)
	assert_eq(player.collision_mask & _ball.collision_layer, 0)


func test_pickup_checks_range_and_state_and_collects_ball_only_once() -> void:
	_ball.set_physics_process(false)
	var player := PLAYER.instantiate() as Player
	player.name = "1"
	player.set_multiplayer_authority(1)
	player.position = _ball.position
	add_child_autofree(player)
	player.set_physics_process(false)
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	_ball.request_pickup()
	assert_eq(hand.net_item_id, "", "Cannot collect before first floor contact")
	_ball.net_landed = true
	player.net_position = Vector3(20, 0, 0)
	_ball.request_pickup()
	assert_eq(hand.net_item_id, "", "Server rejects a distant player's request")
	player.net_position = _ball.position
	player.position = _ball.position
	_ball.request_pickup()
	_ball.request_pickup()
	assert_eq(hand.net_item_id, "ball")
	assert_eq(hand.inventory().backpack.count(""), 8)
	assert_true(_ball.is_queued_for_deletion())
