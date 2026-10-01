extends SceneTree
## Rebuild the uploaded indexed mesh sources using Godot only. Painting is preserved.

const SOURCE := "res://../docs/design/model-sources/casino-codex-bundle"
const ASSETS := "res://assets/casino_props/bundle"
const FEATURE := "res://features/casino_props"
const BATCHES: Array[String] = [
	"casino-assets", "bin-assets", "casino-props", "casino-props-02", "casino-props-03"
]

var _textures: Dictionary[String, Texture2D] = {}


func _initialize() -> void:
	var showcase := Node3D.new()
	showcase.name = "BundleShowcase"
	var manifest: Array[Dictionary] = []
	for batch: String in BATCHES:
		var rows: Array = JSON.parse_string(
			FileAccess.get_file_as_string(SOURCE + "/" + batch + "/meshes.json")
		)
		for row: Dictionary in rows:
			var prop := _build(row, batch, manifest)
			showcase.add_child(prop)
			prop.owner = showcase
			var index := showcase.get_child_count() - 1
			prop.position = Vector3((index % 5) * 2.5, 0, (index / 5) * 2.5)
	var packed := PackedScene.new()
	assert(packed.pack(showcase) == OK)
	assert(ResourceSaver.save(packed, FEATURE + "/bundle_showcase.tscn") == OK)
	showcase.free()
	var output := FileAccess.open(SOURCE + "/runtime-manifest.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(manifest, "\t") + "\n")
	print("CASINO_BUNDLE_IMPORT: %d indexed props, native textures and prefabs" % manifest.size())
	quit()


func _build(row: Dictionary, batch: String, manifest: Array[Dictionary]) -> Node3D:
	var id := str(row["name"])
	var arrays := mesh_arrays(row)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mesh_path := ASSETS + "/models/" + id + ".res"
	assert(ResourceSaver.save(mesh, mesh_path) == OK)
	mesh.take_over_path(mesh_path)
	var texture_name := str(row.get("texture", "casino-atlas-256.png"))
	var texture := _texture(batch, texture_name)
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.texture_repeat = false
	material.roughness = 0.9
	material.metallic_specular = 0.2
	if row.get("emission") != null:
		material.emission_enabled = true
		material.emission = Color.WHITE
		material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		material.emission_texture = _texture(batch, str(row["emission"]))
	var material_path := FEATURE + "/materials/bundle/" + id + ".tres"
	assert(ResourceSaver.save(material, material_path) == OK)
	material.take_over_path(material_path)
	var prop := StaticBody3D.new()
	prop.name = id.to_pascal_case()
	prop.set_meta("prop_id", id)
	var visual := MeshInstance3D.new()
	visual.name = "Model"
	visual.mesh = mesh
	visual.material_override = material
	prop.add_child(visual)
	visual.owner = prop
	# A broad collider is for placement, not a detailed simulation of hollow props.
	var bounds := mesh.get_aabb()
	var collider := CollisionShape3D.new()
	collider.name = "Collider"
	var shape := BoxShape3D.new()
	shape.size = bounds.size.max(Vector3.ONE * 0.004)
	collider.shape = shape
	collider.position = bounds.get_center()
	prop.add_child(collider)
	collider.owner = prop
	var scene := PackedScene.new()
	assert(scene.pack(prop) == OK)
	var scene_path := FEATURE + "/props/bundle/" + id + ".tscn"
	assert(ResourceSaver.save(scene, scene_path) == OK)
	scene.take_over_path(scene_path)
	(
		manifest
		. append(
			{
				"name": id,
				"source": batch + "/meshes.json",
				"triangles": int(row["triangles"]),
				"vertices": int(row["vertices"]),
				"texture_size": texture.get_width(),
				"source_texture": batch + "/" + texture_name,
				"scene": scene_path,
				"bounds": [var_to_str(bounds.position), var_to_str(bounds.size)],
			}
		)
	)
	prop.free()
	return scene.instantiate() as Node3D


func _texture(batch: String, filename: String) -> Texture2D:
	var output := ASSETS + "/textures/" + batch + "-" + filename
	if _textures.has(output):
		return _textures[output]
	var image := Image.load_from_file(
		ProjectSettings.globalize_path(SOURCE + "/" + batch + "/" + filename)
	)
	assert(image != null and not image.is_empty())
	if image.get_width() > 128 or image.get_height() > 128:
		image.resize(128, 128, Image.INTERPOLATE_LANCZOS)
	# Normal rebuilds reuse the approved paint, including any later runtime edits.
	if not FileAccess.file_exists(output):
		assert(image.save_png(output) == OK)
	var runtime := Image.load_from_file(ProjectSettings.globalize_path(output))
	assert(runtime.get_width() <= 128 and runtime.get_height() <= 128)
	assert(runtime.get_width() == runtime.get_height())
	runtime.generate_mipmaps()
	var texture := ImageTexture.create_from_image(runtime)
	texture.take_over_path(output)
	_textures[output] = texture
	return texture


static func mesh_arrays(row: Dictionary) -> Array:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array(row["indices"])
	for value: Array in row["positions"]:
		var point := Vector3(value[0], value[1], value[2])
		assert(point.is_finite())
		positions.append(point)
	for value: Array in row["normals"]:
		var normal := Vector3(value[0], value[1], value[2])
		assert(normal.is_finite() and absf(normal.length() - 1.0) < 0.001)
		normals.append(normal)
	for value: Array in row["uvs"]:
		var uv := Vector2(value[0], value[1])
		assert(uv.is_finite() and uv.x >= 0 and uv.x <= 1 and uv.y >= 0 and uv.y <= 1)
		uvs.append(uv)
	assert(positions.size() == int(row["vertices"]))
	assert(normals.size() == positions.size() and uvs.size() == positions.size())
	assert(indices.size() == int(row["triangles"]) * 3)
	for index: int in indices:
		assert(index >= 0 and index < positions.size())
	for offset: int in range(0, indices.size(), 3):
		var a := indices[offset]
		var b := indices[offset + 1]
		var c := indices[offset + 2]
		var cross := (positions[b] - positions[a]).cross(positions[c] - positions[a])
		assert(cross.length_squared() > 1e-16)
		assert(cross.dot(normals[a] + normals[b] + normals[c]) > 0)
		# The source uses glTF's CCW winding; Godot's native front is clockwise.
		indices[offset + 1] = c
		indices[offset + 2] = b
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
