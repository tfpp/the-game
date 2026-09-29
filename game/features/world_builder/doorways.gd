extends RefCounted
## Room-connection partitions and door manifests. Runtime state lives outside streamed meshes.

const Style := preload("res://features/world_builder/style.gd")


static func validate(link: Variant, errors: Array[String]) -> void:
	if not link is Dictionary or not link.has("door"):
		return
	var door: Variant = link["door"]
	if not door is Dictionary:
		errors.append("Connection door must be an object.")
		return
	for key: String in door:
		if key not in ["id", "label", "width", "height", "key_id"]:
			errors.append("Unknown connection door field: %s" % key)
	var id: Variant = door.get("id")
	if (
		not id is String
		or RegEx.create_from_string("^[A-Za-z][A-Za-z0-9_]{0,47}$").search(id) == null
	):
		errors.append("Connection door needs an identifier starting with a letter.")
	if not door.get("label", "Door") is String or str(door.get("label", "Door")).length() > 64:
		errors.append("Door label must be a string of at most 64 characters.")
	if not door.get("key_id", "") is String or str(door.get("key_id", "")).length() > 64:
		errors.append("Door key_id must be an item identifier of at most 64 characters.")
	if not Style.number_in(door.get("width", 1.8), 1.2, 2.4):
		errors.append("Door width must be between 1.2 and 2.4 metres.")
	if not Style.number_in(door.get("height", 2.6), 2.1, 3.0):
		errors.append("Door height must be between 2.1 and 3 metres.")


static func apply(layout: Dictionary, links: Array) -> void:
	layout["doors"] = []
	for index: int in links.size():
		var link: Variant = links[index]
		if not link is Dictionary or not link.has("door"):
			continue
		var door: Dictionary = link["door"].duplicate()
		for existing: Dictionary in layout["doors"]:
			if existing["id"] == door["id"]:
				layout["errors"].append("Duplicate connection door ID: %s" % door["id"])
		var rect: Rect2i = layout["rooms"][link["to"]]
		var threshold := _threshold(rect, layout["paths"][index])
		if threshold.is_empty():
			layout["errors"].append(
				"Door %s needs a corridor entering its destination room." % door["id"]
			)
			continue
		var scale: float = layout["cell_size"]
		var point: Vector2 = threshold["point"] * scale
		var axis: Vector2 = threshold["axis"]
		var level: float = layout["room_elevations"][link["to"]]
		var width: float = door.get("width", 1.8)
		var height: float = door.get("height", 2.6)
		var span: float = layout["hall_width"] * scale
		var outside := Vector2i((point / scale - axis * 0.5).floor())
		var inside := Vector2i((point / scale + axis * 0.5).floor())
		var clearance := minf(layout["heights"][outside], layout["heights"][inside])
		if width > span - 0.6 or height > clearance - 0.2:
			layout["errors"].append(
				"Door %s does not fit its corridor width or ceiling." % door["id"]
			)
			continue
		if not _clear_threshold(layout, point, axis, level):
			layout["errors"].append(
				(
					"Door %s must span a level corridor without a crossing or alternate gap."
					% door["id"]
				)
			)
			continue
		door.merge(
			{
				"position": Vector3(point.x, level, point.y),
				"normal": Vector3(axis.x, 0, axis.y),
				"width": width,
				"height": height,
				"span": span,
				"clearance": clearance,
				"label": door.get("label", link["to"]),
				"key_id": door.get("key_id", ""),
				"room": link["to"],
				"kit": layout["room_kits"][link["to"]]
			},
			true
		)
		for existing: Dictionary in layout["doors"]:
			if door["position"].distance_to(existing["position"]) < span:
				layout["errors"].append("Connection doors overlap or leave no swing clearance.")
		layout["doors"].append(door)


static func _threshold(rect: Rect2i, path: Array) -> Dictionary:
	for segment: int in [1, 0]:
		var start: Vector2i = path[segment]
		var end: Vector2i = path[segment + 1]
		if start == end or rect.has_point(start) or not rect.has_point(end):
			continue
		var axis := Vector2(end - start).normalized()
		var point := Vector2(end) + Vector2.ONE * 0.5
		if axis.x != 0:
			point.x = rect.position.x if axis.x > 0 else rect.end.x
		else:
			point.y = rect.position.y if axis.y > 0 else rect.end.y
		return {"point": point, "axis": axis}
	return {}


static func _clear_threshold(
	layout: Dictionary, point: Vector2, axis: Vector2, level: float
) -> bool:
	var scale: float = layout["cell_size"]
	var across := Vector2(axis.y, -axis.x)
	var half: int = layout["hall_width"] / 2
	for side: int in range(-half - 1, half + 2):
		var location := point / scale - axis * 0.5 + across * side
		var cell := Vector2i(location.floor())
		if absi(side) > half:
			if layout["cells"].has(cell):
				return false
		elif (
			not layout["floors"].has(cell)
			or not layout["floors"][cell].is_equal_approx(Vector3(0, 0, level))
		):
			return false
	return true


static func wall(door: Dictionary, reverse: bool = false) -> Dictionary:
	var n: Vector3 = door["normal"] * (-1 if reverse else 1)
	var right := Vector3(n.z, 0, -n.x)
	var center: Vector3 = door["position"] + n * 0.08
	return {
		"a": center - right * float(door["span"]) / 2,
		"b": center + right * float(door["span"]) / 2,
		"normal": n,
		"height": door["clearance"],
		"kit": door.get("kit", "classic"),
		"openings":
		[
			{
				"id": door["id"] + ("_Back" if reverse else ""),
				"kind": "door",
				"start": (float(door["span"]) - float(door["width"])) / 2,
				"width": door["width"],
				"height": door["height"],
				"sill": 0.0,
				"interactive": true
			}
		]
	}


static func runtime_scene(layout: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "RoomDoors"
	for definition: Dictionary in layout["doors"]:
		var door := (
			(load("res://features/room_doors/swing_door.tscn") as PackedScene).instantiate()
			as Node3D
		)
		door.name = definition["id"]
		door.position = definition["position"]
		door.rotation.y = atan2(definition["normal"].x, definition["normal"].z)
		door.set("door_label", definition["label"])
		door.set("width", definition["width"])
		door.set("height", definition["height"])
		door.set("key_id", definition["key_id"])
		door.set("kit_id", definition.get("kit", "classic"))
		root.add_child(door)
		door.owner = root
	return root
