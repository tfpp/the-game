extends SceneTree
## Editable, deterministic exterior mesh source. Run from the game project.

const SOURCE := "res://../docs/design/model-sources/r44-metro"
const MEDIA := "res://assets/metro"
const SCENES := "res://features/metro"
const FONT := preload("res://features/procedural_rooms/tools/build_dev_textures.gd").FONT
const UV := preload("res://features/procedural_rooms/model_tools/uv_model.gd")
const CABIN := preload("res://../docs/design/model-sources/r44-metro/cabin.gd")
const PITCH := 22.86
const HALF := 11.1
const REGIONS := ["STEEL", "RIBS", "ROOF", "RUBBER", "GLASS", "TRUCK", "CREAM", "RUST"]
const COLORS := ["929a99", "747c7b", "737d80", "242b2c", "263f43", "383c3c", "ded3ae", "705346"]
var material: StandardMaterial3D
var markings: StandardMaterial3D
var graffiti: StandardMaterial3D
var interior: StandardMaterial3D
var glass: StandardMaterial3D
var lamp: StandardMaterial3D
var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var uvs := PackedVector2Array()
var indices := PackedInt32Array()
var mesh_cache: Dictionary[String, ArrayMesh] = {}
var manifest: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_build")


func _build() -> void:
	var charts: Array[Dictionary] = []
	var guide := Image.create(128, 128, false, Image.FORMAT_RGB8)
	guide.fill(Color("484b4b"))
	for i: int in 8:
		var rect := Rect2i(2 + (i % 2) * 64, 2 + (i / 2) * 32, 60, 28)
		charts.append({"name": REGIONS[i], "rect": rect})
		guide.fill_rect(rect, Color(COLORS[i]))
	var checker := UV.prepare_albedo(UV.template(charts, true), charts)
	checker.save_png(ProjectSettings.globalize_path(SOURCE + "/checker.png"))
	guide.resize(1024, 1024, Image.INTERPOLATE_NEAREST)
	for i: int in 8:
		var rect: Rect2i = charts[i]["rect"]
		label(guide, REGIONS[i], rect.position * 8 + Vector2i(16, 16), 4, Color.WHITE)
	guide.save_png(ProjectSettings.globalize_path(SOURCE + "/uv_template.png"))
	var args := OS.get_cmdline_user_args()
	if args.has("--interior-template"):
		var names := ["WOOD", "ORANGE", "FLOOR", "STEEL", "OCHRE", "CEILING", "LIGHT", "DARK"]
		var colors := [
			"655042", "ac572d", "454440", "999c94", "b39349", "bdb9a4", "dce1c9", "323739"
		]
		guide.fill(Color("484b4b"))
		for i: int in 8:
			var rect: Rect2i = charts[i]["rect"]
			guide.fill_rect(Rect2i(rect.position * 8, rect.size * 8), Color(colors[i]))
			label(guide, names[i], rect.position * 8 + Vector2i(16, 16), 4, Color.WHITE)
		guide.save_png(ProjectSettings.globalize_path(SOURCE + "/interior_uv_template.png"))
		quit()
		return
	if args.has("--template"):
		print("UV template ready")
		quit()
		return
	var atlas_path := MEDIA + "/textures/r44_atlas.png"
	if args.size() == 1:
		var paint := Image.load_from_file(args[0])
		assert(paint != null)
		UV.prepare_albedo(paint, charts).save_png(atlas_path)
	assert(FileAccess.file_exists(atlas_path), "Paint the exported template before building")
	material = StandardMaterial3D.new()
	material.resource_name = "R44 painted steel - 128px"
	material.albedo_texture = save_texture(
		Image.load_from_file(ProjectSettings.globalize_path(atlas_path)), "r44_atlas"
	)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.texture_repeat = false
	material.roughness = 0.86
	ResourceSaver.save(material, SCENES + "/painted_steel.tres", ResourceSaver.FLAG_CHANGE_PATH)
	material.take_over_path(SCENES + "/painted_steel.tres")
	make_markings()
	make_graffiti()
	make_interior(charts)
	var cab := car(true)
	save_scene(cab, SCENES + "/r44_cab_car.tscn")
	export_glb(cab, MEDIA + "/models/r44_cab_car.glb")
	var trailer := car(false)
	save_scene(trailer, SCENES + "/r44_trailer_car.tscn")
	var train := Node3D.new()
	train.name = "R44FiveCarSet"
	for i: int in 5:
		var path: String = (
			SCENES + ("/r44_cab_car.tscn" if i == 0 or i == 4 else "/r44_trailer_car.tscn")
		)
		var scene := load(path) as PackedScene
		var unit := scene.instantiate() as Node3D
		unit.name = "Car%02d" % (i + 1)
		unit.position.z = (2 - i) * PITCH
		if i == 4:
			unit.rotation.y = PI
		train.add_child(unit)
		unit.owner = train
		decorate(unit, i)
	CABIN.animate_train(train)
	save_scene(train, SCENES + "/r44_five_car_set.tscn")
	export_glb(train, MEDIA + "/models/r44_five_car_set.glb")
	var chart_manifest: Array[Dictionary] = []
	for chart: Dictionary in charts:
		var rect: Rect2i = chart["rect"]
		chart_manifest.append(
			{
				"name": chart["name"],
				"rect_px": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
				"padding_px": 2
			}
		)
	var file := FileAccess.open(SOURCE + "/manifest.json", FileAccess.WRITE)
	file.store_string(
		(
			JSON.stringify(
				{
					"units": "metres",
					"up": "+Y",
					"front": "+Z",
					"pivot": "rail centre, mid-consist",
					"car_pitch": PITCH,
					"cars": 5,
					"length_m": PITCH * 5,
					"width_m": 3.150,
					"height_m": 3.66,
					"textures":
					[
						"128x128 painted atlas",
						"128x64 exact livery",
						"128x128 graffiti",
						"128x128 interior"
					],
					"components": manifest,
					"uv_regions": chart_manifest
				},
				"\t"
			)
			+ "\n"
		)
	)
	cab.free()
	trailer.free()
	train.free()
	print("R44_BUILD PASS: finite indexed geometry, winding, normals, UVs, scenes and GLB exports")
	quit()


func label(image: Image, text: String, at: Vector2i, scale_px: int, ink: Color) -> void:
	for letter: int in text.length():
		var bits: String = FONT.get(text[letter], FONT[" "])
		for row: int in 5:
			for col: int in 3:
				if bits[row * 3 + col] == "1":
					image.fill_rect(
						Rect2i(
							at + Vector2i(letter * 4 + col, row) * scale_px, Vector2i.ONE * scale_px
						),
						ink
					)


func make_markings() -> void:
	var image := Image.create(128, 64, false, Image.FORMAT_RGB8)
	image.fill(Color("19272b"))
	for y: int in 28:
		for x: int in 28:
			if Vector2(x - 14, y - 14).length() < 13:
				image.set_pixel(x + 2, y + 2, Color("295477"))
	label(image, "A", Vector2i(11, 6), 4, Color("e0e0ce"))
	image.fill_rect(Rect2i(34, 2, 58, 28), Color("9aa19c"))
	label(image, "MTA", Vector2i(40, 5), 3, Color("254c63"))
	label(image, "NYC", Vector2i(45, 22), 1, Color("303d42"))
	label(image, "5408", Vector2i(3, 38), 2, Color("e1dfcf"))
	label(image, "A 8 AV", Vector2i(40, 38), 1, Color("bcc39b"))
	label(image, "LOCAL", Vector2i(40, 48), 1, Color("bcc39b"))
	for i: int in 5:
		label(image, str(5408 + i), Vector2i(2 + i * 24, 57), 1, Color("e1dfcf"))
	image.save_png(MEDIA + "/textures/r44_livery.png")
	markings = StandardMaterial3D.new()
	markings.resource_name = "R44 pixel livery - 128x64"
	markings.albedo_texture = save_texture(image, "r44_livery")
	markings.roughness = 0.9
	markings.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	markings.texture_repeat = false
	ResourceSaver.save(markings, SCENES + "/livery.tres", ResourceSaver.FLAG_CHANGE_PATH)
	markings.take_over_path(SCENES + "/livery.tres")


func make_graffiti() -> void:
	var path := MEDIA + "/textures/r44_graffiti.png"
	var image := Image.load_from_file(
		ProjectSettings.globalize_path(SOURCE + "/graffiti_source.png")
	)
	assert(image != null)
	image.convert(Image.FORMAT_RGBA8)
	image.resize(128, 128, Image.INTERPOLATE_LANCZOS)
	assert(image.detect_alpha() != Image.ALPHA_NONE, "Graffiti needs real transparency")
	image.save_png(path)
	graffiti = StandardMaterial3D.new()
	graffiti.resource_name = "Original 80s spraypaint - 128px"
	graffiti.albedo_texture = save_texture(image, "r44_graffiti")
	graffiti.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	graffiti.alpha_scissor_threshold = 0.3
	graffiti.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	graffiti.texture_repeat = false
	graffiti.roughness = 1.0
	ResourceSaver.save(graffiti, SCENES + "/graffiti.tres", ResourceSaver.FLAG_CHANGE_PATH)
	graffiti.take_over_path(SCENES + "/graffiti.tres")


func save_texture(image: Image, id: String) -> ImageTexture:
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	texture.take_over_path(MEDIA + "/textures/" + id + ".res")
	assert(
		(
			ResourceSaver.save(
				texture, MEDIA + "/textures/" + id + ".res", ResourceSaver.FLAG_CHANGE_PATH
			)
			== OK
		)
	)
	return texture


func decorate(unit: Node3D, car_index: int) -> void:
	for side: int in [-1, 1]:
		for bay: int in 3:
			var region := posmod(car_index * 3 + bay * 5 + side, 8)
			var a := Vector2(2.5 + (region % 2) * 64, 2.5 + (region / 2) * 32) / 128.0
			var b := a + Vector2(59, 27) / 128.0
			var center := Vector3(side * 1.574, 1.72, (bay - 1) * 5.0)
			var right := Vector3(0, 0, -side)
			var width := 3.35 if bay != 1 else 3.45
			var p: Array[Vector3] = [
				center - right * width / 2 + Vector3.UP * 0.42,
				center + right * width / 2 + Vector3.UP * 0.42,
				center + right * width / 2 - Vector3.UP * 0.42,
				center - right * width / 2 - Vector3.UP * 0.42
			]
			polygon(p, 0, Vector3(side, 0, 0), [a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)])
	var spray := finish(unit, "GraffitiCar%02d" % (car_index + 1), graffiti)
	spray.owner = unit.owner
	for side: int in [-1, 1]:
		decal(
			Vector3(side * 1.575, 2.75, 8.72),
			0.44,
			0.19,
			Vector3(side, 0, 0),
			Rect2(1 + car_index * 24, 55, 18, 9)
		)
	if car_index == 0 or car_index == 4:
		decal(
			Vector3(-0.95, 2.00, 11.15),
			0.55,
			0.16,
			Vector3.BACK,
			Rect2(1 + car_index * 24, 55, 18, 9)
		)
	var number := finish(unit, "NumberCar%02d" % (car_index + 1), markings)
	number.owner = unit.owner


func reset() -> void:
	vertices.clear()
	normals.clear()
	uvs.clear()
	indices.clear()


func polygon(
	points: Array[Vector3], region: int, expected: Vector3, custom: Array[Vector2] = []
) -> void:
	var normal := (points[2] - points[0]).cross(points[1] - points[0]).normalized()
	if normal.dot(expected) < 0:
		points.reverse()
		normal = -normal
	var base := vertices.size()
	var origin := Vector2(2.5 + (region % 2) * 64, 2.5 + (region / 2) * 32)
	var size_uv := Vector2(59, 27)
	var across := (points[1] - points[0]).normalized()
	var down := across.cross(normal)
	var coords: Array[Vector2] = []
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point: Vector3 in points:
		var q := Vector2(point.dot(across), point.dot(down))
		coords.append(q)
		low = low.min(q)
		high = high.max(q)
	for i: int in points.size():
		vertices.append(points[i])
		normals.append(normal)
		var tex := (origin + (coords[i] - low) / (high - low) * size_uv) / 128.0
		if not custom.is_empty():
			tex = custom[i]
		assert(tex.is_finite() and tex.x >= 0 and tex.x <= 1 and tex.y >= 0 and tex.y <= 1)
		uvs.append(tex)
	for i: int in range(1, points.size() - 1):
		assert((points[i] - points[0]).cross(points[i + 1] - points[0]).length() > 0.000001)
		indices.append_array(PackedInt32Array([base, base + i, base + i + 1]))


func box(center: Vector3, size: Vector3, region: int) -> void:
	var a := center - size / 2
	var b := center + size / 2
	polygon(
		[
			Vector3(a.x, b.y, b.z),
			Vector3(b.x, b.y, b.z),
			Vector3(b.x, a.y, b.z),
			Vector3(a.x, a.y, b.z)
		],
		region,
		Vector3.BACK
	)
	polygon(
		[
			Vector3(b.x, b.y, a.z),
			Vector3(a.x, b.y, a.z),
			Vector3(a.x, a.y, a.z),
			Vector3(b.x, a.y, a.z)
		],
		region,
		Vector3.FORWARD
	)
	polygon(
		[
			Vector3(b.x, b.y, b.z),
			Vector3(b.x, b.y, a.z),
			Vector3(b.x, a.y, a.z),
			Vector3(b.x, a.y, b.z)
		],
		region,
		Vector3.RIGHT
	)
	polygon(
		[
			Vector3(a.x, b.y, a.z),
			Vector3(a.x, b.y, b.z),
			Vector3(a.x, a.y, b.z),
			Vector3(a.x, a.y, a.z)
		],
		region,
		Vector3.LEFT
	)
	polygon(
		[
			Vector3(a.x, b.y, a.z),
			Vector3(b.x, b.y, a.z),
			Vector3(b.x, b.y, b.z),
			Vector3(a.x, b.y, b.z)
		],
		region,
		Vector3.UP
	)
	polygon(
		[
			Vector3(a.x, a.y, b.z),
			Vector3(b.x, a.y, b.z),
			Vector3(b.x, a.y, a.z),
			Vector3(a.x, a.y, a.z)
		],
		region,
		Vector3.DOWN
	)


func tube(a: Vector3, b: Vector3, radius: float, region: int, sides: int = 8) -> void:
	var axis := (b - a).normalized()
	var u := axis.cross(Vector3.UP).normalized()
	if u.length() < 0.5:
		u = Vector3.RIGHT
	var v := axis.cross(u)
	var cap_a: Array[Vector3] = []
	var cap_b: Array[Vector3] = []
	for i: int in sides:
		var offset := radius * (u * cos(TAU * i / sides) + v * sin(TAU * i / sides))
		cap_a.append(a + offset)
		cap_b.append(b + offset)
	for i: int in sides:
		var j := (i + 1) % sides
		polygon(
			[cap_a[i], cap_b[i], cap_b[j], cap_a[j]],
			region,
			((cap_a[i] + cap_a[j]) / 2 - a).normalized()
		)
	polygon(cap_a, region, -axis)
	polygon(cap_b, region, axis)


func panel(
	center: Vector3, width: float, height: float, normal: Vector3, region: int, bevel: float = 0.06
) -> void:
	var right := Vector3.RIGHT if absf(normal.z) > 0.5 else Vector3(0, 0, -normal.x)
	var points: Array[Vector3] = []
	var corners: Array[Vector2] = [
		Vector2(-width / 2 + bevel, height / 2),
		Vector2(width / 2 - bevel, height / 2),
		Vector2(width / 2, height / 2 - bevel),
		Vector2(width / 2, -height / 2 + bevel),
		Vector2(width / 2 - bevel, -height / 2),
		Vector2(-width / 2 + bevel, -height / 2),
		Vector2(-width / 2, -height / 2 + bevel),
		Vector2(-width / 2, height / 2 - bevel)
	]
	for p: Vector2 in corners:
		points.append(center + right * p.x + Vector3.UP * p.y)
	polygon(points, region, normal)


func window(center: Vector3, width: float, height: float, normal: Vector3) -> void:
	panel(center, width, height, normal, 3)
	panel(center + normal * 0.008, width - 0.07, height - 0.07, normal, 0)
	panel(center + normal * 0.016, width - 0.12, height - 0.12, normal, 4)


func finish(parent: Node3D, id: String, mat: Material = null) -> MeshInstance3D:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh_id := id
	if id.begins_with("Door"):
		mesh_id = id.left(5)
	if id.begins_with("Truck"):
		mesh_id = "Truck"
	var mesh: ArrayMesh
	if mesh_cache.has(mesh_id):
		mesh = mesh_cache[mesh_id]
	else:
		mesh = ArrayMesh.new()
		mesh.resource_name = mesh_id
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material if mat == null else mat)
		mesh.take_over_path(MEDIA + "/models/" + mesh_id + ".res")
		ResourceSaver.save(
			mesh, MEDIA + "/models/" + mesh_id + ".res", ResourceSaver.FLAG_CHANGE_PATH
		)
		mesh_cache[mesh_id] = mesh
		manifest.append(
			{
				"mesh": mesh_id,
				"triangles": indices.size() / 3,
				"vertices": vertices.size(),
				"surfaces": 1
			}
		)
	var instance := MeshInstance3D.new()
	instance.name = id
	instance.mesh = mesh
	parent.add_child(instance)
	instance.owner = parent
	reset()
	return instance


func car(has_cab: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "R44CabCar" if has_cab else "R44TrailerCar"
	var profile: Array[Vector2] = [
		Vector2(-1.4, 1.05),
		Vector2(-1.52, 1.22),
		Vector2(-1.52, 3.15),
		Vector2(-1.35, 3.5),
		Vector2(-0.85, 3.66),
		Vector2(0.85, 3.66),
		Vector2(1.35, 3.5),
		Vector2(1.52, 3.15),
		Vector2(1.52, 1.22),
		Vector2(1.4, 1.05)
	]
	var end_a: Array[Vector3] = []
	var end_b: Array[Vector3] = []
	for p: Vector2 in profile:
		end_a.append(Vector3(p.x, p.y, HALF))
		end_b.append(Vector3(p.x, p.y, -HALF))
	for i: int in profile.size():
		if i == 1 or i == 7:
			continue  # Side wall bays own the real door and window apertures.
		var j := (i + 1) % profile.size()
		var p := (profile[i] + profile[j]) / 2 - Vector2(0, 2.3)
		polygon(
			[end_a[i], end_b[i], end_b[j], end_a[j]],
			2 if i >= 2 and i <= 6 else 0,
			Vector3(p.x, p.y, 0)
		)
	polygon(end_a, 0, Vector3.BACK)
	polygon(end_b, 0, Vector3.FORWARD)
	# Chassis and equipment, attached below the continuous shell.
	box(Vector3(0, 0.99, 0), Vector3(2.64, 0.20, 21.8), 5)
	for z: float in [-3.8, 0.0, 3.7]:
		box(Vector3(0, 0.66, z), Vector3(1.8, 0.48, 2.7), 5)
		box(Vector3(0.96, 0.69, z), Vector3(0.12, 0.34, 2.4), 1)
	for z: float in [-HALF, HALF]:
		box(Vector3(0, 0.74, z), Vector3(0.26, 0.24, 0.66), 5)
		box(Vector3(0, 0.74, signf(z) * 11.32), Vector3(0.50, 0.29, 0.22), 5)
	# End hardware. Cab has broad three-part glazing and four low lamps.
	for end: int in [-1, 1]:
		var n := Vector3(0, 0, end)
		var z := end * (HALF + 0.012)
		panel(Vector3(0, 2.13, z), 0.76, 2.04, n, 3, 0.025)
		panel(Vector3(0, 2.13, z + end * 0.008), 0.70, 1.98, n, 0, 0.025)
		window(Vector3(0, 2.67, z + end * 0.018), 0.58, 0.89, n)
		if has_cab and end == 1:
			for side: int in [-1, 1]:
				window(Vector3(side * 0.95, 2.64, z), 0.92, 1.03, n)
				for dx: float in [-0.23, 0.23]:
					var centre := Vector3(side * 0.99 + dx, 1.65, z)
					tube(centre, centre + n * 0.045, 0.14, 3, 12)
					tube(
						centre + n * 0.046, centre + n * 0.053, 0.094, 6 if side * dx < 0 else 7, 12
					)
			# Angular wiper and split anti-climber safety rails.
			tube(Vector3(-1.02, 2.21, z + 0.035), Vector3(-0.76, 3.07, z + 0.038), 0.018, 3, 6)
			for side: int in [-1, 1]:
				var rail_z := z + 0.16
				tube(Vector3(side * 0.45, 1.29, z), Vector3(side * 0.45, 1.95, rail_z), 0.027, 0, 6)
				tube(
					Vector3(side * 0.45, 1.95, rail_z),
					Vector3(side * 1.27, 1.95, rail_z),
					0.027,
					0,
					6
				)
				tube(Vector3(side * 1.27, 1.95, rail_z), Vector3(side * 1.27, 1.29, z), 0.027, 0, 6)
		else:
			for side: int in [-1, 1]:
				window(Vector3(side * 0.94, 2.64, z), 0.76, 0.93, n)
				tube(Vector3(side * 0.52, 1.55, z), Vector3(side * 0.52, 2.32, z), 0.028, 0, 6)
		box(Vector3(0, 1.09, end * 11.18), Vector3(1.28, 0.12, 0.20), 5)
	finish(root, "CabShell" if has_cab else "TrailerShell")
	var cabin := CABIN.new()
	cabin.build(self, root)
	for z: float in [-7.75, 7.75]:
		truck()
		var instance := finish(root, "TruckFront" if z > 0 else "TruckRear")
		instance.position.z = z
	# Livery is original pixel lettering, not downloaded photographic material.
	for side: int in [-1, 1]:
		var n := Vector3(side, 0, 0)
		decal(Vector3(side * 1.56, 2.71, -8.77), 0.50, 0.40, n, Rect2(34, 2, 58, 28))
		decal(Vector3(side * 1.563, 2.99, 0), 1.25, 0.19, n, Rect2(37, 34, 30, 24))
	if has_cab:
		decal(Vector3(0.95, 2.66, 11.15), 0.64, 0.70, Vector3.BACK, Rect2(2, 2, 28, 28))
	finish(root, "CabLivery" if has_cab else "TrailerLivery", markings)
	for end: int in [-1, 1]:
		var marker := Marker3D.new()
		marker.name = "CouplerFront" if end > 0 else "CouplerRear"
		marker.position = Vector3(0, 0.74, end * PITCH / 2)
		root.add_child(marker)
		marker.owner = root
	return root


func truck() -> void:
	box(Vector3(0, 0.59, 0), Vector3(2.23, 0.26, 2.70), 5)
	for z: float in [-0.91, 0.91]:
		tube(Vector3(-1.14, 0.43, z), Vector3(1.14, 0.43, z), 0.09, 5)
		for side: int in [-1, 1]:
			tube(Vector3(side * 0.80, 0.43, z), Vector3(side * 1.08, 0.43, z), 0.43, 5, 12)
			tube(Vector3(side * 1.085, 0.43, z), Vector3(side * 1.10, 0.43, z), 0.30, 0, 12)
			box(Vector3(side * 1.13, 0.46, z), Vector3(0.12, 0.27, 0.35), 5)
	for side: int in [-1, 1]:
		box(Vector3(side * 1.13, 0.71, 0), Vector3(0.18, 0.26, 2.7), 5)
		for z: float in [-0.36, 0.36]:
			tube(Vector3(side * 1.16, 0.47, z), Vector3(side * 1.16, 0.65, z), 0.17, 3)


func decal(center: Vector3, width: float, height: float, normal: Vector3, rect: Rect2) -> void:
	var right := Vector3(normal.z, 0, -normal.x)
	var p: Array[Vector3] = [
		center - right * width / 2 + Vector3.UP * height / 2,
		center + right * width / 2 + Vector3.UP * height / 2,
		center + right * width / 2 - Vector3.UP * height / 2,
		center - right * width / 2 - Vector3.UP * height / 2
	]
	var a := (rect.position + Vector2(0.5, 0.5)) / Vector2(128, 64)
	var b := (rect.end - Vector2(0.5, 0.5)) / Vector2(128, 64)
	polygon(p, 0, normal, [a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)])


func save_scene(node: Node3D, path: String) -> void:
	var scene := PackedScene.new()
	assert(scene.pack(node) == OK)
	assert(ResourceSaver.save(scene, path) == OK)


func export_glb(node: Node3D, path: String) -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var portable := node.duplicate() as Node3D
	CABIN.flatten_grids(portable)
	assert(document.append_from_scene(portable, state) == OK)
	assert(document.write_to_filesystem(state, path) == OK)
	portable.free()


func make_interior(charts: Array[Dictionary]) -> void:
	var path := MEDIA + "/textures/r44_interior.png"
	if not FileAccess.file_exists(path):
		var source := Image.load_from_file(
			ProjectSettings.globalize_path(SOURCE + "/interior_source.png")
		)
		assert(source != null)
		UV.prepare_albedo(source, charts).save_png(path)
	interior = StandardMaterial3D.new()
	interior.resource_name = "R44 worn wood and molded seats - 128px"
	interior.albedo_texture = save_texture(
		Image.load_from_file(ProjectSettings.globalize_path(path)), "r44_interior"
	)
	interior.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	interior.texture_repeat = false
	interior.roughness = 0.94
	interior.take_over_path(SCENES + "/interior.tres")
	ResourceSaver.save(interior, interior.resource_path)
	glass = StandardMaterial3D.new()
	glass.resource_name = "R44 dusty transparent glazing"
	glass.albedo_color = Color(0.20, 0.30, 0.29, 0.22)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.roughness = 0.85
	glass.take_over_path(SCENES + "/glass.tres")
	ResourceSaver.save(glass, glass.resource_path)
	lamp = StandardMaterial3D.new()
	lamp.resource_name = "R44 fluorescent diffuser"
	lamp.albedo_color = Color("ced5ba")
	lamp.emission_enabled = true
	lamp.emission = Color("bbc9a8")
	lamp.emission_energy_multiplier = 0.45
	lamp.take_over_path(SCENES + "/lamp.tres")
	ResourceSaver.save(lamp, lamp.resource_path)
