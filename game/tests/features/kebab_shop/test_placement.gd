extends GutTest

const ROOM := preload("res://world/room.tscn")
const SHOP := preload("res://features/kebab_shop/feature.tscn")
const SLOTS := preload("res://features/slot_machine/feature.tscn")
const ROULETTE := preload("res://features/roulette/feature.tscn")
const GPS := preload("res://features/gps/feature.tscn")
var _room: Node3D
var _shop: KebabShop
var _slots: Node3D
var _shape: CapsuleShape3D


func before_each() -> void:
	_room = ROOM.instantiate() as Node3D
	add_child_autofree(_room)
	_shop = SHOP.instantiate() as KebabShop
	add_child_autofree(_shop)
	_slots = SLOTS.instantiate() as Node3D
	add_child_autofree(_slots)
	add_child_autofree(ROULETTE.instantiate())
	_shape = CapsuleShape3D.new()
	_shape.radius = 0.4064
	_shape.height = 1.8288
	await wait_physics_frames(4)


func test_shop_faces_entire_spawn_area_without_blocking_spawns() -> void:
	var spawn := _room.get_node("Spawn") as Marker3D
	var title := _shop.get_node("ShopView/Title") as Label3D
	var space := _shop.get_world_3d().direct_space_state
	for x: int in range(-3, 4):
		for z: int in range(-3, 4):
			var origin := spawn.global_position + Vector3(x, 0, z)
			var query := PhysicsShapeQueryParameters3D.new()
			query.collision_mask = 1
			query.shape = _shape
			query.transform.origin = origin
			assert_true(space.intersect_shape(query).is_empty(), "Spawn remains clear")
			# Check initial and settled eye positions, with the default north-facing view.
			for eye_y: float in [0.9112, 0.1256]:
				var eye := Vector3(origin.x, eye_y, origin.z)
				var direction := (title.global_position - eye).normalized()
				assert_gt(direction.dot(Vector3.FORWARD), 0.75, "Shop ahead of spawn")
				assert_gt((eye - title.global_position).dot(title.global_basis.z), 0.0)
				var ray := PhysicsRayQueryParameters3D.create(eye, title.global_position, 1)
				assert_true(space.intersect_ray(ray).is_empty(), "Unobstructed shop sign")


func test_counter_is_grounded_and_gps_reaches_customer_side() -> void:
	var space := _shop.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(
		_shop.position + Vector3(0, 0.1, 1.5), _shop.position + Vector3(0, -0.1, 1.5), 1
	)
	var hit := space.intersect_ray(ray)
	assert_false(hit.is_empty())
	if not hit.is_empty():
		assert_almost_eq((hit.position as Vector3).y, _shop.position.y, 0.001)
	var counter := _shop.get_node("ShopView/CounterBody") as StaticBody3D
	var box := (counter.get_node("Collision") as CollisionShape3D).shape as BoxShape3D
	assert_almost_eq(counter.global_position.y - box.size.y / 2, _shop.position.y, 0.001)
	var gps := GPS.instantiate()
	var destination := gps.get_node("Destinations/KebabShop") as Marker3D
	assert_almost_eq(
		destination.position, _shop.position + Vector3(1.35, 0, 1.5), Vector3.ONE * 0.001
	)
	gps.free()


func test_customer_bypass_slot_bank_and_north_ramp_routes_remain_clear() -> void:
	var route: Array[Vector3] = [
		Vector3(2, -0.55, 5.9),
		Vector3(2.55, -0.55, -1.5),
		Vector3(4.8, -0.55, -1.5),
		Vector3(4.8, -0.55, -5.9),
	]
	for index: int in route.size() - 1:
		_sweep(route[index], route[index + 1])
	_sweep(Vector3(4.8, -0.55, -5.9), Vector3(4.8, -0.45, -6.2))
	_sweep(Vector3(4.8, -0.45, -6.2), Vector3(0, -0.45, -6.2))
	_sweep(Vector3(0, -0.45, -6.2), Vector3(0, -0.28, -7))
	for machine: Node3D in _slots.get_children():
		var approach := machine.to_global(Vector3(0, 0.95, 2.6))
		_sweep(Vector3(approach.x, approach.y, 5.9), approach)


func _sweep(start: Vector3, end: Vector3) -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = 1
	query.shape = _shape
	query.transform.origin = start
	query.motion = end - start
	var space := _shop.get_world_3d().direct_space_state
	assert_almost_eq(space.cast_motion(query)[0], 1.0, 0.001, "Clear route %s -> %s" % [start, end])
