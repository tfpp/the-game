extends GutTest

const Radar := preload("res://features/radar/radar.gd")
const Geometry := preload("res://features/radar/radar_geometry.gd")


func test_desktop_only_even_with_a_mobile_keyboard_or_gamepad() -> void:
	assert_true(Radar.desktop_visible(false, false, false))
	assert_false(Radar.desktop_visible(true, false, false))
	assert_false(Radar.desktop_visible(false, true, false))
	assert_false(Radar.desktop_visible(false, false, true))


func test_cpu_box_faces_preserve_floor_and_wall_slice() -> void:
	var old := Geometry.new()
	var box := BoxMesh.new()
	box.size = Vector3(8, 4, 6)
	var placement := Transform3D(Basis(Vector3.UP, .7), Vector3(9, 1, -4))
	old.append_mesh(box, placement, 2.0)
	var current := Geometry.new()
	current.append_faces(Geometry.box_faces(box.size), placement, 2.0)
	assert_eq(current.floors.size(), old.floors.size())
	assert_eq(current.walls.size(), old.walls.size())
	for point: Vector2 in current.walls:
		assert_true(old.walls.has(point), "CPU box has the same transformed wall intersections")


func test_large_collision_is_sliced_across_frames_and_unloading_discards_partial_work() -> void:
	var faces := PackedVector3Array()
	for i: int in 1000:
		faces.append_array(Geometry.box_faces(Vector3(2, 4, 2)))
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	var radar := Radar.new()
	autofree(radar)
	radar._build_height = 1.0
	radar._building = Geometry.new()
	radar._pending = [collider]
	radar._build_step()
	assert_eq(radar._pending.size(), 1, "One large root cannot monopolize a whole frame")
	assert_gt(radar._slice_offset, 0)
	assert_lte(radar._slice_offset, Radar.TRIANGLES_PER_FRAME)
	assert_true(radar._building.walls.is_empty(), "Partial root stays private until complete")
	body.free()
	radar._build_step()
	assert_true(radar._geometry.walls.is_empty(), "Unloaded partial roots are not published")
	assert_true(radar._slice_faces.is_empty(), "Release the pending collision snapshot")


func test_chunked_slicing_matches_uninterrupted_geometry() -> void:
	var faces := PackedVector3Array()
	for i: int in 500:
		faces.append_array(Geometry.box_faces(Vector3(2, 4, 2)))
	var whole := Geometry.new()
	whole.append_faces(faces, Transform3D.IDENTITY, 1.0)
	var split := Geometry.new()
	for first: int in range(0, faces.size() / 3, Radar.SLICE_CHUNK):
		split.append_faces(faces, Transform3D.IDENTITY, 1.0, first, Radar.SLICE_CHUNK)
	assert_eq(split.walls, whole.walls)
	assert_eq(split.floors, whole.floors)


func test_csg_collision_slice_preserves_subtracted_openings() -> void:
	var root := CSGBox3D.new()
	root.size = Vector3(8, 4, 6)
	root.use_collision = true
	var opening := CSGBox3D.new()
	opening.size = Vector3(2, 6, 8)
	opening.operation = CSGShape3D.OPERATION_SUBTRACTION
	root.add_child(opening)
	add_child_autofree(root)
	await wait_physics_frames(2)
	var old := Geometry.new()
	var meshes := root.get_meshes()
	old.append_mesh(meshes[1], Transform3D.IDENTITY, 1.0)
	var current := Geometry.new()
	current.append_faces(Radar._collision_faces(root), Transform3D.IDENTITY, 1.0)
	assert_eq(current.walls.size(), old.walls.size())
	assert_eq(current.floors.size(), old.floors.size())
	for point: Vector2 in current.walls:
		assert_true(old.walls.has(point), "Collision slicing preserves the CSG doorway")


func test_slice_shows_walls_and_floor_but_omits_roof_and_other_storeys() -> void:
	var geometry := Geometry.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(8, 1, 8)
	geometry.append_mesh(floor_box, Transform3D(Basis.IDENTITY, Vector3(0, -0.5, 0)), 1.0)
	assert_eq(geometry.floors.size(), 6, "Only the two upward floor triangles")
	assert_eq(geometry.walls.size(), 0)
	geometry.append_mesh(floor_box, Transform3D(Basis.IDENTITY, Vector3(0, 5, 0)), 1.0)
	geometry.append_mesh(floor_box, Transform3D(Basis.IDENTITY, Vector3(0, -6, 0)), 1.0)
	assert_eq(geometry.floors.size(), 6, "Ceiling and lower storey do not cover the map")
	var wall := BoxMesh.new()
	wall.size = Vector3(1, 4, 8)
	geometry.append_mesh(wall, Transform3D(Basis.IDENTITY, Vector3(4, 2, 0)), 1.0)
	assert_eq(geometry.walls.size(), 16, "All four wall sides are sliced")
	assert_eq(geometry.floor_mesh().get_surface_count(), 1)


func test_world_projection_is_north_up_and_player_centered() -> void:
	var radar := Radar.new()
	radar.size = Vector2(228, 228)
	radar._center = Vector2(10, 20)
	assert_eq(radar.map_point(Vector3(10, 1, 20)), Vector2(114, 114))
	assert_eq(radar.map_point(Vector3(10, 1, 10)), Vector2(114, 84))
	assert_eq(radar.map_point(Vector3(20, 1, 20)), Vector2(144, 114))
	radar.free()


func test_salon_boxes_include_gallery_and_furniture_but_exclude_ceiling() -> void:
	var salon := preload("res://features/casino_hub/salon.tscn").instantiate()
	add_child_autofree(salon)
	var radar := Radar.new()
	radar._height = 4.0
	var roots: Array[Node3D] = []
	radar._collect(salon, roots)
	assert_has(roots, salon.get_node("GalleryFloorBody/Shape"))
	assert_does_not_have(roots, salon.get_node("CofferedCeilingBody/Shape"))
	radar._pending = roots.duplicate()
	radar._build_height = 4.0
	radar._building = Geometry.new()
	while not radar._pending.is_empty():
		radar._build_step()
	assert_gt(radar._geometry.floors.size(), 0, "Gallery floor appears at its own storey")
	radar._height = -0.5
	roots.clear()
	radar._collect(salon, roots)
	assert_has(roots, salon.get_node("TableBody0/Shape"))
	assert_does_not_have(roots, salon.get_node("GalleryFloorBody/Shape"))
	radar.free()


func test_saved_generated_scene_maps_rooms_halls_and_rotated_placement() -> void:
	var Layout := preload("res://features/world_builder/layout.gd")
	var Builder := preload("res://features/world_builder/mesh_builder.gd")
	var spec: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://features/world_builder/examples/annex.json")
	)
	var layout: Dictionary = Layout.compile(spec)
	var world: Node3D = Builder.build(layout)
	var packed := PackedScene.new()
	assert_eq(packed.pack(world), OK)
	world.free()
	var restored := packed.instantiate() as Node3D
	restored.position = Vector3(80, 5, -1400)
	restored.rotation.y = PI / 2.0
	add_child_autofree(restored)
	var radar := Radar.new()
	radar._height = 6.0
	radar._center = Vector2(80, -1400)
	var roots: Array[Node3D] = []
	radar._collect(restored, roots)
	assert_gt(roots.size(), 0, "Persistent collision group survives packing")
	for root: Node3D in roots:
		assert_true(root is CollisionShape3D, "No decorative render meshes")
	radar._pending = roots.duplicate()
	radar._build_height = 6.0
	radar._building = Geometry.new()
	while not radar._pending.is_empty():
		radar._build_step()
	assert_gt(radar._geometry.walls.size(), 0)
	var floors := radar._geometry.floors
	var area := 0.0
	for index: int in range(0, floors.size(), 3):
		area += (
			absf((floors[index + 1] - floors[index]).cross(floors[index + 2] - floors[index])) / 2
		)
	var cell_size: float = layout["cell_size"]
	assert_almost_eq(area, layout["cells"].size() * cell_size * cell_size, 0.02)
	for cell: Vector2i in layout["cells"]:
		var point := restored.to_global(Vector3(cell.x + 0.43, 0, cell.y + 0.61) * cell_size)
		assert_true(_floor_contains(floors, Vector2(point.x, point.z)), "Room/hall cell %s" % cell)
	radar._height = 20.0
	roots.clear()
	radar._collect(restored, roots)
	assert_true(roots.is_empty(), "A different storey does not map this floor")
	radar.free()


func test_unmarked_or_disabled_mesh_collision_is_not_mapped() -> void:
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(BoxMesh.new().get_faces())
	collider.shape = shape
	body.add_child(collider)
	add_child_autofree(body)
	var radar := Radar.new()
	radar._height = 0.25
	var roots: Array[Node3D] = []
	radar._collect(body, roots)
	assert_true(roots.is_empty())
	collider.add_to_group(&"radar_geometry")
	radar._collect(body, roots)
	assert_eq(roots.size(), 1)
	roots.clear()
	collider.disabled = true
	radar._collect(body, roots)
	assert_true(roots.is_empty())
	radar.free()


func _floor_contains(floors: PackedVector2Array, point: Vector2) -> bool:
	for index: int in range(0, floors.size(), 3):
		if Geometry2D.point_is_inside_triangle(
			point, floors[index], floors[index + 1], floors[index + 2]
		):
			return true
	return false
