extends RefCounted
## Metre-scale authored profiles: MP5, M4A4 and AK-47 share UV tooling, not shapes.

const PROP := preload("res://features/procedural_rooms/model_tools/prop_model.gd")
const PARTS: Array[String] = ["Frame", "Bolt", "Magazine", "ChargingHandle"]


static func definition(kind: String) -> Dictionary:
	var faces: Array[Dictionary] = []
	match kind:
		"mp5":
			_mp5(faces)
		"m4a4":
			_m4(faces)
		"ak47":
			_ak(faces)
	_grip(faces, kind)
	var result := PROP.pack_faces(faces, 600.0)
	# Interior surfaces stay visible during bolt travel and through the sight hood.
	var interiors: Array[Dictionary] = []
	for face: Dictionary in faces:
		if face.get("interior", false):
			var inside := face.duplicate(true)
			var points: PackedVector3Array = inside["points"]
			var uv: PackedVector2Array = inside["uv_m"]
			points.reverse()
			uv.reverse()
			inside["points"] = points
			inside["uv_m"] = uv
			inside["normal"] = -face["normal"]
			interiors.append(inside)
	faces.append_array(interiors)
	return result


static func _mp5(f: Array[Dictionary]) -> void:
	_profile(
		f,
		"Frame",
		"RECEIVER",
		[
			Vector2(-.175, .028),
			Vector2(.070, .028),
			Vector2(.084, .060),
			Vector2(.074, .082),
			Vector2(-.165, .082)
		],
		.021
	)
	_tube(f, "Frame", "COCKING_TUBE", Vector3(0, .083, 0), -.165, -.303, .009, "METAL")
	_profile(
		f,
		"Frame",
		"STOCK",
		[
			Vector2(.064, .025),
			Vector2(.27, -.027),
			Vector2(.32, -.022),
			Vector2(.32, .081),
			Vector2(.073, .083)
		],
		.025
	)
	_profile(
		f,
		"Frame",
		"HANDGUARD",
		[Vector2(-.303, .029), Vector2(-.178, .013), Vector2(-.169, .063), Vector2(-.295, .072)],
		.030
	)
	_profile(
		f,
		"Magazine",
		"MAGAZINE",
		[
			Vector2(-.154, .031),
			Vector2(-.099, .031),
			Vector2(-.099, -.04),
			Vector2(-.11, -.093),
			Vector2(-.139, -.159),
			Vector2(-.185, -.143),
			Vector2(-.159, -.080)
		],
		.012
	)
	_tube(f, "Frame", "BARREL", Vector3(0, .052, 0), -.290, -.337, .008, "METAL", true)
	_tube(f, "Frame", "FRONT_HOOD", Vector3(0, .099, 0), -.294, -.307, .014, "DARK", true)
	_box(f, "Frame", "FRONT_POST", Vector3(0, .096, -.300), Vector3(.004, .022, .008), "DARK")
	_box(f, "Frame", "SIGHT_BASE", Vector3(0, .083, -.300), Vector3(.030, .035, .018), "METAL")
	_tube(f, "Frame", "REAR_DRUM", Vector3(0, .102, 0), .052, .035, .014, "DARK", true)
	_box(f, "Bolt", "BOLT", Vector3(.022, .061, -.092), Vector3(.004, .029, .058), "METAL")
	_box(
		f,
		"ChargingHandle",
		"COCKING_HANDLE",
		Vector3(-.032, .080, -.248),
		Vector3(.042, .012, .020),
		"METAL"
	)
	_box(f, "Frame", "SELECTOR", Vector3(-.025, .032, .022), Vector3(.008, .009, .028), "DARK")
	_box(f, "Frame", "MAG_RELEASE", Vector3(0, .008, -.087), Vector3(.015, .026, .012), "METAL")


static func _m4(f: Array[Dictionary]) -> void:
	_profile(
		f,
		"Frame",
		"RECEIVER",
		[
			Vector2(-.155, .020),
			Vector2(.087, .020),
			Vector2(.089, .088),
			Vector2(.056, .104),
			Vector2(-.153, .104)
		],
		.024
	)
	_profile(
		f,
		"Frame",
		"STOCK",
		[
			Vector2(.108, .032),
			Vector2(.256, -.028),
			Vector2(.292, -.027),
			Vector2(.292, .098),
			Vector2(.193, .100),
			Vector2(.156, .073),
			Vector2(.108, .067)
		],
		.027
	)
	_tube(f, "Frame", "BUFFER", Vector3(0, .067, 0), .095, .219, .015, "METAL")
	_box(f, "Frame", "BUTTPAD", Vector3(0, .033, .292), Vector3(.055, .13, .010), "DARK")
	_profile(
		f,
		"Frame",
		"HANDGUARD",
		[Vector2(-.355, .036), Vector2(-.155, .029), Vector2(-.155, .092), Vector2(-.355, .092)],
		.027
	)
	for z: float in [-.338, -.313, -.288, -.263, -.238, -.213, -.188, -.163]:
		_box(f, "Frame", "RAIL", Vector3(0, .108, z), Vector3(.040, .010, .012), "METAL")
		for x: float in [-.032, .032]:
			_box(f, "Frame", "SIDE_RAIL", Vector3(x, .057, z), Vector3(.011, .020, .013), "DARK")
	_box(f, "Frame", "TOP_RAIL", Vector3(0, .105, -.025), Vector3(.035, .012, .24), "METAL")
	_profile(
		f,
		"Magazine",
		"MAGAZINE",
		[
			Vector2(-.133, .025),
			Vector2(-.067, .025),
			Vector2(-.069, -.065),
			Vector2(-.094, -.152),
			Vector2(-.151, -.145),
			Vector2(-.128, -.058)
		],
		.013
	)
	_tube(f, "Frame", "BARREL", Vector3(0, .068, 0), -.352, -.49, .008, "METAL")
	_tube(f, "Frame", "FLASH_HIDER", Vector3(0, .068, 0), -.481, -.526, .012, "METAL", true)
	_profile(
		f,
		"Frame",
		"FRONT_SIGHT",
		[Vector2(-.386, .071), Vector2(-.357, .071), Vector2(-.365, .145), Vector2(-.378, .145)],
		.006,
		"METAL"
	)
	_box(f, "Frame", "FRONT_POST", Vector3(0, .150, -.372), Vector3(.004, .014, .007), "DARK")
	_box(f, "Frame", "REAR_SIGHT_BASE", Vector3(0, .115, .058), Vector3(.042, .009, .017), "DARK")
	_box(f, "Frame", "REAR_SIGHT_LEFT", Vector3(-.015, .13, .058), Vector3(.01, .025, .017), "DARK")
	_box(f, "Frame", "REAR_SIGHT_RIGHT", Vector3(.015, .13, .058), Vector3(.01, .025, .017), "DARK")
	_box(f, "Bolt", "BOLT", Vector3(.025, .074, -.056), Vector3(.006, .032, .061), "METAL")
	_box(
		f, "Frame", "FORWARD_ASSIST", Vector3(.033, .073, .041), Vector3(.024, .017, .024), "METAL"
	)
	_box(
		f,
		"ChargingHandle",
		"CHARGING_HANDLE",
		Vector3(0, .103, .090),
		Vector3(.056, .012, .020),
		"METAL"
	)
	_box(f, "Frame", "MAG_BUTTON", Vector3(.028, .033, -.09), Vector3(.009, .011, .015), "METAL")


static func _ak(f: Array[Dictionary]) -> void:
	_profile(
		f,
		"Frame",
		"RECEIVER",
		[
			Vector2(-.182, .018),
			Vector2(.099, .018),
			Vector2(.112, .076),
			Vector2(.084, .107),
			Vector2(-.177, .107)
		],
		.024
	)
	_profile(
		f,
		"Frame",
		"STOCK",
		[
			Vector2(.098, .028),
			Vector2(.280, -.025),
			Vector2(.322, -.023),
			Vector2(.322, .092),
			Vector2(.135, .080),
			Vector2(.100, .069)
		],
		.026
	)
	_profile(
		f,
		"Frame",
		"HANDGUARD",
		[Vector2(-.323, .030), Vector2(-.18, .017), Vector2(-.18, .071), Vector2(-.313, .071)],
		.030
	)
	_profile(
		f,
		"Frame",
		"UPPER_WOOD",
		[Vector2(-.312, .082), Vector2(-.181, .082), Vector2(-.181, .105), Vector2(-.31, .105)],
		.019,
		"WOOD"
	)
	_profile(
		f,
		"Magazine",
		"MAGAZINE",
		[
			Vector2(-.156, .025),
			Vector2(-.083, .025),
			Vector2(-.085, -.055),
			Vector2(-.114, -.118),
			Vector2(-.160, -.18),
			Vector2(-.225, -.154),
			Vector2(-.171, -.099),
			Vector2(-.15, -.045)
		],
		.015
	)
	_tube(f, "Frame", "BARREL", Vector3(0, .061, 0), -.309, -.514, .009, "METAL", true)
	_tube(f, "Frame", "GAS_TUBE", Vector3(0, .104, 0), -.185, -.385, .010, "METAL")
	_box(f, "Frame", "GAS_BLOCK", Vector3(0, .084, -.378), Vector3(.030, .055, .031), "METAL")
	_profile(
		f,
		"Frame",
		"FRONT_SIGHT",
		[Vector2(-.483, .068), Vector2(-.459, .068), Vector2(-.463, .135), Vector2(-.480, .135)],
		.008,
		"METAL"
	)
	for x: float in [-.012, .012]:
		_box(f, "Frame", "SIGHT_EAR", Vector3(x, .140, -.472), Vector3(.006, .032, .020), "DARK")
	_box(f, "Frame", "FRONT_POST", Vector3(0, .141, -.472), Vector3(.004, .020, .007), "DARK")
	_box(f, "Frame", "REAR_SIGHT", Vector3(0, .117, -.177), Vector3(.039, .018, .030), "METAL")
	_box(f, "Bolt", "BOLT", Vector3(.024, .083, -.080), Vector3(.006, .026, .105), "METAL")
	_box(f, "Bolt", "BOLT_HANDLE", Vector3(.043, .080, -.031), Vector3(.038, .012, .015), "METAL")
	_box(
		f,
		"ChargingHandle",
		"HANDLE",
		Vector3(.047, .080, -.031),
		Vector3(.021, .012, .015),
		"METAL"
	)
	_profile(
		f,
		"Frame",
		"SAFETY",
		[Vector2(-.035, .032), Vector2(.077, .039), Vector2(.079, .049), Vector2(-.035, .042)],
		.029,
		"METAL"
	)
	_box(f, "Frame", "BUTTPAD", Vector3(0, .034, .323), Vector3(.054, .12, .005), "METAL")


static func _grip(f: Array[Dictionary], kind: String) -> void:
	_profile(
		f,
		"Frame",
		"GRIP",
		[
			Vector2(-.030, -.070),
			Vector2(.035, -.085),
			Vector2(.040, -.065),
			Vector2(.007, .028),
			Vector2(-.028, .022)
		],
		.018,
		"WOOD" if kind == "ak47" else "POLYMER"
	)
	# A continuous open trigger guard, with separate inner and outer wall loops.
	var outer: Array[Vector2] = [
		Vector2(-.071, .023),
		Vector2(.019, .023),
		Vector2(.025, .012),
		Vector2(.015, -.025),
		Vector2(-.059, -.025),
		Vector2(-.077, -.012)
	]
	var inner: Array[Vector2] = [
		Vector2(-.065, .017),
		Vector2(.012, .017),
		Vector2(.017, .009),
		Vector2(.010, -.018),
		Vector2(-.055, -.018),
		Vector2(-.069, -.010)
	]
	for i: int in outer.size():
		var n := (i + 1) % outer.size()
		for x: float in [-.009, .009]:
			var p: Array[Vector3] = [
				Vector3(x, outer[i].y, outer[i].x),
				Vector3(x, outer[n].y, outer[n].x),
				Vector3(x, inner[n].y, inner[n].x),
				Vector3(x, inner[i].y, inner[i].x)
			]
			if x > 0:
				p.reverse()
			_face(f, "Frame", "GUARD", p, "METAL", .4)
		for loop: Array[Vector2] in [outer, inner]:
			var p: Array[Vector3] = [
				Vector3(-.009, loop[i].y, loop[i].x),
				Vector3(.009, loop[i].y, loop[i].x),
				Vector3(.009, loop[n].y, loop[n].x),
				Vector3(-.009, loop[n].y, loop[n].x)
			]
			if loop == inner:
				p.reverse()
			_face(f, "Frame", "GUARD_WALL", p, "METAL", .4)
	_profile(
		f,
		"Frame",
		"TRIGGER",
		[
			Vector2(-.024, .020),
			Vector2(-.016, .020),
			Vector2(-.020, -.010),
			Vector2(-.029, -.014),
			Vector2(-.034, -.008),
			Vector2(-.026, -.005)
		],
		.005,
		"METAL"
	)


static func _profile(
	f: Array[Dictionary],
	part: String,
	id: String,
	profile: Array[Vector2],
	width: float,
	material: String = ""
) -> void:
	var pieces: Array[Dictionary] = []
	var area := 0.0
	for index: int in profile.size():
		area += profile[index].cross(profile[(index + 1) % profile.size()])
	if area < 0.0:
		profile = profile.duplicate()
		profile.reverse()
	PROP.add_prism(pieces, id, profile, width)
	for piece: Dictionary in pieces:
		var side := (
			String(piece["name"]).ends_with("LEFT") or String(piece["name"]).ends_with("RIGHT")
		)
		var key: String = piece["name"] if side else "EDGE"
		if not material.is_empty():
			key = material
		var points: Array[Vector3] = []
		points.assign(piece["points"])
		if id == "RECEIVER" and String(piece["name"]).ends_with("RIGHT"):
			_port_side(f, profile, width, key)
			continue
		_face(f, part, id, points, key, 1.0 if side else .35)
		if id == "RECEIVER":
			f[-1]["interior"] = true


static func _port_side(
	f: Array[Dictionary], profile: Array[Vector2], width: float, key: String
) -> void:
	var bounds := Rect2(profile[0], Vector2.ZERO)
	for point: Vector2 in profile:
		bounds = bounds.expand(point)
	var front := bounds.position.x + .045
	var rear := bounds.position.x + .11
	var bottom := bounds.position.y + .025
	var top := bounds.end.y - .009
	var regions: Array[Rect2] = [
		Rect2(bounds.position, Vector2(front - bounds.position.x, bounds.size.y)),
		Rect2(Vector2(rear, bounds.position.y), Vector2(bounds.end.x - rear, bounds.size.y)),
		Rect2(Vector2(front, bounds.position.y), Vector2(rear - front, bottom - bounds.position.y)),
		Rect2(Vector2(front, top), Vector2(rear - front, bounds.end.y - top))
	]
	for region: Rect2 in regions:
		var clip := PackedVector2Array(
			[
				region.position,
				Vector2(region.end.x, region.position.y),
				region.end,
				Vector2(region.position.x, region.end.y)
			]
		)
		for polygon: PackedVector2Array in Geometry2D.intersect_polygons(
			PackedVector2Array(profile), clip
		):
			var points: Array[Vector3] = []
			var uv := PackedVector2Array()
			for point: Vector2 in polygon:
				points.append(Vector3(width, point.y, point.x))
				uv.append(bounds.end - point)
			_face(f, "Frame", "PORT_SURROUND", points, key, 1.0)
			f[-1]["size_m"] = bounds.size
			f[-1]["uv_m"] = uv
			f[-1]["interior"] = true


static func _box(
	f: Array[Dictionary], part: String, id: String, center: Vector3, size: Vector3, key: String
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
		var p: Array[Vector3] = []
		for v: Vector3 in piece["points"]:
			p.append(v + center)
		_face(f, part, id, p, key, .45)


static func _tube(
	f: Array[Dictionary],
	part: String,
	id: String,
	center: Vector3,
	rear: float,
	front: float,
	radius: float,
	key: String,
	hollow: bool = false
) -> void:
	var cap: Array[Vector3] = []
	for i: int in 10:
		var a := TAU * i / 10
		var b := TAU * (i + 1) / 10
		var va := Vector3(cos(a) * radius, sin(a) * radius, front) + center
		var vb := Vector3(cos(b) * radius, sin(b) * radius, front) + center
		var p: Array[Vector3] = [
			va + Vector3(0, 0, rear - front), vb + Vector3(0, 0, rear - front), vb, va
		]
		_face(f, part, id, p, key, .45)
		cap.append(va)
		if hollow:
			var ia := center + Vector3(cos(a) * radius * .65, sin(a) * radius * .65, front)
			var ib := center + Vector3(cos(b) * radius * .65, sin(b) * radius * .65, front)
			_face(f, part, id + "_RIM", [va, vb, ib, ia], key, .3)
			_face(
				f,
				part,
				id + "_INNER",
				[ib, ia, ia + Vector3(0, 0, .010), ib + Vector3(0, 0, .010)],
				"DARK",
				.3
			)
	if not hollow:
		_face(f, part, id + "_CAP", cap, key, .3)


static func _face(
	f: Array[Dictionary],
	part: String,
	id: String,
	points: Array[Vector3],
	key: String,
	weight: float
) -> void:
	PROP.add_face(f, id, points)
	f[-1]["part"] = part
	f[-1]["reuse_key"] = key
	f[-1]["importance"] = weight
	f[-1]["interior"] = part == "Bolt" or "HOOD" in id or "INNER" in id
