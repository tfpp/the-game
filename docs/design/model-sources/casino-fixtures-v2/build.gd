extends SceneTree
## Indexed profile meshes; source, UV allocation and native exports are one recipe.

const ROOT := "res://assets/casino_hub/fixtures_v2/"
var _tool: SurfaceTool
var _triangles := 0
var _fixture := false


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	if "--libraries" in OS.get_cmdline_user_args():
		_libraries()
		quit()
		return
	_start(false)
	# Continuous handrails: full hexagonal profiles, ends buried in shared posts.
	_tube(Vector3(0, 1.025, 0), Vector3(2, 1.025, 0), 0.065, 6, false)
	_tube(Vector3(0, 0.32, 0), Vector3(2, 0.32, 0), 0.027, 6, false)
	for x: float in [0.5, 1.0, 1.5]:
		_profile(
			Vector3(x, 0, 0),
			[
				Vector2(.29, .027),
				Vector2(.35, .027),
				Vector2(.39, .022),
				Vector2(.93, .022),
				Vector2(.98, .027),
				Vector2(1.02, .027)
			],
			4,
			true
		)
	_save("res://assets/room_kits/brass_pit_railing/rail_span.res")
	_start(false)
	_profile(
		Vector3.ZERO,
		[
			Vector2(0, .055),
			Vector2(.035, .07),
			Vector2(.09, .055),
			Vector2(.13, .045),
			Vector2(.93, .045),
			Vector2(.97, .055),
			Vector2(1.025, .07),
			Vector2(1.075, .06),
			Vector2(1.105, .025)
		],
		8,
		true
	)
	_save("res://assets/room_kits/brass_pit_railing/rail_post.res")
	_start(true)
	# Wall mount, continuous bent arm and supported opal diffuser.
	_profile(
		Vector3(0, 0, 0),
		[Vector2(-.32, .09), Vector2(-.28, .11), Vector2(.28, .11), Vector2(.32, .08)],
		6,
		false
	)
	_sweep([Vector3(0, -.19, .025), Vector3(0, -.19, .27), Vector3(0, -.05, .34)], .035, 6, false)
	_profile(
		Vector3(0, 0, .34),
		[Vector2(-.08, .035), Vector2(-.045, .10), Vector2(-.02, .11), Vector2(0, .10)],
		8,
		false
	)
	_profile(
		Vector3(0, 0, .34),
		[Vector2(-.015, .085), Vector2(.035, .13), Vector2(.20, .13), Vector2(.26, .07)],
		8,
		true
	)
	_save(ROOT + "sconce.res")
	_start(true)
	# Ceiling cup and rod connect to a hub; swept arms terminate inside lamp cups.
	_profile(Vector3.ZERO, [Vector2(-.07, .10), Vector2(-.035, .17), Vector2(0, .14)], 8, false)
	_tube(Vector3(0, -.07, 0), Vector3(0, -.90, 0), .028, 6, false)
	_profile(
		Vector3.ZERO,
		[Vector2(-1.08, .04), Vector2(-1.04, .13), Vector2(-.90, .13), Vector2(-.86, .05)],
		8,
		false
	)
	for index: int in 4:
		var angle := TAU * index / 4.0
		var outward := Vector3(cos(angle), 0, sin(angle))
		var points: Array[Vector3] = [
			outward * .10 + Vector3(0, -.98, 0),
			outward * .29 + Vector3(0, -1.08, 0),
			outward * .55 + Vector3(0, -1.08, 0),
			outward * .67 + Vector3(0, -.94, 0)
		]
		_sweep(points, .027, 6, false)
		var center := outward * .67
		_profile(center, [Vector2(-.96, .03), Vector2(-.93, .10), Vector2(-.90, .105)], 6, false)
		_profile(
			center,
			[Vector2(-.91, .085), Vector2(-.86, .12), Vector2(-.63, .12), Vector2(-.58, .06)],
			6,
			true
		)
	_save(ROOT + "chandelier.res")
	quit()


func _start(fixture: bool) -> void:
	_fixture = fixture
	_tool = SurfaceTool.new()
	_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_triangles = 0


func _quad(points: Array[Vector3], secondary: bool, row: float, next_row: float) -> void:
	var normal := (points[2] - points[0]).cross(points[1] - points[0]).normalized()
	assert(normal.is_finite() and normal.length() > .99)
	var left := .55 if secondary else .08
	var right := .90 if secondary else .42
	# The retained rail atlas has distinct brass swatches above/below V=.5.
	# Keep each brass part in the upper swatch; wood uses its full grain strip.
	if not _fixture and not secondary:
		row = lerpf(.12, .38, row)
		next_row = lerpf(.12, .38, next_row)
	var uv: Array[Vector2] = [
		Vector2(left, row), Vector2(right, row), Vector2(right, next_row), Vector2(left, next_row)
	]
	for triangle: Array in [[0, 1, 2], [0, 2, 3]]:
		var face_normal := (
			(points[triangle[2]] - points[triangle[0]])
			. cross(points[triangle[1]] - points[triangle[0]])
			. normalized()
		)
		for index: int in triangle:
			_tool.set_normal(face_normal)
			_tool.set_uv(uv[index])
			_tool.add_vertex(points[index])
	_triangles += 2


func _profile(center: Vector3, rings: Array, sides: int, secondary: bool) -> void:
	for row: int in range(rings.size() - 1):
		var a: Vector2 = rings[row]
		var b: Vector2 = rings[row + 1]
		var wood := secondary and (_fixture or b.x - a.x > .3)
		for side: int in sides:
			var angle := TAU * side / sides
			var next := TAU * (side + 1) / sides
			_quad(
				[
					center + Vector3(cos(angle) * a.y, a.x, sin(angle) * a.y),
					center + Vector3(cos(next) * a.y, a.x, sin(next) * a.y),
					center + Vector3(cos(next) * b.y, b.x, sin(next) * b.y),
					center + Vector3(cos(angle) * b.y, b.x, sin(angle) * b.y)
				],
				wood,
				lerpf(.08, .92, float(row) / (rings.size() - 1)),
				lerpf(.08, .92, float(row + 1) / (rings.size() - 1))
			)
	# Closed ends: cap islands reuse each component's material strip centre.
	for end: int in [0, rings.size() - 1]:
		var ring: Vector2 = rings[end]
		var normal := Vector3.DOWN if end == 0 else Vector3.UP
		for side: int in sides:
			var angles: Array[float] = [TAU * side / sides, TAU * (side + 1) / sides]
			if end == 0:
				angles.reverse()
			_tool.set_normal(normal)
			_tool.set_uv(Vector2(.72 if secondary and _fixture else .25, .5 if _fixture else .25))
			_tool.add_vertex(center + Vector3(0, ring.x, 0))
			for angle: float in angles:
				_tool.add_vertex(center + Vector3(cos(angle) * ring.y, ring.x, sin(angle) * ring.y))
			_triangles += 1


func _tube(a: Vector3, b: Vector3, radius: float, sides: int, secondary: bool) -> void:
	_sweep([a, b], radius, sides, secondary)


func _sweep(path: Array[Vector3], radius: float, sides: int, secondary: bool) -> void:
	var rings: Array[PackedVector3Array] = []
	var previous_across := Vector3.ZERO
	for index: int in path.size():
		var tangent := (
			(path[mini(index + 1, path.size() - 1)] - path[maxi(index - 1, 0)]).normalized()
		)
		var reference := Vector3.FORWARD if absf(tangent.dot(Vector3.FORWARD)) < .95 else Vector3.UP
		var across := tangent.cross(reference).normalized()
		if previous_across.length() > .5:
			across = (previous_across - tangent * previous_across.dot(tangent)).normalized()
		previous_across = across
		var around := across.cross(tangent).normalized()
		var ring := PackedVector3Array()
		for side: int in sides:
			var angle := TAU * side / sides
			ring.append(path[index] + radius * (across * cos(angle) + around * sin(angle)))
		rings.append(ring)
	for row: int in range(path.size() - 1):
		for side: int in sides:
			var next := (side + 1) % sides
			_quad(
				[rings[row][side], rings[row][next], rings[row + 1][next], rings[row + 1][side]],
				secondary,
				lerpf(.08, .92, float(row) / (path.size() - 1)),
				lerpf(.08, .92, float(row + 1) / (path.size() - 1))
			)


func _save(path: String) -> void:
	_tool.index()
	var mesh := _tool.commit()
	assert(mesh.get_faces().size() / 3 == _triangles)
	assert(ResourceSaver.save(mesh, path) == OK)
	print("FIXTURE_MESH: ", path, " triangles=", _triangles, " bounds=", mesh.get_aabb())


func _libraries() -> void:
	var library := load("res://features/casino_hub/gridmap/casino_tiles.tres") as MeshLibrary
	var material := load("res://features/room_kits/brass_railing_material.tres") as Material
	for pair: Array in [[9, "rail_span"], [10, "rail_post"]]:
		var mesh := (
			load("res://assets/room_kits/brass_pit_railing/" + str(pair[1]) + ".res") as ArrayMesh
		)
		mesh.surface_set_material(0, material)
		assert(
			(
				ResourceSaver.save(
					mesh, "res://assets/room_kits/brass_pit_railing/" + str(pair[1]) + ".res"
				)
				== OK
			)
		)
		library.set_item_mesh(int(pair[0]), mesh)
	var slope := Basis(Vector3(0, .625, 1), Vector3.UP, Vector3.LEFT)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.append_from(library.get_item_mesh(9), 0, Transform3D(slope, Vector3.ZERO))
	var rail := tool.commit()
	rail.surface_set_material(0, material)
	library.set_item_mesh(16, rail)
	assert(ResourceSaver.save(library, "res://features/casino_hub/gridmap/casino_tiles.tres") == OK)
	var decor_script := load("res://features/casino_hub/gridmap/decor.gd") as GDScript
	var decor: MeshLibrary = decor_script.library()
	assert(ResourceSaver.save(decor, "res://features/casino_hub/gridmap/casino_decor.tres") == OK)
