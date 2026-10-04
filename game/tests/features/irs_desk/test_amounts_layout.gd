extends GutTest

const Desk := preload("res://features/irs_desk/irs_desk.gd")
const SCENE := preload("res://features/irs_desk/feature.tscn")


func test_dollars_parse_exactly_without_tax_assistance() -> void:
	for example: Array in [["0", 0], ["0.00", 0], ["1.2", 120], ["12.34", 1234], [" 99 ", 9900]]:
		assert_eq(Desk.parse_amount(example[0], Desk.MAX_TAX_CENTS), example[1])
	for invalid: String in [
		"",
		"-1",
		"+1",
		"1e2",
		"NaN",
		"1.001",
		".5",
		"1.",
		"1,000",
		"1 0",
		"1..2",
		"999999999999999999999999",
		"100.01"
	]:
		assert_eq(Desk.parse_amount(invalid, Desk.MAX_TAX_CENTS), -1, invalid)
	assert_eq(Desk.parse_amount("100", Desk.MAX_TAX_CENTS), 10000)


func test_desk_is_supported_and_front_approach_and_south_aisle_stay_clear() -> void:
	var room := preload("res://features/casino_hub/casino_gridmap.tscn").instantiate() as Node3D
	add_child_autofree(room)
	var desk := SCENE.instantiate() as Node3D
	add_child_autofree(desk)
	await wait_physics_frames(4)
	assert_eq(desk.global_position, Vector3(10, 0, 17.8))
	var model := desk.get_node("Desk/Model") as MeshInstance3D
	var bounds := model.global_transform * model.get_aabb()
	assert_almost_eq(bounds.position.y, 0.0, 0.01)
	assert_almost_eq(bounds.end.y, 0.803, 0.01)
	var sign := desk.get_node("Sign") as SignBoard
	assert_true((sign.global_basis * Vector3.BACK).is_equal_approx(Vector3.FORWARD))
	assert_lt(sign.board_size().x, 1.1)
	var space := desk.get_world_3d().direct_space_state
	for point: Vector3 in [Vector3(10, 0, 16.4), Vector3(9, 0, 17.8), Vector3(11, 0, 17.8)]:
		var floor_hit := space.intersect_ray(
			PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2, point + Vector3.DOWN, 1)
		)
		assert_false(floor_hit.is_empty())
		if not floor_hit.is_empty():
			assert_almost_eq((floor_hit["position"] as Vector3).y, 0.0, 0.01)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	for index: int in 21:
		var point := Vector3(0, 0.95, 15).lerp(Vector3(10, 0.95, 16.4), index / 20.0)
		query.transform = Transform3D(Basis.IDENTITY, point)
		assert_true(space.intersect_shape(query).is_empty(), "Standing approach remains clear")
	desk.get_node("TaxForm")._close()
