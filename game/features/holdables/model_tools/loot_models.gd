extends RefCounted
## Deterministic exterior geometry, explicit reuse groups and the shared native UV packer.

const UV := preload("res://features/procedural_rooms/model_tools/prop_model.gd")


static func definition(kind: String) -> Dictionary:
	var faces: Array[Dictionary] = []
	match kind:
		"dumpster":
			_dumpster(faces)
		"scrap":
			_scrap(faces)
		"wallet":
			_wallet(faces)
	var data := UV.pack_faces(faces)
	data["kind"] = kind
	return data


## Split the closed atlas into a hollow body and a lid at a rear hinge.
## Reuse the existing packed rectangles so the painted atlas never moves.
static func dumpster_parts(data: Dictionary) -> Dictionary:
	var body: Array[Dictionary] = []
	var lid: Array[Dictionary] = []
	var interior: Array[Dictionary] = []
	var templates: Dictionary[String, Dictionary] = {}
	for face: Dictionary in data["faces"]:
		templates[face["name"]] = face
		if face["name"] in ["BIN_2", "BIN_3", "BIN_4"]:
			lid.append(face.duplicate(true))
		elif face["name"] not in ["BIN_LEFT", "BIN_RIGHT"]:
			body.append(face.duplicate(true))
	var shell: Array[Dictionary] = []
	UV.add_prism(
		shell,
		"BIN",
		[Vector2(-.6, .14), Vector2(.6, .14), Vector2(.7, 1.43), Vector2(-.7, 1.43)],
		1.2
	)
	for face: Dictionary in shell:
		if face["name"] in ["BIN_LEFT", "BIN_RIGHT"]:
			body.append(_map_face(face, templates[face["name"]]))
		if face["name"] == "BIN_2":
			continue
		var points: Array[Vector3] = []
		for point: Vector3 in face["points"]:
			points.push_front(Vector3(point.x * .96, maxf(point.y, .22), point.z * .94))
		var inside: Array[Dictionary] = []
		UV.add_face(inside, "INTERIOR", points)
		var template: Dictionary = templates[face["name"] if face["name"] != "BIN_3" else "BIN_5"]
		interior.append(_map_face(inside[0], template))
	var cover: Array[Dictionary] = []
	UV.add_prism(
		cover,
		"COVER",
		[Vector2(-.7, 1.43), Vector2(.7, 1.43), Vector2(.73, 1.6), Vector2(-.73, 1.6)],
		1.2
	)
	for face: Dictionary in cover:
		if face["name"] in ["COVER_LEFT", "COVER_RIGHT"]:
			lid.append(_map_face(face, templates["BIN_LEFT"]))
		elif face["name"] == "COVER_0":
			lid.append(_map_face(face, templates["BIN_3"]))
	# Thin rim joins the outer and inner shells without sealing the opening.
	var outer := [
		Vector3(-1.2, 1.43, -.7),
		Vector3(-1.2, 1.43, .7),
		Vector3(1.2, 1.43, .7),
		Vector3(1.2, 1.43, -.7)
	]
	for index: int in 4:
		var a: Vector3 = outer[index]
		var b: Vector3 = outer[(index + 1) % 4]
		var rim: Array[Dictionary] = []
		UV.add_face(
			rim,
			"RIM",
			[b, a, Vector3(a.x * .96, a.y, a.z * .94), Vector3(b.x * .96, b.y, b.z * .94)]
		)
		body.append(_map_face(rim[0], templates["BIN_1"]))
	for face: Dictionary in lid:
		face["points"] = Transform3D(Basis.IDENTITY, -Vector3(0, 1.43, -.7)) * face["points"]
	return {
		"body": UV.mesh({"faces": body, "density": data["density"]}),
		"lid": UV.mesh({"faces": lid, "density": data["density"]}),
		"interior": UV.mesh({"faces": interior, "density": data["density"]})
	}


static func _map_face(face: Dictionary, source: Dictionary) -> Dictionary:
	for key: String in ["island", "rect", "rotated", "weight"]:
		face[key] = source[key]
	# Fit reused artwork within the original island even for a longer rim edge.
	var fit := minf(
		source["size_m"].x / maxf(face["size_m"].x, .001),
		source["size_m"].y / maxf(face["size_m"].y, .001)
	)
	face["uv_m"] = Transform2D(0, Vector2.ONE * minf(fit, 1.0), 0, Vector2.ZERO) * face["uv_m"]
	face["size_m"] *= minf(fit, 1.0)
	return face


static func _dumpster(faces: Array[Dictionary]) -> void:
	UV.add_prism(
		faces,
		"BIN",
		[
			Vector2(-.6, .14),
			Vector2(.6, .14),
			Vector2(.7, 1.43),
			Vector2(.73, 1.6),
			Vector2(-.73, 1.6),
			Vector2(-.7, 1.43)
		],
		1.2
	)
	for face: Dictionary in faces:
		match face["name"]:
			"BIN_LEFT", "BIN_RIGHT":
				face["reuse_key"] = "SIDE_PANEL"
			"BIN_1", "BIN_5":
				face["reuse_key"] = "GREEN_BODY"
			"BIN_3":
				face["reuse_key"] = "RIBBED_LID"
				face["importance"] = .85
			"BIN_0":
				face["reuse_key"] = "UNDERSIDE"
				face["importance"] = .2
			_:
				face["reuse_key"] = "LID_EDGE"
				face["importance"] = .6
	for side: int in [-1, 1]:
		var handle: Array[Dictionary] = []
		UV.add_prism(
			handle,
			"HANDLE",
			[Vector2(-.25, .94), Vector2(.25, .94), Vector2(.25, 1.02), Vector2(-.25, 1.02)],
			.025
		)
		_transform(handle, Transform3D(Basis.IDENTITY, Vector3(side * 1.21, 0, 0)), "DARK_METAL")
		faces.append_array(handle)
		for z: float in [-.5, .5]:
			var wheel: Array[Dictionary] = []
			UV.add_cylinder(wheel, "CASTOR", .14, .12)
			_transform(
				wheel,
				Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(side * 1.08, .14, z)),
				"RUBBER"
			)
			faces.append_array(wheel)


static func _scrap(faces: Array[Dictionary]) -> void:
	UV.add_prism(
		faces,
		"PLATE",
		[
			Vector2(-.07, -.015),
			Vector2(0, -.015),
			Vector2(.09, .045),
			Vector2(.09, .06),
			Vector2(0, 0),
			Vector2(-.07, 0)
		],
		.09
	)
	for face: Dictionary in faces:
		face["reuse_key"] = "RUSTED_SHEET"
	var nut: Array[Dictionary] = []
	var segments := 8
	for index: int in segments:
		var a := index * TAU / segments
		var b := (index + 1) * TAU / segments
		var outer_a := Vector3(cos(a) * .035, .018, sin(a) * .035)
		var outer_b := Vector3(cos(b) * .035, .018, sin(b) * .035)
		var inner_a := Vector3(cos(a) * .016, .018, sin(a) * .016)
		var inner_b := Vector3(cos(b) * .016, .018, sin(b) * .016)
		UV.add_face(nut, "NUT_TOP", [outer_a, outer_b, inner_b, inner_a])
		UV.add_face(
			nut,
			"NUT_BOTTOM",
			[
				Vector3(inner_a.x, 0, inner_a.z),
				Vector3(inner_b.x, 0, inner_b.z),
				Vector3(outer_b.x, 0, outer_b.z),
				Vector3(outer_a.x, 0, outer_a.z)
			]
		)
		UV.add_face(
			nut,
			"NUT_OUTER",
			[outer_b, outer_a, Vector3(outer_a.x, 0, outer_a.z), Vector3(outer_b.x, 0, outer_b.z)]
		)
		UV.add_face(
			nut,
			"NUT_INNER",
			[inner_a, inner_b, Vector3(inner_b.x, 0, inner_b.z), Vector3(inner_a.x, 0, inner_a.z)]
		)
	_transform(nut, Transform3D(Basis(Vector3.UP, .4), Vector3(-.04, .002, -.033)), "BOLTED_STEEL")
	faces.append_array(nut)
	var bolt: Array[Dictionary] = []
	UV.add_cylinder(bolt, "BOLT", .011, .075)
	_transform(
		bolt, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(.045, .018, -.045)), "BOLTED_STEEL"
	)
	faces.append_array(bolt)


static func _wallet(faces: Array[Dictionary]) -> void:
	UV.add_prism(
		faces,
		"WALLET",
		[
			Vector2(-.045, -.01),
			Vector2(.045, -.01),
			Vector2(.045, .01),
			Vector2(.039, .015),
			Vector2(-.039, .015),
			Vector2(-.045, .01)
		],
		.06
	)
	for face: Dictionary in faces:
		match face["name"]:
			"WALLET_3":
				face["reuse_key"] = "STITCHED_LEATHER"
			"WALLET_0":
				face["reuse_key"] = "BACK_LEATHER"
				face["importance"] = .55
			_:
				face["reuse_key"] = "FOLDED_EDGES"
				face["importance"] = .7
	var strap: Array[Dictionary] = []
	UV.add_prism(
		strap,
		"STRAP",
		[Vector2(-.04, .015), Vector2(.018, .015), Vector2(.018, .020), Vector2(-.04, .020)],
		.009
	)
	_transform(strap, Transform3D(Basis.IDENTITY, Vector3(.029, 0, 0)), "STRAP_LEATHER")
	faces.append_array(strap)
	var snap: Array[Dictionary] = []
	UV.add_cylinder(snap, "SNAP", .004, .002)
	_transform(snap, Transform3D(Basis.IDENTITY, Vector3(.029, .020, .012)), "BRASS_SNAP")
	faces.append_array(snap)


static func _transform(faces: Array[Dictionary], transform: Transform3D, reuse_key: String) -> void:
	for face: Dictionary in faces:
		face["points"] = transform * face["points"]
		face["normal"] = transform.basis * face["normal"]
		face["reuse_key"] = reuse_key
