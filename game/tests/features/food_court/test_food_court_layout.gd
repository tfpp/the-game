extends GutTest
## Capsule routes through the relocated dining plaza and all three storefronts.

const ROOM := preload("res://features/strip_mall/interior.tscn")
const COURT := preload("res://features/food_court/feature.tscn")
const SHOP := preload("res://features/kebab_shop/feature.tscn")

var _court: FoodCourt
var _shop: KebabShop
var _shape: CapsuleShape3D


func before_each() -> void:
	var room := ROOM.instantiate() as Node3D
	room.position = Vector3(0, 0, -5000)
	add_child_autofree(room)
	_court = COURT.instantiate() as FoodCourt
	add_child_autofree(_court)
	_shop = SHOP.instantiate() as KebabShop
	add_child_autofree(_shop)
	_shape = CapsuleShape3D.new()
	_shape.radius = .4064
	_shape.height = 1.8288
	await wait_physics_frames(4)


func test_arrival_and_central_aisle_reach_all_food_counters() -> void:
	_sweep(Vector3(4, .95, 28), Vector3(26, .95, 28))
	for z: float in [22.5, 29.35, 35.0]:
		_sweep(Vector3(26, .95, 28), Vector3(26, .95, z))
		_sweep(Vector3(26, .95, z), Vector3(28.3, .95, z))
		_assert_floor(Vector3(28.3, .95, z))
	_assert_floor(Vector3(4, 1, 28))


func test_shop_bays_are_covered_but_dining_plaza_is_open_air() -> void:
	for z: float in [21.0, 28.0, 35.0]:
		_assert_floor(Vector3(30, 1, z))
		assert_false(_ray(Vector3(30, 2, z), Vector3(30, 12, z)).is_empty(), "Shop roof")
		assert_true(_ray(Vector3(18, 2, z), Vector3(18, 12, z)).is_empty(), "Open plaza")
	for target: Vector3 in [Vector3(18, 1.5, 50), Vector3(40, 1.5, 28), Vector3(18, 1.5, 15)]:
		assert_false(_ray(Vector3(18, 1.5, 28), target).is_empty(), "Site boundary")


func test_every_booth_is_reachable_and_stand_up_spots_are_clear() -> void:
	for index: int in _court.seats.size():
		var spot := _court.to_local(_court.stand_position(index)) + Vector3(0, .95, 0)
		_assert_clear(spot)
		assert_true(_court.in_reach(_court.to_global(spot), index))
		_sweep(Vector3(spot.x, spot.y, 28), spot)
		_assert_floor(spot)


func test_booths_stand_on_floor_with_their_original_footprints() -> void:
	for booth: Node3D in _court.get_node("Booths").get_children():
		var shape := booth.get_node("TableBody").get_child(0) as CollisionShape3D
		var box := shape.shape as BoxShape3D
		assert_almost_eq(shape.global_position.y - box.size.y * .5, 0.0, .001)
		assert_between(booth.position.z, 21.4, 34.6)
		assert_between(booth.position.x, 4.5, 26.0)


func test_poke_and_wendys_still_face_the_plaza_with_grounded_display_food() -> void:
	for path: String in ["PokeStand", "WendysStand"]:
		var stand := _court.get_node(path) as Node3D
		assert_almost_eq(stand.global_basis.z, Vector3.LEFT, Vector3.ONE * .001)
		var customer := _court.to_local(stand.to_global(Vector3(0, .95, 1.7)))
		_assert_clear(customer)
		_assert_floor(customer)
		var counter := stand.get_node("Counter") as Node3D
		assert_almost_eq(counter.global_position.y, .5, .01)
	var poke := _court.get_node("PokeStand") as Node3D
	var wendys := _court.get_node("WendysStand") as Node3D
	assert_eq(poke.position, Vector3(30, 0, 22.5))
	assert_eq(wendys.position, Vector3(30, 0, 35))
	assert_gt(wendys.global_position.distance_to(poke.global_position), 6.0)
	assert_gt(wendys.global_position.distance_to(_shop.global_position), 6.0)


func test_display_food_remains_in_contact_with_the_original_counters() -> void:
	var poke := _court.get_node("PokeStand")
	var bowl := poke.get_node("DisplayBowl/Bowl") as MeshInstance3D
	var bowl_mesh := bowl.mesh as CylinderMesh
	var top := poke.get_node("Top") as CSGBox3D
	assert_almost_eq(
		bowl.global_position.y - bowl_mesh.height * .5,
		top.global_position.y + top.size.y * .5,
		.001
	)
	var wendys := _court.get_node("WendysStand")
	var burger := wendys.get_node("DisplayBurger/BottomBun") as MeshInstance3D
	var bun := burger.mesh as CylinderMesh
	var surface := wendys.get_node("Top") as MeshInstance3D
	var box := surface.mesh as BoxMesh
	assert_almost_eq(
		burger.global_position.y - bun.height * .5,
		surface.global_position.y + box.size.y * .5,
		.001
	)


func _assert_clear(point: Vector3) -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = 1
	query.shape = _shape
	query.transform.origin = _court.to_global(point)
	assert_true(
		_court.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),
		"Clear standing capsule at %s" % point
	)


func _sweep(start: Vector3, end: Vector3) -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = 1
	query.shape = _shape
	query.transform.origin = _court.to_global(start)
	query.motion = end - start
	assert_almost_eq(
		_court.get_world_3d().direct_space_state.cast_motion(query)[0],
		1.0,
		.001,
		"Clear route %s -> %s" % [start, end]
	)


func _assert_floor(point: Vector3) -> void:
	var hit := _ray(point, point - Vector3(0, 4, 0))
	assert_false(hit.is_empty(), "Floor under %s" % point)
	if not hit.is_empty():
		assert_almost_eq((hit["position"] as Vector3).y, 0.0, .02)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(_court.to_global(from), _court.to_global(to))
	return _court.get_world_3d().direct_space_state.intersect_ray(query)
