extends GutTest

const FEATURE := preload("res://features/starter_room/feature.tscn")


func test_finishes_are_indexed_and_have_valid_winding_and_small_atlas() -> void:
	for name: String in ["garage_shutter", "garage_window_frame", "garage_broom_cupboard"]:
		var mesh := load("res://assets/starter_room/%s.res" % name) as ArrayMesh
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		assert_gt(indices.size(), 0)
		for i: int in range(0, indices.size(), 3):
			var a := indices[i]
			var b := indices[i + 1]
			var c := indices[i + 2]
			var cross := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
			assert_gt(cross.length(), .000001, name)
			assert_lt(cross.normalized().dot(normals[a]), -.99, name)
	var Texture := preload("res://assets/starter_room/garage_finishes.png")
	assert_eq(Texture.get_size(), Vector2(128, 128))
	assert_true(Texture.get_image().has_mipmaps())


func test_window_storm_and_clean_garage_unload_together() -> void:
	var feature := FEATURE.instantiate() as Node3D
	add_child_autofree(feature)
	var room := feature.get_node("Room") as StreamedRoom
	room.load_room(3000)
	await wait_physics_frames(3)
	var content := room.get_node("Content")
	assert_true(content.has_node("GarageFinishes/AlleyWindow/Collision/Pane"))
	assert_true(content.has_node("AlleyView/AlleyRain"))
	assert_true(content.has_node("AlleyView/AlleyStormAmbience"))
	assert_eq(feature.find_children("*", "Label3D", true, false).size(), 0)
	var rain := content.get_node("AlleyView/AlleyRain") as CPUParticles3D
	assert_lt(rain.position.x + rain.emission_box_extents.x, -8.0)
	var camera := Camera3D.new()
	room.add_child(camera)
	camera.position = Vector3(0, 1.7, 3)
	camera.make_current()
	await wait_process_frames(3)
	assert_true(rain.emitting)
	camera.position = Vector3(0, 1.7, 30)
	await wait_process_frames(3)
	assert_false(rain.emitting)
	camera.queue_free()
	room.unload_room()
	await wait_process_frames(3)
	assert_false(room.is_loaded())
