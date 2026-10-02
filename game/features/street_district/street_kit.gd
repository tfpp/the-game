extends RefCounted
## Open-air modules share the garage's socket attachment and canonical shell builder.

const SOCKET := preload("res://features/procedural_rooms/socket_attachment.gd")
const STREET := preload("res://features/street_district/profiles/street_12m.tres")
const WALK := preload("res://features/procedural_rooms/profiles/walk_3m.tres")
const SHELL := preload("res://features/procedural_rooms/shell_mesh.gd")
const CATALOGUE := preload("res://features/street_district/catalogue.gd")


static func junction(id: String) -> Node3D:
	var node := Node3D.new()
	node.name = id
	node.set_meta("kind", "junction")
	node.set_meta("footprint", AABB(Vector3(-6, 0, 0), Vector3(12, 0, 12)))
	var xs := [-6.0, -4.0, 4.0, 6.0]
	var zs := [0.0, 2.0, 10.0, 12.0]
	for x: int in range(3):
		for z: int in range(3):
			var material := "sidewalk" if x != 1 and z != 1 else "asphalt"
			_floor(node, xs[x], xs[x + 1], zs[z], zs[z + 1], material)
	_socket(node, "In", Vector3.ZERO, PI, STREET)
	_socket(node, "Out", Vector3(0, 0, 12), 0, STREET)
	_socket(node, "West", Vector3(-6, 0, 6), -PI / 2, STREET)
	_socket(node, "East", Vector3(6, 0, 6), PI / 2, STREET)
	return node


static func street(id: String, length: float = 16) -> Node3D:
	var node := Node3D.new()
	node.name = id
	node.set_meta("kind", "street")
	node.set_meta("footprint", AABB(Vector3(-6, 0, 0), Vector3(12, 0, length)))
	_floor(node, -4, 4, 0, length, "asphalt")
	_floor(node, -6, -4, 0, length, "sidewalk")
	_floor(node, 4, 6, 0, length, "sidewalk")
	_socket(node, "In", Vector3.ZERO, PI, STREET)
	_socket(node, "Out", Vector3(0, 0, length), 0, STREET)
	_socket(node, "West", Vector3(-6, 0, length / 2), -PI / 2, WALK)
	_socket(node, "East", Vector3(6, 0, length / 2), PI / 2, WALK)
	return node


static func alley(id: String, length: float = 16) -> Node3D:
	var node := Node3D.new()
	node.name = id
	node.set_meta("kind", "alley")
	node.set_meta("footprint", AABB(Vector3(-1.5, 0, 0), Vector3(3, 0, length)))
	_floor(node, -1.5, 1.5, 0, length, "alley")
	_socket(node, "In", Vector3.ZERO, PI, WALK)
	_socket(node, "Out", Vector3(0, 0, length), 0, WALK)
	return node


static func _floor(node: Node3D, x0: float, x1: float, z0: float, z1: float, mat: String) -> void:
	SHELL.face(
		node,
		PackedVector3Array(
			[Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)]
		),
		Vector3.UP,
		mat
	)


static func _socket(
	node: Node3D, id: String, at: Vector3, yaw: float, profile: ProceduralSocketProfile
) -> void:
	var socket := SOCKET.new()
	socket.name = id
	socket.position = at
	socket.rotation.y = yaw
	socket.profile = profile
	node.add_child(socket)
	var cap := Node3D.new()
	cap.name = "Cap"
	socket.add_child(cap)
	socket.cap = cap
	var points := PackedVector3Array()
	var pose := Transform3D(Basis(Vector3.UP, yaw), at)
	for point: Vector3 in profile.boundary():
		points.append(pose * point)
	# Same cap ownership as the garage: opening a join removes visual and collision caps.
	SHELL.face(node, points, pose.basis * Vector3.FORWARD, "closure", true, false, cap)
	for x: float in range(-int(profile.width / 2) + 1, int(profile.width / 2), 2):
		CATALOGUE.prop(cap, "chain_link_fence", Vector3(x, 0, 0))
	if profile.width > 3:
		for x: float in [-3.0, 0.0, 3.0]:
			CATALOGUE.prop(cap, "concrete_barrier", Vector3(x, 0, -.8))
			CATALOGUE.prop(cap, "traffic_cone", Vector3(x, 0, -1.5))
