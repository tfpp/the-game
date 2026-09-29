extends RefCounted
## Pure, deterministic blueprint compiler. Coordinates are integer floor cells (x, z).

const Style := preload("res://features/world_builder/style.gd")
const Details := preload("res://features/world_builder/layout_details.gd")

const MAX_CELLS := 65536
const DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]


static func compile(spec: Dictionary) -> Dictionary:
	var errors := _validate(spec)
	if not errors.is_empty():
		return {"errors": errors}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 1))
	var rooms: Dictionary[String, Rect2i] = {}
	var cells: Dictionary[Vector2i, bool] = {}
	var definitions: Array = spec["rooms"]
	var columns := ceili(sqrt(definitions.size()))
	for i: int in definitions.size():
		var definition: Dictionary = definitions[i]
		var size := Vector2i(int(definition["size"][0]), int(definition["size"][1]))
		var origin := Vector2i((i % columns) * 48, (i / columns) * 48)
		origin += Vector2i(rng.randi_range(0, 6), rng.randi_range(0, 6))
		if definition.has("at"):
			origin = Vector2i(int(definition["at"][0]), int(definition["at"][1]))
		var rect := Rect2i(origin, size)
		for other: Rect2i in rooms.values():
			if rect.grow(1).intersects(other):
				errors.append("Room '%s' overlaps or touches another room." % definition["id"])
		rooms[definition["id"]] = rect
		_paint(cells, rect)
	var connections: Array = spec.get("connections", [])
	if not spec.has("connections"):
		for i: int in range(1, definitions.size()):
			connections.append([definitions[i - 1]["id"], definitions[i]["id"]])
	var paths: Array[Array] = []
	var width := int(spec.get("hall_width", 3))
	for connection: Array in connections:
		var start := rooms[connection[0]].get_center()
		var end := rooms[connection[1]].get_center()
		var bend := Vector2i(end.x, start.y) if rng.randi() % 2 else Vector2i(start.x, end.y)
		_carve(cells, start, bend, width)
		_carve(cells, bend, end, width)
		paths.append([start, bend, end])
	if cells.size() > MAX_CELLS:
		errors.append("Layout exceeds %d walkable cells." % MAX_CELLS)
	elif not _connected(cells):
		errors.append("Rooms are disconnected; add connections linking every room.")
	var result := {
		"errors": errors,
		"rooms": rooms,
		"cells": cells,
		"paths": paths,
		"cell_size": float(spec.get("cell_size", 1.0)),
		"hall_width": width,
		"height": float(spec.get("height", 3.5)),
		"ceiling": bool(spec.get("ceiling", true)),
		"seed": rng.seed,
	}

	Details.apply(result, spec)
	return result


static func _validate(spec: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	Style.validate(spec, errors)
	for key: String in spec:
		if (
			key
			not in [
				"version",
				"seed",
				"rooms",
				"connections",
				"hall_width",
				"cell_size",
				"height",
				"ceiling",
				"style",
				"hall_height"
			]
		):
			errors.append("Unknown blueprint field: %s" % key)
	if spec.get("version") != 1:
		errors.append("Blueprint version must be 1.")
	if not _integer(spec.get("seed", 1), -2147483648, 2147483647):
		errors.append("seed must be a 32-bit integer.")
	if not _integer(spec.get("hall_width", 3), 3, 7) or int(spec.get("hall_width", 3)) % 2 == 0:
		errors.append("hall_width must be 3, 5 or 7 cells.")
	for key: String in ["cell_size", "height"]:
		var value: Variant = spec.get(key, 1.0 if key == "cell_size" else 3.5)
		var minimum := 0.75 if key == "cell_size" else 2.5
		if not _number(value) or float(value) < minimum or float(value) > 8.0:
			errors.append("%s must be a finite number between %s and 8." % [key, minimum])
	if spec.has("ceiling") and not spec["ceiling"] is bool:
		errors.append("ceiling must be true or false.")
	var definitions: Variant = spec.get("rooms")
	if not definitions is Array or definitions.is_empty() or definitions.size() > 64:
		errors.append("rooms must contain 1 to 64 room definitions.")
	else:
		_validate_rooms(definitions, errors)
	var connections: Variant = spec.get("connections", [])
	if not connections is Array or connections.size() > 128:
		errors.append("connections must be an array of at most 128 room ID pairs.")
	elif errors.is_empty():
		var ids: Array[String] = []
		for definition: Dictionary in definitions:
			ids.append(definition["id"])
		for pair: Variant in connections:
			if not pair is Array or pair.size() != 2:
				errors.append("Each connection must contain two room IDs.")
			elif pair[0] not in ids or pair[1] not in ids or pair[0] == pair[1]:
				errors.append("Connection must reference two distinct existing rooms: %s" % [pair])
	return errors


static func _validate_rooms(definitions: Array, errors: Array[String]) -> void:
	var ids: Array[String] = []
	var positioned := 0
	var id_pattern := RegEx.create_from_string("^[A-Za-z][A-Za-z0-9_]{0,47}$")
	for definition: Variant in definitions:
		if not definition is Dictionary:
			errors.append("Each room must be an object.")
			continue
		for key: String in definition:
			if key not in ["id", "size", "at", "height", "openings", "pillars"]:
				errors.append("Unknown room field: %s" % key)
		Style.validate_room(definition, errors)
		var room_id: Variant = definition.get("id")
		if not room_id is String or id_pattern.search(room_id) == null or room_id in ids:
			errors.append("Room IDs must be unique identifiers starting with a letter.")
		else:
			ids.append(room_id)
		if not _pair(definition.get("size"), 7, 32):
			errors.append("Room size must be two integers between 7 and 32 cells.")
		if definition.has("at"):
			positioned += 1
			if not _pair(definition["at"], -256, 256):
				errors.append("Room at must be two integer coordinates between -256 and 256.")
	if positioned != 0 and positioned != definitions.size():
		errors.append(
			"Provide 'at' for every room, or omit it for every room for automatic placement."
		)


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (
		_number(value)
		and float(value) == floorf(float(value))
		and value >= minimum
		and value <= maximum
	)


static func _pair(value: Variant, minimum: int, maximum: int) -> bool:
	return (
		value is Array
		and value.size() == 2
		and _integer(value[0], minimum, maximum)
		and _integer(value[1], minimum, maximum)
	)


static func _paint(cells: Dictionary[Vector2i, bool], rect: Rect2i) -> void:
	for z: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			cells[Vector2i(x, z)] = true


static func _carve(
	cells: Dictionary[Vector2i, bool], start: Vector2i, end: Vector2i, width: int
) -> void:
	var offset := Vector2i.ONE * (width / 2)
	var origin := Vector2i(mini(start.x, end.x), mini(start.y, end.y)) - offset
	_paint(cells, Rect2i(origin, (end - start).abs() + Vector2i.ONE * width))


static func _connected(cells: Dictionary[Vector2i, bool]) -> bool:
	var queue: Array[Vector2i] = [cells.keys()[0]]
	var seen: Dictionary[Vector2i, bool] = {queue[0]: true}
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		for direction: Vector2i in DIRECTIONS:
			var neighbor := cell + direction
			if cells.has(neighbor) and not seen.has(neighbor):
				seen[neighbor] = true
				queue.append(neighbor)
	return seen.size() == cells.size()
