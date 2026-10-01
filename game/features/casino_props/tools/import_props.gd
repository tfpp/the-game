extends SceneTree
## Convert the reviewed Z-up OBJ sources to native Y-up meshes and collision prefabs.
## Does not generate or overwrite any painted texture.

const SOURCE := "res://../docs/design/model-sources/casino-props"
const ASSETS := "res://assets/casino_props"
const FEATURE := "res://features/casino_props"


func _initialize() -> void:
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(SOURCE + "/manifest.json"))
	for entry: Dictionary in rows:
		_build(entry)
	_build_showcase(rows)
	print("CASINO_PROPS_IMPORT: 50 native meshes, materials and collision prefabs")
	quit()


func _build_showcase(rows: Array) -> void:
	var showcase := Node3D.new()
	showcase.name = "CasinoPropsShowcase"
	for index: int in range(rows.size()):
		var id := str(rows[index]["name"])
		var packed := load(FEATURE + "/props/" + id + ".tscn") as PackedScene
		var prop := packed.instantiate() as StaticBody3D
		showcase.add_child(prop)
		prop.owner = showcase
		prop.position = Vector3((index % 10) * 3.0, 0, (index / 10) * 3.0)
	var scene := PackedScene.new()
	assert(scene.pack(showcase) == OK)
	assert(ResourceSaver.save(scene, FEATURE + "/showcase.tscn") == OK)
	showcase.free()


func _build(entry: Dictionary) -> void:
	var id := str(entry["name"])
	var positions := PackedVector3Array()
	var uvs := PackedVector2Array()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var mapped := PackedVector2Array()
	var text := FileAccess.get_file_as_string(SOURCE + "/models/" + id + ".obj")
	for line: String in text.split("\n"):
		var fields := line.split(" ", false)
		if fields.is_empty():
			continue
		match fields[0]:
			"v":
				positions.append(Vector3(float(fields[1]), float(fields[3]), -float(fields[2])))
			"vt":
				uvs.append(Vector2(float(fields[1]), 1.0 - float(fields[2])))
			"f":
				assert(fields.size() == 4, "Source must be triangulated")
				var corners := PackedInt32Array()
				var texels := PackedInt32Array()
				for field: String in fields.slice(1):
					var pair := field.split("/")
					corners.append(int(pair[0]) - 1)
					texels.append(int(pair[1]) - 1)
				var normal := (
					(positions[corners[1]] - positions[corners[0]])
					. cross(positions[corners[2]] - positions[corners[0]])
					. normalized()
				)
				assert(normal.length_squared() > 0.9, id + " has a degenerate face")
				# Godot fronts use clockwise winding; retain the authored outward normal.
				for index: int in [0, 2, 1]:
					vertices.append(positions[corners[index]])
					normals.append(normal)
					mapped.append(uvs[texels[index]])
	assert(vertices.size() == int(entry["triangles"]) * 3)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = mapped
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	assert(ResourceSaver.save(mesh, ASSETS + "/models/" + id + ".res") == OK)
	mesh.take_over_path(ASSETS + "/models/" + id + ".res")
	var texture := load(ASSETS + "/textures/" + id + ".png") as Texture2D
	assert(texture != null and texture.get_width() == int(entry["texture_size"]))
	assert(texture.get_width() <= 128 and texture.get_height() == texture.get_width())
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.texture_repeat = false
	material.roughness = 1.0
	material.metallic_specular = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	assert(ResourceSaver.save(material, FEATURE + "/materials/" + id + ".tres") == OK)
	material.take_over_path(FEATURE + "/materials/" + id + ".tres")
	var prop := StaticBody3D.new()
	prop.name = id.to_pascal_case()
	prop.set_meta("prop_id", id)
	var visual := MeshInstance3D.new()
	visual.name = "Model"
	visual.mesh = mesh
	visual.material_override = material
	prop.add_child(visual)
	visual.owner = prop
	var collider := CollisionShape3D.new()
	collider.name = "Collider"
	var shape := BoxShape3D.new()
	var bounds := mesh.get_aabb()
	shape.size = bounds.size.max(Vector3.ONE * 0.004)
	collider.shape = shape
	collider.position = bounds.get_center()
	prop.add_child(collider)
	collider.owner = prop
	var scene := PackedScene.new()
	assert(scene.pack(prop) == OK)
	assert(ResourceSaver.save(scene, FEATURE + "/props/" + id + ".tscn") == OK)
	prop.free()
