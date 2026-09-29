extends RefCounted
## Resolves room heights, exterior openings and column positions before mesh generation.

const Style := preload("res://features/world_builder/style.gd")
const DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]


static func apply(layout: Dictionary, spec: Dictionary) -> void:
	layout["style"] = Style.settings(spec)
	var heights: Dictionary[Vector2i, float] = {}
	var scale: float = layout["cell_size"]
	for cell: Vector2i in layout["cells"]:
		heights[cell] = float(spec.get("hall_height", layout["height"]))
	for room: Dictionary in spec["rooms"]:
		var rect: Rect2i = layout["rooms"][room["id"]]
		for z: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				heights[Vector2i(x, z)] = float(room.get("height", layout["height"]))
	layout["heights"] = heights
	layout["walls"] = _walls(heights, scale)
	layout["openings"] = []
	layout["pillars"] = []
	for room: Dictionary in spec["rooms"]:
		var rect: Rect2i = layout["rooms"][room["id"]]
		for opening: Dictionary in room.get("openings", []):
			_add_opening(layout, room, rect, opening)
		for point: Array in room.get("pillars", []):
			_add_pillar(layout, room, rect, point)
	if layout["style"]["windows"]:
		_auto_windows(layout)
	if (
		layout["style"]["theme"] == "prototype"
		and (not layout["openings"].is_empty() or not layout["pillars"].is_empty())
	):
		layout["errors"].append("Openings and pillars require the hotel theme.")


static func _walls(heights: Dictionary[Vector2i, float], scale: float) -> Array[Dictionary]:
	var groups: Dictionary[Vector3, Array] = {}
	for cell: Vector2i in heights:
		for direction: int in 4:
			if heights.has(cell + DIRECTIONS[direction]):
				continue
			var fixed := cell.x + direction if direction < 2 else cell.y + direction - 2
			var key := Vector3(direction, fixed, heights[cell])
			if not groups.has(key):
				groups[key] = []
			groups[key].append(cell.y if direction < 2 else cell.x)
	var walls: Array[Dictionary] = []
	for key: Vector3 in groups:
		var values: Array = groups[key]
		values.sort()
		var index := 0
		while index < values.size():
			var start: int = values[index]
			var end := start + 1
			index += 1
			while index < values.size() and values[index] == end:
				end += 1
				index += 1
			var a := Vector3(key.y, 0, start) if key.x < 2 else Vector3(start, 0, key.y)
			var b := Vector3(key.y, 0, end) if key.x < 2 else Vector3(end, 0, key.y)
			var normal: Vector3 = [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD][int(
				key.x
			)]
			walls.append(
				{
					"a": a * scale,
					"b": b * scale,
					"normal": normal,
					"height": key.z,
					"side": int(key.x),
					"openings": []
				}
			)
	return walls


static func _add_opening(
	layout: Dictionary, room: Dictionary, rect: Rect2i, source: Dictionary
) -> void:
	var errors: Array[String] = layout["errors"]
	var opening := source.duplicate()
	opening["id"] = "%s_%s" % [room["id"], source["id"]]
	for existing: Dictionary in layout["openings"]:
		if existing["id"] == opening["id"]:
			errors.append("Duplicate opening ID: %s" % opening["id"])
			return
	var side: int = Style.SIDES[opening["side"]]
	var scale: float = layout["cell_size"]
	var fixed := rect.position.x if side == 0 else rect.end.x
	if side >= 2:
		fixed = rect.position.y if side == 2 else rect.end.y
	var origin := (rect.position.y if side < 2 else rect.position.x) * scale
	var length := (rect.size.y if side < 2 else rect.size.x) * scale
	var width := float(opening.get("width", 1.4))
	var offset := float(opening["offset"])
	var height := float(opening.get("height", 2.2))
	var sill := float(opening.get("sill", 1.2)) if opening["kind"] == "window" else 0.0
	if offset < 0.35 or offset + width > length - 0.35:
		errors.append("Opening %s must leave 0.35m at each room corner." % opening["id"])
		return
	if opening["kind"] == "door" and (width < 1.0 or height < 2.1):
		errors.append("Doors need at least 1m width and 2.1m height for player clearance.")
		return
	for wall: Dictionary in layout["walls"]:
		var a: Vector3 = wall["a"]
		var b: Vector3 = wall["b"]
		var wall_fixed := a.x if side < 2 else a.z
		var wall_start := a.z if side < 2 else a.x
		var wall_end := b.z if side < 2 else b.x
		if wall["side"] != side or not is_equal_approx(wall_fixed, fixed * scale):
			continue
		var start := origin + offset - wall_start
		if start < 0.3 or origin + offset + width > wall_end - 0.3:
			continue
		if sill + height > float(wall["height"]) - 0.35:
			errors.append("Opening %s does not fit below the ceiling trim." % opening["id"])
			return
		opening.merge({"start": start, "width": width, "height": height, "sill": sill}, true)
		if _overlaps(wall["openings"], start, width):
			errors.append("Opening %s overlaps another opening or its frame." % opening["id"])
			return
		wall["openings"].append(opening)
		layout["openings"].append(opening)
		return
	errors.append("Opening %s must lie on an exposed wall, clear of hallway joins." % opening["id"])


static func _overlaps(openings: Array, start: float, width: float) -> bool:
	for other: Dictionary in openings:
		if start < other["start"] + other["width"] + 0.4 and start + width > other["start"] - 0.4:
			return true
	return false


static func _auto_windows(layout: Dictionary) -> void:
	var style: Dictionary = layout["style"]
	for wall: Dictionary in layout["walls"]:
		var length: float = wall["a"].distance_to(wall["b"])
		var width: float = style["window_width"]
		var spacing := maxf(style["window_spacing"], width + 0.8)
		var count := floori(length / spacing)
		for i: int in count:
			var start := (i + 0.5) * length / count - width / 2.0
			var height := minf(style["window_height"], wall["height"] - style["window_sill"] - 0.4)
			if (
				start < 0.4
				or start + width > length - 0.4
				or height < 0.6
				or _overlaps(wall["openings"], start, width)
			):
				continue
			var opening := {
				"id": "AutoWindow%d" % layout["openings"].size(),
				"kind": "window",
				"start": start,
				"width": width,
				"height": height,
				"sill": style["window_sill"]
			}
			wall["openings"].append(opening)
			layout["openings"].append(opening)


static func _add_pillar(layout: Dictionary, room: Dictionary, rect: Rect2i, point: Array) -> void:
	var scale: float = layout["cell_size"]
	var margin := float(layout["style"]["pillar_width"]) + 0.65
	var position := Vector3(
		rect.position.x * scale + float(point[0]), 0, rect.position.y * scale + float(point[1])
	)
	if (
		point[0] < margin
		or point[1] < margin
		or point[0] > rect.size.x * scale - margin
		or point[1] > rect.size.y * scale - margin
	):
		layout["errors"].append("Pillars must sit inside rooms with player clearance to walls.")
		return
	for path: Array in layout["paths"]:
		for i: int in 2:
			var a := (Vector2(path[i]) + Vector2.ONE * 0.5) * scale
			var b := (Vector2(path[i + 1]) + Vector2.ONE * 0.5) * scale
			var nearest := Geometry2D.get_closest_point_to_segment(
				Vector2(position.x, position.z), a, b
			)
			if nearest.distance_to(Vector2(position.x, position.z)) < margin:
				layout["errors"].append(
					"Pillar blocks a room-to-hallway route; move it off the center path."
				)
				return
	for other: Dictionary in layout["pillars"]:
		if position.distance_to(other["position"]) < margin * 2:
			layout["errors"].append("Pillars overlap or leave insufficient clearance.")
			return
	layout["pillars"].append(
		{"position": position, "height": float(room.get("height", layout["height"]))}
	)
