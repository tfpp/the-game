extends SceneTree
## Native indexed lift meshes; matched UV charts, supports and collision.

const PROP := preload("res://features/procedural_rooms/model_tools/prop_model.gd")
const OUT := "res://assets/starter_room/"
const AUTHOR := "res://../docs/design/model-sources/workshop-lift/"
const CHARTS: Array[Rect2i] = [
	Rect2i(4, 4, 28, 120),
	Rect2i(40, 4, 80, 32),
	Rect2i(40, 44, 40, 52),
	Rect2i(86, 44, 34, 34),
	Rect2i(86, 84, 34, 28),
	Rect2i(40, 106, 40, 16)
]
var _parts: Array[Array] = [[], []]


func _initialize() -> void:
	for side: float in [-1, 1]:
		_box(0, Vector3(side * 1.9, .06, -.7), Vector3(.65, .12, .75), 2)
		_box(0, Vector3(side * 1.9, 2.18, -.7), Vector3(.32, 4.24, .32), 0)
		_box(0, Vector3(side * 1.9, 4.34, -.7), Vector3(.48, .16, .45), 2)
		_box(0, Vector3(side * 1.72, 2.12, -.7), Vector3(.045, 4.1, .17), 4)
		_box(0, Vector3(side * 1.9, .58, -.53), Vector3(.325, .62, .018), 5)
		# Carriages ride the post guides; articulated arms contact ladder rails.
		_box(1, Vector3(side * 1.72, .47, -.7), Vector3(.23, .62, .3), 2)
		for z: float in [-1.25, 1.25]:
			var start := Vector3(side * 1.7, .24, -.7)
			var end := Vector3(side * .64, .24, z)
			_beam(1, start, end)
			_box(1, Vector3(side * .64, .31, z), Vector3(.22, .1, .22), 4)
	# Overhead cross tie and cable cover leave the walking aisle open.
	_box(0, Vector3(0, 4.35, -.7), Vector3(3.8, .14, .22), 2)
	_box(0, Vector3(0, 4.45, -.7), Vector3(3.8, .06, .08), 4)
	_box(0, Vector3(-2.09, 1.2, -.42), Vector3(.34, .44, .22), 2)
	_box(0, Vector3(-2.09, 1.2, -.301), Vector3(.285, .375, .022), 3)
	for i: int in 2:
		_save(i, "workshop_lift_posts.res" if i == 0 else "workshop_lift_arms.res")
	var image := Image.create(128, 128, false, Image.FORMAT_RGB8)
	image.fill(Color("34383a"))
	for chart: Rect2i in CHARTS:
		image.fill_rect(chart, Color("a8b0a6"))
	image.resize(1024, 1024, Image.INTERPOLATE_NEAREST)
	image.save_png(AUTHOR + "uv-template.png")
	if not OS.get_cmdline_user_args().is_empty():
		image = Image.load_from_file(OS.get_cmdline_user_args()[0])
		image.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		var unpadded := image.duplicate() as Image
		for chart: Rect2i in CHARTS:
			for y: int in range(chart.position.y - 2, chart.end.y + 2):
				for x: int in range(chart.position.x - 2, chart.end.x + 2):
					image.set_pixel(
						x,
						y,
						unpadded.get_pixel(
							clampi(x, chart.position.x, chart.end.x - 1),
							clampi(y, chart.position.y, chart.end.y - 1)
						)
					)
		image.save_png(OUT + "workshop_lift.png")
	quit()


func _beam(part: int, start: Vector3, end: Vector3) -> void:
	var length := start.distance_to(end)
	var angle := atan2((end - start).x, (end - start).z)
	_box(part, (start + end) / 2, Vector3(.14, .12, length), 1, Basis(Vector3.UP, angle))
	_box(part, start, Vector3(.24, .13, .24), 2)


func _box(
	part: int, center: Vector3, size: Vector3, chart: int, basis: Basis = Basis.IDENTITY
) -> void:
	var faces: Array[Dictionary] = []
	PROP.add_prism(
		faces,
		"LIFT",
		[
			Vector2(-size.z / 2, -size.y / 2),
			Vector2(size.z / 2, -size.y / 2),
			Vector2(size.z / 2, size.y / 2),
			Vector2(-size.z / 2, size.y / 2)
		],
		size.x / 2
	)
	for face: Dictionary in faces:
		var poly: Array[Dictionary] = []
		var rect := CHARTS[chart]
		var source: PackedVector3Array = face["points"]
		var projected: PackedVector2Array = face["uv_m"]
		for i: int in source.size():
			var relative := projected[i] / (face["size_m"] as Vector2)
			# Long post faces use top-to-bottom chart orientation.
			if chart == 0:
				var normal: Vector3 = face["normal"]
				var horizontal := (source[i].x + size.x / 2) / size.x
				if absf(normal.x) > .99:
					horizontal = (source[i].z + size.z / 2) / size.z
				relative = Vector2(horizontal, clampf((size.y / 2 - source[i].y) / size.y, 0, 1))
			if chart == 3 and (face["normal"] as Vector3).z > .99:
				relative = Vector2(
					(source[i].x + size.x / 2) / size.x, (size.y / 2 - source[i].y) / size.y
				)
			var uv := (
				(
					Vector2(rect.position)
					+ Vector2(.5, .5)
					+ relative * Vector2(rect.size - Vector2i.ONE)
				)
				/ 128
			)
			poly.append(
				{
					"p": basis * source[i] + center,
					"n": basis * (face["normal"] as Vector3),
					"uv": uv
				}
			)
		_parts[part].append(poly)


func _save(part: int, filename: String) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	var shared: Dictionary[Array, int] = {}
	for poly: Array in _parts[part]:
		for i: int in range(1, poly.size() - 1):
			var triangle: Array = [poly[0], poly[i], poly[i + 1]]
			var cross: Vector3 = (triangle[1]["p"] - triangle[0]["p"]).cross(
				triangle[2]["p"] - triangle[0]["p"]
			)
			if cross.dot(triangle[0]["n"]) > 0:
				triangle.reverse()
			for vertex: Dictionary in triangle:
				var key: Array = [vertex["p"], vertex["n"], vertex["uv"]]
				if not shared.has(key):
					shared[key] = vertices.size()
					vertices.append(vertex["p"])
					normals.append(vertex["n"])
					uv.append(vertex["uv"])
				indices.append(shared[key])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	ResourceSaver.save(mesh, OUT + filename)
	print(filename, ": ", indices.size() / 3, " triangles")
