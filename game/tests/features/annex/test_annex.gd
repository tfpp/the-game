extends GutTest
## Structural checks for the annex feature (features/annex/feature.tscn): the ten
## rooms connected to the expanded main room.

const FEATURE_PATH := "res://features/annex/feature.tscn"

const MAIN_ROOM_HALF_EXTENT := 35.0


func test_feature_loads_with_ten_rooms() -> void:
	var root: Node3D = add_child_autofree(_instantiate())
	var markers: Array[Marker3D] = []
	_collect_room_markers(root, markers)
	assert_eq(markers.size(), 10)


func test_every_room_sits_outside_the_expanded_main_room() -> void:
	var root: Node3D = add_child_autofree(_instantiate())
	var markers: Array[Marker3D] = []
	_collect_room_markers(root, markers)
	for marker: Marker3D in markers:
		var pos := marker.global_position
		var outside := absf(pos.x) > MAIN_ROOM_HALF_EXTENT or absf(pos.z) > MAIN_ROOM_HALF_EXTENT
		assert_true(outside, "%s should sit outside the main room, got %s" % [marker.name, pos])


func test_dead_end_wings_are_not_connected_to_each_other() -> void:
	# WingNB and WingSC are separate branches off the main room; they never
	# meet, so their far rooms should be well apart.
	var root: Node3D = add_child_autofree(_instantiate())
	var room4 := root.find_child("Room4Marker", true, false) as Marker3D
	var room8 := root.find_child("Room8Marker", true, false) as Marker3D
	assert_gt(room4.global_position.distance_to(room8.global_position), 100.0)


func _instantiate() -> Node3D:
	var scene := load(FEATURE_PATH) as PackedScene
	return scene.instantiate()


func _collect_room_markers(node: Node, out: Array[Marker3D]) -> void:
	for child in node.get_children():
		if child is Marker3D and String(child.name).ends_with("Marker"):
			out.append(child)
		_collect_room_markers(child, out)
