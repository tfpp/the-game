extends GutTest

const PROP := preload("res://features/procedural_rooms/model_tools/prop_model.gd")
const SCENES := [
	preload("res://features/procedural_rooms/props/crate.tscn"),
	preload("res://features/procedural_rooms/props/barrel.tscn"),
	preload("res://features/procedural_rooms/props/car.tscn")
]
const SHOWCASE := preload("res://features/procedural_rooms/showcase.gd")


func test_polygon_unwrap_has_safe_shared_islands_and_outward_triangles() -> void:
	for kind: String in ["crate", "barrel", "car", "wheel"]:
		var data := PROP.definition(kind)
		var occupied: Array[Rect2i] = []
		for face: Dictionary in data["islands"]:
			var rect: Rect2i = face["rect"]
			assert_true(Rect2i(0, 0, 128, 128).encloses(rect.grow(2)), kind)
			for other: Rect2i in occupied:
				assert_false(rect.grow(2).intersects(other), kind)
			occupied.append(rect.grow(2))
		for face: Dictionary in data["faces"]:
			var points: PackedVector3Array = face["points"]
			var projected: PackedVector2Array = face["uv_m"]
			for index: int in points.size():
				var next := (index + 1) % points.size()
				assert_almost_eq(
					points[index].distance_to(points[next]),
					projected[index].distance_to(projected[next]),
					.0001,
					kind + " undistorted UV edge"
				)
		var mesh := PROP.mesh(data)
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index: int in range(0, indices.size(), 3):
			var a := indices[index]
			var b := indices[index + 1]
			var c := indices[index + 2]
			var normal := -(vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).normalized()
			assert_gt(normal.dot(normals[a]), .999, kind + " outward clockwise triangle")
		var center := mesh.get_aabb().get_center()
		for index: int in vertices.size():
			assert_gt((vertices[index] - center).dot(normals[index]), 0.0, kind + " external face")


func test_prefabs_have_floor_pivots_correct_sizes_and_fitted_colliders() -> void:
	var bounds := [Vector3(1, 1, 1), Vector3(.86, 1.2, .86), Vector3(1.74, 1.45, 4)]
	for index: int in SCENES.size():
		var model := SCENES[index].instantiate() as Node3D
		var merged := AABB()
		var first := true
		for visual: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var box := visual.transform * visual.mesh.get_aabb()
			merged = box if first else merged.merge(box)
			first = false
			assert_eq(
				(visual.material_override as StandardMaterial3D).albedo_texture.get_width(), 128
			)
		assert_almost_eq(merged.position.y, 0.0, .0001)
		assert_lt(merged.size.distance_to(bounds[index]), .001)
		assert_gt(model.find_children("*", "CollisionShape3D", true, false).size(), 0)
		model.free()


func test_room_sets_instantiate_prefabs_and_keep_the_central_lane_clear() -> void:
	for kind: String in ["garage", "storage", "pump"]:
		var room := Node3D.new()
		SHOWCASE.set_piece(room, kind)
		var props := room.get_node("SetPieces")
		var count := 0
		for prop: Node3D in props.get_children():
			if prop.scene_file_path.is_empty():
				continue
			count += 1
			for visual: MeshInstance3D in prop.find_children("*", "MeshInstance3D", true, false):
				var bounds := prop.transform * visual.transform * visual.mesh.get_aabb()
				assert_true(bounds.end.x <= -1.5 or bounds.position.x >= 1.5, kind)
		assert_gt(count, 0, kind + " uses reusable prefab instances")
		room.free()


func test_exported_glbs_include_all_parts_and_preserve_uv_associations() -> void:
	var exports: Array[PackedScene] = [
		preload("res://assets/procedural_rooms/models/crate/crate.glb"),
		preload("res://assets/procedural_rooms/models/barrel/barrel.glb"),
		preload("res://assets/procedural_rooms/models/car/car.glb")
	]
	var kinds: Array[String] = ["crate", "barrel", "car"]
	for index: int in exports.size():
		var model := exports[index].instantiate() as Node3D
		var meshes := model.find_children("*", "MeshInstance3D", true, false)
		assert_eq(meshes.size(), 5 if kinds[index] == "car" else 1)
		var arrays := (model.get_node("Visual") as MeshInstance3D).mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var native := PROP.mesh(PROP.definition(kinds[index])).surface_get_arrays(0)
		var expected: PackedVector2Array = native[Mesh.ARRAY_TEX_UV]
		var positions: PackedVector3Array = native[Mesh.ARRAY_VERTEX]
		for corner: int in expected.size():
			var found := false
			for exported: int in uv.size():
				if (
					expected[corner].distance_to(uv[exported]) * 128 < .01
					and positions[corner].distance_to(vertices[exported]) < .001
				):
					found = true
			assert_true(found, kinds[index] + " exported UV association")
		model.free()


func test_repeated_surfaces_share_islands_and_raise_visible_texture_quality() -> void:
	var crate := PROP.definition("crate")
	var barrel := PROP.definition("barrel")
	var car := PROP.definition("car")
	var wheel := PROP.definition("wheel")
	assert_eq(crate["islands"].size(), 1)
	assert_eq(barrel["islands"].size(), 2)
	assert_eq(car["islands"].size(), 10, "Includes the shared hub and tread in the body atlas")
	assert_eq(wheel["islands"], car["islands"], "Same master atlas for wheel and body")
	assert_gte(crate["occupied_fraction"], .9)
	assert_gte(barrel["occupied_fraction"], .6)
	assert_gte(car["occupied_fraction"], .6)
	assert_gte(crate["density"], 120.0)
	assert_gte(barrel["density"], 100.0)
	assert_gte(car["density"], 28.0)
	var sides: Array[Dictionary] = []
	for face: Dictionary in barrel["faces"]:
		if face["island"] == "DRUM_SIDE":
			sides.append(face)
	assert_eq(sides.size(), 8)
	for face: Dictionary in sides:
		assert_eq(face["rect"], sides[0]["rect"])
	for face: Dictionary in car["faces"]:
		if face["name"] == "BODY_RIGHT":
			assert_true(face["flip_x"], "Shared side artwork keeps front and rear aligned")
		if face["name"] == "BODY_0":
			assert_eq(face["weight"], .2, "Underside gets a smaller texture budget")
	for scene: PackedScene in SCENES:
		var model := scene.instantiate() as Node3D
		if model.name == &"Car":
			var body_material := (model.get_node("Visual") as MeshInstance3D).material_override
			for visual: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				assert_same(
					visual.material_override,
					body_material,
					"All wheels share body atlas and material"
				)
		model.free()
