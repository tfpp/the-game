extends GutTest
## The wing is walkable from the casino without teleports, and its booths, kebab
## counter and signs sit on the real geometry.

const ROOM := preload("res://world/room.tscn")
const ANNEX := preload("res://features/annex/feature.tscn")
const COURT := preload("res://features/food_court/feature.tscn")
const SHOP := preload("res://features/kebab_shop/feature.tscn")

var _court: FoodCourt
var _shop: KebabShop
var _shape: CapsuleShape3D


func before_each() -> void:
	add_child_autofree(ROOM.instantiate())
	add_child_autofree(ANNEX.instantiate())
	_court = COURT.instantiate() as FoodCourt
	add_child_autofree(_court)
	_shop = SHOP.instantiate() as KebabShop
	add_child_autofree(_shop)
	_shape = CapsuleShape3D.new()
	_shape.radius = 0.4064
	_shape.height = 1.8288
	await wait_physics_frames(4)


func test_walk_from_casino_through_doorway_to_the_kebab_counter() -> void:
	var route: Array[Vector3] = [
		Vector3(0, 0.95, 28),
		Vector3(0, 0.95, 40),
		Vector3(6, 0.95, 40),
		Vector3(6, 0.95, 43),
		Vector3(28.7, 0.95, 43),
		Vector3(28.7, 0.95, 44.35),
	]
	for index: int in route.size() - 1:
		_sweep(route[index], route[index + 1])
	for point: Vector3 in route:
		_assert_floor(point, 0.0)


func test_wing_is_enclosed_and_covered() -> void:
	for x: float in [6.0, 18.0, 30.0]:
		for z: float in [36.0, 43.0, 50.0]:
			_assert_floor(Vector3(x, 1, z), 0.0)
			assert_false(_ray(Vector3(x, 2, z), Vector3(x, 12, z)).is_empty(), "Ceiling")
	for target: Vector3 in [Vector3(18, 1.5, 60), Vector3(40, 1.5, 43), Vector3(18, 1.5, 30)]:
		assert_false(_ray(Vector3(18, 1.5, 43), target).is_empty(), "Walls toward %s" % target)
	# The corridor wall stays solid beside and above the doorway.
	assert_false(_ray(Vector3(0, 1.5, 44), Vector3(6, 1.5, 44)).is_empty())
	assert_false(_ray(Vector3(0, 3.6, 40), Vector3(6, 3.6, 40)).is_empty())


func test_every_booth_is_reachable_and_stand_up_spots_are_clear() -> void:
	for index: int in _court.seats.size():
		var spot := _court.stand_position(index) + Vector3(0, 0.95, 0)
		_assert_clear(spot)
		assert_true(_court.in_reach(spot, index), "Seat %d reachable from its aisle" % index)
		var aisle := Vector3(spot.x, spot.y, 43)
		_sweep(aisle, spot)
		_assert_floor(spot, 0.0)


func test_booths_stand_on_the_floor_and_clear_the_walls() -> void:
	for booth: Node3D in _court.get_node("Booths").get_children():
		var table := booth.get_node("TableBody").get_child(0) as CollisionShape3D
		var box := table.shape as BoxShape3D
		assert_almost_eq(table.global_position.y - box.size.y * 0.5, 0.0, 0.001)
		assert_between(booth.global_position.z, 36.4, 49.6)
		assert_between(booth.global_position.x, 4.5, 26.0)


func _assert_clear(origin: Vector3) -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = 1
	query.shape = _shape
	query.transform.origin = origin
	var space := _court.get_world_3d().direct_space_state
	assert_true(space.intersect_shape(query).is_empty(), "Clear standing room at %s" % origin)


func _sweep(start: Vector3, end: Vector3) -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = 1
	query.shape = _shape
	query.transform.origin = start
	query.motion = end - start
	var space := _court.get_world_3d().direct_space_state
	assert_almost_eq(space.cast_motion(query)[0], 1.0, 0.001, "Clear route %s -> %s" % [start, end])


func _assert_floor(from: Vector3, expected_y: float) -> void:
	var hit := _ray(from, from - Vector3(0, 4, 0))
	assert_false(hit.is_empty(), "Floor under %s" % from)
	if not hit.is_empty():
		assert_almost_eq((hit["position"] as Vector3).y, expected_y, 0.02)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	return _court.get_world_3d().direct_space_state.intersect_ray(query)
