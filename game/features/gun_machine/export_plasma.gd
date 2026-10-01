extends SceneTree
## Re-export the Blockbench mesh after editing its source (centimeters, +Y up, -Z forward).
## Run: godot --headless --path game -s res://features/gun_machine/export_plasma.gd

const SOURCE := "res://assets/gun_machine/models/double_barrel_plasma.bbmodel"
const OUTPUT := "res://assets/gun_machine/models/double_barrel_plasma.glb"


func _initialize() -> void:
	var model: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	var texture_data: Dictionary = model["textures"][0]
	var image := Image.new()
	var encoded: String = texture_data["source"].split(",", true, 1)[1]
	assert(image.load_png_from_buffer(Marshalls.base64_to_raw(encoded)) == OK)
	var palette := ImageTexture.create_from_image(image)
	var mesh := ArrayMesh.new()
	for energy: bool in [false, true]:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for element: Dictionary in model["elements"]:
			assert(element["type"] == "mesh", "Export expects mesh elements")
			assert(_vector(element.get("rotation", [0, 0, 0])).is_zero_approx())
			if str(element["name"]).begins_with("Energy") != energy:
				continue
			var origin := _vector(element["origin"])
			for face: Dictionary in element["faces"].values():
				var keys: Array = face["vertices"]
				# Blockbench uses counterclockwise faces; Godot uses clockwise.
				for index: int in range(1, keys.size() - 1):
					for corner: int in [0, index + 1, index]:
						var key: String = keys[corner]
						var uv: Array = face["uv"][key]
						surface.set_uv(Vector2(float(uv[0]), float(uv[1])) / 64.0)
						surface.set_smooth_group(-1)
						surface.add_vertex((_vector(element["vertices"][key]) + origin) * 0.01)
		var material := StandardMaterial3D.new()
		material.resource_name = "PlasmaEnergy" if energy else "PlasmaArmor"
		material.albedo_texture = palette
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		material.roughness = 0.8
		if energy:
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.emission_enabled = true
			material.emission = Color(0.65, 0.15, 1.0)
			material.emission_energy_multiplier = 1.8
		surface.set_material(material)
		surface.generate_normals()
		surface.index()
		surface.commit(mesh)
	var root := Node3D.new()
	root.name = "DoubleBarrelPlasma"
	var geometry := MeshInstance3D.new()
	geometry.name = "PlasmaMesh"
	geometry.mesh = mesh
	root.add_child(geometry)
	geometry.owner = root
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_scene(root, state) == OK)
	assert(document.write_to_filesystem(state, OUTPUT) == OK)
	root.free()
	quit()


func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
