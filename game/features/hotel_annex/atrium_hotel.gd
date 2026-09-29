extends Node3D
## The hotel building: four storeys of galleries and guest rooms around a central,
## skylit atrium. Built from boxes when the streamed room loads, identically on every
## peer. Everything here is static; doors and arrival markers live in `feature.tscn`.
##
## Coordinates are in the hotel room's local space, metres. X runs west to east and
## Z north to south. The classic hotel door sits in the north wall at x = 8.75.

const Materials := preload("res://features/world_builder/materials.gd")

const LEVELS := 4
const STOREY := 4.0
const SLAB := 0.3
const WALL := 0.3
const OUTER := Rect2(-20, 0, 54, 34)
const ATRIUM := Rect2(-3, 7, 20, 20)
## Switchback ramps along the south wall. Even storeys climb east in lane A, odd
## storeys climb west in lane B.
## A 24 m run for each 4 m rise keeps ramps at 9.46 degrees.
const RAMP_X := Vector2(-5, 19)
const LANE_A := Vector2(31.5, 34)
const LANE_B := Vector2(29, 31.5)
const WING_WALLS: Array[float] = [-7.0, 21.0]
const ROOM_SPLITS: Array[float] = [11.5, 22.5]
const ROOM_DOORS: Array[float] = [5.5, 17.0, 28.5]
const GROUND_NAMES: Array[String] = [
	"Reading Room",
	"West Salon",
	"Gallery",
	"Grand Lounge",
	"Conservatory",
	"East Salon",
]
const RAIL_HEIGHT := 1.1

var _materials: Dictionary[String, Material] = {}
var _body: StaticBody3D


func _ready() -> void:
	var palette := Materials.create("hotel")
	for key: String in palette:
		var material := palette[key] as StandardMaterial3D
		material.uv1_triplanar = true
		_materials[key] = material
	_body = StaticBody3D.new()
	_body.name = "Structure"
	add_child(_body)
	for level: int in LEVELS:
		_build_storey(level)
	_build_shell()
	_build_atrium()


## Floor height of a storey.
static func floor_y(level: int) -> float:
	return level * STOREY


## Start and end (x, y, z) of the ramp that climbs from `level` to the next storey.
static func ramp_ends(level: int) -> Array[Vector3]:
	var lane := LANE_A if level % 2 == 0 else LANE_B
	var z := (lane.x + lane.y) * 0.5
	var start := Vector3(RAMP_X.x, floor_y(level), z)
	var end := Vector3(RAMP_X.y, floor_y(level + 1), z)
	if level % 2 == 1:
		start.x = RAMP_X.y
		end.x = RAMP_X.x
	return [start, end]


## Rectangles (x, z) cut out of a storey's floor: the atrium and the ramp arriving
## from below.
static func floor_holes(level: int) -> Array[Rect2]:
	if level == 0:
		return []
	var lane := LANE_A if (level - 1) % 2 == 0 else LANE_B
	return [ATRIUM, Rect2(RAMP_X.x, lane.x, RAMP_X.y - RAMP_X.x, lane.y - lane.x)]


## Splits `outer` into rectangles that cover it except for `holes`.
static func subtract(outer: Rect2, holes: Array[Rect2]) -> Array[Rect2]:
	var xs: Array[float] = [outer.position.x, outer.end.x]
	var zs: Array[float] = [outer.position.y, outer.end.y]
	for hole: Rect2 in holes:
		xs.append_array([hole.position.x, hole.end.x])
		zs.append_array([hole.position.y, hole.end.y])
	xs.sort()
	zs.sort()
	var result: Array[Rect2] = []
	for i: int in xs.size() - 1:
		var run_start := -1.0
		var run_open := false
		for j: int in zs.size() - 1:
			var cell := Rect2(xs[i], zs[j], xs[i + 1] - xs[i], zs[j + 1] - zs[j])
			var solid := cell.has_area() and outer.encloses(cell)
			for hole: Rect2 in holes:
				if hole.encloses(cell):
					solid = false
			if solid and not run_open:
				run_start = zs[j]
				run_open = true
			elif not solid and run_open:
				result.append(Rect2(xs[i], run_start, xs[i + 1] - xs[i], zs[j] - run_start))
				run_open = false
		if run_open:
			result.append(Rect2(xs[i], run_start, xs[i + 1] - xs[i], zs[-1] - run_start))
	return result


func _build_storey(level: int) -> void:
	var y := floor_y(level)
	var height := STOREY - SLAB
	var floor_key := "floor" if level == 0 else "carpet"
	for rect: Rect2 in subtract(OUTER, floor_holes(level)):
		_slab(rect, y - SLAB, SLAB, floor_key)
	# Wings: a wall facing the galleries with a door into each of three rooms.
	var door_width := 3.0 if level == 0 else 1.8
	for side: int in WING_WALLS.size():
		var wall_x: float = WING_WALLS[side]
		var gaps: Array[Vector2] = []
		for door_z: float in ROOM_DOORS:
			gaps.append(Vector2(door_z - door_width * 0.5, door_z + door_width * 0.5))
		_wall_along_z(wall_x, OUTER.position.y, OUTER.end.y, y, height, gaps, 2.6)
		var x0 := OUTER.position.x if side == 0 else wall_x
		var x1 := wall_x if side == 0 else OUTER.end.x
		for split: float in ROOM_SPLITS:
			_box(Vector3(x0, y, split - WALL * 0.5), Vector3(x1, y + height, split + WALL * 0.5))
		for room: int in ROOM_DOORS.size():
			_room_sign(level, side, room, wall_x)
			if level > 0:
				_bed(level, side, room)
	if level == 0:
		return
	# Gallery railings around the atrium and the stairwell.
	var rail_y := y
	_rail(Vector3(ATRIUM.position.x, rail_y, ATRIUM.position.y), Vector3(ATRIUM.end.x, 0, 0))
	_rail(Vector3(ATRIUM.position.x, rail_y, ATRIUM.end.y), Vector3(ATRIUM.end.x, 0, 0))
	_rail(Vector3(ATRIUM.position.x, rail_y, ATRIUM.position.y), Vector3(0, 0, ATRIUM.end.y))
	_rail(Vector3(ATRIUM.end.x, rail_y, ATRIUM.position.y), Vector3(0, 0, ATRIUM.end.y))
	_rail(Vector3(RAMP_X.x, rail_y, LANE_B.x), Vector3(RAMP_X.y, 0, 0))
	_rail(Vector3(RAMP_X.x, rail_y, LANE_A.x), Vector3(RAMP_X.y, 0, 0))
	if (level - 1) % 2 == 0:
		# The ramp below arrives at the east end; close the drop at its west end.
		_rail(Vector3(RAMP_X.x, rail_y, LANE_A.x), Vector3(0, 0, LANE_A.y))
	else:
		_rail(Vector3(RAMP_X.y, rail_y, LANE_B.x), Vector3(0, 0, LANE_B.y))


func _build_shell() -> void:
	var top := floor_y(LEVELS)
	var t := 0.4
	var o := OUTER
	_box(
		Vector3(o.position.x - t, -SLAB, o.position.y - t), Vector3(o.end.x + t, top, o.position.y)
	)
	_box(Vector3(o.position.x - t, -SLAB, o.end.y), Vector3(o.end.x + t, top, o.end.y + t))
	_box(Vector3(o.position.x - t, -SLAB, o.position.y), Vector3(o.position.x, top, o.end.y))
	_box(Vector3(o.end.x, -SLAB, o.position.y), Vector3(o.end.x + t, top, o.end.y))
	for rect: Rect2 in subtract(OUTER, [ATRIUM]):
		_slab(rect, top - SLAB, SLAB, "ceiling")
	_slab(ATRIUM, top - 0.1, 0.1, "glass")
	for level: int in LEVELS - 1:
		var ends := ramp_ends(level)
		_ramp(ends[0], ends[1], LANE_A if level % 2 == 0 else LANE_B)
	# The classic hotel door's visible leaf and frame on the inside of the north wall.
	_visual(Vector3(8.75, 1.35, 0.04), Vector3(1.5, 2.7, 0.08), "wood")
	_visual(Vector3(8.75, 2.8, 0.06), Vector3(1.9, 0.2, 0.12), "gold")
	for x: float in [7.9, 9.6]:
		_visual(Vector3(x, 1.4, 0.06), Vector3(0.2, 2.8, 0.12), "gold")


func _build_atrium() -> void:
	var center := ATRIUM.get_center()
	var fountain := Vector3(center.x, 0, center.y)
	var basin := CylinderMesh.new()
	basin.top_radius = 2.2
	basin.bottom_radius = 2.4
	basin.height = 0.7
	_mesh(basin, fountain + Vector3(0, 0.35, 0), "plaster")
	var water := CylinderMesh.new()
	water.top_radius = 2.0
	water.bottom_radius = 2.0
	water.height = 0.05
	_mesh(water, fountain + Vector3(0, 0.62, 0), "glass")
	var spout := CylinderMesh.new()
	spout.top_radius = 0.25
	spout.bottom_radius = 0.4
	spout.height = 2.2
	_mesh(spout, fountain + Vector3(0, 1.1, 0), "gold")
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 2.4
	cylinder.height = 0.7
	shape.shape = cylinder
	shape.position = fountain + Vector3(0, 0.35, 0)
	_body.add_child(shape)
	# Columns at the atrium corners, running the full height to the skylight.
	var top := floor_y(LEVELS) - SLAB
	for corner: Vector2 in [
		ATRIUM.position,
		Vector2(ATRIUM.end.x, ATRIUM.position.y),
		ATRIUM.end,
		Vector2(ATRIUM.position.x, ATRIUM.end.y)
	]:
		_box(
			Vector3(corner.x - 0.3, 0, corner.y - 0.3),
			Vector3(corner.x + 0.3, top, corner.y + 0.3),
			"plaster"
		)
	var sign := Label3D.new()
	sign.text = "THE ATRIUM HOTEL"
	sign.font_size = 64
	sign.pixel_size = 0.004
	sign.modulate = Color(1, 0.83, 0.52)
	sign.outline_size = 6
	sign.position = Vector3(8.75, 3.45, 0.1)
	add_child(sign)
	# One light per storey over the atrium and one per wing: no shadows, only loaded
	# for visitors.
	for level: int in LEVELS:
		var y := floor_y(level) + STOREY - 0.8
		_light(Vector3(center.x, y, center.y), 18.0)
		_light(Vector3(-13.5, y, 17), 14.0)
		_light(Vector3(27.5, y, 17), 14.0)


func _room_sign(level: int, side: int, room: int, wall_x: float) -> void:
	var label := Label3D.new()
	if level == 0:
		label.text = GROUND_NAMES[side * ROOM_DOORS.size() + room]
	else:
		label.text = "%d%02d" % [level, side * ROOM_DOORS.size() + room + 1]
	label.font_size = 48
	label.pixel_size = 0.004
	label.modulate = Color(1, 0.83, 0.52)
	label.outline_size = 4
	# Face the gallery: the west wing's sign faces +X, the east wing's -X.
	var facing := 1.0 if side == 0 else -1.0
	label.position = Vector3(wall_x + facing * (WALL * 0.5 + 0.02), floor_y(level) + 3.0, 0)
	label.position.z = ROOM_DOORS[room]
	label.rotation.y = PI * 0.5 * facing
	add_child(label)


func _bed(level: int, side: int, room: int) -> void:
	var x := -18.0 if side == 0 else 32.0
	var z: float = ROOM_DOORS[room]
	var y := floor_y(level)
	_box(Vector3(x - 1.1, y, z - 1.0), Vector3(x + 1.1, y + 0.55, z + 1.0), "carpet")
	var head := 1.0 if side == 0 else -1.0
	var board := x - head * 1.1
	_box(
		Vector3(minf(board, board - head * 0.12), y, z - 1.0),
		Vector3(maxf(board, board - head * 0.12), y + 1.2, z + 1.0),
		"wood"
	)


## A wall at `x` from `z0` to `z1`, with doorways in `gaps` (z ranges).
func _wall_along_z(
	x: float, z0: float, z1: float, y: float, height: float, gaps: Array[Vector2], door: float
) -> void:
	var cursor := z0
	for gap: Vector2 in gaps:
		_box(Vector3(x - WALL * 0.5, y, cursor), Vector3(x + WALL * 0.5, y + height, gap.x))
		_box(Vector3(x - WALL * 0.5, y + door, gap.x), Vector3(x + WALL * 0.5, y + height, gap.y))
		cursor = gap.y
	_box(Vector3(x - WALL * 0.5, y, cursor), Vector3(x + WALL * 0.5, y + height, z1))


func _rail(from: Vector3, to_axis: Vector3) -> void:
	# `to_axis` gives the end coordinate on the one axis the rail runs along.
	var end := from
	if to_axis.x != 0.0:
		end.x = to_axis.x
	else:
		end.z = to_axis.z
	var half := 0.06
	_box(
		Vector3(minf(from.x, end.x) - half, from.y, minf(from.z, end.z) - half),
		Vector3(maxf(from.x, end.x) + half, from.y + RAIL_HEIGHT, maxf(from.z, end.z) + half),
		"gold"
	)


func _ramp(start: Vector3, end: Vector3, lane: Vector2) -> void:
	var run := end.x - start.x
	var rise := end.y - start.y
	var length := Vector2(run, rise).length()
	var thickness := 0.25
	var basis := Basis(Vector3.BACK, atan2(rise * signf(run), absf(run)))
	var up := basis.y
	var center := (
		Vector3((start.x + end.x) * 0.5, (start.y + end.y) * 0.5, 0) - up * thickness * 0.5
	)
	center.z = (lane.x + lane.y) * 0.5
	var size := Vector3(length, thickness, lane.y - lane.x - 0.1)
	_solid(Transform3D(basis, center), size, "wood")


func _slab(rect: Rect2, y: float, thickness: float, key: String) -> void:
	_box(
		Vector3(rect.position.x, y, rect.position.y),
		Vector3(rect.end.x, y + thickness, rect.end.y),
		key
	)


func _box(from: Vector3, to: Vector3, key: String = "wall") -> void:
	var size := (to - from).abs()
	if size.x < 0.001 or size.y < 0.001 or size.z < 0.001:
		return
	_solid(Transform3D(Basis.IDENTITY, (from + to) * 0.5), size, key)


func _solid(transform: Transform3D, size: Vector3, key: String) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.transform = transform
	instance.material_override = _materials[key]
	add_child(instance)
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.transform = transform
	collider.add_to_group(&"radar_geometry")
	_body.add_child(collider)


func _visual(center: Vector3, size: Vector3, key: String) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_mesh(mesh, center, key)


func _mesh(mesh: Mesh, at: Vector3, key: String) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = _materials[key]
	add_child(instance)


func _light(at: Vector3, reach: float) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.omni_range = reach
	light.light_energy = 1.2
	light.light_color = Color(1, 0.88, 0.7)
	light.shadow_enabled = false
	add_child(light)
