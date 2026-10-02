extends GutTest

const Model := preload("res://features/procedural_rooms/model_tools/elevator_model.gd")
const CAB := preload("res://features/elevator/models/cab.tscn")
const DOOR := preload("res://features/elevator/models/doors.tscn")
const EXPORT := preload("res://assets/procedural_rooms/models/elevator/elevator.glb")


func test_atlas_reuses_repeated_surfaces_and_has_safe_uvs_and_winding() -> void:
	var data := Model.definition()
	assert_eq(data["islands"].size(), 8)
	assert_gt(data["occupied_fraction"], .65)
	var occupied: Array[Rect2i] = []
	for island: Dictionary in data["islands"]:
		var rect: Rect2i = island["rect"]
		assert_true(Rect2i(0, 0, 128, 128).encloses(rect.grow(2)))
		for other: Rect2i in occupied:
			assert_false(rect.grow(2).intersects(other))
		occupied.append(rect.grow(2))
	var walls := 0
	var doors := 0
	for face: Dictionary in data["faces"]:
		walls += int(face["island"] == "WOOD")
		doors += int(face["island"] == "DOOR")
	assert_eq(walls, 3)
	assert_eq(doors, 2)
	for id: String in ["cab", "frame", "leaf", "button"]:
		var mesh := Model.part(data, id)
		var arrays := mesh.surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for coordinate: Vector2 in arrays[Mesh.ARRAY_TEX_UV]:
			assert_true(Rect2(0, 0, 1, 1).has_point(coordinate))
		for index: int in range(0, indices.size(), 3):
			var a := indices[index]
			var b := indices[index + 1]
			var c := indices[index + 2]
			var normal := -(points[b] - points[a]).cross(points[c] - points[a]).normalized()
			assert_gt(normal.dot(normals[a]), .999, id + " winding")
		var saved := (
			load("res://assets/procedural_rooms/models/elevator/" + id + ".tres") as ArrayMesh
		)
		assert_eq(saved.get_faces().size(), mesh.get_faces().size())


func test_prefabs_preserve_the_three_metre_cab_and_door_collision() -> void:
	var cab := CAB.instantiate() as Node3D
	var visual := cab.get_node("Visual") as MeshInstance3D
	assert_eq(visual.mesh.get_aabb().position, Vector3(-1.5, 0, -1.5))
	assert_lt(visual.mesh.get_aabb().size.distance_to(Vector3(3, 3, 2.78)), .001)
	var material := visual.material_override as StandardMaterial3D
	assert_eq(material.albedo_texture.get_size(), Vector2(128, 128))
	assert_false(material.uv1_triplanar)
	assert_false(material.uv1_world_triplanar)
	assert_eq(material.texture_filter, BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS)
	var door := DOOR.instantiate() as Node3D
	var left := door.get_node("LeftLeaf/Visual") as MeshInstance3D
	var right := door.get_node("RightLeaf/Visual") as MeshInstance3D
	assert_same(left.mesh, right.mesh)
	assert_same(left.material_override, material)
	var collider := door.get_node("LeftLeaf/Collision/Shape") as CollisionShape3D
	assert_eq((collider.shape as BoxShape3D).size, Vector3(1.49, 2.98, .14))
	cab.free()
	door.free()


func test_glb_contains_cab_two_leaves_frame_and_compact_floor_panel() -> void:
	var model := EXPORT.instantiate()
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	assert_eq(meshes.size(), 6)
	for mesh: MeshInstance3D in meshes:
		var material := mesh.get_active_material(0) as StandardMaterial3D
		if material.albedo_texture != null:
			assert_lte(material.albedo_texture.get_width(), 128)
			assert_lte(material.albedo_texture.get_height(), 128)
	assert_not_null(model.find_child("LeftLeaf", true, false))
	assert_not_null(model.find_child("RightLeaf", true, false))
	assert_not_null(model.find_child("ElevatorPanel", true, false))
	model.free()


func test_moving_developer_door_uses_local_projection_without_changing_world_materials() -> void:
	var scene := load("res://features/procedural_rooms/sliding_door.tscn") as PackedScene
	var door := scene.instantiate() as ProceduralSlidingDoor
	add_child(door)
	for leaf: Node3D in door._leaves:
		for mesh: MeshInstance3D in leaf.get_children():
			var material := mesh.material_override as StandardMaterial3D
			assert_false(
				material.uv1_world_triplanar,
				"Moving surface must not swim through world coordinates"
			)
	var world_material := (
		load("res://features/procedural_rooms/materials/grey.tres") as StandardMaterial3D
	)
	assert_true(
		world_material.uv1_world_triplanar,
		"Stationary shell materials retain their seamless world projection"
	)
	door.free()
