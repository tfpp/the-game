extends GutTest

const MODELS := preload("res://features/holdables/model_tools/loot_models.gd")
const MESH := preload("res://features/procedural_rooms/model_tools/prop_model.gd")
const ALLEY := preload("res://features/slum_alley/feature.tscn")
const EXPORTS := [
	preload("res://assets/slum_alley/models/dumpster/dumpster.glb"),
	preload("res://assets/holdables/models/scrap/scrap.glb"),
	preload("res://assets/holdables/models/wallet/wallet.glb")
]


func test_exported_loot_models_preserve_uvs_positions_and_runtime_texture_size() -> void:
	for index: int in EXPORTS.size():
		var model := EXPORTS[index].instantiate() as Node3D
		var visual := model.get_node("Model") as MeshInstance3D
		var arrays := visual.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var kind: String = ["dumpster", "scrap", "wallet"][index]
		var native := MESH.mesh(MODELS.definition(kind)).surface_get_arrays(0)
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
					break
			assert_true(found, kind + " exported UV association")
		var texture := (visual.get_active_material(0) as StandardMaterial3D).albedo_texture
		assert_eq(texture.get_width(), 128)
		assert_eq(texture.get_height(), 128)
		model.free()


func test_shared_loot_uv_islands_have_padding_complete_coordinates_and_valid_normals() -> void:
	for kind: String in ["dumpster", "scrap", "wallet"]:
		var data := MODELS.definition(kind)
		assert_gte(data["occupied_fraction"], .6)
		var occupied: Array[Rect2i] = []
		for island: Dictionary in data["islands"]:
			var rect: Rect2i = island["rect"]
			assert_true(Rect2i(0, 0, 128, 128).encloses(rect.grow(2)))
			for other: Rect2i in occupied:
				assert_false(rect.grow(2).intersects(other))
			occupied.append(rect.grow(2))
		var arrays := MESH.mesh(data).surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		assert_eq(uv.size(), vertices.size())
		for coordinate: Vector2 in uv:
			assert_between(coordinate.x, 0.0, 1.0)
			assert_between(coordinate.y, 0.0, 1.0)
		for index: int in range(0, indices.size(), 3):
			var a := indices[index]
			var b := indices[index + 1]
			var c := indices[index + 2]
			var normal := -(vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).normalized()
			assert_gt(normal.dot(normals[a]), .999, kind)


func test_catalog_views_keep_grips_prices_and_drop_clearance() -> void:
	for id: String in ["scrap", "stolen_wallet"]:
		var item := ItemCatalog.find(id)
		var view := ItemCatalog.create_view(id)
		assert_not_null(view.get_node_or_null("Grip"))
		var visual := view.get_node("Mesh") as MeshInstance3D
		assert_true(visual.mesh is ArrayMesh)
		assert_gt(visual.mesh.get_faces().size(), 24)
		var texture := (visual.material_override as StandardMaterial3D).albedo_texture
		assert_eq(texture.get_width(), 128)
		assert_eq(texture.get_height(), 128)
		assert_gte(visual.mesh.get_aabb().position.y + item.ground_clearance, 0.0)
		assert_eq(item.sale_value_cents, 100 if id == "scrap" else 300)
		view.free()


func test_alley_uses_new_dumpster_mesh_without_changing_container_paths() -> void:
	var alley := ALLEY.instantiate() as Node3D
	for side: String in ["North", "South", "West", "East"]:
		var root := alley.get_node("District/Dumpster" + side) as StaticBody3D
		assert_not_null(root)
		var model := root.get_node("Model") as MeshInstance3D
		var shape := (root.get_node("Shape") as CollisionShape3D).shape as BoxShape3D
		assert_eq(shape.size, Vector3(2.47, 1.6, 1.46))
		var bounds := model.mesh.get_aabb()
		var lid := model.get_node("Hinge/Lid") as MeshInstance3D
		bounds = bounds.merge((model.get_node("Hinge") as Node3D).transform * lid.mesh.get_aabb())
		assert_lt(bounds.size.distance_to(shape.size), .001)
		assert_almost_eq(
			root.position.y + model.position.y + model.mesh.get_aabb().position.y, 0.0, .001
		)
		var loot := root.get_node("Loot") as LootContainer
		assert_eq(loot.noun, "dumpster")
		assert_true(loot.loot_table.item_ids.has("scrap"))
		assert_true(loot.loot_table.item_ids.has("stolen_wallet"))
	alley.free()
