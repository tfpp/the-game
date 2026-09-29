extends GutTest

const Layout := preload("res://features/world_builder/layout.gd")
const Builder := preload("res://features/world_builder/mesh_builder.gd")
const Elevation := preload("res://features/world_builder/elevation.gd")
const Geometry := preload("res://features/world_builder/geometry.gd")
const Materials := preload("res://features/world_builder/materials.gd")


class ColumnRecorder:
	extends "res://features/world_builder/architecture.gd"
	var columns: Array[Vector3] = []
	var pilasters: Array[Vector3] = []

	func _column(position: Vector3, _height: float, _width: float) -> void:
		columns.append(position)

	func _pilaster(wall: Dictionary, x: float, _height: float) -> void:
		pilasters.append(wall["a"] + (wall["b"] - wall["a"]).normalized() * x)


func _spec(kind: String = "ramp", end: Array = [0, 32], level: float = 3.0) -> Dictionary:
	return {
		"version": 1,
		"seed": 12,
		"style": {"lights": false},
		"rooms":
		[
			{"id": "Lower", "size": [8, 8], "at": [0, 0]},
			{"id": "Upper", "size": [8, 8], "at": end, "elevation": level}
		],
		"connections": [{"from": "Lower", "to": "Upper", "kind": kind}]
	}


func test_one_column_per_corner_and_no_nearby_wall_end_pilasters() -> void:
	var layout := Layout.compile(
		{"version": 1, "rooms": [{"id": "Only", "size": [8, 8]}], "style": {"lights": false}}
	)
	assert_eq(layout["errors"], [])
	assert_eq(layout["corners"].size(), 4)
	var architecture := ColumnRecorder.new()
	var geometry := Geometry.new()
	geometry.materials = Materials.create("hotel")
	var root := Node3D.new()
	architecture.build(geometry, layout, root)
	assert_eq(architecture.columns.size(), 4)
	for corner: Dictionary in layout["corners"]:
		assert_eq(architecture.columns.count(corner["position"]), 1)
		for position: Vector3 in architecture.pilasters:
			assert_gt(position.distance_to(corner["position"]), 0.6)
	root.free()


func test_inside_and_outside_corner_miters_share_the_same_profile_edge() -> void:
	var layout := Layout.compile(_spec("ramp", [32, 32], 0.0))
	assert_eq(layout["errors"], [])
	var kinds: Array[String] = []
	for corner: Dictionary in layout["corners"]:
		kinds.append(corner["kind"])
		var matches: Array[Dictionary] = []
		for wall: Dictionary in layout["walls"]:
			for end: String in ["a", "b"]:
				if wall[end].is_equal_approx(corner["position"]):
					matches.append({"wall": wall, "end": end})
		assert_eq(matches.size(), 2)
		for depth: float in [0.03, 0.1, 0.2, 0.47]:
			var points: Array[Vector3] = []
			for match_info: Dictionary in matches:
				var wall: Dictionary = match_info["wall"]
				var u: Vector3 = (wall["b"] - wall["a"]).normalized()
				points.append(
					(
						wall[match_info["end"]]
						+ (wall["normal"] + u * wall["join_" + match_info["end"]]) * depth
					)
				)
			assert_almost_eq(points[0].distance_to(points[1]), 0.0, 0.0001)
	assert_has(kinds, "inside")
	assert_has(kinds, "outside")


func test_ramps_are_continuous_deterministic_and_never_above_ten_degrees() -> void:
	for end: Array in [[0, 32], [32, 0], [0, -32], [-32, 0], [32, 32], [-32, -32]]:
		for level: float in [-3.0, 3.0]:
			var spec := _spec("ramp", end, level)
			var layout := Layout.compile(spec)
			assert_eq(layout["errors"], [], str(end))
			assert_eq(layout["floors"], Layout.compile(spec)["floors"])
			assert_eq(layout["flights"].size(), 1)
			assert_lte(layout["flights"][0]["slope_degrees"], 10.0)
			_assert_continuous(layout)
			for room_id: String in layout["rooms"]:
				var rect: Rect2i = layout["rooms"][room_id]
				assert_eq(
					layout["floors"][rect.position],
					Vector3(0, 0, layout["room_elevations"][room_id])
				)
			for point: Vector2i in layout["paths"][0]:
				var plane: Vector3 = layout["floors"][point]
				assert_true(
					Vector2(plane.x, plane.y).is_zero_approx(),
					"Room centers and bend landings are level"
				)


func test_stairs_have_safe_risers_treads_and_slope_in_both_directions() -> void:
	for level: float in [3.0, -3.0]:
		var layout := Layout.compile(_spec("stairs", [0, 18], level))
		assert_eq(layout["errors"], [])
		var flight: Dictionary = layout["flights"][0]
		assert_lte(absf(level) / flight["steps"], 0.18)
		assert_gte(float(flight["length"]) / flight["steps"], 0.22)
		assert_gte(flight["slope_degrees"], 30.0)
		assert_lte(flight["slope_degrees"], 37.0)
		_assert_continuous(layout)


func test_short_runs_invalid_connections_and_bad_elevations_are_rejected() -> void:
	assert_false(Layout.compile(_spec("ramp", [0, 12]))["errors"].is_empty())
	assert_false(Layout.compile(_spec("stairs", [0, 12], 8.0))["errors"].is_empty())
	for value: Variant in ["bad", null, INF, NAN, 65, -65]:
		var spec := _spec()
		spec["rooms"][1]["elevation"] = value
		assert_false(Layout.compile(spec)["errors"].is_empty())
	for value: Variant in [
		null,
		{},
		[],
		["Lower"],
		{"from": "Lower", "to": "Missing"},
		{"from": "Lower", "to": "Upper", "kind": "ladder"},
		{"from": "Lower", "to": "Upper", "max_slope": 11},
		{"from": "Lower", "to": "Upper", "max_slope": 0},
		{"from": "Lower", "to": "Upper", "max_slope": "bad"},
		{"from": "Lower", "to": "Upper", "kind": "stairs", "max_slope": 10}
	]:
		var spec := _spec()
		spec["connections"] = [value]
		assert_false(Layout.compile(spec)["errors"].is_empty(), str(value))
	var gentle := _spec()
	gentle["connections"][0]["max_slope"] = 5
	assert_false(Layout.compile(gentle)["errors"].is_empty(), "Requested lower cap is enforced")


func test_cell_scale_and_legacy_links_support_elevations() -> void:
	for scale: float in [0.75, 2.0, 8.0]:
		var spec := _spec("ramp", [0, 40], 2.0)
		spec["cell_size"] = scale
		spec["connections"] = [["Lower", "Upper"]]
		var layout := Layout.compile(spec)
		assert_eq(layout["errors"], [])
		assert_lte(layout["flights"][0]["slope_degrees"], 10.0)
		_assert_continuous(layout)


func test_conflicting_corridor_crossings_are_rejected() -> void:
	var spec := _spec()
	# A third room interrupts the ramp at the lower elevation.
	spec["rooms"].append({"id": "Crossing", "size": [8, 8], "at": [-16, 16]})
	spec["connections"].append(["Lower", "Crossing"])
	spec["connections"].append(["Crossing", "Upper"])
	assert_false(Layout.compile(spec)["errors"].is_empty())


func test_roofless_scaled_stairs_keep_collision_in_every_sector() -> void:
	var spec := _spec("stairs", [0, 40], 6.0)
	spec["ceiling"] = false
	spec["cell_size"] = 8.0
	spec["style"] = {"theme": "prototype", "lights": false}
	var layout := Layout.compile(spec)
	assert_eq(layout["errors"], [])
	var world := Builder.build(layout)
	add_child_autofree(world)
	await wait_physics_frames(3)
	var space := world.get_world_3d().direct_space_state
	for cell: Vector2i in layout["flight_cells"]:
		var point := (Vector2(cell) + Vector2.ONE * 0.5) * 8.0
		var y := Elevation.floor_at(layout, cell, point)
		var from := Vector3(point.x, y + 0.5, point.y)
		var hit := space.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN)
		)
		assert_false(hit.is_empty(), "Structural stair collision at %s" % cell)
		if not hit.is_empty():
			assert_almost_eq(hit["position"].y, y, 0.001)


func test_stairs_stay_steep_on_long_runs_and_reject_an_incompatible_grid() -> void:
	for end: Array in [[0, 32], [32, 0], [0, -32], [-32, 0], [32, 32]]:
		for level: float in [-1.5, 1.5, 3.0]:
			var layout := Layout.compile(_spec("stairs", end, level))
			assert_eq(layout["errors"], [])
			var flight: Dictionary = layout["flights"][0]
			assert_gte(flight["slope_degrees"], 30.0)
			assert_lte(flight["slope_degrees"], 37.0)
			_assert_continuous(layout)
	assert_false(Layout.compile(_spec("stairs", [0, 32], 1.0))["errors"].is_empty())
	var fine := _spec("stairs", [0, 32], 1.0)
	fine["cell_size"] = 0.75
	assert_eq(Layout.compile(fine)["errors"], [])


func test_saved_raised_rooms_keep_floor_ceiling_openings_and_collision() -> void:
	for kind: String in ["ramp", "stairs"]:
		var spec := _spec(kind, [0, 18] if kind == "stairs" else [0, 32])
		spec["rooms"][1]["openings"] = [
			{"id": "Door", "kind": "door", "side": "south", "offset": 2, "open": true}
		]
		spec["rooms"][1]["pillars"] = [[2, 2]]
		var layout := Layout.compile(spec)
		assert_eq(layout["errors"], [])
		var original := Builder.build(layout)
		var packed := PackedScene.new()
		assert_eq(packed.pack(original), OK)
		var path := "user://elevation_" + kind + ".scn"
		assert_eq(ResourceSaver.save(packed, path), OK)
		original.free()
		var world := (load(path) as PackedScene).instantiate() as Node3D
		add_child_autofree(world)
		await wait_physics_frames(3)
		assert_almost_eq(world.get_node("Rooms/Upper").position.y, 3.0, 0.001)
		assert_almost_eq(world.get_node("Openings/Upper_Door").position.y, 3.0, 0.001)
		assert_almost_eq(layout["pillars"][0]["position"].y, 3.0, 0.001)
		var space := world.get_world_3d().direct_space_state
		for cell: Vector2i in layout["cells"]:
			var center := Vector2(cell) + Vector2.ONE * 0.5
			var y := Elevation.floor_at(layout, cell, center)
			var from := Vector3(center.x, y + 0.5, center.y)
			var hit := space.intersect_ray(
				PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN)
			)
			assert_false(hit.is_empty(), "Floor at %s (%s)" % [cell, kind])
			if not hit.is_empty():
				assert_almost_eq(hit["position"].y, y, 0.002)
			var ceiling := space.intersect_ray(
				PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 4)
			)
			assert_false(ceiling.is_empty(), "Ceiling at %s" % cell)
		await _walk_flight(world, layout["flights"][0])
		world.queue_free()
		await wait_physics_frames(2)
		DirAccess.remove_absolute(path)


func _walk_flight(world: Node3D, flight: Dictionary) -> void:
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.8288
	capsule.radius = 0.4064
	shape.shape = capsule
	body.add_child(shape)
	body.floor_max_angle = acos(0.7)
	body.floor_snap_length = 0.4572
	body.floor_block_on_wall = false
	world.add_child(body)
	var axis: Vector2 = flight["axis"]
	var start: Vector2 = flight["start"]
	var length: float = flight["length"]
	var forward := Vector3(axis.x, 0, axis.y)
	for reverse: bool in [false, true]:
		var point := start + axis * (length + 0.65 if reverse else -0.65)
		body.position = Vector3(
			point.x, (flight["high"] if reverse else flight["low"]) + 0.94, point.y
		)
		body.velocity = Vector3.ZERO
		await wait_physics_frames(2)
		var direction := -forward if reverse else forward
		for frame: int in ceili((length + 1.3) * 64 / 3) + 64:
			body.velocity = direction * 6 + Vector3.DOWN * 5
			body.move_and_slide()
			await wait_physics_frames(1)
			var travelled := Vector2(body.position.x - start.x, body.position.z - start.y).dot(axis)
			if travelled < -0.55 if reverse else travelled > length + 0.55:
				break
		var distance := Vector2(body.position.x - start.x, body.position.z - start.y).dot(axis)
		assert_true(
			distance < 0 if reverse else distance > length,
			"Player traverses %s without jumping" % flight["kind"]
		)
		assert_almost_eq(
			body.position.y - capsule.height / 2, flight["low"] if reverse else flight["high"], 0.06
		)
	body.queue_free()


func _assert_continuous(layout: Dictionary) -> void:
	var scale: float = layout["cell_size"]
	for cell: Vector2i in layout["cells"]:
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var other := cell + direction
			if not layout["cells"].has(other):
				continue
			var a := Vector2(cell + direction) * scale
			var b := a + Vector2(direction.y, direction.x) * scale
			for point: Vector2 in [a, b]:
				assert_almost_eq(
					Elevation.floor_at(layout, cell, point),
					Elevation.floor_at(layout, other, point),
					0.001
				)
