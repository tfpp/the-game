extends SceneTree
## Offline native geometry/UV source. Normal rebuilds preserve approved painting.

const REGIONS: Array[Rect2i] = [
	Rect2i(2, 2, 60, 60),
	Rect2i(66, 2, 60, 60),
	Rect2i(2, 66, 60, 28),
	Rect2i(66, 66, 60, 28),
	Rect2i(2, 98, 60, 28),
	Rect2i(66, 98, 60, 28),
]
const NAMES: Array[String] = ["Paving", "Asphalt", "Brick", "Canvas", "Metal", "Leaves"]
const SOURCE := "../docs/design/model-sources/strip-mall"
const PAINT := "res://assets/strip_mall/atlas.png"

var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _uv := PackedVector2Array()
var _indices := PackedInt32Array()
var _colors := PackedColorArray()
var _material: StandardMaterial3D


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SOURCE)
	DirAccess.make_dir_recursive_absolute("res://assets/strip_mall")
	var template := Image.create(128, 128, false, Image.FORMAT_RGB8)
	template.fill(Color("454540"))
	var colors: Array[Color] = [
		Color("b2a995"),
		Color("44484b"),
		Color("986c53"),
		Color("688076"),
		Color("777d80"),
		Color("536044")
	]
	for i: int in REGIONS.size():
		template.fill_rect(REGIONS[i], colors[i])
	template.resize(1024, 1024, Image.INTERPOLATE_NEAREST)
	template.save_png(SOURCE + "/uv-template.png")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		var image := Image.load_from_file(args[0])
		assert(image != null)
		image.convert(Image.FORMAT_RGB8)
		image.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		# Each region's own edge colour fills its two-pixel gutter.
		var painted := image.duplicate() as Image
		for rect: Rect2i in REGIONS:
			for y: int in range(rect.position.y - 2, rect.end.y + 2):
				for x: int in range(rect.position.x - 2, rect.end.x + 2):
					painted.set_pixel(
						x,
						y,
						image.get_pixel(
							clampi(x, rect.position.x, rect.end.x - 1),
							clampi(y, rect.position.y, rect.end.y - 1)
						)
					)
		painted.save_png(PAINT)
	if not FileAccess.file_exists(PAINT):
		quit()
		return
	_material = StandardMaterial3D.new()
	_material.albedo_texture = load(PAINT)
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	_material.roughness = 0.92
	_material.vertex_color_use_as_albedo = true
	ResourceSaver.save(_material, "res://features/strip_mall/material.tres")
	var library := MeshLibrary.new()
	_tile(library, 0, "Paving", Vector3(1, .25, 1), Vector3(0, -.125, 0), 0)
	_tile(library, 1, "Asphalt", Vector3(1, .25, 1), Vector3(0, -.125, 0), 1)
	_clear()
	for layer: int in 4:
		_box(Vector3(1, 1, .2), Vector3(0, layer + .5, 0), 2)
	_save(library, 2, "BrickWall", Vector3(1, 4, .2), Vector3(0, 2, 0))
	_tile(library, 3, "Roof", Vector3(1, .25, 1), Vector3(0, .125, 0), 4)
	_clear()
	# Canvas canopy slopes down towards the plaza (-X). Metal spine at rear.
	_box(Vector3(2.2, .12, 1), Vector3(-.9, 3.25, 0), 3, Basis(Vector3.BACK, .12))
	_box(Vector3(.12, .5, 1), Vector3(-1.98, 3, 0), 3)
	_box(Vector3(.16, .16, 1), Vector3(.12, 3.42, 0), 4)
	_save(library, 4, "CanvasAwning")
	_clear()
	_box(Vector3(1, 3.2, .12), Vector3(0, 1.6, 0), 4)
	_box(Vector3(.84, 2, .06), Vector3(0, 1.7, -.095), 4, Basis.IDENTITY, Color(.18, .28, .3))
	_box(Vector3(.06, 2, .08), Vector3(0, 1.7, -.13), 4)
	_box(Vector3(1, .7, .22), Vector3(0, .35, 0), 2)
	_save(library, 5, "StoreWindow", Vector3(1, 3.2, .3), Vector3(0, 1.6, 0))
	_tile(library, 6, "CanopyPost", Vector3(.16, 3.1, .16), Vector3(0, 1.55, 0), 4)
	_clear()
	# Joined trough walls around a recessed soil bed, open at top.
	_box(Vector3(1.8, .12, .8), Vector3(0, .06, 0), 4)
	_box(Vector3(1.8, .58, .1), Vector3(0, .41, -.35), 4)
	_box(Vector3(1.8, .58, .1), Vector3(0, .41, .35), 4)
	_box(Vector3(.1, .58, .6), Vector3(-.85, .41, 0), 4)
	_box(Vector3(.1, .58, .6), Vector3(.85, .41, 0), 4)
	_box(Vector3(1.6, .06, .6), Vector3(0, .55, 0), 2)
	for x: float in [-.55, 0.0, .55]:
		var leaf := PrismMesh.new()
		leaf.size = Vector3(.6, .9, .5)
		_append(leaf, Transform3D(Basis.IDENTITY, Vector3(x, 1.02, 0)), 5)
	_save(library, 7, "Planter", Vector3(1.8, .7, .8), Vector3(0, .35, 0))
	_clear()
	_box(Vector3(1, .25, 1), Vector3(0, -.125, 0), 1)
	_box(Vector3(.08, .008, 1), Vector3(0, .004, 0), 0)
	_save(library, 8, "ParkingStripe", Vector3(1, .25, 1), Vector3(0, -.125, 0))
	_clear()
	_box(Vector3(1, 1.2, .2), Vector3(0, .6, 0), 2)
	for x: float in [-.48, -.24, 0.0, .24, .48]:
		_box(Vector3(.035, 2.3, .05), Vector3(x, 2.25, 0), 4)
	for y: float in [1.3, 3.35]:
		_box(Vector3(1, .045, .07), Vector3(0, y, 0), 4)
	_save(library, 9, "SiteFence", Vector3(1, 3.4, .2), Vector3(0, 1.7, 0))
	ResourceSaver.save(library, "res://features/strip_mall/tiles.tres")
	_export_review(library)
	quit()


func _export_review(library: MeshLibrary) -> void:
	var root := Node3D.new()
	root.name = "StripMallGridset"
	for id: int in library.get_item_list():
		var model := MeshInstance3D.new()
		model.name = library.get_item_name(id)
		model.mesh = library.get_item_mesh(id)
		model.position.x = id * 3.0
		root.add_child(model)
		model.owner = root
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_scene(root, state) == OK)
	assert(document.write_to_filesystem(state, SOURCE + "/gridset.glb") == OK)
	root.free()


func _tile(
	library: MeshLibrary, id: int, label: String, size: Vector3, center: Vector3, region: int
) -> void:
	_clear()
	_box(size, center, region)
	_save(library, id, label, size, center)


func _clear() -> void:
	_vertices.clear()
	_normals.clear()
	_uv.clear()
	_indices.clear()
	_colors.clear()


func _box(
	size: Vector3, center: Vector3, region: int, basis := Basis.IDENTITY, tint := Color.WHITE
) -> void:
	var box := BoxMesh.new()
	box.size = size
	_append(box, Transform3D(basis, center), region, tint)


func _append(mesh: PrimitiveMesh, at: Transform3D, region: int, tint := Color.WHITE) -> void:
	var arrays := mesh.get_mesh_arrays()
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var base := _vertices.size()
	# Box faces share their complete material patch; do not sample the native
	# six-face cross, which would crop the brick courses into stretched columns.
	if mesh is BoxMesh:
		var size := (mesh as BoxMesh).size
		for i: int in points.size():
			var p := points[i] / size + Vector3.ONE * .5
			var n := normals[i].abs()
			if n.y > .9:
				uv[i] = Vector2(p.x, p.z)
			elif n.x > .9:
				uv[i] = Vector2(p.z, 1.0 - p.y)
			else:
				uv[i] = Vector2(p.x, 1.0 - p.y)
	# Primitive faces deliberately stack/reuse the same material island.
	# Half-texel bounds keep UVs within painted interiors.
	var rect := Rect2(REGIONS[region]).grow(-.5)
	for i: int in points.size():
		_vertices.append(at * points[i])
		_normals.append(at.basis * normals[i])
		_uv.append((rect.position + uv[i] * rect.size) / 128.0)
		_colors.append(tint)
	for index: int in indices:
		_indices.append(base + index)


func _save(
	library: MeshLibrary, id: int, label: String, size := Vector3.ZERO, center := Vector3.ZERO
) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_INDEX] = _indices
	arrays[Mesh.ARRAY_COLOR] = _colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	var path: String = "res://assets/strip_mall/" + label.to_snake_case() + ".res"
	ResourceSaver.save(mesh, path)
	library.create_item(id)
	library.set_item_name(id, label)
	library.set_item_mesh(id, mesh)
	if size != Vector3.ZERO:
		var shape := BoxShape3D.new()
		shape.size = size
		library.set_item_shapes(id, [shape, Transform3D(Basis.IDENTITY, center)])
	print("%s: %d triangles, one material" % [label, _indices.size() / 3])
