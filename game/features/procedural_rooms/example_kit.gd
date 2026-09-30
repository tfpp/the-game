extends RefCounted
## Primitive modules declare interior shell faces, not wall boxes.

const OPENING := preload("res://features/procedural_rooms/profiles/walk_3m.tres")
const Socket := preload("res://features/procedural_rooms/socket_attachment.gd")
const Shell := preload("res://features/procedural_rooms/shell_mesh.gd")
const FLOOR := preload("res://features/procedural_rooms/materials/floor.tres")
const WATER := preload("res://features/procedural_rooms/materials/water.tres")
const COVER := preload("res://features/procedural_rooms/materials/cover.tres")


static func room(id: String, turn: bool = false, wall_height: float = 3.5) -> Node3D:
	var root := Node3D.new()
	root.name = id
	root.set_meta("length", 8.0)
	root.set_meta("rise", 0.0)
	_plane(root, 8, 8, 0, "floor", Vector3.UP)
	_plane(root, 8, 8, 3.5, "roof", Vector3.DOWN)
	_end(root, "In", Vector3.ZERO, PI, 8, wall_height)
	if turn:
		_end(root, "Out", Vector3(4, 0, 4), PI * 0.5, 8, wall_height)
		_end_wall(root, Vector3(0, 0, 8), 0, -4, 4, 0, wall_height)
	else:
		_end(root, "Out", Vector3(0, 0, 8), 0, 8, wall_height)
		_side(root, 4, Vector2(0, 0), Vector2(8, 0), wall_height, "wall")
	_side(root, -4, Vector2(0, 0), Vector2(8, 0), wall_height, "wall")
	return root


static func connector(id: String, kind: String, span: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = id
	var length := 26.0 if kind == "ramp" else 10.0
	if span > 0:
		length = span
	var rise := 4.0 if kind in ["ramp", "stairs"] else 0.0
	root.set_meta("length", length)
	root.set_meta("rise", rise)
	root.set_meta("kind", kind)
	var section := [Vector2(0, 0), Vector2(1, 0), Vector2(length - 1, rise), Vector2(length, rise)]
	for index: int in 3:
		var a: Vector2 = section[index]
		var b: Vector2 = section[index + 1]
		var floor_points := _strip(a, b)
		var normal := Vector3(0, b.x - a.x, a.y - b.y).normalized()
		Shell.face(root, floor_points, normal, "floor", true, kind != "stairs" or index != 1)
		var roof_points := PackedVector3Array()
		for point: Vector3 in floor_points:
			roof_points.append(point + Vector3.UP * 3)
		Shell.face(root, roof_points, -normal, "roof")
		if kind != "stairs" or index != 1:
			for x: float in [-1.5, 1.5]:
				_side(root, x, a, b, 3, "grey" if kind == "sewer" else "wall")
	if kind == "stairs":
		_stairs(root, length, rise)
	if kind == "sewer":
		box(
			root,
			"DrainWater",
			Vector3(0.75, 0.01, length),
			Vector3(0, 0.006, length * 0.5),
			WATER,
			false
		)
		for side: float in [-1, 1]:
			box(
				root,
				"Pipe%s" % side,
				Vector3(0.16, 0.16, length),
				Vector3(side * 1.36, 2.5, length * 0.5),
				COVER,
				false
			)
	_end(root, "In", Vector3.ZERO, PI, 3, 3)
	_end(root, "Out", Vector3(0, rise, length), 0, 3, 3)
	return root


static func _stairs(root: Node3D, length: float, rise: float) -> void:
	for index: int in 24:
		var z0 := 1.0 + (length - 2) * index / 24.0
		var z1 := 1.0 + (length - 2) * (index + 1) / 24.0
		var y0 := rise * index / 24.0
		var y1 := rise * (index + 1) / 24.0
		Shell.face(root, _strip(Vector2(z0, y1), Vector2(z1, y1)), Vector3.UP, "floor", false)
		Shell.face(
			root,
			PackedVector3Array(
				[
					Vector3(-1.5, y0, z0),
					Vector3(1.5, y0, z0),
					Vector3(1.5, y1, z0),
					Vector3(-1.5, y1, z0)
				]
			),
			Vector3.FORWARD,
			"floor",
			false
		)
		for x: float in [-1.5, 1.5]:
			Shell.face(
				root,
				PackedVector3Array(
					[
						Vector3(x, y1, z0),
						Vector3(x, y1, z1),
						Vector3(x, y1 + 3, z1),
						Vector3(x, y0 + 3, z0)
					]
				),
				Vector3.LEFT if x > 0 else Vector3.RIGHT,
				"wall"
			)


static func _strip(a: Vector2, b: Vector2) -> PackedVector3Array:
	return PackedVector3Array(
		[
			Vector3(-1.5, a.y, a.x),
			Vector3(1.5, a.y, a.x),
			Vector3(1.5, b.y, b.x),
			Vector3(-1.5, b.y, b.x)
		]
	)


static func _plane(
	root: Node3D, width: float, length: float, y: float, material: String, normal: Vector3
) -> void:
	Shell.face(
		root,
		PackedVector3Array(
			[
				Vector3(-width / 2, y, 0),
				Vector3(width / 2, y, 0),
				Vector3(width / 2, y, length),
				Vector3(-width / 2, y, length)
			]
		),
		normal,
		material
	)


static func _side(
	root: Node3D, x: float, a: Vector2, b: Vector2, height: float, material: String
) -> void:
	Shell.face(
		root,
		PackedVector3Array(
			[
				Vector3(x, a.y, a.x),
				Vector3(x, b.y, b.x),
				Vector3(x, b.y + height, b.x),
				Vector3(x, a.y + height, a.x)
			]
		),
		Vector3.LEFT if x > 0 else Vector3.RIGHT,
		material
	)


static func _end(
	root: Node3D, id: String, origin: Vector3, yaw: float, width: float, height: float
) -> void:
	var socket := Socket.new()
	socket.name = id
	socket.profile = OPENING
	socket.position = origin
	socket.rotation.y = yaw
	root.add_child(socket)
	if width > 3:
		_end_wall(root, origin, yaw, -width / 2, -1.5, 0, height)
		_end_wall(root, origin, yaw, 1.5, width / 2, 0, height)
	if height > 3:
		_end_wall(root, origin, yaw, -1.5, 1.5, 3, height)
	var cap := Node3D.new()
	cap.name = "Cap"
	socket.add_child(cap)
	socket.cap = cap
	_end_wall(root, origin, yaw, -1.5, 1.5, 0, 3, cap)


static func _end_wall(
	root: Node3D,
	origin: Vector3,
	yaw: float,
	x0: float,
	x1: float,
	y0: float,
	y1: float,
	cap: Node3D = null
) -> void:
	var pose := Transform3D(Basis(Vector3.UP, yaw), origin)
	var points := PackedVector3Array()
	for point: Vector3 in [
		Vector3(x0, y0, 0), Vector3(x1, y0, 0), Vector3(x1, y1, 0), Vector3(x0, y1, 0)
	]:
		points.append(pose * point)
	Shell.face(root, points, pose.basis * Vector3.FORWARD, "wall", true, true, cap)


static func box(
	root: Node3D, id: String, size: Vector3, at: Vector3, material: Material, solid: bool = true
) -> void:
	# Solid primitives are for doors/props only; structural shells use indexed faces.
	var mesh := MeshInstance3D.new()
	mesh.name = id
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = material
	mesh.position = at
	root.add_child(mesh)
	if solid:
		var body := StaticBody3D.new()
		var collider := CollisionShape3D.new()
		var collision := BoxShape3D.new()
		collision.size = size
		collider.shape = collision
		body.add_child(collider)
		mesh.add_child(body)
