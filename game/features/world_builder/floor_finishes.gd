extends RefCounted
## Per-room floor finishes and cell-aligned service shafts.


static func validate(room: Dictionary, errors: Array[String]) -> void:
	if room.get("floor_material", "wood") not in ["wood", "concrete"]:
		errors.append("Room floor_material must be wood or concrete.")
	var holes: Variant = room.get("floor_holes", [])
	if not holes is Array or holes.size() > 4:
		errors.append("floor_holes must contain at most four [x,z,width,depth] rectangles.")
		return
	for hole: Variant in holes:
		if not hole is Array or hole.size() != 4:
			errors.append("Each floor hole needs [x,z,width,depth] in room cells.")
			continue
		var valid := true
		for value: Variant in hole:
			valid = (
				valid
				and (value is int or value is float)
				and is_finite(float(value))
				and float(value) == floorf(float(value))
				and value >= 1
				and value <= 32
			)
		if not valid or not room.get("size") is Array or room["size"].size() != 2:
			errors.append("Floor holes need positive whole-cell dimensions.")
			continue
		if hole[0] + hole[2] >= room["size"][0] or hole[1] + hole[3] >= room["size"][1]:
			errors.append("Floor holes must leave at least one cell at room walls.")
		if room.get("floor_material", "wood") != "concrete":
			errors.append("Service floor holes require a concrete room without a carpet.")


static func apply(layout: Dictionary, rooms: Array) -> void:
	layout["floor_finishes"] = {}
	layout["room_floor_finishes"] = {}
	for cell: Vector2i in layout["cells"]:
		var kit: String = layout["cell_kits"][cell]
		layout["floor_finishes"][cell] = "floor" if kit == "classic" else kit + "_floor"
	for room: Dictionary in rooms:
		var kit: String = layout["room_kits"][room["id"]]
		var material := "floor" if kit == "classic" else kit + "_floor"
		if room.get("floor_material") == "concrete":
			material = "concrete"
		layout["room_floor_finishes"][room["id"]] = material
		var rect: Rect2i = layout["rooms"][room["id"]]
		for z: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				layout["floor_finishes"][Vector2i(x, z)] = material
		for hole: Array in room.get("floor_holes", []):
			for z: int in range(int(hole[1]), int(hole[1] + hole[3])):
				for x: int in range(int(hole[0]), int(hole[0] + hole[2])):
					layout["floor_finishes"][rect.position + Vector2i(x, z)] = "hole"
