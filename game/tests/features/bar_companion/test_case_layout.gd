extends GutTest

const ROOM := preload("res://features/casino_hub/gridmap/playable.tscn")
const BAR := preload("res://features/bar_companion/feature.tscn")
var _room: Node3D
var _bar: Node3D
var _case: VivienneCase


func before_each() -> void:
	_room = ROOM.instantiate()
	add_child_autofree(_room)
	_bar = BAR.instantiate()
	add_child_autofree(_bar)
	_case = _bar.get_node("VivienneCase")
	await wait_physics_frames(3)


func test_documents_and_phone_rest_on_real_furniture_and_do_not_block() -> void:
	var furniture := _room.get_node("Casino/Furnishings")
	for index: int in 5:
		var point := _case.get_node("Evidence%d" % index) as Node3D
		var collider: CollisionShape3D
		if index < 3:
			collider = furniture.get_node("TableBody%d/Shape" % index)
		elif index == 3:
			collider = furniture.get_node("BarCounter/Shape")
		else:
			collider = furniture.get_node("BundleFurnishings/CocktailTable/Collider")
		var shape := collider.shape as BoxShape3D
		var top := collider.global_position.y + shape.size.y / 2
		assert_almost_eq(point.global_position.y, top, 0.001)
		var model := point.get_node("Model") as MeshInstance3D
		var bounds := model.global_transform * model.get_aabb()
		assert_almost_eq(bounds.position.y, top, 0.003, "no floating or sinking")
		var center := collider.to_local(bounds.get_center())
		assert_lt(absf(center.x) + bounds.size.x / 2, shape.size.x / 2)
		assert_lt(absf(center.z) + bounds.size.z / 2, shape.size.z / 2)
		assert_true(point.find_children("*", "CollisionObject3D", true, false).is_empty())
		if index < 3:
			for slot: int in 3:
				var glass := _bar.get_node("BusboyShift/Glass%d" % (index * 3 + slot)) as Node3D
				assert_gt(point.global_position.distance_to(glass.global_position), 0.25)
	assert_gt(
		VivienneCase.SPOTS[3].distance_to(
			(_bar.get_node("BusboyShift/Bar") as Node3D).global_position
		),
		0.5
	)
	assert_gt(
		VivienneCase.SPOTS[4].distance_to(
			(furniture.get_node("BundleFurnishings/Martini") as Node3D).global_position
		),
		0.15
	)


func test_all_objectives_have_clear_grounded_approaches_and_remain_in_range() -> void:
	var approaches: Array[Vector3] = [
		Vector3(-6.6, -1.25, -6.8),
		Vector3(-6.6, -1.25, -1.8),
		Vector3(-6.6, -1.25, 2.8),
		Vector3(-11, -1.25, -8.7),
		Vector3(19.4, 0, 8.9)
	]
	for index: int in 5:
		var feet := approaches[index]
		var query := PhysicsShapeQueryParameters3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = 0.35
		shape.height = 1.8
		query.shape = shape
		query.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * 0.94)
		query.collision_mask = 1
		assert_true(
			_room.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),
			"standing clearance at objective %d" % index
		)
		var ray := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.1, feet - Vector3.UP, 1)
		assert_false(_room.get_world_3d().direct_space_state.intersect_ray(ray).is_empty())
		assert_lt(feet.distance_to(VivienneCase.SPOTS[index]), 2.2)
