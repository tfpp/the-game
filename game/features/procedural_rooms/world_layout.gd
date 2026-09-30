extends RefCounted
## A fixed, socket-assembled vertical district used to validate the kit at world scale.

const Kit := preload("res://features/procedural_rooms/example_kit.gd")
const Shell := preload("res://features/procedural_rooms/shell_mesh.gd")
const Showcase := preload("res://features/procedural_rooms/showcase.gd")
const LIFT := preload("res://features/procedural_rooms/lift_stop.tscn")
const MOVING_LIFT := preload("res://features/procedural_rooms/moving_lift.tscn")
const GPS := preload("res://features/gps/gps_destination.gd")
const DOOR := preload("res://features/procedural_rooms/sliding_door.tscn")
const Population := preload("res://features/procedural_rooms/room_population.gd")
const RULE := preload("res://features/procedural_rooms/garage_population.tres")
const Lights := preload("res://features/procedural_rooms/garage_lights.gd")


static func build(
	parent: Node3D,
	seed_value: int = 73021,
	rules: Array[ProceduralPopulationRule] = [],
	casino_connection: bool = false
) -> Node3D:
	var world := Node3D.new()
	world.name = "CrownGarage"
	parent.add_child(world)
	var lift := MOVING_LIFT.instantiate() as ProceduralMovingLift
	lift.casino_connection = casino_connection
	world.add_child(lift)
	var shaft := _shaft(casino_connection)
	world.add_child(shaft)
	var decks: Array[Node3D] = []
	var west: Array[Node3D] = []
	var east: Array[Node3D] = []
	for floor_index: int in 5:
		var deck := _deck("Deck%d" % floor_index)
		world.add_child(deck)
		deck.position.y = floor_index * 4.0
		decks.append(deck)
		_destination(deck, "Garage B%d" % (5 - floor_index), Vector3(0, 0, 5))
		Showcase.placard(
			deck, "B%d   /   GOLDEN CROWN SERVICE GARAGE" % (5 - floor_index), Vector3(0, 2.8, 3)
		)
		for side: int in [-1, 1]:
			for end: int in 2:
				var landing := Kit.room(
					"%s%d_%d" % ["West" if side < 0 else "East", floor_index, end], false, 4.0
				)
				# Replace the original solid side face with a socket split.
				var faces: Array = landing.get_meta("shell_faces")
				faces.remove_at(10 if side < 0 else 11)
				Kit._end(landing, "Deck", Vector3(-side * 4, 0, 4), -side * PI / 2, 8, 4.0)
				world.add_child(landing)
				landing.position = Vector3(side * 25, floor_index * 4, end * 34)
				_join(
					deck.get_node(("West" if side < 0 else "East") + str(end)),
					landing.get_node("Deck")
				)
				(west if side < 0 else east).append(landing)
				var terminal := (floor_index == 0 and end == 1) or (floor_index == 4 and end == 0)
				Showcase.placard(
					landing,
					"SERVICE ROOM" if terminal else ("RAMP" if side < 0 else "STAIRS"),
					Vector3(0, 2.7, 4)
				)
				Showcase.portal(
					landing.get_node("Deck"), "GARAGE / B%d" % (5 - floor_index), Color("ffe2a2")
				)
				if terminal:
					Showcase.set_piece(landing, "utility" if side > 0 else "storage")
					var props := landing.get_node("SetPieces") as Node3D
					props.rotation.y = PI / 2
					props.position = Vector3(-4, 0, 4)  # Keep the side-wall garage entrance clear.
					_destination(
						landing,
						"Service room B%d / %s" % [5 - floor_index, "west" if side < 0 else "east"],
						Vector3(0, 0, 4)
					)
		var cab := Kit.room("LiftLobby%d" % floor_index, false, 4.0)
		# Landing slabs stop before the gate; only the narrow sill bridges to the cab.
		for face: Dictionary in cab.get_meta("shell_faces"):
			if face["material"] not in ["floor", "roof"]:
				continue
			var points: PackedVector3Array = face["points"]
			for point: int in points.size():
				points[point].z = minf(points[point].z, 7.88)
			face["points"] = points
		world.add_child(cab)
		socket_attach(deck.get_node("Lift"), cab.get_node("In"))
		Showcase.set_piece(cab, "utility")
		_join(cab.get_node("Out"), shaft.get_node("Floor%d" % floor_index))
		var gate := DOOR.instantiate() as ProceduralSlidingDoor
		gate.name = "ShaftGate%d" % floor_index
		gate.managed_by_lift = true
		world.add_child(gate)
		gate.global_transform = cab.get_node("Out").global_transform
		lift.gates.append(gate)
		var stop := LIFT.instantiate() as Node3D
		stop.set("floor_index", floor_index)
		cab.add_child(stop)
		stop.position = Vector3(-2, 0, 7.5)
		_destination(cab, "Elevator B%d" % (5 - floor_index), Vector3(0, 0, 4))
		Population.populate(deck, _rule(floor_index, rules), seed_value + floor_index * 104729)
		_decorate(deck, floor_index, seed_value)
	for floor_index: int in 4:
		var ramp := Kit.connector("Ramp%d" % floor_index, "ramp")
		world.add_child(ramp)
		socket_attach(west[floor_index * 2].get_node("Out"), ramp.get_node("In"))
		_join(ramp.get_node("Out"), west[(floor_index + 1) * 2 + 1].get_node("In"))
		var stairs := Kit.connector("Stairs%d" % floor_index, "stairs")
		world.add_child(stairs)
		socket_attach(east[floor_index * 2].get_node("Out"), stairs.get_node("In"))
		var hall := Kit.connector("StairLanding%d" % floor_index, "hall", 16)
		world.add_child(hall)
		socket_attach(stairs.get_node("Out"), hall.get_node("In"))
		_join(hall.get_node("Out"), east[(floor_index + 1) * 2 + 1].get_node("In"))
	var sewer := Kit.connector("Sewer", "sewer")
	world.add_child(sewer)
	socket_attach(decks[0].get_node("Sewer"), sewer.get_node("In"))
	_door(decks[0], decks[0].get_node("Sewer"), "SewerDoor")
	var pump := Kit.room("PumpRoom", false, 4.0)
	world.add_child(pump)
	socket_attach(sewer.get_node("Out"), pump.get_node("In"))
	Showcase.set_piece(pump, "pump")
	_destination(pump, "Sewer pump station", Vector3(0, 0, 4))
	Showcase.placard(decks[0], "SEWER / PUMP STATION →", Vector3(0, 2.6, 39))
	if casino_connection:
		(shaft.get_node("Floor5") as ProceduralSocketAttachment).open("casino-east-doorway")
		var gate := DOOR.instantiate() as ProceduralSlidingDoor
		gate.name = "CasinoGate"
		gate.managed_by_lift = true
		world.add_child(gate)
		gate.position = Vector3(0, 22, -8)
		lift.gates.append(gate)
		var stop := LIFT.instantiate() as Node3D
		stop.name = "CasinoCall"
		stop.set("floor_index", 5)
		stop.set("lift_path", NodePath("../Lift"))
		world.add_child(stop)
		stop.position = Vector3(-2.1, 22, -7.95)
		stop.rotation.y = PI
		var sign := Showcase.placard(
			world, "SERVICE ELEVATOR\nC / CASINO  •  B1–B5", Vector3(0, 25.25, -7.85)
		)
		sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sign.add_to_group(&"render_zone_shared")
	Shell.rebuild(world)
	var collision := world.get_node("Structure/ShellCollision").get_child(0) as CollisionShape3D
	(collision.shape as ConcavePolygonShape3D).backface_collision = true
	# The same wall face is visible from either side, including outside terminal rooms.
	# Keep a single joined mesh rather than duplicating outward faces or wall blocks.
	var walls := world.get_node("Structure/Wall") as MeshInstance3D
	var wall_material := walls.material_override.duplicate() as StandardMaterial3D
	wall_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	walls.material_override = wall_material
	var rail_mesh := world.get_node("Structure/Grey") as MeshInstance3D
	var rail_material := rail_mesh.material_override.duplicate() as StandardMaterial3D
	rail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	rail_mesh.material_override = rail_material
	return world


static func repopulate(
	world: Node3D, seed_value: int, rules: Array[ProceduralPopulationRule] = []
) -> void:
	for index: int in 5:
		Population.populate(
			world.get_node("Deck%d" % index), _rule(index, rules), seed_value + index * 104729
		)


static func _rule(index: int, rules: Array[ProceduralPopulationRule]) -> ProceduralPopulationRule:
	if index < rules.size() and rules[index] != null:
		return rules[index]
	var rule := RULE.duplicate() as ProceduralPopulationRule
	if index < 2:
		rule.allowed_sets = ["storage", "utility", "pump", "garage"]
		rule.weights = PackedFloat32Array([3, 3, 2, 1])
	return rule


static func _door(parent: Node3D, socket: Node3D, id: String) -> void:
	var door := DOOR.instantiate() as ProceduralSlidingDoor
	door.name = id
	door.net_open = true
	parent.add_child(door)
	door.global_transform = socket.global_transform


static func _shaft(casino_connection: bool = false) -> Node3D:
	var shaft := Node3D.new()
	shaft.name = "LiftShaft"
	# Enclose the continuous shaft; openings are guarded by interlocked landing doors.
	for index: int in 6 if casino_connection else 5:
		var height := ProceduralMovingLift.floor_height(index)
		Kit._end(shaft, "Floor%d" % index, Vector3(0, height, -8), 0, 4, 4)
		Shell.face(
			shaft,
			PackedVector3Array(
				[
					Vector3(-1.5, height, -8.22),
					Vector3(1.5, height, -8.22),
					Vector3(1.5, height, -7.88),
					Vector3(-1.5, height, -7.88)
				]
			),
			Vector3.UP,
			"floor"
		)
	var top := 26.0 if casino_connection else 20.0
	if casino_connection:
		Kit._end_wall(shaft, Vector3(0, 20, -8), 0, -2, 2, 0, 2)
	Kit._side(shaft, -2, Vector2(-12, 0), Vector2(-8, 0), top, "grey")
	Kit._side(shaft, 2, Vector2(-12, 0), Vector2(-8, 0), top, "grey")
	Kit._end_wall(shaft, Vector3(0, 0, -12), PI, -2, 2, 0, top)
	for y: float in [-.2, top]:
		Shell.face(
			shaft,
			PackedVector3Array(
				[Vector3(-2, y, -12), Vector3(2, y, -12), Vector3(2, y, -8), Vector3(-2, y, -8)]
			),
			Vector3.UP if y < 0 else Vector3.DOWN,
			"floor" if y < 0 else "roof"
		)
	return shaft


static func socket_attach(from: ProceduralSocketAttachment, to: ProceduralSocketAttachment) -> void:
	var errors := ProceduralSocketAttachment.attach(from, to, str(from.get_path()))
	assert(errors.is_empty(), str(errors))


static func _join(from: ProceduralSocketAttachment, to: ProceduralSocketAttachment) -> void:
	assert(from.join_id.is_empty() and to.join_id.is_empty())
	assert(from.errors_with(to).is_empty(), str(from.errors_with(to)))
	from.open(str(from.get_path()))
	to.open(from.join_id)


static func _deck(id: String) -> Node3D:
	var deck := Node3D.new()
	deck.name = id
	# Four broad strips surround a 20 x 18 m open atrium.
	for rect: Rect2 in [
		Rect2(-21, 0, 42, 12), Rect2(-21, 30, 42, 12), Rect2(-21, 12, 11, 18), Rect2(10, 12, 11, 18)
	]:
		var points := PackedVector3Array(
			[
				Vector3(rect.position.x, 0, rect.position.y),
				Vector3(rect.end.x, 0, rect.position.y),
				Vector3(rect.end.x, 0, rect.end.y),
				Vector3(rect.position.x, 0, rect.end.y)
			]
		)
		Shell.face(deck, points, Vector3.UP, "floor")
		points = points.duplicate()
		for index: int in points.size():
			points[index].y = 3.5
		Shell.face(deck, points, Vector3.DOWN, "roof")
	Kit._end(deck, "Lift", Vector3.ZERO, PI, 42, 4.0)
	Kit._end(deck, "Sewer", Vector3(0, 0, 42), 0, 42, 4.0)
	for side: int in [-1, 1]:
		for end: int in 2:
			Kit._end(
				deck,
				("West" if side < 0 else "East") + str(end),
				Vector3(side * 21, 0, 4 + end * 34),
				side * PI / 2,
				8,
				4.0
			)
		Kit._side(deck, side * 21, Vector2(8, 0), Vector2(34, 0), 4.0, "wall")
	# Rails are two-sided planar collision faces, not blocks or hidden boxes.
	for pair: Array in [
		[Vector3(-10, 0, 12), Vector3(10, 0, 12)],
		[Vector3(10, 0, 12), Vector3(10, 0, 30)],
		[Vector3(10, 0, 30), Vector3(-10, 0, 30)],
		[Vector3(-10, 0, 30), Vector3(-10, 0, 12)]
	]:
		var a: Vector3 = pair[0]
		var b: Vector3 = pair[1]
		var normal := (b - a).cross(Vector3.UP).normalized()
		Shell.face(deck, PackedVector3Array([a, b, b + Vector3.UP, a + Vector3.UP]), normal, "grey")
		Shell.face(
			deck, PackedVector3Array([b, a, a + Vector3.UP, b + Vector3.UP]), -normal, "grey"
		)
	return deck


static func _decorate(deck: Node3D, index: int, seed_value: int) -> void:
	var titles: Array[String] = [
		"PUMPS / SERVICE STORAGE",
		"MAINTENANCE",
		"FREIGHT STORAGE",
		"ABANDONED PARKING",
		"ELEVATOR ARRIVAL"
	]
	Showcase.placard(deck, "B%d / %s" % [5 - index, titles[index]], Vector3(0, 2.7, 39))
	Showcase.placard(deck, "← RAMPS     /     STAIRS →", Vector3(0, 2.5, 8))
	Showcase.placard(deck, "↑ ELEVATOR / RETURN", Vector3(0, 2.5, 34))
	var sign := Showcase.placard(deck, "ELEVATOR / B%d" % (5 - index), Vector3(0, 3.25, 0.25))
	sign.name = "ElevatorSign"
	sign.font_size = 48
	sign.pixel_size = 0.008
	sign.modulate = Color("ffe2a2")
	var beacon := OmniLight3D.new()
	beacon.name = "ElevatorBeacon"
	beacon.position = Vector3(0, 2.5, 1)
	beacon.light_color = Color("ffc67a")
	beacon.light_energy = 1.8
	beacon.omni_range = 8
	deck.add_child(beacon)
	var fluorescents := Lights.new()
	fluorescents.name = "Fluorescents"
	deck.add_child(fluorescents)
	fluorescents.build(index, seed_value)


static func _destination(module: Node3D, label: String, at: Vector3) -> void:
	var marker := GPS.new()
	marker.label = label
	marker.hint = "Socket world prototype"
	marker.position = at
	module.add_child(marker)
