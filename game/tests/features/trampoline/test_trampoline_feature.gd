extends GutTest
## The retired hall no longer auto-loads bounce pads; reusable pad/math stay intact.


func test_retired_feature_has_no_pads_or_launch_areas() -> void:
	var scene := load("res://features/trampoline/feature.tscn") as PackedScene
	var root := scene.instantiate()
	add_child_autofree(root)
	assert_eq(root.get_child_count(), 0)
	assert_eq(root.find_children("*", "Area3D", true, false).size(), 0)
