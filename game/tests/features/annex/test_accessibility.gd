extends GutTest
## Sweeps the standing player hull along every annex route, in both directions.

const ROOM := preload("res://world/room.tscn")
const ANNEX := preload("res://features/annex/feature.tscn")
var _world: Node3D
var _shape: CapsuleShape3D


func before_all() -> void:
	_world = Node3D.new()
	add_child(_world)
	_world.add_child(ROOM.instantiate())
	_world.add_child(ANNEX.instantiate())
	_shape = CapsuleShape3D.new()
	_shape.radius = 0.4064
	_shape.height = 1.8288
	await wait_physics_frames(4)


func after_all() -> void:
	_world.free()


func test_northwest_loop_and_all_four_rooms() -> void:
	_route(
		[
			Vector2(-12, -30),
			Vector2(-12, -45),
			Vector2(-33, -45),
			Vector2(-44, -45),
			Vector2(-44, -58),
			Vector2(-50, -58),
			Vector2(-50, 28),
			Vector2(-56, 28),
			Vector2(-56, 37),
			Vector2(-50, 37),
			Vector2(-50, 55)
		]
	)


func test_west_entrance_joins_both_halves_of_loop() -> void:
	_route([Vector2(-26, 8), Vector2(-50, 8), Vector2(-50, -50)])
	_route([Vector2(-50, 8), Vector2(-50, 28)])


func test_northeast_rooms_and_branch_junction() -> void:
	_route([Vector2(10, -30), Vector2(10, -62.5)])
	_route([Vector2(10, -45), Vector2(30, -45)])


func test_east_rooms() -> void:
	_route(
		[Vector2(34, -10), Vector2(65, -10), Vector2(65, -16), Vector2(60, -16), Vector2(60, -40)]
	)


func test_removed_south_wing_is_closed_and_has_no_floor() -> void:
	var space := _world.get_world_3d().direct_space_state
	var closure := PhysicsRayQueryParameters3D.create(Vector3(0, 1, 32), Vector3(0, 1, 38))
	assert_false(space.intersect_ray(closure).is_empty(), "Former entrance is sealed")
	for point: Vector3 in [Vector3(0, 2, 41.5), Vector3(-22.5, 2, 48), Vector3(-22.5, 2, 74)]:
		var down := PhysicsRayQueryParameters3D.create(point, point - Vector3(0, 4, 0))
		assert_true(space.intersect_ray(down).is_empty(), "Removed wing has no floor")


func _route(points: Array[Vector2]) -> void:
	var space := _world.get_world_3d().direct_space_state
	for index: int in range(points.size() - 1):
		var start := Vector3(points[index].x, 0.94, points[index].y)
		var end := Vector3(points[index + 1].x, 0.94, points[index + 1].y)
		for reverse: bool in [false, true]:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = _shape
			query.transform.origin = end if reverse else start
			query.motion = start - end if reverse else end - start
			var result := space.cast_motion(query)
			assert_almost_eq(result[0], 1.0, 0.001, "Standing route %s -> %s" % [start, end])
		# Sample support across the whole route, including the middle of each room.
		var steps := ceili(start.distance_to(end) / 0.5)
		for step: int in range(steps + 1):
			var point := start.lerp(end, float(step) / steps)
			var support := PhysicsShapeQueryParameters3D.new()
			support.shape = _shape
			support.transform.origin = point
			support.motion = Vector3(0, -0.15, 0)
			assert_lt(space.cast_motion(support)[0], 1.0, "Floor support at %s" % point)
