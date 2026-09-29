extends RefCounted
## Floor planes in metres: Vector3 stores X slope, Z slope and Y intercept.
## Flights occupy straight runs; room thresholds and corridor bends stay level.

const MAX_RAMP_DEGREES := 10.0
const MIN_STAIR_DEGREES := 30.0
const MAX_STAIR_DEGREES := 37.0
const TARGET_STAIR_DEGREES := 33.5
const MAX_RISER := 0.18
const MIN_TREAD := 0.22


static func connection(value: Variant) -> Dictionary:
	if value is Array:
		return {"from": value[0], "to": value[1], "kind": "ramp", "max_slope": 10.0}
	return value


static func validate(value: Variant, ids: Array[String], errors: Array[String]) -> void:
	if value is Array:
		if value.size() != 2:
			errors.append("Each connection pair must contain two room IDs.")
			return
	elif value is Dictionary:
		for key: String in value:
			if key not in ["from", "to", "kind", "max_slope", "door"]:
				errors.append("Unknown connection field: %s" % key)
		if value.get("kind", "ramp") not in ["ramp", "stairs"]:
			errors.append("Connection kind must be ramp or stairs.")
		if not preload("res://features/world_builder/style.gd").number_in(
			value.get("max_slope", 10.0), 0.1, MAX_RAMP_DEGREES
		):
			errors.append("Ramp max_slope must be between 0.1 and 10 degrees.")
		if value.get("kind") == "stairs" and value.has("max_slope"):
			errors.append("max_slope applies to ramps only.")
	else:
		errors.append("A connection must be a room ID pair or a from/to object.")
		return
	var link := connection(value)
	if (
		not link.get("from") is String
		or not link.get("to") is String
		or link.get("from") not in ids
		or link.get("to") not in ids
		or link.get("from") == link.get("to")
	):
		errors.append("Connection must reference two distinct existing rooms.")


static func sample(plane: Vector3, point: Vector2) -> float:
	return plane.x * point.x + plane.y * point.y + plane.z


static func floor_at(layout: Dictionary, cell: Vector2i, point: Vector2) -> float:
	return sample(layout["floors"][cell], point)


static func apply(layout: Dictionary, spec: Dictionary, links: Array) -> void:
	var floors: Dictionary[Vector2i, Vector3] = {}
	var room_cells: Dictionary[Vector2i, bool] = {}
	layout["room_elevations"] = {}
	layout["flights"] = []
	layout["flight_cells"] = {}
	for room: Dictionary in spec["rooms"]:
		var level := float(room.get("elevation", 0.0))
		layout["room_elevations"][room["id"]] = level
		var rect: Rect2i = layout["rooms"][room["id"]]
		for z: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				var cell := Vector2i(x, z)
				floors[cell] = Vector3(0, 0, level)
				room_cells[cell] = true
	for index: int in links.size():
		var link := connection(links[index])
		var low: float = layout["room_elevations"][link["from"]]
		var high: float = layout["room_elevations"][link["to"]]
		var path: Array = layout["paths"][index]
		var flight: Dictionary = {}
		if not is_equal_approx(low, high):
			flight = _flight(layout, room_cells, path, link, low, high)
			if flight.is_empty():
				continue
			layout["flights"].append(flight)
		_paint_path(layout, floors, path, low, flight)
	# Keep invalid layouts inspectable, but never bake them.
	for cell: Vector2i in layout["cells"]:
		if not floors.has(cell):
			floors[cell] = Vector3.ZERO
	layout["floors"] = floors
	layout["room_cells"] = room_cells
	_validate_edges(layout)


static func _flight(
	layout: Dictionary, rooms: Dictionary, path: Array, link: Dictionary, low: float, high: float
) -> Dictionary:
	var best: Dictionary = {}
	var scale: float = layout["cell_size"]
	var half: int = layout["hall_width"] / 2
	# Keep a full cell of landing at room thresholds and the whole bend square level.
	for segment: int in 2:
		var start: Vector2i = path[segment]
		var end: Vector2i = path[segment + 1]
		var delta := end - start
		if delta == Vector2i.ZERO:
			continue
		var axis := Vector2i(signi(delta.x), signi(delta.y))
		var across := Vector2i(-axis.y, axis.x)
		var length := absi(delta.x) + absi(delta.y)
		var run_start := -1
		for step: int in range(half + 1, length - half + 1):
			var free := step < length - half
			for side: int in range(-half, half + 1):
				free = free and not rooms.has(start + axis * step + across * side)
			if free and run_start < 0:
				run_start = step
			if not free and run_start >= 0:
				var count := step - run_start - 2
				if count > 0 and count * scale > float(best.get("length", 0)):
					var first := start + axis * (run_start + 1)
					var point := (Vector2(first) + Vector2.ONE * 0.5 - Vector2(axis) * 0.5) * scale
					best = {
						"segment": segment,
						"start": point,
						"axis": Vector2(axis),
						"length": count * scale,
						"low": low,
						"high": high,
						"kind": link.get("kind", "ramp"),
						"width": layout["hall_width"] * scale
					}
				run_start = -1
	var rise := absf(high - low)
	var steps := ceili(rise / MAX_RISER)
	var stairs: bool = link.get("kind", "ramp") == "stairs"
	var angle := MAX_STAIR_DEGREES if stairs else float(link.get("max_slope", MAX_RAMP_DEGREES))
	var required := rise / tan(deg_to_rad(angle))
	if stairs:
		required = maxf(required, steps * MIN_TREAD)
	if best.is_empty() or float(best["length"]) + 0.00001 < required:
		layout["errors"].append(
			(
				"Connection %s -> %s needs %.2fm of clear straight run for %s, plus level landings."
				% [link["from"], link["to"], required, link.get("kind", "ramp")]
			)
		)
		return {}
	if stairs:
		# Flights end on cell edges so floors, walls and collision meet exactly.
		# Use the remaining straight run as level landings, not shallow steps.
		var shortest := ceili((required - 0.00001) / scale)
		var longest := floori((rise / tan(deg_to_rad(MIN_STAIR_DEGREES)) + 0.00001) / scale)
		longest = mini(longest, roundi(float(best["length"]) / scale))
		if shortest > longest:
			(
				layout["errors"]
				. append(
					(
						"Stairs %s -> %s cannot fit 30-37 degrees on this grid; use a smaller cell_size or a ramp."
						% [link["from"], link["to"]]
					)
				)
			)
			return {}
		var cells := clampi(
			roundi(rise / tan(deg_to_rad(TARGET_STAIR_DEGREES)) / scale), shortest, longest
		)
		var length := cells * scale
		var offset := floorf((float(best["length"]) - length) / (2 * scale)) * scale
		best["start"] += best["axis"] * offset
		best["length"] = length
	best["steps"] = steps
	best["slope_degrees"] = rad_to_deg(atan(rise / float(best["length"])))
	return best


static func _paint_path(
	layout: Dictionary, floors: Dictionary, path: Array, low: float, flight: Dictionary
) -> void:
	var half: int = layout["hall_width"] / 2
	var scale: float = layout["cell_size"]
	for segment: int in 2:
		var start: Vector2i = path[segment]
		var end: Vector2i = path[segment + 1]
		var origin := Vector2i(mini(start.x, end.x), mini(start.y, end.y)) - Vector2i.ONE * half
		var extent := (
			Vector2i(maxi(start.x, end.x), maxi(start.y, end.y)) + Vector2i.ONE * (half + 1)
		)
		for z: int in range(origin.y, extent.y):
			for x: int in range(origin.x, extent.x):
				var cell := Vector2i(x, z)
				var plane := Vector3(0, 0, low)
				if not flight.is_empty():
					plane = _plane(flight, segment, (Vector2(cell) + Vector2.ONE * 0.5) * scale)
					if not Vector2(plane.x, plane.y).is_zero_approx():
						layout["flight_cells"][cell] = flight
				if floors.has(cell) and not plane.is_equal_approx(floors[cell]):
					var message := (
						"Corridors or rooms meet at incompatible elevations near cell %s." % cell
					)
					if message not in layout["errors"]:
						layout["errors"].append(message)
				else:
					floors[cell] = plane


static func _plane(flight: Dictionary, segment: int, point: Vector2) -> Vector3:
	var low: float = flight["low"]
	var high: float = flight["high"]
	if segment != flight["segment"]:
		return Vector3(0, 0, low if segment < flight["segment"] else high)
	var axis: Vector2 = flight["axis"]
	var start: Vector2 = flight["start"]
	var distance := (point - start).dot(axis)
	if distance < 0:
		return Vector3(0, 0, low)
	if distance > float(flight["length"]):
		return Vector3(0, 0, high)
	var gradient := axis * (high - low) / float(flight["length"])
	return Vector3(gradient.x, gradient.y, low - gradient.dot(start))


static func _validate_edges(layout: Dictionary) -> void:
	var floors: Dictionary = layout["floors"]
	var scale: float = layout["cell_size"]
	for cell: Vector2i in floors:
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var other := cell + direction
			if not floors.has(other):
				continue
			var a := Vector2(cell + direction) * scale
			var b := a + Vector2(direction.y, direction.x) * scale
			if (
				absf(sample(floors[cell], a) - sample(floors[other], a)) > 0.001
				or absf(sample(floors[cell], b) - sample(floors[other], b)) > 0.001
			):
				layout["errors"].append(
					"Unconnected floor edges at %s; move the intersecting corridors." % cell
				)
				return
