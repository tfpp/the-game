extends GutTest

const Layout := preload("res://features/world_builder/layout.gd")
const Sewer := preload("res://features/sewer_kit/kit.gd")
const Feature := preload("res://features/hotel_annex/feature.tscn")


func test_three_hotels_select_distinct_kits_and_plain_service_rooms() -> void:
	for id: String in ["hotel", "modern", "deco"]:
		var spec: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://features/hotel_annex/%s.json" % id)
		)
		var layout := Layout.compile(spec)
		assert_eq(layout["errors"], [])
		assert_eq(layout["room_kits"]["StorageRoom"], "concrete")
		assert_eq(
			layout["room_kits"]["GrandLounge" if id == "hotel" else "Lobby"],
			"classic" if id == "hotel" else id
		)
		var count := 0
		for wall: Dictionary in layout["walls"]:
			var midpoint: Vector3 = (wall["a"] + wall["b"]) / 2 + wall["normal"] * 0.01
			if Rect2(-20, -10, 12, 14).has_point(Vector2(midpoint.x, midpoint.z)):
				assert_eq(wall["kit"], "concrete", "Every storage wall uses service materials")
				count += 1
		assert_gt(count, 3)
		var scene := load("res://features/hotel_annex/%s.scn" % id) as PackedScene
		var root := scene.instantiate()
		for mesh: MeshInstance3D in root.find_children("Chunk*", "MeshInstance3D", true, false):
			for surface: int in mesh.mesh.get_surface_count():
				var material := mesh.mesh.surface_get_material(surface)
				if (
					material.resource_name
					not in ["Cream damask", "Panelled walnut", "Carved limestone", "Antique brass"]
				):
					continue
				var points: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[
					Mesh.ARRAY_VERTEX
				]
				var decorated_storage := false
				for point: Vector3 in points:
					if (
						point.y > 0.2
						and point.y < 3.51
						and Rect2(-20.01, -10.01, 12.02, 14.0).has_point(Vector2(point.x, point.z))
					):
						decorated_storage = true
						break
				assert_false(decorated_storage, "Storage contains no hotel trim or wallpaper")
		root.free()


func test_sewer_network_branches_loops_and_reaches_all_three_access_shafts() -> void:
	var cells := Sewer.district_cells()
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	var seen: Array[Vector2i] = []
	var junctions := 0
	var edges := 0
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		if cell in seen:
			continue
		seen.append(cell)
		var exits := 0
		for direction: Vector2i in Sewer.DIRECTIONS:
			if cell + direction in cells:
				queue.append(cell + direction)
				exits += 1
		edges += exits
		if exits > 2:
			junctions += 1
	assert_eq(seen.size(), cells.size())
	assert_has(seen, Vector2i(-14, 0))
	assert_has(seen, Vector2i(14, 0))
	assert_gt(junctions, 2)
	assert_gte(edges / 2, cells.size(), "At least one alternate loop, not just a tree")


func test_saved_sewer_junctions_and_three_ladder_routes_are_walkable() -> void:
	var feature := Feature.instantiate() as Node3D
	add_child_autofree(feature)
	var hotel := feature.get_node("Hotel") as StreamedRoom
	hotel.load_room(10000)
	for name: String in ["SewerDoor", "ModernSewerDoor", "DecoSewerDoor"]:
		(hotel.get_node(name) as SwingDoor).net_state = SwingDoor.State.OPEN_IN
	for name: String in ["ModernDoors", "DecoDoors"]:
		for door: SwingDoor in hotel.get_node(name).get_children():
			door.net_state = SwingDoor.State.OPEN_IN
	await wait_seconds(0.5)
	var space := hotel.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var hull := CapsuleShape3D.new()
	hull.radius = 0.4064
	hull.height = 1.8288
	query.shape = hull
	var sewer := hotel.get_node("Content/ServiceArea/Sewer") as Node3D
	var cells := Sewer.district_cells()
	for cell: Vector2i in cells:
		var at := Vector3(cell.x * 6, 1, cell.y * 6)
		query.transform = Transform3D(Basis.IDENTITY, sewer.to_global(at))
		query.motion = Vector3.ZERO
		assert_true(space.intersect_shape(query).is_empty(), "Clear module center")
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			if cell + direction in cells:
				query.motion = Vector3(direction.x * 6, 0, direction.y * 6)
				assert_almost_eq(
					space.cast_motion(query)[0], 1.0, 0.001, "Clear connected sewer ports"
				)
	for name: String in ["SewerLadder", "ModernLadder", "DecoLadder"]:
		var ladder := hotel.get_node(name) as ClimbableLadder
		var points: Array[Vector3] = [
			ladder.top_landing, Vector3(0, 1, 0), Vector3(0, -5, 0), ladder.bottom_landing
		]
		for index: int in points.size() - 1:
			query.transform = Transform3D(Basis.IDENTITY, ladder.to_global(points[index]))
			query.motion = points[index + 1] - points[index]
			assert_almost_eq(space.cast_motion(query)[0], 1.0, 0.001, "Clear shaft " + name)
		assert_true(hotel.contains(ladder.to_global(ladder.bottom_landing)))
		assert_true(hotel.contains(ladder.to_global(ladder.top_landing)))
	for kit: String in ["modern", "deco"]:
		var spec: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://features/hotel_annex/%s.json" % kit)
		)
		var layout := Layout.compile(spec)
		var wing := hotel.get_node("Content/" + kit.capitalize() + "Hotel") as Node3D
		for path: Array in layout["paths"]:
			for segment: int in 2:
				var start: Vector2 = Vector2(path[segment]) + Vector2.ONE * 0.5
				var finish: Vector2 = Vector2(path[segment + 1]) + Vector2.ONE * 0.5
				query.transform = Transform3D(
					Basis.IDENTITY, wing.to_global(Vector3(start.x, 1.05, start.y))
				)
				query.motion = Vector3(finish.x - start.x, 0, finish.y - start.y)
				assert_almost_eq(
					space.cast_motion(query)[0], 1.0, 0.001, "Walkable " + kit + " hotel connection"
				)
