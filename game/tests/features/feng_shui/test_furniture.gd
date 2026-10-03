extends GutTest

const Room := preload("res://features/feng_shui/room_harmony.gd")
const Furniture := preload("res://features/feng_shui/furniture.gd")
const Desk := preload("res://features/hotel_props/props/writing_desk.tscn")
const Lamp := preload("res://features/hotel_props/props/floor_lamp.tscn")
const Hotel := preload("res://features/hotel_props/interior.tscn")
const FLOOR := Rect2(-10.3, -8.3, 20.6, 16.6)
const ENTRY := Vector2(0, -8.3)


class CountingRoom:
	extends FengShuiRoom
	var computations := 0

	func _compute_evaluation() -> Dictionary:
		computations += 1
		return super._compute_evaluation()


func _mesh(parent: Node3D, at: Vector3, element: String = "") -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.position = at
	if not element.is_empty():
		mesh.set_meta("feng_shui_element", element)
	parent.add_child(mesh)
	return mesh


func test_existing_prop_defaults_and_future_fallback() -> void:
	for identity: String in ["writing_desk", "potted_plant", "single_bed", "casino_stool"]:
		assert_eq(Furniture.default_element(identity), "wood", identity)
	for identity: String in ["floor_lamp", "wall_sconce", "radiator", "crt_television"]:
		assert_eq(Furniture.default_element(identity), "fire", identity)
	for identity: String in ["whiskey_bottle", "water_pitcher", "ice_bucket", "martini-glass"]:
		assert_eq(Furniture.default_element(identity), "water", identity)
	for identity: String in ["slot_machine", "car", "standing_fan", "brass-wall-clock"]:
		assert_eq(Furniture.default_element(identity), "metal", identity)
	for identity: String in ["soap_bar", "tea_saucer", "towel_stack", "FutureMysteryFurniture"]:
		assert_eq(Furniture.default_element(identity), "earth", identity)


func test_real_prefabs_count_once_and_ignore_collision_padding() -> void:
	var root := Node3D.new()
	var desk := Desk.instantiate() as Node3D
	root.add_child(desk)
	var mesh := desk.get_node("Model") as MeshInstance3D
	var bounds := mesh.mesh.get_aabb()
	var snapshot := Furniture.snapshot(root, FLOOR)
	assert_true(snapshot["valid"])
	assert_eq(snapshot["elements"], PackedFloat64Array([1, 0, 0, 0, 0]))
	assert_eq(snapshot["footprints"].size(), 1)
	assert_eq(
		snapshot["footprints"][0],
		Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
	)
	root.free()


func test_nested_rotated_scaled_furniture_uses_room_local_mesh_bounds() -> void:
	var root := Node3D.new()
	root.position = Vector3(900, 40, -600)
	root.rotation.y = 0.3
	var group := Node3D.new()
	group.position = Vector3(2, 0, 3)
	group.rotation.y = PI * 0.5
	group.scale = Vector3(2, 1, 3)
	root.add_child(group)
	var desk := Desk.instantiate() as Node3D
	desk.position = Vector3(1, 0, 0)
	group.add_child(desk)
	var mesh := desk.get_node("Model") as MeshInstance3D
	var expected := group.transform * desk.transform * mesh.transform * mesh.mesh.get_aabb()
	var snapshot := Furniture.snapshot(root, FLOOR)
	var rect: Rect2 = snapshot["footprints"][0]
	assert_almost_eq(rect.position.x, expected.position.x, 0.00001)
	assert_almost_eq(rect.position.y, expected.position.z, 0.00001)
	assert_almost_eq(rect.size.x, expected.size.x, 0.00001)
	assert_almost_eq(rect.size.y, expected.size.z, 0.00001)
	root.free()


func test_metadata_overrides_defaults_and_none_excludes_whole_object() -> void:
	var root := Node3D.new()
	var desk := Desk.instantiate() as Node3D
	desk.set_meta("feng_shui_element", "water")
	root.add_child(desk)
	var lamp := Lamp.instantiate() as Node3D
	lamp.set_meta("feng_shui_element", "none")
	root.add_child(lamp)
	assert_eq(Furniture.snapshot(root, FLOOR)["elements"], PackedFloat64Array([0, 0, 0, 0, 1]))
	root.free()


func test_structure_actors_and_outside_furniture_do_not_contribute() -> void:
	var root := Node3D.new()
	var floor_mesh := _mesh(root, Vector3.ZERO)
	floor_mesh.name = "Floor"
	var grid := GridMap.new()
	root.add_child(grid)
	var actor := CharacterBody3D.new()
	root.add_child(actor)
	_mesh(actor, Vector3.ZERO)
	_mesh(root, Vector3(50, 0, 50), "wood")
	var snapshot := Furniture.snapshot(root, FLOOR)
	assert_eq(snapshot["elements"], PackedFloat64Array([0, 0, 0, 0, 0]))
	assert_true(snapshot["footprints"].is_empty())
	root.free()


func test_tabletop_and_wall_decor_add_elements_without_floor_obstacles() -> void:
	var root := Node3D.new()
	_mesh(root, Vector3(1, 2, 1), "water")
	var wall := _mesh(root, Vector3.ZERO, "fire")
	wall.name = "WallSconce"
	var snapshot := Furniture.snapshot(root, FLOOR)
	assert_eq(snapshot["elements"], PackedFloat64Array([0, 1, 0, 0, 1]))
	assert_true(snapshot["footprints"].is_empty())
	root.free()


func test_future_furniture_only_needs_element_metadata() -> void:
	var root := Node3D.new()
	_mesh(root, Vector3(0, 0, 3), "metal")
	var room := Room.new()
	assert_true(room.set_furnished_layout(FLOOR, ENTRY, root))
	assert_true(room.evaluation()["valid"])
	assert_eq(room.evaluation()["components"]["elements"], 0.0)
	assert_lt(room.evaluation()["components"]["space"], 1.0)
	root.free()
	assert_true(room.evaluation()["valid"], "snapshot retains no nodes")


func test_invalid_override_preserves_existing_score_and_cache() -> void:
	var root := Node3D.new()
	_mesh(root, Vector3.ZERO, "invalid")
	var room := CountingRoom.new()
	assert_true(room.set_layout(FLOOR, ENTRY, [], PackedFloat64Array([1, 1, 1, 1, 1])))
	assert_eq(room.score(), 100.0)
	assert_false(room.set_furnished_layout(FLOOR, ENTRY, root))
	assert_eq(room.score(), 100.0)
	assert_eq(room.computations, 1)
	root.free()


func test_real_unloaded_hotel_scene_is_lazy_cached_and_non_neutral() -> void:
	var anchor := StreamedRoom.new()
	anchor.room_scene = "res://features/hotel_props/interior.tscn"
	var room := CountingRoom.new()
	assert_true(room.set_scene_layout(FLOOR, ENTRY, Hotel))
	assert_eq(room.computations, 0)
	var score_before := room.score()
	assert_true(room.evaluation()["valid"])
	assert_between(score_before, 0.0, 100.0)
	assert_ne(room.evaluation()["components"]["elements"], 0.5)
	assert_lt(room.evaluation()["components"]["space"], 1.0)
	assert_eq(room.computations, 1)
	assert_false(anchor.is_loaded())
	assert_eq(anchor.get_child_count(), 0)
	room.clear()
	assert_false(room.evaluation()["valid"])
	assert_eq(room.computations, 1)
	anchor.free()


func test_scene_layout_can_be_replaced_by_explicit_or_generated_layout() -> void:
	var room := Room.new()
	assert_true(room.set_scene_layout(FLOOR, ENTRY, Hotel))
	assert_true(room.set_layout(FLOOR, ENTRY, [], PackedFloat64Array([1, 1, 1, 1, 1])))
	assert_eq(room.score(), 100.0)
	var root := Node3D.new()
	root.add_child(Desk.instantiate())
	assert_true(room.set_scene_layout(FLOOR, ENTRY, Hotel))
	assert_true(room.set_furnished_layout(FLOOR, ENTRY, root))
	assert_almost_eq(room.evaluation()["components"]["elements"], 0.0, 0.00001)
	root.free()
