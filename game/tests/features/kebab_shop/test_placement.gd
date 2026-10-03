extends GutTest
## The counter lives in the strip mall, with unchanged customer-facing geometry.

const ROOM := preload("res://features/strip_mall/interior.tscn")
const COURT := preload("res://features/food_court/feature.tscn")
const SHOP := preload("res://features/kebab_shop/feature.tscn")
const GPS := preload("res://features/gps/feature.tscn")

var _shop: KebabShop


func before_each() -> void:
	var room := ROOM.instantiate() as Node3D
	room.position = Vector3(0, 0, -5000)
	add_child_autofree(room)
	add_child_autofree(COURT.instantiate())
	_shop = SHOP.instantiate() as KebabShop
	add_child_autofree(_shop)
	await wait_physics_frames(4)


func test_kebab_counter_faces_the_hall_and_gps_marks_its_customer_side() -> void:
	var counter := _shop.get_node("ShopView/CounterBody") as StaticBody3D
	var box := (counter.get_node("Collision") as CollisionShape3D).shape as BoxShape3D
	assert_almost_eq(counter.global_position.y - box.size.y / 2, 0.0, 0.001)
	assert_almost_eq(_shop.global_basis.z, Vector3.LEFT, Vector3.ONE * 0.001, "Front faces west")
	var bench := _shop.get_node("ShopView/BackBenchBody") as Node3D
	assert_lt(bench.global_position.x + 0.3, 33.0, "Kitchen inside the east wall")
	var gps := GPS.instantiate()
	var destination := gps.get_node("Destinations/KebabShop") as Marker3D
	assert_almost_eq(
		destination.position, _shop.to_global(Vector3(1.35, 0, 1.5)), Vector3.ONE * 0.001
	)
	var court := gps.get_node("Destinations/FoodCourt") as Marker3D
	_assert_floor(court.position + Vector3.UP, 0.0)
	gps.free()


func _assert_floor(from: Vector3, expected_y: float) -> void:
	var query := PhysicsRayQueryParameters3D.create(from, from - Vector3(0, 4, 0))
	var hit := _shop.get_world_3d().direct_space_state.intersect_ray(query)
	assert_false(hit.is_empty(), "Floor under %s" % from)
	if not hit.is_empty():
		assert_almost_eq((hit["position"] as Vector3).y, expected_y, 0.02)
