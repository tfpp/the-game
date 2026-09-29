extends GutTest

const ANNEX := preload("res://features/annex/feature.tscn")
const SHOP := preload("res://features/kebab_shop/feature.tscn")


func test_shop_is_grounded_and_customer_route_and_plaque_remain_clear() -> void:
	var annex := ANNEX.instantiate() as Node3D
	add_child_autofree(annex)
	var shop := SHOP.instantiate() as KebabShop
	add_child_autofree(shop)
	await wait_physics_frames(4)
	var floor_box := annex.get_node("WingNB/Room3Floor") as CSGBox3D
	var floor_y := floor_box.global_position.y + floor_box.size.y / 2.0
	assert_eq(shop.global_position.y, floor_y)
	var counter := shop.get_node("ShopView/CounterBody") as StaticBody3D
	var collider := counter.get_node("Collision") as CollisionShape3D
	var box := collider.shape as BoxShape3D
	assert_almost_eq(counter.global_position.y - box.size.y / 2.0, floor_y, 0.001)
	assert_gt(counter.global_position.z - box.size.z / 2.0, -69.5)
	assert_lt(counter.global_position.x + box.size.x / 2.0, 14.5)
	assert_gt(counter.global_position.x - box.size.x / 2.0, 5.5)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4064
	shape.height = 1.8288
	var space := shop.get_world_3d().direct_space_state
	# Existing approach, cashier front, then around the east side to the wall plaque.
	var route: Array[Vector3] = [
		Vector3(10, 0.94, -55),
		Vector3(10, 0.94, -62.5),
		Vector3(11.35, 0.94, -64),
		Vector3(13.8, 0.94, -64),
		Vector3(13.8, 0.94, -68.8),
		Vector3(10, 0.94, -68.8)
	]
	for index: int in route.size() - 1:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform.origin = route[index]
		query.motion = route[index + 1] - route[index]
		assert_almost_eq(space.cast_motion(query)[0], 1.0, 0.001, "Clear customer/plaque route")
		var ray := PhysicsRayQueryParameters3D.create(route[index], route[index] - Vector3.UP * 2)
		assert_false(space.intersect_ray(ray).is_empty(), "Route has floor support")
