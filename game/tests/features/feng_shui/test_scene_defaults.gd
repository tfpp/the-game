extends GutTest

const Room := preload("res://features/feng_shui/room_harmony.gd")
const Furniture := preload("res://features/feng_shui/furniture.gd")
const FLOOR := Rect2(-100, -100, 200, 200)
const Desk := preload("res://features/hotel_props/props/writing_desk.tscn")


class ScriptTrap:
	extends Node3D
	static var initializations := 0

	func _init() -> void:
		initializations += 1


func test_all_existing_reusable_prop_kits_have_element_defaults() -> void:
	var count := 0
	for directory: String in [
		"res://features/hotel_props/props",
		"res://features/casino_props/props",
		"res://features/casino_props/props/bundle",
		"res://features/street_props/props",
		"res://features/procedural_rooms/props",
	]:
		for file: String in DirAccess.get_files_at(directory):
			if not file.ends_with(".tscn"):
				continue
			var scene := load(directory.path_join(file)) as PackedScene
			var root := scene.instantiate() as Node3D
			var snapshot := Furniture.snapshot(root, FLOOR)
			assert_true(snapshot["valid"], file)
			var total := 0.0
			for weight: float in snapshot["elements"]:
				total += weight
			assert_eq(total, 1.0, file + " must contribute once, not once per mesh")
			root.free()
			count += 1
	assert_gte(count, 169)


func test_existing_static_room_scenes_can_be_scored_without_entering_tree() -> void:
	for path: String in [
		"res://features/hotel_props/interior.tscn",
		"res://features/casino_hub/interior.tscn",
		"res://features/room_doors/rooms/lounge.tscn",
		"res://features/room_doors/rooms/cellar.tscn",
		"res://features/pawn_shop/interior.tscn",
		"res://features/starter_room/interior.tscn",
		"res://features/strip_mall/interior.tscn",
	]:
		var room := Room.new()
		assert_true(room.set_scene_layout(FLOOR, Vector2(0, -100), load(path) as PackedScene), path)
		assert_true(room.evaluation()["valid"], path)
		assert_between(room.score(), 0.0, 100.0, path)


func test_generated_apartment_lobby_has_defaults_without_new_authoring_fields() -> void:
	var scene := load("res://features/apartments/lobby_content.tscn") as PackedScene
	var generated := scene.instantiate() as Node3D
	add_child_autofree(generated)  # Owning builder generates furniture in _ready.
	var floor_rect := Rect2(-8, -7, 16, 14)
	var snapshot := Furniture.snapshot(generated, floor_rect)
	assert_gt(snapshot["elements"][0], 0.0, "existing desk and benches default to wood")
	assert_gt(snapshot["footprints"].size(), 0)
	var room := Room.new()
	assert_true(room.set_furnished_layout(floor_rect, Vector2(0, 7), generated))
	assert_true(room.evaluation()["valid"])
	assert_lt(room.evaluation()["components"]["space"], 1.0)


func test_floor_height_supports_raised_furniture() -> void:
	var root := Node3D.new()
	var desk := Desk.instantiate() as Node3D
	desk.position.y = 2.5
	root.add_child(desk)
	assert_true(Furniture.snapshot(root, FLOOR)["footprints"].is_empty())
	assert_eq(Furniture.snapshot(root, FLOOR, 2.5)["footprints"].size(), 1)
	var room := Room.new()
	assert_true(room.set_furnished_layout(FLOOR, Vector2.ZERO, root, 2.5))
	assert_lt(room.evaluation()["components"]["space"], 1.0)
	assert_false(room.set_furnished_layout(FLOOR, Vector2.ZERO, root, NAN))
	assert_false(room.set_scene_layout(FLOOR, Vector2.ZERO, Desk, INF))
	assert_true(room.evaluation()["valid"])
	root.free()


func test_numbered_existing_objects_keep_their_defaults() -> void:
	assert_eq(Furniture.default_element("Rack0"), "wood")
	assert_eq(Furniture.default_element("Rack12"), "wood")
	var root := Node3D.new()
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = BoxMesh.new()
	floor_mesh.name = "Floor2"
	root.add_child(floor_mesh)
	assert_true(Furniture.snapshot(root, FLOOR)["footprints"].is_empty())
	root.free()


func test_light_is_fire_without_occupying_the_floor() -> void:
	var root := Node3D.new()
	var light := OmniLight3D.new()
	light.position = Vector3(3, 2, 4)
	root.add_child(light)
	var snapshot := Furniture.snapshot(root, FLOOR)
	assert_eq(snapshot["elements"], PackedFloat64Array([0, 1, 0, 0, 0]))
	assert_true(snapshot["footprints"].is_empty())
	root.free()


func test_invalid_deferred_scene_reports_invalid_not_a_neutral_score() -> void:
	var root := Node3D.new()
	root.set_meta("feng_shui_element", "typo")
	var scene := PackedScene.new()
	assert_eq(scene.pack(root), OK)
	root.free()
	var room := Room.new()
	assert_true(room.set_scene_layout(FLOOR, Vector2.ZERO, scene))
	assert_false(room.evaluation()["valid"])
	assert_eq(room.score(), 0.0)


func test_scene_reader_never_runs_scripts_even_init() -> void:
	var root := ScriptTrap.new()
	root.name = "Room"
	var desk := Desk.instantiate() as Node3D
	root.add_child(desk)
	desk.owner = root
	var scene := PackedScene.new()
	assert_eq(scene.pack(root), OK)
	root.free()
	ScriptTrap.initializations = 0
	var room := Room.new()
	assert_true(room.set_scene_layout(FLOOR, Vector2.ZERO, scene))
	assert_true(room.evaluation()["valid"])
	assert_almost_eq(room.evaluation()["components"]["elements"], 0.0, 0.00001)
	assert_eq(ScriptTrap.initializations, 0)


func test_scene_instance_overrides_match_generated_snapshot() -> void:
	var root := Node3D.new()
	root.name = "Room"
	var desk := Desk.instantiate() as Node3D
	desk.position = Vector3(4, 0, 7)
	desk.rotation.y = 0.5
	desk.set_meta("feng_shui_element", "water")
	root.add_child(desk)
	desk.owner = root
	var expected := Room.new()
	assert_true(expected.set_furnished_layout(FLOOR, Vector2.ZERO, root))
	var scene := PackedScene.new()
	assert_eq(scene.pack(root), OK)
	root.free()
	var actual := Room.new()
	assert_true(actual.set_scene_layout(FLOOR, Vector2.ZERO, scene))
	assert_eq(actual.evaluation(), expected.evaluation())


func test_empty_scene_replacement_preserves_prior_cache() -> void:
	var room := Room.new()
	assert_true(room.set_layout(FLOOR, Vector2.ZERO, [], PackedFloat64Array([1, 1, 1, 1, 1])))
	assert_eq(room.score(), 100.0)
	assert_false(room.set_scene_layout(FLOOR, Vector2.ZERO, PackedScene.new()))
	assert_eq(room.score(), 100.0)


func test_furnished_snapshot_replacement_remains_lazy() -> void:
	var root := Node3D.new()
	var furniture := MeshInstance3D.new()
	furniture.mesh = BoxMesh.new()
	furniture.set_meta("feng_shui_element", "wood")
	root.add_child(furniture)
	var room := Room.new()
	assert_true(room.set_furnished_layout(FLOOR, Vector2.ZERO, root))
	furniture.set_meta("feng_shui_element", "water")
	root.free()
	# Geometry and element snapshot must not retain or observe the former scene nodes.
	assert_true(room.evaluation()["valid"])
	assert_almost_eq(room.evaluation()["components"]["elements"], 0.0, 0.00001)
