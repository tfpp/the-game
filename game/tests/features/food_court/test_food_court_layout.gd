extends GutTest
## The southeast court is walkable from the lobby without teleports, and its booths, kebab
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


func test_walk_from_south_lobby_to_the_kebab_counter() -> void:
	var route: Array[Vector3] = [
		Vector3(0, 0.95, 28),
		Vector3(28.7, 0.95, 28),
		Vector3(28.7, 0.95, 29.85),
	]
	for index: int in route.size() - 1:
		_sweep(route[index], route[index + 1])
	for point: Vector3 in route:
		_assert_floor(point, 0.0)


func test_court_uses_the_casino_floor_walls_and_ceiling() -> void:
	for x: float in [14.0, 19.0, 28.0]:
		for z: float in [24.5, 27.5, 30.5]:
			_assert_floor(Vector3(x, 1, z), 0.0)
			assert_false(_ray(Vector3(x, 2, z), Vector3(x, 12, z)).is_empty(), "Ceiling")
	for target: Vector3 in [Vector3(22, 1.5, 40), Vector3(40, 1.5, 27.5), Vector3(22, 1.5, 18)]:
		assert_false(_ray(Vector3(22, 1.5, 27.5), target).is_empty(), "Walls toward %s" % target)


func test_every_booth_is_reachable_and_stand_up_spots_are_clear() -> void:
	for index: int in _court.seats.size():
		var spot := _court.stand_position(index) + Vector3(0, 0.95, 0)
		_assert_clear(spot)
		assert_true(_court.in_reach(spot, index), "Seat %d reachable from its aisle" % index)
		var aisle := Vector3(spot.x, spot.y, 27.5)
		_sweep(aisle, spot)
		_assert_floor(spot, 0.0)


func test_booths_stand_on_the_floor_and_clear_the_walls() -> void:
	for booth: Node3D in _court.get_node("Booths").get_children():
		var table := booth.get_node("TableBody").get_child(0) as CollisionShape3D
		var box := table.shape as BoxShape3D
		assert_almost_eq(table.global_position.y - box.size.y * 0.5, 0.0, 0.001)
		assert_between(booth.global_position.z, 23.0, 32.0)
		assert_between(booth.global_position.x, 14.5, 26.5)


func test_poke_counter_is_grounded_faces_west_and_has_a_clear_approach() -> void:
	var stand := _court.get_node("PokeStand") as PokeStand
	var counter := stand.get_node("Counter") as CSGBox3D
	assert_almost_eq(counter.global_position.y - counter.size.y * 0.5, 0.0, 0.001)
	assert_almost_eq(stand.global_basis.z, Vector3.LEFT, Vector3.ONE * 0.001)
	assert_almost_eq(stand.global_position, Vector3(30, 0, 23), Vector3.ONE * 0.001)
	var customer := stand.to_global(Vector3(0, 0.95, 1.7))
	_sweep(Vector3(28, 0.95, 27.5), Vector3(28, 0.95, 23))
	_sweep(Vector3(28, 0.95, 23), customer)
	_assert_clear(customer)
	_assert_floor(customer, 0.0)
	var bowl := stand.get_node("DisplayBowl/Bowl") as MeshInstance3D
	var mesh := bowl.mesh as CylinderMesh
	var top := stand.get_node("Top") as CSGBox3D
	assert_almost_eq(
		bowl.global_position.y - mesh.height * 0.5, top.global_position.y + top.size.y * 0.5, 0.001
	)


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
