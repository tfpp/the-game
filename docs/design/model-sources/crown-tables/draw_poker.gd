extends SceneTree
## One coherent extruded cabinet, with angled glass and an integrated control deck.
const SOURCE := "res://../docs/design/model-sources/crown-tables/"
const TEXTURE := "res://assets/table_games/textures/draw_poker.png"
const CHARTS := {
	"WALNUT SIDE": Rect2i(4, 4, 44, 84),
	"SCREEN": Rect2i(52, 4, 72, 48),
	"CONTROLS": Rect2i(52, 56, 72, 20),
	"LOWER FRONT": Rect2i(52, 80, 40, 40),
	"BACK": Rect2i(96, 80, 28, 40),
	"TRIM": Rect2i(4, 92, 44, 28)
}
const PROFILE := [
	Vector2(-.38, 0),
	Vector2(.30, 0),
	Vector2(.30, .70),
	Vector2(.38, .80),
	Vector2(.38, .88),
	Vector2(.18, .94),
	Vector2(.06, 1.39),
	Vector2(-.01, 1.49),
	Vector2(-.38, 1.49)
]
var _positions := PackedVector3Array()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()


func _initialize() -> void:
	var template := _template()
	template.save_png(SOURCE + "draw-poker-uv.png")
	template.resize(1024, 1024, Image.INTERPOLATE_NEAREST)
	template.save_png(SOURCE + "draw-poker-uv-guide.png")
	if "--paint" in OS.get_cmdline_user_args():
		_paint()
	var polygon := PackedVector2Array(PROFILE)
	var side_indices := Geometry2D.triangulate_polygon(polygon)
	for side: float in [-1, 1]:
		for i: int in range(0, side_indices.size(), 3):
			var points: Array[Vector3] = []
			var uv: Array[Vector2] = []
			for corner: int in 3:
				var p: Vector2 = PROFILE[side_indices[i + corner]]
				points.append(Vector3(side * .34, p.y, p.x))
				uv.append(_uv("WALNUT SIDE", Vector2((p.x + .38) / .76, 1 - p.y / 1.49)))
			_triangle(points, uv, Vector3.RIGHT * side)
	for i: int in PROFILE.size():
		var a: Vector2 = PROFILE[i]
		var b: Vector2 = PROFILE[(i + 1) % PROFILE.size()]
		var chart := "TRIM"
		if i == 1:
			chart = "LOWER FRONT"
		elif i == 4:
			chart = "CONTROLS"
		elif i == 5:
			chart = "SCREEN"
		elif i == 8:
			chart = "BACK"
		var points: Array[Vector3] = [
			Vector3(-.34, a.y, a.x),
			Vector3(.34, a.y, a.x),
			Vector3(.34, b.y, b.x),
			Vector3(-.34, b.y, b.x)
		]
		var normal := Vector3(0, a.x - b.x, b.y - a.y).normalized()
		_triangle(
			[points[0], points[1], points[2]],
			[_uv(chart, Vector2(0, 1)), _uv(chart, Vector2(1, 1)), _uv(chart, Vector2(1, 0))],
			normal
		)
		_triangle(
			[points[0], points[2], points[3]],
			[_uv(chart, Vector2(0, 1)), _uv(chart, Vector2(1, 0)), _uv(chart, Vector2(0, 0))],
			normal
		)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _positions
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_texture = (
		load(TEXTURE)
		if ResourceLoader.exists(TEXTURE)
		else ImageTexture.create_from_image(_template())
	)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.roughness = .9
	mesh.surface_set_material(0, material)
	assert(
		ResourceSaver.save(mesh, "res://assets/table_games/models/video_poker_machine.res") == OK
	)
	var root := Node3D.new()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	root.add_child(instance)
	instance.owner = root
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_scene(root, state) == OK)
	assert(document.write_to_filesystem(state, SOURCE + "draw-poker.glb") == OK)
	root.free()
	print("Draw poker: ", _indices.size() / 3, " triangles, one material, ", mesh.get_aabb())
	quit()


func _uv(chart: String, at: Vector2) -> Vector2:
	var rect: Rect2i = CHARTS[chart]
	return (
		(Vector2(rect.position) + Vector2(.5, .5) + at * Vector2(rect.size - Vector2i.ONE)) / 128.0
	)


func _triangle(points: Array[Vector3], uv: Array[Vector2], normal: Vector3) -> void:
	var cross_product := (points[1] - points[0]).cross(points[2] - points[0])
	assert(cross_product.length() > .000001)
	if cross_product.dot(normal) > 0:
		var swap := points[1]
		points[1] = points[2]
		points[2] = swap
		var uv_swap := uv[1]
		uv[1] = uv[2]
		uv[2] = uv_swap
	for i: int in 3:
		var found := -1
		for j: int in _positions.size():
			if (
				_positions[j].is_equal_approx(points[i])
				and _normals[j].is_equal_approx(normal)
				and _uvs[j].is_equal_approx(uv[i])
			):
				found = j
				break
		if found < 0:
			found = _positions.size()
			_positions.append(points[i])
			_normals.append(normal)
			_uvs.append(uv[i])
		_indices.append(found)


func _template() -> Image:
	var result := Image.create(128, 128, false, Image.FORMAT_RGB8)
	result.fill(Color("30251e"))
	var colors: Array[Color] = [
		Color("8d5935"),
		Color("203f42"),
		Color("b9a878"),
		Color("63452f"),
		Color("4c4037"),
		Color("282528")
	]
	var index := 0
	for rect: Rect2i in CHARTS.values():
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				result.set_pixel(x, y, colors[index])
		index += 1
	return result


func _paint() -> void:
	var source := Image.load_from_file(SOURCE + "draw-poker-painted.png")
	assert(source != null)
	source.convert(Image.FORMAT_RGB8)
	source.resize(128, 128, Image.INTERPOLATE_LANCZOS)
	var final := Image.create(128, 128, false, Image.FORMAT_RGB8)
	final.fill(Color("30251e"))
	for rect: Rect2i in CHARTS.values():
		for y: int in range(rect.position.y - 2, rect.end.y + 2):
			for x: int in range(rect.position.x - 2, rect.end.x + 2):
				final.set_pixel(
					x,
					y,
					source.get_pixel(
						clampi(x, rect.position.x, rect.end.x - 1),
						clampi(y, rect.position.y, rect.end.y - 1)
					)
				)
	final.save_png(TEXTURE)
