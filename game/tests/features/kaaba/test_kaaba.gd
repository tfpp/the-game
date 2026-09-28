extends GutTest
## Structural checks for the kaaba feature (features/kaaba/feature.tscn): a static
## landmark cube placed on open floor inside the main room.

const FEATURE_PATH := "res://features/kaaba/feature.tscn"

const MAIN_ROOM_HALF_EXTENT := 34.5


func test_feature_loads_inside_the_main_room() -> void:
	var root: Node3D = add_child_autofree(_instantiate())
	var pos := root.global_position
	var inside := absf(pos.x) < MAIN_ROOM_HALF_EXTENT and absf(pos.z) < MAIN_ROOM_HALF_EXTENT
	assert_true(inside, "Kaaba should sit inside the main room, got %s" % pos)


func test_structure_has_collision_enabled() -> void:
	var root: Node3D = add_child_autofree(_instantiate())
	var structure := root.find_child("Structure", false, false) as CSGCombiner3D
	assert_not_null(structure)
	assert_true(structure.use_collision)


func test_cube_and_hizam_band_are_present() -> void:
	var root: Node3D = add_child_autofree(_instantiate())
	var structure := root.find_child("Structure", false, false)
	assert_not_null(structure.find_child("Cube", false, false))
	for side: String in ["North", "South", "East", "West"]:
		assert_not_null(structure.find_child("Hizam%s" % side, false, false))


func _instantiate() -> Node3D:
	return (load(FEATURE_PATH) as PackedScene).instantiate() as Node3D
