extends GutTest
## Gnomes and doors remain grounded, with labels visible at the same distance as doors.

const Feature := preload("res://features/gnomes/feature.tscn")
const BodyScene := preload("res://features/gnomes/gnome_body.tscn")


func _bottom(mesh_instance: MeshInstance3D) -> float:
	var box := mesh_instance.mesh.get_aabb()
	return (mesh_instance.transform * box).position.y


func test_door_frames_reach_down_to_the_floor() -> void:
	var feature := Feature.instantiate() as Node3D
	add_child_autofree(feature)
	for side: String in ["North", "South", "East", "West"]:
		for number in 4:
			var hole := feature.get_node("Train%s/Hole%d" % [side, number]) as Node3D
			var frame := hole.get_node("Frame") as MeshInstance3D
			assert_lte(hole.position.y + _bottom(frame), 0.0, "%s %d frame" % [side, number])


func test_door_labels_have_no_mobile_distance_cap() -> void:
	var feature := Feature.instantiate() as Node3D
	add_child_autofree(feature)
	var labels := feature.get_node("TrainNorth/Hole2").find_children("*", "Label3D", false, false)
	assert_eq(labels.size(), 1)
	var label := labels[0] as Label3D
	assert_eq(label.visibility_range_end, 0.0)


func test_gnome_stands_on_boots_over_a_contact_shadow() -> void:
	var gnome := BodyScene.instantiate() as Gnome
	add_child_autofree(gnome)
	for boot: String in ["Body/BootL", "Body/BootR"]:
		assert_almost_eq(_bottom(gnome.get_node(boot) as MeshInstance3D), 0.0, 0.001)
	var shadow := gnome.get_node("Body/ContactShadow") as MeshInstance3D
	assert_between(shadow.position.y, 0.0, 0.01)
	gnome.set_shown(false)
	assert_false(shadow.is_visible_in_tree(), "shadow hides with the gnome")
