extends RefCounted
## Hotel boundaries use the garage socket API, W03 halls and 1.2m guest doors.

const SHELL := preload("res://features/procedural_rooms/shell_mesh.gd")
const WALK := preload("res://features/procedural_rooms/profiles/walk_3m.tres")
const DOOR := preload("res://features/street_hotel/profiles/guest_door.tres")
const SPEC := preload("res://features/street_hotel/spec.gd")


static func corridor(id: String) -> Node3D:
	var node := _base(id, 3, 6)
	_boundary(node, "In", Vector3.ZERO, PI, 3, WALK)
	_boundary(node, "Out", Vector3(0, 0, 6), 0, 3, WALK)
	_boundary(node, "West", Vector3(-1.5, 0, 3), -PI / 2, 6, DOOR)
	_boundary(node, "East", Vector3(1.5, 0, 3), PI / 2, 6, DOOR)
	return node


static func lobby() -> Node3D:
	var node := _base("Lobby", SPEC.WIDTH, 12)
	# Remove both deck and ceiling over the continuous elevator shaft.
	node.remove_meta("shell_faces")
	for height: float in [0.0, SPEC.HEIGHT]:
		var normal := Vector3.UP if height == 0 else Vector3.DOWN
		for rect: Rect2 in [
			Rect2(-9.5, 0, SPEC.SHAFT_X0 + 9.5, 12),
			Rect2(SPEC.SHAFT_X1, 0, 9.5 - SPEC.SHAFT_X1, 12),
			Rect2(SPEC.SHAFT_X0, 0, 4, SPEC.SHAFT_Z0),
			Rect2(SPEC.SHAFT_X0, SPEC.SHAFT_Z1, 4, 12 - SPEC.SHAFT_Z1),
		]:
			_face(
				node,
				PackedVector3Array(
					[
						Vector3(rect.position.x, height, rect.position.y),
						Vector3(rect.end.x, height, rect.position.y),
						Vector3(rect.end.x, height, rect.end.y),
						Vector3(rect.position.x, height, rect.end.y),
					]
				),
				normal,
				"floor" if height == 0 else "roof"
			)
	_boundary(node, "Out", Vector3(0, 0, 12), 0, SPEC.WIDTH, WALK)
	_wall(node, Vector3.ZERO, PI, -9.5, 9.5, 0, SPEC.HEIGHT)
	_wall(node, Vector3(-9.5, 0, 6), -PI / 2, -6, 6, 0, SPEC.HEIGHT)
	_wall(node, Vector3(9.5, 0, 6), PI / 2, -6, 6, 0, SPEC.HEIGHT)
	return node


static func guest(id: String) -> Node3D:
	var node := _base(id, 6, 8)
	_boundary(node, "In", Vector3.ZERO, PI, 6, DOOR)
	_wall(node, Vector3(-3, 0, 4), -PI / 2, -4, 4, 0, SPEC.HEIGHT)
	_wall(node, Vector3(3, 0, 4), PI / 2, -4, 4, 0, SPEC.HEIGHT)
	# Actual window opening; sill and header retain collision. The pane blocks falling.
	_wall(node, Vector3(0, 0, 8), 0, -3, -1.9, 0, SPEC.HEIGHT)
	_wall(node, Vector3(0, 0, 8), 0, 1.9, 3, 0, SPEC.HEIGHT)
	_wall(node, Vector3(0, 0, 8), 0, -1.9, 1.9, 0, .9)
	_wall(node, Vector3(0, 0, 8), 0, -1.9, 1.9, 2.7, SPEC.HEIGHT)
	_wall(node, Vector3(0, 0, 8), 0, -1.9, 1.9, .9, 2.7, "glass", true, false)
	return node


static func _base(id: String, width: float, length: float) -> Node3D:
	var node := Node3D.new()
	node.name = id
	node.set_meta("dimensions", Vector3(width, SPEC.HEIGHT, length))
	_face(
		node,
		PackedVector3Array(
			[
				Vector3(-width / 2, 0, 0),
				Vector3(width / 2, 0, 0),
				Vector3(width / 2, 0, length),
				Vector3(-width / 2, 0, length)
			]
		),
		Vector3.UP,
		"floor"
	)
	_face(
		node,
		PackedVector3Array(
			[
				Vector3(-width / 2, SPEC.HEIGHT, 0),
				Vector3(width / 2, SPEC.HEIGHT, 0),
				Vector3(width / 2, SPEC.HEIGHT, length),
				Vector3(-width / 2, SPEC.HEIGHT, length)
			]
		),
		Vector3.DOWN,
		"roof"
	)
	return node


static func _boundary(
	node: Node3D, id: String, at: Vector3, yaw: float, span: float, profile: ProceduralSocketProfile
) -> void:
	var socket := ProceduralSocketAttachment.new()
	socket.name = id
	socket.position = at
	socket.rotation.y = yaw
	socket.profile = profile
	node.add_child(socket)
	var cap := Node3D.new()
	cap.name = "Cap"
	socket.add_child(cap)
	socket.cap = cap
	var h := profile.width / 2
	_wall(node, at, yaw, -span / 2, -h, 0, SPEC.HEIGHT)
	_wall(node, at, yaw, h, span / 2, 0, SPEC.HEIGHT)
	_wall(node, at, yaw, -h, h, profile.height, SPEC.HEIGHT)
	var points := PackedVector3Array()
	for point: Vector3 in profile.boundary():
		points.append(at + Basis(Vector3.UP, yaw) * point)
	SHELL.face(node, points, -Basis(Vector3.UP, yaw).z, "wall", true, true, cap)


static func _wall(
	node: Node3D,
	at: Vector3,
	yaw: float,
	x0: float,
	x1: float,
	y0: float,
	y1: float,
	material: String = "wall",
	solid: bool = true,
	visible: bool = true
) -> void:
	if x1 <= x0 or y1 <= y0:
		return
	var basis := Basis(Vector3.UP, yaw)
	var points := PackedVector3Array()
	for point: Vector3 in [
		Vector3(x0, y0, 0), Vector3(x1, y0, 0), Vector3(x1, y1, 0), Vector3(x0, y1, 0)
	]:
		points.append(at + basis * point)
	SHELL.face(node, points, -basis.z, material, solid, visible)


static func _face(
	node: Node3D, points: PackedVector3Array, normal: Vector3, material: String
) -> void:
	SHELL.face(node, points, normal, material)
