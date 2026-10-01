extends GutTest
## The former Jump Lounge is now the food court; no launch pads remain on the map.


func test_jump_lounge_pads_are_removed() -> void:
	const SCENE := preload("res://features/trampoline/feature.tscn")
	var root: Node3D = add_child_autofree(SCENE.instantiate())
	assert_eq(root.get_child_count(), 0)
