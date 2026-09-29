extends GutTest
## Every patron route leg is clear for a patron (and a standing player) on the
## real casino floor, with the slots and roulette loaded.

const ROOM := preload("res://world/room.tscn")
const SLOTS := preload("res://features/slot_machine/feature.tscn")
const ROULETTE := preload("res://features/roulette/feature.tscn")

var _world: Node3D
var _hull: CapsuleShape3D


func before_all() -> void:
	_world = Node3D.new()
	add_child(_world)
	_world.add_child(ROOM.instantiate())
	_world.add_child(SLOTS.instantiate())
	_world.add_child(ROULETTE.instantiate())
	_hull = CapsuleShape3D.new()
	_hull.radius = 0.35
	_hull.height = 1.75
	await wait_physics_frames(4)


func after_all() -> void:
	_world.free()


func test_each_waypoint_stands_on_the_floor() -> void:
	var space := _world.get_world_3d().direct_space_state
	for index: int in PatronMath.ROUTES.size():
		for point: Vector3 in PatronMath.route(index):
			var ray := PhysicsRayQueryParameters3D.create(
				point + Vector3.UP * 0.5, point + Vector3.DOWN * 0.5
			)
			var hit := space.intersect_ray(ray)
			assert_false(hit.is_empty(), "floor under %s" % point)
			if not hit.is_empty():
				assert_almost_eq((hit["position"] as Vector3).y, point.y, 0.05, str(point))


func test_each_route_leg_is_clear() -> void:
	var space := _world.get_world_3d().direct_space_state
	for index: int in PatronMath.ROUTES.size():
		var points := PatronMath.route(index)
		for i: int in points.size():
			var start := points[i] + Vector3.UP * 0.95
			var end := points[PatronMath.next_waypoint(i, points.size())] + Vector3.UP * 0.95
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = _hull
			query.transform.origin = start
			query.motion = end - start
			var result := space.cast_motion(query)
			assert_almost_eq(result[0], 1.0, 0.001, "route %d leg %s -> %s" % [index, start, end])
