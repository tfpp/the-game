extends SceneTree
## Convert the reviewed Z-up OBJ sources to native Y-up meshes and collision prefabs.
## Does not generate or overwrite any painted texture.

const SOURCE := "res://../docs/design/model-sources/street-buildings"
const ASSETS := "res://assets/street_district"
const FEATURE := "res://features/street_district"


func _initialize() -> void:
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(SOURCE + "/manifest.json"))
	for entry: Dictionary in rows:
		_build(entry)
	print("STREET_BUILDINGS_IMPORT: 10 native meshes, materials and collision prefabs")
	quit()


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
	if id in ["corner_store", "service_workshop"]:
		var height := 10.0 if id == "corner_store" else 6.0
		_collision(prop, Vector3(.24, height, 14.2), Vector3(-2.88, height / 2, 0))
		_collision(prop, Vector3(.24, height, 14.2), Vector3(2.88, height / 2, 0))
		_collision(prop, Vector3(5.52, height, .24), Vector3(0, height / 2, -6.98))
		for x: float in [-2.25, 2.25]:
			_collision(prop, Vector3(1.5, height, .24), Vector3(x, height / 2, 6.98))
		_collision(prop, Vector3(3, height - 3, .24), Vector3(0, (height + 3) / 2, 6.98))
		_collision(prop, Vector3(6.24, .16, 14.44), Vector3(0, height + .08, 0))
	else:
		var bounds := mesh.get_aabb()
		_collision(prop, bounds.size.max(Vector3.ONE * .004), bounds.get_center())
	var scene := PackedScene.new()
	assert(scene.pack(prop) == OK)
	assert(ResourceSaver.save(scene, FEATURE + "/props/" + id + ".tscn") == OK)
	prop.free()


func _collision(prop: StaticBody3D, size: Vector3, at: Vector3) -> void:
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	collider.position = at
	prop.add_child(collider)
	collider.owner = prop
