extends RefCounted
## Bakes architecture into ordinary static scene nodes, with no runtime generator.

const Geometry := preload("res://features/world_builder/geometry.gd")
const Materials := preload("res://features/world_builder/materials.gd")
const Architecture := preload("res://features/world_builder/architecture.gd")
const Elevation := preload("res://features/world_builder/elevation.gd")
const Stairs := preload("res://features/world_builder/stairs.gd")
const Doorways := preload("res://features/world_builder/doorways.gd")
const DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]


static func build(layout: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "GeneratedWorld"
	root.set_meta("blueprint_version", 1)
	root.set_meta("seed", layout["seed"])
	root.set_meta("theme", layout["style"]["theme"])
	var geometry := Geometry.new()
	geometry.materials = Materials.create(layout["style"]["theme"])
	_floors(geometry, layout)
	for flight: Dictionary in layout["flights"]:
		if flight["kind"] == "stairs":
			Stairs.build(geometry, flight)
	for wall: Dictionary in layout["walls"]:
		_wall(geometry, wall, layout["style"])
	for door: Dictionary in layout["doors"]:
		for reverse: bool in [false, true]:
			_wall(geometry, Doorways.wall(door, reverse), layout["style"])
	_height_transitions(geometry, layout)
	var openings := Node3D.new()
	openings.name = "Openings"
	Geometry.attach(root, openings, root)
	if layout["style"]["theme"] == "hotel":
		Architecture.new().build(geometry, layout, root)
	preload("res://features/world_builder/skylights.gd").build(layout, root)
	geometry.finish(root)
	var markers := Node3D.new()
	markers.name = "Rooms"
	Geometry.attach(root, markers, root)
	for room_id: String in layout["rooms"]:
		var rect: Rect2i = layout["rooms"][room_id]
		var center := Vector2(rect.get_center()) + Vector2(0.5, 0.5)
		var marker := Marker3D.new()
		marker.name = room_id
		marker.position = Vector3(center.x, 0, center.y) * float(layout["cell_size"])
		marker.position.y = layout["room_elevations"][room_id]
		marker.set_meta("elevation", marker.position.y)
		marker.set_meta("floor_rect", rect)
		marker.set_meta("height", layout["heights"][rect.position])
		Geometry.attach(markers, marker, root)
	return root


static func _floors(g: Geometry, layout: Dictionary) -> void:
	var remaining: Dictionary = layout["cells"].duplicate()
	var scale: float = layout["cell_size"]
	var heights: Dictionary = layout["heights"]
	var floors: Dictionary = layout["floors"]
	var finishes: Dictionary = layout["floor_finishes"]
	while not remaining.is_empty():
		var origin: Vector2i = remaining.keys()[0]
		var height: float = heights[origin]
		var plane: Vector3 = floors[origin]
		var material: String = finishes[origin]
		var skylight: bool = layout["skylight_cells"].has(origin)
		var width := 1
		var chunk_end := Vector2i(
			(floori(origin.x / 16.0) + 1) * 16, (floori(origin.y / 16.0) + 1) * 16
		)
		while (
			origin.x + width < chunk_end.x
			and remaining.has(origin + Vector2i(width, 0))
			and heights[origin + Vector2i(width, 0)] == height
			and floors[origin + Vector2i(width, 0)] == plane
			and finishes[origin + Vector2i(width, 0)] == material
			and layout["skylight_cells"].has(origin + Vector2i(width, 0)) == skylight
		):
			width += 1
		var depth := 1
		while (
			origin.y + depth < chunk_end.y
			and _has_row(
				remaining,
				layout,
				origin + Vector2i(0, depth),
				width,
				height,
				plane,
				material,
				skylight
			)
		):
			depth += 1
		for z: int in depth:
			for x: int in width:
				remaining.erase(origin + Vector2i(x, z))
		var a := Vector3(origin.x * scale, 0, origin.y * scale)
		var b := a + Vector3(width * scale, 0, 0)
		var c := b + Vector3(0, 0, depth * scale)
		var d := a + Vector3(0, 0, depth * scale)
		a.y = Elevation.sample(plane, Vector2(a.x, a.z))
		b.y = Elevation.sample(plane, Vector2(b.x, b.z))
		c.y = Elevation.sample(plane, Vector2(c.x, c.z))
		d.y = Elevation.sample(plane, Vector2(d.x, d.z))
		var normal := Vector3(-plane.x, 1, -plane.y).normalized()
		# Stair treads cover this structural slope. Keeping the surface also ensures
		# every collision sector has a mesh when there is no ceiling above the stairs.
		if material != "hole":
			g.quad(material, [a, b, c, d], normal)
		if layout["ceiling"] and not skylight:
			var up := Vector3.UP * height
			var kit: String = layout["cell_kits"][origin]
			g.quad(
				"ceiling" if kit == "classic" else kit + "_ceiling",
				[a + up, b + up, c + up, d + up],
				-normal
			)


static func _has_row(
	cells: Dictionary,
	layout: Dictionary,
	origin: Vector2i,
	width: int,
	height: float,
	plane: Vector3,
	material: String,
	skylight: bool
) -> bool:
	for x: int in width:
		var cell := origin + Vector2i(x, 0)
		if (
			not cells.has(cell)
			or layout["heights"][cell] != height
			or layout["floors"][cell] != plane
			or layout["floor_finishes"][cell] != material
			or layout["skylight_cells"].has(cell) != skylight
		):
			return false
	return true


static func _wall(g: Geometry, wall: Dictionary, style: Dictionary) -> void:
	var a: Vector3 = wall["a"]
	var b: Vector3 = wall["b"]
	var length := a.distance_to(b)
	var u := (b - a).normalized()
	var x_cuts: Array[float] = [0.0, length]
	var y_cuts: Array[float] = [0.0, wall["height"]]
	if style["theme"] == "hotel":
		y_cuts.append(style["wainscot_height"])
	for opening: Dictionary in wall["openings"]:
		x_cuts.append(opening["start"])
		x_cuts.append(opening["start"] + opening["width"])
		y_cuts.append(opening["sill"])
		y_cuts.append(opening["sill"] + opening["height"])
	x_cuts.sort()
	y_cuts.sort()
	for x: int in x_cuts.size() - 1:
		for y: int in y_cuts.size() - 1:
			var left := x_cuts[x]
			var right := x_cuts[x + 1]
			var bottom := y_cuts[y]
			var top := y_cuts[y + 1]
			if (
				right - left < 0.0001
				or top - bottom < 0.0001
				or _in_opening(wall, (left + right) / 2, (top + bottom) / 2)
			):
				continue
			var material := (
				"wood" if style["theme"] == "hotel" and top <= style["wainscot_height"] else "wall"
			)
			if wall.get("kit", "classic") != "classic":
				material = str(wall["kit"]) + "_wall"
			g.quad(
				material,
				[
					a + u * left + Vector3.UP * bottom,
					a + u * right + Vector3.UP * bottom,
					a + u * right + Vector3.UP * top,
					a + u * left + Vector3.UP * top
				],
				wall["normal"]
			)


static func _in_opening(wall: Dictionary, x: float, y: float) -> bool:
	for opening: Dictionary in wall["openings"]:
		if (
			x > opening["start"]
			and x < opening["start"] + opening["width"]
			and y > opening["sill"]
			and y < opening["sill"] + opening["height"]
		):
			return true
	return false


static func _height_transitions(g: Geometry, layout: Dictionary) -> void:
	var heights: Dictionary = layout["heights"]
	var scale: float = layout["cell_size"]
	for cell: Vector2i in heights:
		for side: int in 4:
			var other := cell + DIRECTIONS[side]
			if not heights.has(other) or heights[other] >= heights[cell]:
				continue
			var fixed := cell.x + side if side < 2 else cell.y + side - 2
			var start := cell.y if side < 2 else cell.x
			var a := (
				Vector3(fixed * scale, heights[other], start * scale)
				if side < 2
				else Vector3(start * scale, heights[other], fixed * scale)
			)
			var b := a + (Vector3.BACK if side < 2 else Vector3.RIGHT) * scale
			a.y += Elevation.floor_at(layout, cell, Vector2(a.x, a.z))
			b.y += Elevation.floor_at(layout, cell, Vector2(b.x, b.z))
			var up: Vector3 = Vector3.UP * float(heights[cell] - heights[other])
			var normal: Vector3 = [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD][side]
			var kit: String = layout["cell_kits"][cell]
			g.quad("wall" if kit == "classic" else kit + "_wall", [a, b, b + up, a + up], normal)
