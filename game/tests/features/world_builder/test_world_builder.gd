extends GutTest

const Layout := preload("res://features/world_builder/layout.gd")
const Builder := preload("res://features/world_builder/mesh_builder.gd")
const EXAMPLE := "res://features/world_builder/examples/annex.json"


func _example() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(EXAMPLE)) as Dictionary


func test_example_is_connected_and_repeatable() -> void:
	var first := Layout.compile(_example())
	var second := Layout.compile(_example())
	assert_eq(first["errors"], [])
	assert_eq(first["cells"], second["cells"])
	assert_eq(first["paths"], second["paths"])
	assert_eq(first["rooms"].size(), 4)


func test_automatic_placement_and_connections_for_many_seeds() -> void:
	var spec := _example()
	spec.erase("connections")
	for room: Dictionary in spec["rooms"]:
		room.erase("at")
	var previous: Dictionary = {}
	for seed_value: int in 20:
		spec["seed"] = seed_value
		var layout := Layout.compile(spec)
		assert_eq(layout["errors"], [], "seed %d" % seed_value)
		assert_eq(layout["paths"].size(), 3)
		assert_ne(layout["rooms"], previous)
		previous = layout["rooms"]


func test_invalid_blueprints_return_errors_without_building() -> void:
	var cases: Array[Dictionary] = [
		{},
		{"version": 1, "rooms": "bad"},
		{"version": 1, "rooms": []},
	]
	for replacement: Dictionary in [
		{"hall_width": "bad"},
		{"hall_width": 4},
		{"height": 1},
		{"seed": 1.2},
		{"cell_size": 0},
		{"ceiling": "yes"},
		{"connections": [["Lobby", "Missing"]]},
		{"connections": [["Lobby", "Lobby"]]},
		{"connections": []},
		{"typo": true},
		{"rooms": [{"id": "bad/name", "size": [10, 10]}]},
		{"rooms": [{"id": "Room", "size": [3.5, 9]}]},
		{"rooms": [{"id": "Room", "size": [999999, 9]}]},
	]:
		var spec := _example()
		spec.merge(replacement, true)
		cases.append(spec)
	for spec: Dictionary in cases:
		assert_false(Layout.compile(spec)["errors"].is_empty(), str(spec))


func test_duplicate_overlapping_and_partly_positioned_rooms_are_rejected() -> void:
	var spec := _example()
	spec["rooms"][1]["id"] = "Lobby"
	assert_false(Layout.compile(spec)["errors"].is_empty())
	spec = _example()
	spec["rooms"][1]["at"] = [3, 3]
	assert_false(Layout.compile(spec)["errors"].is_empty())
	spec = _example()
	spec["rooms"][1].erase("at")
	assert_false(Layout.compile(spec)["errors"].is_empty())


func test_saved_scene_keeps_meshes_collision_materials_and_room_markers() -> void:
	var layout := Layout.compile(_example())
	var world := Builder.build(layout)
	var packed := PackedScene.new()
	assert_eq(packed.pack(world), OK)
	assert_eq(ResourceSaver.save(packed, "user://world_builder_test.scn"), OK)
	world.free()
	var restored := (load("user://world_builder_test.scn") as PackedScene).instantiate() as Node3D
	add_child_autofree(restored)
	assert_eq(restored.get_node("Rooms").get_child_count(), 4)
	assert_null(restored.get_script())
	var triangles := 0
	for child: Node in restored.get_children():
		if child is MeshInstance3D:
			var instance := child as MeshInstance3D
			assert_true(instance.has_node("Solid/Collision"))
			assert_not_null(instance.mesh.surface_get_material(0))
			triangles += instance.mesh.get_faces().size() / 3
	assert_lt(triangles, layout["cells"].size() * 4, "Flat floor/ceiling quads are merged")
	await wait_physics_frames(3)
	_check_routes(restored, layout)
	DirAccess.remove_absolute("user://world_builder_test.scn")


func test_negative_coordinates_and_floor_without_ceiling() -> void:
	var spec := {
		"version": 1, "ceiling": false, "rooms": [{"id": "Only", "size": [8, 8], "at": [-4, -4]}]
	}
	var layout := Layout.compile(spec)
	assert_eq(layout["errors"], [])
	var world := Builder.build(layout)
	add_child_autofree(world)
	await wait_physics_frames(3)
	var space := world.get_world_3d().direct_space_state
	assert_false(
		(
			space
			. intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 1, 0), Vector3(0, -1, 0)))
			. is_empty()
		)
	)
	assert_true(
		(
			space
			. intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 1, 0), Vector3(0, 8, 0)))
			. is_empty()
		)
	)
	assert_false(
		(
			space
			. intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 1, 0), Vector3(-6, 1, 0)))
			. is_empty()
		)
	)


func _check_routes(world: Node3D, layout: Dictionary) -> void:
	var space := world.get_world_3d().direct_space_state
	var hull := CapsuleShape3D.new()
	hull.radius = 0.4064
	hull.height = 1.8288
	for path: Array in layout["paths"]:
		for i: int in 2:
			var start: Vector2i = path[i]
			var end: Vector2i = path[i + 1]
			for reverse: bool in [false, true]:
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = hull
				var a := Vector3(start.x + 0.5, 0.94, start.y + 0.5)
				var b := Vector3(end.x + 0.5, 0.94, end.y + 0.5)
				query.transform.origin = b if reverse else a
				query.motion = a - b if reverse else b - a
				assert_almost_eq(
					space.cast_motion(query)[0], 1.0, 0.001, "Hallway capsule clearance"
				)
	for cell: Vector2i in layout["cells"]:
		var from := Vector3(cell.x + 0.5, 1, cell.y + 0.5)
		var ray := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2)
		assert_false(space.intersect_ray(ray).is_empty(), "Floor at %s" % cell)
		var ceiling := PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 4)
		assert_false(space.intersect_ray(ceiling).is_empty(), "Ceiling at %s" % cell)
