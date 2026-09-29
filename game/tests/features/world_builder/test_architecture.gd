extends GutTest

const Layout := preload("res://features/world_builder/layout.gd")
const Builder := preload("res://features/world_builder/mesh_builder.gd")
const Geometry := preload("res://features/world_builder/geometry.gd")
const Profiles := preload("res://features/world_builder/profiles.gd")
const HOTEL := "res://features/world_builder/examples/hotel.json"


func _spec() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(HOTEL)) as Dictionary


func test_fluted_column_ends_join_round_bases_and_normals_face_outward() -> void:
	var geometry := Geometry.new()
	geometry.materials["stone"] = StandardMaterial3D.new()
	Profiles.lathe(
		geometry,
		"stone",
		Vector3.ZERO,
		Basis.IDENTITY,
		[Vector2(1, 0), Vector2(1, 1), Vector2(1, 2), Vector2(1, 3)],
		48,
		false,
		8
	)
	var world := Node3D.new()
	geometry.finish(world)
	add_child_autofree(world)
	var has_flute := false
	for node: Node in world.get_children():
		var arrays := (node as MeshInstance3D).mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i: int in vertices.size():
			var radial := Vector3(vertices[i].x, 0, vertices[i].z)
			assert_gt(normals[i].dot(radial), 0.0, "Curved normals face away from shaft")
			if is_zero_approx(vertices[i].y) or is_equal_approx(vertices[i].y, 3):
				assert_almost_eq(radial.length(), 1.0, 0.001, "End ring closes against round base")
			else:
				has_flute = has_flute or radial.length() < 0.9
	assert_true(has_flute, "Interior rings retain real recessed flute geometry")


func test_room_and_hall_heights_are_independent() -> void:
	var layout := Layout.compile(_spec())
	assert_eq(layout["errors"], [])
	assert_almost_eq(layout["heights"][Vector2i(1, 1)], 5.2, 0.001)
	assert_almost_eq(layout["heights"][Vector2i(6, 15)], 3.6, 0.001)
	assert_almost_eq(layout["heights"][Vector2i(1, 28)], 4.2, 0.001)
	assert_eq(layout["openings"].size(), 7)
	assert_eq(layout["pillars"].size(), 2)


func test_bad_dimensions_openings_and_pillars_are_rejected() -> void:
	for replacement: Dictionary in [
		{"style": {"panel_spacing": 0}},
		{"style": {"windows": "yes"}},
		{"style": {"window_width": 20}},
		{"hall_height": 1},
	]:
		var spec := _spec()
		spec.merge(replacement, true)
		assert_false(Layout.compile(spec)["errors"].is_empty(), str(replacement))
	for replacement: Dictionary in [
		{"height": 2.5},
		{"pillars": [[6.5, 5.5]]},
		{"pillars": [[0.1, 0.1]]},
		{"pillars": [[2, 2], [2.1, 2.1]]},
		{"pillars": "bad"},
		{"openings": "bad"},
		{"openings": [{"id": "Broken", "kind": "window", "side": "west", "offset": 9.8}]},
		{"openings": [{"id": "Broken", "kind": "door", "side": "west", "offset": 2, "width": 0.7}]},
		{"openings": [{"id": "Broken", "kind": "window", "side": "ceiling", "offset": 2}]},
		{"openings": [{"id": "Hall", "kind": "window", "side": "south", "offset": 5}]},
	]:
		var spec := _spec()
		spec["rooms"][0].merge(replacement, true)
		assert_false(Layout.compile(spec)["errors"].is_empty(), str(replacement))
	var spec := _spec()
	spec["rooms"][0]["openings"].append(spec["rooms"][0]["openings"][0].duplicate())
	assert_false(Layout.compile(spec)["errors"].is_empty(), "Duplicate opening IDs")
	spec["rooms"][0]["openings"][-1]["id"] = "Overlap"
	assert_false(Layout.compile(spec)["errors"].is_empty(), "Overlapping opening frames")


func test_auto_windows_fit_short_rooms_and_avoid_authored_openings() -> void:
	var spec := {
		"version": 1,
		"height": 2.5,
		"style": {"windows": true},
		"rooms": [{"id": "Short", "size": [8, 8], "at": [0, 0]}]
	}
	var layout := Layout.compile(spec)
	assert_eq(layout["errors"], [])
	assert_gt(layout["openings"].size(), 0)
	for opening: Dictionary in layout["openings"]:
		assert_lte(opening["sill"] + opening["height"], 2.15)
	spec = _spec()
	spec["style"]["windows"] = true
	layout = Layout.compile(spec)
	assert_eq(layout["errors"], [])
	for wall: Dictionary in layout["walls"]:
		for a: Dictionary in wall["openings"]:
			for b: Dictionary in wall["openings"]:
				if a["id"] != b["id"]:
					assert_true(
						(
							a["start"] + a["width"] <= b["start"]
							or b["start"] + b["width"] <= a["start"]
						)
					)


func test_saved_hotel_keeps_materials_markers_and_structural_collision() -> void:
	var layout := Layout.compile(_spec())
	var original := Builder.build(layout)
	var packed := PackedScene.new()
	assert_eq(packed.pack(original), OK)
	assert_eq(ResourceSaver.save(packed, "user://hotel_test.scn", ResourceSaver.FLAG_COMPRESS), OK)
	original.free()
	var world := (load("user://hotel_test.scn") as PackedScene).instantiate() as Node3D
	add_child_autofree(world)
	await wait_physics_frames(3)
	assert_eq(world.get_node("Openings").get_child_count(), 7)
	assert_true(world.has_node("Openings/GrandLounge_GardenDoor"))
	assert_almost_eq(world.get_node("Rooms/GrandLounge").get_meta("height"), 5.2, 0.001)
	var triangles := 0
	var shaped_normals := 0
	for node: Node in world.get_children():
		if node is MeshInstance3D:
			triangles += node.mesh.get_faces().size() / 3
			for surface: int in node.mesh.get_surface_count():
				var arrays: Array = node.mesh.surface_get_arrays(surface)
				for normal: Vector3 in arrays[Mesh.ARRAY_NORMAL]:
					var absolute := normal.abs()
					if maxf(absolute.x, maxf(absolute.y, absolute.z)) < 0.98:
						shaped_normals += 1
				var material := node.mesh.surface_get_material(surface) as StandardMaterial3D
				assert_not_null(material.albedo_texture)
				assert_eq(material.albedo_texture.get_size(), Vector2(128, 128))
	assert_gt(shaped_normals, 1000, "Curved and bevelled architectural mesh surfaces")
	assert_lt(triangles, 80000, "Profiled two-room hotel geometry budget")
	var space := world.get_world_3d().direct_space_state
	# Closed door and fixed glazing stop players; the authored open doorway is a real hole.
	assert_false(_ray(space, Vector3(10, 1, 2.75), Vector3(13, 1, 2.75)).is_empty())
	assert_false(_ray(space, Vector3(1, 2, 1.75), Vector3(-1, 2, 1.75)).is_empty())
	assert_true(_ray(space, Vector3(8.75, 1, 1), Vector3(8.75, 1, -1)).is_empty())
	assert_false(_ray(space, Vector3(8.75, 3.4, 1), Vector3(8.75, 3.4, -1)).is_empty())
	_sweep(space, Vector3(8.75, 0.94, 1), Vector3(8.75, 0.94, -1))
	_sweep(space, Vector3(6.5, 0.94, 5.5), Vector3(6.5, 0.94, 30.5))
	# Roofs meet different heights and the vertical step closes the gap above the hall.
	for point: Vector3 in [Vector3(1, 5.2, 1), Vector3(6.5, 3.6, 15), Vector3(1, 4.2, 28)]:
		var hit := _ray(space, Vector3(point.x, 1.5, point.z), Vector3(point.x, 9, point.z))
		assert_false(hit.is_empty())
		if not hit.is_empty():
			assert_almost_eq((hit["position"] as Vector3).y, point.y, 0.01)
	assert_false(_ray(space, Vector3(6.5, 4.5, 9), Vector3(6.5, 4.5, 11)).is_empty())
	assert_false(
		_ray(space, Vector3(2, 1, 3), Vector3(2, 1, 1)).is_empty(), "Freestanding pillar collides"
	)
	DirAccess.remove_absolute("user://hotel_test.scn")


func test_minimum_height_and_cell_scale_keep_hallway_clear() -> void:
	var spec := {
		"version": 1,
		"height": 2.5,
		"cell_size": 0.75,
		"rooms":
		[
			{"id": "A", "size": [8, 8], "at": [0, 0]},
			{"id": "B", "size": [8, 8], "at": [0, 20]},
		]
	}
	var layout := Layout.compile(spec)
	assert_eq(layout["errors"], [])
	var world := Builder.build(layout)
	add_child_autofree(world)
	await wait_physics_frames(3)
	_sweep(
		world.get_world_3d().direct_space_state,
		Vector3(3.375, 0.94, 3.375),
		Vector3(3.375, 0.94, 18.375)
	)


func _ray(space: PhysicsDirectSpaceState3D, start: Vector3, end: Vector3) -> Dictionary:
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(start, end))


func _sweep(space: PhysicsDirectSpaceState3D, start: Vector3, end: Vector3) -> void:
	var hull := CapsuleShape3D.new()
	hull.height = 1.8288
	hull.radius = 0.4064
	for reverse: bool in [false, true]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = hull
		query.transform.origin = end if reverse else start
		query.motion = start - end if reverse else end - start
		assert_almost_eq(space.cast_motion(query)[0], 1.0, 0.001, "Player clearance")


func test_columns_and_lamp_bowls_have_eight_sides_at_most() -> void:
	var architecture := preload("res://features/world_builder/architecture.gd").new()
	var geometry := Geometry.new()
	geometry.materials = preload("res://features/world_builder/materials.gd").create("hotel")
	architecture._g = geometry
	architecture._column_mesh(Vector3.ZERO, 4.0, 0.5, Basis.IDENTITY, false)
	architecture._bowl(Vector3.ZERO, "glow", [Vector2(0.2, 5), Vector2(0.4, 5.3)])
	var world := Node3D.new()
	geometry.finish(world)
	add_child_autofree(world)
	var angles: Dictionary[int, bool] = {}
	for node: Node in world.get_children():
		var mesh := (node as MeshInstance3D).mesh
		for index: int in mesh.get_surface_count():
			var vertices: PackedVector3Array = mesh.surface_get_arrays(index)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				var angle := fposmod(atan2(vertex.z, vertex.x), TAU)
				angles[roundi(rad_to_deg(angle)) % 360] = true
	assert_eq(angles.size(), 8, "Bases, shafts, capitals and lamp bowls share eight radial edges")
