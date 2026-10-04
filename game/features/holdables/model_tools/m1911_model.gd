extends RefCounted
## Authoritative M1911-inspired profiles, animation pivots and named UV regions.

const PROP := preload("res://features/procedural_rooms/model_tools/prop_model.gd")
const PIVOTS := {
	"Frame": Vector3.ZERO,
	"Slide": Vector3.ZERO,
	"Barrel": Vector3(0, 0.061, -0.054),
	"Magazine": Vector3.ZERO,
	"Hammer": Vector3(0, 0.052, 0.039)
}


static func definition() -> Dictionary:
	var faces: Array[Dictionary] = []
	_profile(
		faces,
		"Frame",
		"FRAME",
		[
			Vector2(-.150, .032),
			Vector2(-.146, .027),
			Vector2(-.068, .027),
			Vector2(-.047, .011),
			Vector2(-.032, -.061),
			Vector2(.036, -.069),
			Vector2(.033, -.053),
			Vector2(.012, .018),
			Vector2(.041, .028),
			Vector2(.052, .026),
			Vector2(.055, .034),
			Vector2(.043, .047),
			Vector2(-.146, .047)
		],
		.0145
	)
	_profile(
		faces,
		"Frame",
		"GRIP",
		[Vector2(-.030, -.057), Vector2(.026, -.064), Vector2(.004, .020), Vector2(-.037, .013)],
		.0175
	)
	_guard(faces)
	_profile(
		faces,
		"Frame",
		"TRIGGER",
		[
			Vector2(-.052, .022),
			Vector2(-.044, .022),
			Vector2(-.047, .002),
			Vector2(-.043, -.004),
			Vector2(-.050, -.006),
			Vector2(-.055, .001)
		],
		.007
	)
	var section: Array[Vector2] = [
		Vector2(-.014, .049),
		Vector2(.014, .049),
		Vector2(.014, .067),
		Vector2(.009, .075),
		Vector2(-.009, .075),
		Vector2(-.014, .067)
	]
	_slide(faces, "SLIDE_FRONT", section, -.166, -.068)
	_slide(faces, "SLIDE_REAR", section, -.038, .042)
	var port: Array[Vector2] = [
		Vector2(-.014, .049),
		Vector2(.014, .049),
		Vector2(.014, .058),
		Vector2(.003, .058),
		Vector2(.003, .070),
		Vector2(-.003, .075),
		Vector2(-.009, .075),
		Vector2(-.014, .067)
	]
	_slide(faces, "SLIDE_PORT", port, -.068, -.038)
	for z: float in [-.068, -.038]:
		var bridge: Array[Vector3] = [
			Vector3(.003, .058, z),
			Vector3(.014, .058, z),
			Vector3(.014, .067, z),
			Vector3(.009, .075, z),
			Vector3(-.003, .075, z),
			Vector3(.003, .070, z)
		]
		if z < -.05:
			bridge.reverse()
		_face(faces, "Slide", "PORT_END", bridge, "METAL_SMALL", .4)
	_tube(
		faces,
		"Barrel",
		"BARREL",
		Vector3(0, .061, 0),
		[Vector2(-.038, .009), Vector2(-.070, .009), Vector2(-.153, .008), Vector2(-.167, .008)],
		"BARREL_WRAP",
		true
	)
	_tube(
		faces,
		"Slide",
		"SPRING_PLUG",
		Vector3(0, .041, 0),
		[Vector2(-.147, .005), Vector2(-.163, .005)],
		"METAL_SMALL",
		false
	)
	# The chamber remains exposed behind the barrel when the slide retracts.
	_box(
		faces,
		"Barrel",
		"CHAMBER",
		Vector3(0, .061, -.024),
		Vector3(.018, .018, .028),
		"METAL_SMALL"
	)
	_box(
		faces,
		"Slide",
		"FRONT_SIGHT",
		Vector3(0, .077, -.148),
		Vector3(.003, .005, .010),
		"DARK_SMALL"
	)
	_box(
		faces,
		"Slide",
		"REAR_SIGHT_BASE",
		Vector3(0, .077, .031),
		Vector3(.016, .004, .010),
		"DARK_SMALL"
	)
	for x: float in [-.0055, .0055]:
		_box(
			faces,
			"Slide",
			"REAR_SIGHT_EAR",
			Vector3(x, .081, .032),
			Vector3(.005, .005, .008),
			"DARK_SMALL"
		)
	_box(
		faces,
		"Frame",
		"SLIDE_STOP",
		Vector3(-.0165, .038, -.040),
		Vector3(.005, .004, .026),
		"METAL_SMALL"
	)
	_box(
		faces,
		"Frame",
		"SAFETY",
		Vector3(-.0165, .040, .024),
		Vector3(.005, .005, .016),
		"METAL_SMALL"
	)
	_box(
		faces,
		"Frame",
		"MAG_RELEASE",
		Vector3(-.017, .014, -.029),
		Vector3(.006, .007, .007),
		"METAL_SMALL"
	)
	_profile(
		faces,
		"Hammer",
		"HAMMER",
		[
			Vector2(.031, .049),
			Vector2(.049, .049),
			Vector2(.054, .060),
			Vector2(.044, .067),
			Vector2(.029, .061)
		],
		.004
	)
	_profile(
		faces,
		"Magazine",
		"MAGAZINE",
		[Vector2(-.028, -.066), Vector2(.027, -.073), Vector2(.004, .018), Vector2(-.036, .010)],
		.011
	)
	_box(
		faces,
		"Magazine",
		"MAG_BASE",
		Vector3(0, -.070, .003),
		Vector3(.033, .006, .061),
		"DARK_SMALL"
	)
	var result := PROP.pack_faces(faces, 1000.0)
	# These shells are viewed from inside through the open ejection port.
	# Reverse the existing triangles with their UVs intact, including skin views.
	var interiors: Array[Dictionary] = []
	for face: Dictionary in faces:
		if face["part"] not in ["Slide", "Barrel"]:
			continue
		var inside := face.duplicate(true)
		var points: PackedVector3Array = inside["points"]
		var coordinates: PackedVector2Array = inside["uv_m"]
		points.reverse()
		coordinates.reverse()
		inside["points"] = points
		inside["uv_m"] = coordinates
		inside["normal"] = -face["normal"]
		interiors.append(inside)
	faces.append_array(interiors)
	result["pivots"] = PIVOTS
	return result


static func _profile(
	faces: Array[Dictionary], part: String, id: String, profile: Array[Vector2], half_width: float
) -> void:
	var pieces: Array[Dictionary] = []
	PROP.add_prism(pieces, id, profile, half_width)
	for piece: Dictionary in pieces:
		var key := id + "_EDGE"
		var importance := .45
		if String(piece["name"]).ends_with("LEFT") or String(piece["name"]).ends_with("RIGHT"):
			key = piece["name"]
			importance = 1.4 if id == "FRAME" else 1.0
		if id in ["TRIGGER", "HAMMER", "MAGAZINE"]:
			key = "DARK_SMALL" if id == "MAGAZINE" else "METAL_SMALL"
			importance = .6
		var points: Array[Vector3] = []
		points.assign(piece["points"])
		_face(faces, part, piece["name"], points, key, importance)


static func _slide(
	faces: Array[Dictionary], id: String, section: Array[Vector2], front: float, rear: float
) -> void:
	var front_cap: Array[Vector3] = []
	var rear_cap: Array[Vector3] = []
	for point: Vector2 in section:
		front_cap.append(Vector3(point.x, point.y, front))
		rear_cap.push_front(Vector3(point.x, point.y, rear))
	if id == "SLIDE_FRONT":
		var perimeter: Array[Vector2] = []
		for index: int in section.size():
			perimeter.append(section[index])
			perimeter.append((section[index] + section[(index + 1) % section.size()]) * .5)
		for index: int in perimeter.size():
			var a := perimeter[index]
			var b := perimeter[(index + 1) % perimeter.size()]
			var inside_a := Vector2(0, .061) + (a - Vector2(0, .061)).normalized() * .009
			var inside_b := Vector2(0, .061) + (b - Vector2(0, .061)).normalized() * .009
			_face(
				faces,
				"Slide",
				"FRONT_RING",
				[
					Vector3(a.x, a.y, front),
					Vector3(b.x, b.y, front),
					Vector3(inside_b.x, inside_b.y, front),
					Vector3(inside_a.x, inside_a.y, front)
				],
				"METAL_SMALL",
				.5
			)
	if id == "SLIDE_REAR":
		_face(faces, "Slide", "REAR_CAP", rear_cap, "DARK_SMALL", .5)
	for index: int in section.size():
		var a := section[index]
		var b := section[(index + 1) % section.size()]
		var key := "SLIDE_TOP"
		if index == 1:
			key = id + "_RIGHT"
		elif index == section.size() - 1:
			key = id + "_LEFT"
		elif index == 0:
			key = "METAL_SMALL"
		_face(
			faces,
			"Slide",
			id + "_%d" % index,
			[
				Vector3(a.x, a.y, rear),
				Vector3(b.x, b.y, rear),
				Vector3(b.x, b.y, front),
				Vector3(a.x, a.y, front)
			],
			key,
			1.4 if "RIGHT" in key or "LEFT" in key else .6
		)
		if key == "SLIDE_REAR_RIGHT":
			faces[-1]["flip_x"] = true


static func _guard(faces: Array[Dictionary]) -> void:
	var outer: Array[Vector2] = [
		Vector2(-.077, .027),
		Vector2(-.027, .027),
		Vector2(-.022, .020),
		Vector2(-.026, -.010),
		Vector2(-.034, -.015),
		Vector2(-.064, -.015),
		Vector2(-.075, -.005),
		Vector2(-.080, .018)
	]
	var inner: Array[Vector2] = [
		Vector2(-.072, .022),
		Vector2(-.032, .022),
		Vector2(-.029, .018),
		Vector2(-.031, -.006),
		Vector2(-.036, -.009),
		Vector2(-.061, -.009),
		Vector2(-.069, -.002),
		Vector2(-.074, .016)
	]
	for index: int in 8:
		var next := (index + 1) % 8
		for x: float in [-.008, .008]:
			var points: Array[Vector3] = [
				Vector3(x, outer[index].y, outer[index].x),
				Vector3(x, outer[next].y, outer[next].x),
				Vector3(x, inner[next].y, inner[next].x),
				Vector3(x, inner[index].y, inner[index].x)
			]
			if x > 0:
				points.reverse()
			_face(faces, "Frame", "GUARD_RING", points, "METAL_SMALL", .5)
		for outline: Array[Vector2] in [outer, inner]:
			var a := outline[index]
			var b := outline[next]
			var points: Array[Vector3] = [
				Vector3(-.008, a.y, a.x),
				Vector3(.008, a.y, a.x),
				Vector3(.008, b.y, b.x),
				Vector3(-.008, b.y, b.x)
			]
			if outline == inner:
				points.reverse()
			_face(faces, "Frame", "GUARD_WALL", points, "METAL_SMALL", .5)


static func _tube(
	faces: Array[Dictionary],
	part: String,
	id: String,
	center: Vector3,
	rings: Array[Vector2],
	key: String,
	hollow: bool
) -> void:
	var count := 12
	var circumference := TAU * rings[0].y
	var length := absf(rings[-1].x - rings[0].x)
	for ring: int in rings.size() - 1:
		for index: int in count:
			var a := TAU * index / count
			var b := TAU * (index + 1) / count
			var points: Array[Vector3] = [
				center + Vector3(cos(a) * rings[ring].y, sin(a) * rings[ring].y, rings[ring].x),
				center + Vector3(cos(b) * rings[ring].y, sin(b) * rings[ring].y, rings[ring].x),
				(
					center
					+ Vector3(
						cos(b) * rings[ring + 1].y, sin(b) * rings[ring + 1].y, rings[ring + 1].x
					)
				),
				(
					center
					+ Vector3(
						cos(a) * rings[ring + 1].y, sin(a) * rings[ring + 1].y, rings[ring + 1].x
					)
				)
			]
			_face(faces, part, id + "_WALL", points, key, .9)
			if key == "BARREL_WRAP":
				faces[-1]["size_m"] = Vector2(length, circumference)
				faces[-1]["uv_m"] = PackedVector2Array(
					[
						Vector2(absf(rings[ring].x - rings[0].x), circumference * index / count),
						Vector2(
							absf(rings[ring].x - rings[0].x), circumference * (index + 1) / count
						),
						Vector2(
							absf(rings[ring + 1].x - rings[0].x),
							circumference * (index + 1) / count
						),
						Vector2(absf(rings[ring + 1].x - rings[0].x), circumference * index / count)
					]
				)
	var end := rings[-1]
	var inner_radius := end.y * .65 if hollow else 0.0
	for index: int in count:
		var a := TAU * index / count
		var b := TAU * (index + 1) / count
		var outer_a := center + Vector3(cos(a) * end.y, sin(a) * end.y, end.x)
		var outer_b := center + Vector3(cos(b) * end.y, sin(b) * end.y, end.x)
		var inner_a := center + Vector3(cos(a) * inner_radius, sin(a) * inner_radius, end.x)
		var inner_b := center + Vector3(cos(b) * inner_radius, sin(b) * inner_radius, end.x)
		if hollow:
			_face(faces, part, id + "_RIM", [outer_a, outer_b, inner_b, inner_a], "METAL_SMALL", .7)
			_face(
				faces,
				part,
				id + "_BORE",
				[inner_b, inner_a, inner_a + Vector3(0, 0, .018), inner_b + Vector3(0, 0, .018)],
				"DARK_SMALL",
				.4
			)
		else:
			_face(
				faces,
				part,
				id + "_CAP",
				[outer_a, outer_b, center + Vector3(0, 0, end.x)],
				"METAL_SMALL",
				.4
			)


static func _box(
	faces: Array[Dictionary], part: String, id: String, center: Vector3, size: Vector3, key: String
) -> void:
	var pieces: Array[Dictionary] = []
	PROP.add_prism(
		pieces,
		id,
		[
			Vector2(-size.z / 2, -size.y / 2),
			Vector2(size.z / 2, -size.y / 2),
			Vector2(size.z / 2, size.y / 2),
			Vector2(-size.z / 2, size.y / 2)
		],
		size.x / 2
	)
	for piece: Dictionary in pieces:
		var points: Array[Vector3] = []
		for point: Vector3 in piece["points"]:
			points.append(point + center)
		_face(faces, part, id, points, key, .6)


static func _face(
	faces: Array[Dictionary],
	part: String,
	id: String,
	points: Array[Vector3],
	key: String,
	weight: float
) -> void:
	var pivot: Vector3 = PIVOTS[part]
	for index: int in points.size():
		points[index] -= pivot
	PROP.add_face(faces, id, points)
	faces[-1]["part"] = part
	faces[-1]["reuse_key"] = key
	faces[-1]["importance"] = weight
