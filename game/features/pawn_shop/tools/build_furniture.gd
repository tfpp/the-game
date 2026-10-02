extends SceneTree
## Mesh-first furniture. Reuses indexed primitive topology; merges the fitted parts.

const AUTHORING := "res://../docs/design/model-sources/pawn-shop/"
const ASSETS := "res://assets/pawn_shop/"
const CHARTS: Array[Rect2i] = [
	Rect2i(2, 2, 28, 28), Rect2i(34, 2, 28, 28), Rect2i(2, 34, 28, 28), Rect2i(34, 34, 28, 28)
]
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()


func _initialize() -> void:
	var guide := Image.create(64, 64, false, Image.FORMAT_RGB8)
	guide.fill(Color("333333"))
	var colors: Array[Color] = [Color("98683b"), Color("b0b8ab"), Color("32473d"), Color("bd9b55")]
	for index: int in CHARTS.size():
		guide.fill_rect(CHARTS[index], colors[index])
	guide.resize(512, 512, Image.INTERPOLATE_NEAREST)
	assert(guide.save_png(ProjectSettings.globalize_path(AUTHORING + "uv_template.png")) == OK)
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var source := Image.load_from_file(args[0])
		assert(source != null)
		source.resize(64, 64, Image.INTERPOLATE_LANCZOS)
		var painted := Image.create(64, 64, false, Image.FORMAT_RGB8)
		for chart: Rect2i in CHARTS:
			for x: int in range(chart.position.x - 2, chart.end.x + 2):
				for y: int in range(chart.position.y - 2, chart.end.y + 2):
					painted.set_pixel(
						x,
						y,
						source.get_pixel(
							clampi(x, chart.position.x, chart.end.x - 1),
							clampi(y, chart.position.y, chart.end.y - 1)
						)
					)
		assert(
			painted.save_png(ProjectSettings.globalize_path(ASSETS + "shop_furniture.png")) == OK
		)
	# Counter: 2.8 x 1.15 x .8, floor centred, customer face +Z.
	_box(Vector3(2.8, .12, .8), Vector3(0, .06, 0), 0)
	_box(Vector3(2.72, .34, .72), Vector3(0, .29, 0), 0)
	_box(Vector3(2.72, .04, .72), Vector3(0, .48, 0), 2)
	# Real corner extrusions: lower case to upper frame, mitre-free square joints.
	for x: float in [-1.37, 1.37]:
		for z: float in [-.37, .37]:
			_box(Vector3(.06, .63, .06), Vector3(x, .815, z), 3)
	for z: float in [-.37, .37]:
		_box(Vector3(2.68, .06, .06), Vector3(0, 1.12, z), 3)
	for x: float in [-1.37, 1.37]:
		_box(Vector3(.06, .06, .68), Vector3(x, 1.12, 0), 3)
	_save("display_case")
	# Freestanding metal shop shelving: 2.4 x 2.6 x .55.
	for x: float in [-1.17, 1.17]:
		for z: float in [-.245, .245]:
			_box(Vector3(.06, 2.6, .06), Vector3(x, 1.3, z), 1)
	for y: float in [.15, .93, 1.71, 2.49]:
		_box(Vector3(2.28, .06, .55), Vector3(0, y, 0), 1)
	_box(Vector3(2.28, 2.28, .025), Vector3(0, 1.32, -.2625), 0)
	_save("shop_shelves")
	var manifest := {
		"atlas_size": 64,
		"padding": 2,
		"charts": ["walnut veneer", "aged cream steel", "dark green felt", "dull brass"],
		"display_case_triangles": 144,
		"shelves_triangles": 108,
		"pivot": "floor center",
		"front": "+Z"
	}
	var file := FileAccess.open(AUTHORING + "manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t") + "\n")
	quit()


func _box(size: Vector3, at: Vector3, chart_id: int) -> void:
	var box := BoxMesh.new()
	box.size = size
	var arrays := box.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var base := _vertices.size()
	var rect := Rect2(CHARTS[chart_id]).grow(-.5)
	for index: int in vertices.size():
		var vertex := vertices[index]
		var normal := normals[index]
		var uv := Vector2.ZERO
		if absf(normal.y) > .5:
			uv = Vector2(vertex.x / size.x, vertex.z / size.z) + Vector2(.5, .5)
		elif absf(normal.x) > .5:
			uv = Vector2(vertex.z / size.z, -vertex.y / size.y) + Vector2(.5, .5)
		else:
			uv = Vector2(vertex.x / size.x, -vertex.y / size.y) + Vector2(.5, .5)
		_vertices.append(vertex + at)
		_normals.append(normal)
		_uvs.append((rect.position + uv * rect.size) / 64.0)
	for index: int in indices:
		_indices.append(base + index)


func _save(asset: String) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices
	for uv: Vector2 in _uvs:
		assert(uv.is_finite() and uv.x > 0 and uv.x < 1 and uv.y > 0 and uv.y < 1)
	for index: int in range(0, _indices.size(), 3):
		var a := _vertices[_indices[index]]
		var b := _vertices[_indices[index + 1]]
		var c := _vertices[_indices[index + 2]]
		assert((b - a).cross(c - a).dot(_normals[_indices[index]]) < -0.000001)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	assert(ResourceSaver.save(mesh, ASSETS + asset + ".res") == OK)
	_export(asset, mesh)
	print(asset, ": ", _indices.size() / 3, " triangles")
	_vertices.clear()
	_normals.clear()
	_uvs.clear()
	_indices.clear()


func _export(asset: String, mesh: ArrayMesh) -> void:
	var paint_path := ProjectSettings.globalize_path(ASSETS + "shop_furniture.png")
	if not FileAccess.file_exists(paint_path):
		return
	var paint := StandardMaterial3D.new()
	var image := Image.load_from_file(paint_path)
	image.generate_mipmaps()
	paint.albedo_texture = ImageTexture.create_from_image(image)
	paint.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	paint.roughness = .85
	var model := Node3D.new()
	model.name = asset
	var frame := MeshInstance3D.new()
	frame.mesh = mesh
	frame.material_override = paint
	model.add_child(frame)
	if asset == "display_case":
		var glass := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(2.68, .59, .68)
		glass.mesh = box
		glass.position.y = .795
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(.55, .75, .7, .12)
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		glass.material_override = material
		model.add_child(glass)
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	assert(gltf.append_from_scene(model, state) == OK)
	assert(gltf.write_to_filesystem(state, AUTHORING + asset + ".glb") == OK)
	var obj := FileAccess.open(AUTHORING + asset + ".obj", FileAccess.WRITE)
	obj.store_line("mtllib furniture.mtl")
	obj.store_line("usemtl painted")
	var vertex_base := 1
	for child: MeshInstance3D in model.get_children():
		if child != frame:
			obj.store_line("usemtl glass")
		var arrays := child.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for point: Vector3 in vertices:
			point += child.position
			obj.store_line("v %f %f %f" % [point.x, point.y, point.z])
		for uv: Vector2 in uvs:
			obj.store_line("vt %f %f" % [uv.x, 1.0 - uv.y])
		for normal: Vector3 in normals:
			obj.store_line("vn %f %f %f" % [normal.x, normal.y, normal.z])
		for index: int in range(0, indices.size(), 3):
			var a := vertex_base + indices[index]
			var b := vertex_base + indices[index + 2]
			var c := vertex_base + indices[index + 1]
			obj.store_line("f %d/%d/%d %d/%d/%d %d/%d/%d" % [a, a, a, b, b, b, c, c, c])
		vertex_base += vertices.size()
	var mtl := FileAccess.open(AUTHORING + "furniture.mtl", FileAccess.WRITE)
	mtl.store_string("newmtl painted\nKd 1 1 1\nmap_Kd shop_furniture.png\n")
	mtl.store_string("newmtl glass\nKd 0.55 0.75 0.7\nd 0.12\n")
	DirAccess.copy_absolute(
		paint_path, ProjectSettings.globalize_path(AUTHORING + "shop_furniture.png")
	)
	model.free()
