extends GutTest

const STREET := preload("res://features/pawn_shop/street.tscn")
const SHOP := preload("res://features/pawn_shop/feature.tscn")


func test_trees_are_grounded_and_clear_of_street_and_buildings() -> void:
	var street := STREET.instantiate() as Node3D
	add_child_autofree(street)
	street.set_process(false)
	var grass := street.get_node("GrassGround") as MeshInstance3D
	var trees := street.get_node("Trees")
	assert_eq(trees.get_child_count(), 6)
	var blockers: Array[Rect2] = [
		Rect2(-59, 30, 100, 18),  # Both sidewalks and road, including van and lamps.
		Rect2(-22.12, 48.28, 6.24, 14.44),  # Left tenement.
		Rect2(-1.12, 48.28, 6.24, 14.44),  # Right tenement.
		Rect2(-11.62, 48.78, 6.24, 14.44),  # Warehouse.
	]
	for tree: MeshInstance3D in trees.get_children():
		var mesh := tree.mesh as QuadMesh
		var bottom := tree.position.y + (mesh.center_offset.y - mesh.size.y / 2) * tree.scale.y
		assert_almost_eq(bottom, grass.position.y, 0.001, "Painted root touches grass")
		# Any camera yaw plus the shader's maximum wind excursion.
		var radius := (mesh.size.x / 2 + 0.195) * tree.scale.x
		var centre := Vector2(tree.position.x, tree.position.z)
		for blocker: Rect2 in blockers:
			assert_false(
				blocker.grow(radius).has_point(centre), "%s clears %s" % [tree.name, blocker]
			)
		for other: MeshInstance3D in trees.get_children():
			if other == tree:
				continue
			assert_gt(tree.position.distance_to(other.position), 5.0, "Trees spread apart")
		assert_eq(tree.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		assert_eq(tree.get_child_count(), 0, "Decor only: no collision, scripts or gameplay")
		assert_null(tree.get_script())


func test_shared_mesh_texture_and_wind_budget() -> void:
	var street := STREET.instantiate() as Node3D
	add_child_autofree(street)
	street.set_process(false)
	var trees := street.get_node("Trees")
	var first := trees.get_child(0) as MeshInstance3D
	var material := first.mesh.surface_get_material(0) as ShaderMaterial
	var texture := material.get_shader_parameter("tree_texture") as Texture2D
	assert_eq(texture.get_size(), Vector2(128, 128))
	assert_eq(material.get_shader_parameter("sway_amplitude"), 0.16)
	assert_eq(material.get_shader_parameter("flutter_amplitude"), 0.035)
	var mesh := first.mesh as QuadMesh
	assert_eq(mesh.subdivide_width, 2)
	assert_eq(mesh.subdivide_depth, 7)
	assert_eq(mesh.get_faces().size() / 3, 48, "Only 48 triangles per tree")
	for tree: MeshInstance3D in trees.get_children():
		assert_same(tree.mesh, first.mesh, "Share geometry and one material")
	var image := texture.get_image()
	assert_gt(image.get_pixel(64, 127).a, 0.5, "Trunk reaches quad bottom")
	assert_lt(image.get_pixel(0, 127).a, 0.5, "No opaque rectangular backdrop")


func test_streaming_reloads_same_trees_at_remote_shop_origin() -> void:
	var shop := SHOP.instantiate() as Node3D
	add_child_autofree(shop)
	var room := shop.get_node("Room") as StreamedRoom
	room.set_physics_process(false)
	room.load_room()
	var tree := room.find_child("FarGap", true, false) as MeshInstance3D
	assert_not_null(tree)
	var position_before := tree.global_position
	assert_almost_eq(position_before, Vector3(-13.75, -0.42, -3949.5), Vector3.ONE * 0.001)
	assert_true(room.global_render_bounds().has_point(position_before + Vector3.UP * 6))
	room.unload_room()
	await wait_process_frames(2)
	assert_null(room.find_child("FarGap", true, false))
	room.load_room()
	tree = room.find_child("FarGap", true, false) as MeshInstance3D
	assert_not_null(tree)
	assert_eq(tree.global_position, position_before, "Late load/offline uses identical scene")
