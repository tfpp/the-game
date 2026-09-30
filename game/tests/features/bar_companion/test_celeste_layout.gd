extends GutTest

const ROOM := preload("res://world/room.tscn")
const BAR := preload("res://features/bar_companion/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _room: Node3D
var _bar: BarCompanion
var _npc: Celeste


func before_each() -> void:
	_room = ROOM.instantiate() as Node3D
	add_child_autofree(_room)
	_bar = BAR.instantiate() as BarCompanion
	add_child_autofree(_bar)
	_npc = _bar.get_node("Celeste") as Celeste
	await wait_physics_frames(3)


func test_home_has_floor_body_clearance_and_space_from_vivienne_and_ramp() -> void:
	var home := _npc.global_position
	assert_eq(home, Vector3(-6.6, -1.5, -7.8))
	var space := _room.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(home + Vector3.UP, home + Vector3.DOWN, 1)
	var hit := space.intersect_ray(ray)
	assert_false(hit.is_empty())
	if not hit.is_empty():
		assert_almost_eq((hit.position as Vector3).y, home.y, 0.02)
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, home + Vector3(0, 0.94, 0))
	query.collision_mask = 1
	assert_true(
		space.intersect_shape(query).is_empty(), "body and approach clear of salon furniture"
	)
	var vivienne := _bar.get_node("Vivienne") as Node3D
	assert_gt(home.distance_to(vivienne.global_position), 1.5)
	assert_lt(home.x + shape.radius, -3.0, "outside the six-metre central ramp")


func test_follows_clear_route_on_floor_and_faces_motion() -> void:
	var player := PLAYER.instantiate() as Player
	player.set_multiplayer_authority(1)
	add_child_autofree(player)
	player.set_physics_process(false)
	player.net_position = _npc.global_position + Vector3(0, 0, 1)
	_npc.use()
	player.net_position = Vector3(-3.6, -1.5, -7.8)
	await wait_physics_frames(100)
	assert_gt(_npc.global_position.x, -6.0, "actually moves toward the leader")
	assert_almost_eq(_npc.global_position.y, -1.5, 0.04, "does not sink or float")
	var forward := _npc.global_basis * Vector3.FORWARD
	assert_gt(forward.x, 0.0, "faces toward movement, not backwards")


func test_world_collision_stops_walk_through_counter() -> void:
	var player := PLAYER.instantiate() as Player
	player.set_multiplayer_authority(1)
	add_child_autofree(player)
	player.set_physics_process(false)
	player.net_position = _npc.global_position
	_npc.use()
	# Simulate a leader jumping over the counter; Celeste must stay on the near side.
	_npc.global_position = Vector3(-6, -1.5, -8.5)
	_npc.net_position = _npc.global_position
	_npc._trail.clear()
	player.net_position = Vector3(-6, -1.5, -11)
	await wait_physics_frames(100)
	assert_gt(_npc.global_position.z, -9.4, "cannot walk through the bar")
