extends SceneTree
## Mesh-first continuous table construction. UV charts and exports share this source.
const SOURCE := "res://../docs/design/model-sources/crown-tables/"
const TEXTURE := "res://assets/table_games/textures/card_tables.png"
const CHARTS := {
	"POKER FELT": Rect2i(4, 4, 72, 40),
	"BLACKJACK FELT": Rect2i(80, 4, 44, 40),
	"PADDED BURGUNDY RAIL": Rect2i(4, 48, 120, 12),
	"WALNUT APRON": Rect2i(4, 64, 120, 16),
	"PEDESTAL WALNUT": Rect2i(4, 84, 56, 36),
	"BASE WALNUT": Rect2i(64, 84, 40, 16),
	"BRASS": Rect2i(108, 84, 16, 16),
	"UNDERSIDE": Rect2i(64, 104, 60, 16)
}
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/table_games/textures")
	_template(false).save_png(SOURCE + "card-tables-uv.png")
	_template(true).save_png(SOURCE + "card-tables-checker.png")
	var guide := _template(false)
	guide.resize(1024, 1024, Image.INTERPOLATE_NEAREST)
	guide.save_png(SOURCE + "card-tables-uv-guide.png")
	if "--paint" in OS.get_cmdline_user_args():
		var paint := Image.load_from_file(SOURCE + "card-tables-painted.png")
		assert(paint != null)
		paint.convert(Image.FORMAT_RGB8)
		paint.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		var final := Image.create(128, 128, false, Image.FORMAT_RGB8)
		final.fill(Color("30251e"))
		for rect: Rect2i in CHARTS.values():
			var padded := rect.grow(2)
			for y: int in range(padded.position.y, padded.end.y):
				for x: int in range(padded.position.x, padded.end.x):
					final.set_pixel(
						x,
						y,
						paint.get_pixel(
							clampi(x, rect.position.x, rect.end.x - 1),
							clampi(y, rect.position.y, rect.end.y - 1)
						)
					)
		final.save_png(TEXTURE)
	var manifest: Array[Dictionary] = []
	for kind: String in ["poker", "blackjack", "baccarat"]:
		_vertices.clear()
		_normals.clear()
		_uvs.clear()
		_indices.clear()
		var shape := _outline(kind)
		# Upholstery is a single closed profile; the inner seam meets the felt exactly.
		_cap(shape, .93, .86, "BLACKJACK FELT" if kind == "blackjack" else "POKER FELT", true)
		_join(shape, .86, .93, 1.0, .98, "PADDED BURGUNDY RAIL")
		_join(shape, 1.0, .98, 1.0, .87, "PADDED BURGUNDY RAIL")
		_join(shape, 1.0, .87, .96, .87, "PADDED BURGUNDY RAIL")
		_join(shape, .96, .87, .96, .76, "WALNUT APRON")
		_join(shape, .96, .76, .96, .74, "BRASS")
		_cap(shape, .74, .96, "UNDERSIDE", false)
		# Two solid pedestal assemblies, touching the apron underside and their bases.
		for side: float in [-1, 1]:
			_pedestal(side * (.95 if kind == "baccarat" else .66))
		_validate()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _vertices
		arrays[Mesh.ARRAY_NORMAL] = _normals
		arrays[Mesh.ARRAY_TEX_UV] = _uvs
		arrays[Mesh.ARRAY_INDEX] = _indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := StandardMaterial3D.new()
		material.albedo_texture = (
			load(TEXTURE)
			if ResourceLoader.exists(TEXTURE)
			else ImageTexture.create_from_image(_template(true))
		)
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		material.roughness = .9
		mesh.surface_set_material(0, material)
		assert(
			ResourceSaver.save(mesh, "res://assets/table_games/models/" + kind + "_table.res") == OK
		)
		var scene := Node3D.new()
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		scene.add_child(visual)
		visual.owner = scene
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		assert(document.append_from_scene(scene, state) == OK)
		assert(document.write_to_filesystem(state, SOURCE + kind + "-table.glb") == OK)
		scene.free()
		manifest.append(
			{
				"id": kind + "_table",
				"triangles": _indices.size() / 3,
				"surfaces": 1,
				"bounds": str(mesh.get_aabb()),
				"texture": TEXTURE,
				"texture_size": "128x128",
				"pivot": "floor-centred",
				"front": "+Z"
			}
		)
		print(manifest.back())
	var file := FileAccess.open(SOURCE + "remake-inventory.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"models": manifest, "charts": CHARTS}, "\t") + "\n")
	quit()


func _outline(kind: String) -> PackedVector2Array:
	var points := PackedVector2Array()
	if kind != "blackjack":
		for i: int in 16:
			var angle := TAU * i / 16.0
			points.append(
				Vector2(
					cos(angle) * (1.8375 if kind == "baccarat" else 1.21),
					sin(angle) * (.86625 if kind == "baccarat" else .71)
				)
			)
	else:
		# D-shaped dealer table: straight rear edge and one continuous player-side arc.
		for i: int in 13:
			var angle := PI * i / 12.0
			points.append(Vector2(cos(angle) * 1.35, -.66 + sin(angle) * 1.32))
	return points


func _chart(name: String, coordinate: Vector2) -> Vector2:
	var rect: Rect2i = CHARTS[name]
	return (
		(Vector2(rect.position) + Vector2(.5, .5) + coordinate * Vector2(rect.size - Vector2i.ONE))
		/ 128.0
	)


func _triangle(
	a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, normal: Vector3
) -> void:
	# Godot front faces are clockwise. Share vertices wherever normals and UVs agree.
	if (b - a).cross(c - a).dot(normal) > 0:
		var swap := b
		b = c
		c = swap
		var uv_swap := ub
		ub = uc
		uc = uv_swap
	for i: int in 3:
		var p: Vector3 = [a, b, c][i]
		var uv: Vector2 = [ua, ub, uc][i]
		var found := -1
		for j: int in _vertices.size():
			if (
				_vertices[j].is_equal_approx(p)
				and _normals[j].is_equal_approx(normal)
				and _uvs[j].is_equal_approx(uv)
			):
				found = j
				break
		if found < 0:
			found = _vertices.size()
			_vertices.append(p)
			_normals.append(normal)
			_uvs.append(uv)
		_indices.append(found)


func _cap(
	shape: PackedVector2Array, height: float, scale_factor: float, chart: String, up: bool
) -> void:
	var bounds := Rect2(shape[0], Vector2.ZERO)
	for point: Vector2 in shape:
		bounds = bounds.expand(point)
	var centre := Vector2.ZERO
	for point: Vector2 in shape:
		centre += point / shape.size()
	for i: int in shape.size():
		var a := shape[i]
		var b := shape[(i + 1) % shape.size()]
		_triangle(
			Vector3(centre.x * scale_factor, height, centre.y * scale_factor),
			Vector3(a.x * scale_factor, height, a.y * scale_factor),
			Vector3(b.x * scale_factor, height, b.y * scale_factor),
			_chart(chart, (centre - bounds.position) / bounds.size),
			_chart(chart, (a - bounds.position) / bounds.size),
			_chart(chart, (b - bounds.position) / bounds.size),
			Vector3.UP if up else Vector3.DOWN
		)


func _join(
	shape: PackedVector2Array,
	inner: float,
	low: float,
	outer: float,
	high: float,
	chart: String,
	offset: Vector2 = Vector2.ZERO
) -> void:
	var total := 0.0
	for i: int in shape.size():
		total += shape[i].distance_to(shape[(i + 1) % shape.size()])
	var travelled := 0.0
	for i: int in shape.size():
		var first := shape[i]
		var second := shape[(i + 1) % shape.size()]
		var start := travelled / total
		travelled += first.distance_to(second)
		var end := travelled / total
		var a := Vector3(first.x * inner + offset.x, low, first.y * inner + offset.y)
		var b := Vector3(second.x * inner + offset.x, low, second.y * inner + offset.y)
		var c := Vector3(second.x * outer + offset.x, high, second.y * outer + offset.y)
		var d := Vector3(first.x * outer + offset.x, high, first.y * outer + offset.y)
		var normal := (b - a).cross(d - a).normalized()
		if is_equal_approx(inner, outer) and high > low:
			normal = -normal
		# Face orientation follows loop direction/profile; explicit outward geometric normal.
		_triangle(
			a,
			b,
			c,
			_chart(chart, Vector2(start, 1)),
			_chart(chart, Vector2(end, 1)),
			_chart(chart, Vector2(end, 0)),
			normal
		)
		_triangle(
			a,
			c,
			d,
			_chart(chart, Vector2(start, 1)),
			_chart(chart, Vector2(end, 0)),
			_chart(chart, Vector2(start, 0)),
			normal
		)


func _pedestal(x: float) -> void:
	var shape := PackedVector2Array(
		[Vector2(-.20, -.28), Vector2(.20, -.28), Vector2(.20, .28), Vector2(-.20, .28)]
	)
	_join(shape, 1.0, .13, 1.0, .74, "PEDESTAL WALNUT", Vector2(x, 0))
	var base := PackedVector2Array(
		[Vector2(-.30, -.48), Vector2(.30, -.48), Vector2(.30, .48), Vector2(-.30, .48)]
	)
	_join(base, 1.0, 0, 1.0, .08, "BASE WALNUT", Vector2(x, 0))
	# Closed sloped shoulder joins the footprint to the column without intersecting blocks.
	for i: int in 4:
		var j := (i + 1) % 4
		var a := Vector3(base[i].x + x, .08, base[i].y)
		var b := Vector3(base[j].x + x, .08, base[j].y)
		var c := Vector3(shape[j].x + x, .13, shape[j].y)
		var d := Vector3(shape[i].x + x, .13, shape[i].y)
		var normal := -(b - a).cross(d - a).normalized()
		_triangle(
			a,
			b,
			c,
			_chart("BASE WALNUT", Vector2(0, 1)),
			_chart("BASE WALNUT", Vector2(1, 1)),
			_chart("BASE WALNUT", Vector2(1, 0)),
			normal
		)
		_triangle(
			a,
			c,
			d,
			_chart("BASE WALNUT", Vector2(0, 1)),
			_chart("BASE WALNUT", Vector2(1, 0)),
			_chart("BASE WALNUT", Vector2(0, 0)),
			normal
		)
	var moved := PackedVector2Array()
	for p: Vector2 in base:
		moved.append(p + Vector2(x, 0))
	_cap(moved, 0, 1, "UNDERSIDE", false)


func _template(checker: bool) -> Image:
	var result := Image.create(128, 128, false, Image.FORMAT_RGB8)
	result.fill(Color("30251e"))
	var colours: Array[Color] = [
		Color("287253"),
		Color("315d65"),
		Color("793740"),
		Color("9c6a40"),
		Color("b18557"),
		Color("735333"),
		Color("b8a15a"),
		Color("494339")
	]
	var index := 0
	for rect: Rect2i in CHARTS.values():
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				result.set_pixel(
					x,
					y,
					(
						(Color("dddddd") if (x / 4 + y / 4) % 2 == 0 else Color("555555"))
						if checker
						else colours[index]
					)
				)
		index += 1
	return result


func _validate() -> void:
	assert(_indices.size() % 3 == 0)
	assert(_indices.size() / 3 <= 250, "Complete furniture triangle budget")
	for i: int in _vertices.size():
		assert(_vertices[i].is_finite() and _uvs[i].is_finite())
		assert(_normals[i].is_finite() and absf(_normals[i].length() - 1) < .0001)
		assert(_uvs[i].x > 0 and _uvs[i].x < 1 and _uvs[i].y > 0 and _uvs[i].y < 1)
	for i: int in range(0, _indices.size(), 3):
		for corner: int in 3:
			assert(_indices[i + corner] >= 0 and _indices[i + corner] < _vertices.size())
		var a := _indices[i]
		var b := _indices[i + 1]
		var c := _indices[i + 2]
		var cross_product := (_vertices[b] - _vertices[a]).cross(_vertices[c] - _vertices[a])
		assert(cross_product.length() > .000001, "Nondegenerate triangle")
		assert(cross_product.normalized().dot(_normals[a]) < -.999, "Clockwise outward winding")
	var occupied: Array[Rect2i] = []
	for rect: Rect2i in CHARTS.values():
		var padded := rect.grow(2)
		assert(Rect2i(0, 0, 128, 128).encloses(padded))
		for other: Rect2i in occupied:
			assert(not padded.intersects(other), "Distinct charts retain padded separation")
		occupied.append(padded)
