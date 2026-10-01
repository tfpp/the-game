extends RefCounted
## Fixed route graph: every placement after the anchor is solved by the garage sockets.

const KIT := preload("res://features/street_district/street_kit.gd")
const SHELL := preload("res://features/procedural_rooms/shell_mesh.gd")
const CATALOGUE := preload("res://features/street_district/catalogue.gd")
const ASPHALT := preload("res://features/street_district/materials/asphalt.tres")
const SIDEWALK := preload("res://features/street_district/materials/sidewalk.tres")
const ALLEY := preload("res://features/street_district/materials/alley.tres")
const ROOMS := preload("res://features/casino_wing/room_kit.gd")
const COUNTER := preload("res://features/hotel_props/props/reception_counter.tscn")
const MARQUEE := preload("res://features/street_district/props/casino_marquee.tscn")


static func build(parent: Node3D) -> Node3D:
	var level := Node3D.new()
	level.name = "District"
	parent.add_child(level)
	var junctions: Array[Array] = []
	var horizontals: Array[Array] = []
	for row: int in range(3):
		var nodes: Array[Node3D] = []
		for column: int in range(3):
			var junction := KIT.junction("J%d%d" % [row, column])
			level.add_child(junction)
			nodes.append(junction)
		junctions.append(nodes)
		if row == 0:
			(nodes[0] as Node3D).position = Vector3(-28, 0, -6)
		else:
			var connector := KIT.street("V%d0" % (row - 1))
			level.add_child(connector)
			_join(level, junctions[row - 1][0], "Out", connector, "In")
			_join(level, connector, "Out", nodes[0], "In")
		var streets: Array[Node3D] = []
		for column: int in range(2):
			var connector := KIT.street("H%d%d" % [row, column])
			level.add_child(connector)
			_join(level, nodes[column], "East", connector, "In")
			_join(level, connector, "Out", nodes[column + 1], "West")
			streets.append(connector)
		horizontals.append(streets)
	for row: int in range(2):
		for column: int in range(1, 3):
			var connector := KIT.street("V%d%d" % [row, column])
			level.add_child(connector)
			_join(level, junctions[row][column], "Out", connector, "In")
			_join(level, connector, "Out", junctions[row + 1][column], "In", true)
	for row: int in range(2):
		for column: int in range(2):
			var alley := KIT.alley("Alley%d%d" % [row, column])
			level.add_child(alley)
			_join(level, horizontals[row][column], "West", alley, "In")
			_join(level, alley, "Out", horizontals[row + 1][column], "East", true)
			_furnish_alley(alley)
			_build_block(
				level,
				horizontals[row][column],
				column * 28 - 14,
				row * 28 + 14,
				row * 4 + column * 2
			)
	_outer_buildings(level)
	_casino_frontage(level)
	SHELL.rebuild(
		level,
		{
			"asphalt": ASPHALT,
			"sidewalk": SIDEWALK,
			"alley": ALLEY,
			"floor": SIDEWALK,
			"wall": ALLEY,
			"roof": ALLEY
		}
	)
	for row: int in range(3):
		for column: int in range(2):
			_furnish_street(horizontals[row][column], row == 1 and column == 0)
	return level


static func _join(
	level: Node3D, from: Node3D, exit: String, to: Node3D, entry: String, close_loop: bool = false
) -> void:
	var a := from.get_node(exit) as ProceduralSocketAttachment
	var b := to.get_node(entry) as ProceduralSocketAttachment
	if close_loop:
		assert(a.errors_with(b).is_empty(), "Loop must already align before attachment")
	var id := "%s-%s-%s-%s" % [from.name, exit, to.name, entry]
	# Release exports strip assert expressions; placement must always execute.
	var errors := ProceduralSocketAttachment.attach(a, b, id)
	if not errors.is_empty():
		push_error("Street socket join %s failed: %s" % [id, ", ".join(errors)])
		return
	var joins: Array = level.get_meta("joins", [])
	joins.append({"from": a, "to": b})
	level.set_meta("joins", joins)


static func _build_block(level: Node3D, street: Node3D, x: float, z: float, index: int) -> void:
	var paving := Node3D.new()
	paving.name = "BlockPaving%d" % index
	level.add_child(paving)
	for side: int in [-1, 1]:
		var width := 6.5
		var center := x + side * 4.75
		var visitable := index in [1, 6]
		if visitable:
			KIT._floor(paving, center - width / 2, center + width / 2, z - 8, z - 7.1, "alley")
			KIT._floor(paving, center - width / 2, center + width / 2, z + 7.1, z + 8, "alley")
			KIT._floor(paving, center - width / 2, center - 3, z - 7.1, z + 7.1, "alley")
			KIT._floor(paving, center + 3, center + width / 2, z - 7.1, z + 7.1, "alley")
		else:
			KIT._floor(paving, center - width / 2, center + width / 2, z - 8, z + 8, "alley")
		var building := CATALOGUE.BUILDINGS[index].instantiate() as Node3D
		level.add_child(building)
		building.position = Vector3(center, 0, z)
		# Blender -Y becomes Godot +Z; frontages face the street at lower world Z.
		building.rotation.y = PI
		if visitable:
			_interior(level, street, building, index)
		else:
			CATALOGUE.prop(level, "service_door", Vector3(center, 0, z - 7.15), PI)
		index += 1
		if index % 2 == 0 and not visitable:
			CATALOGUE.prop(level, "rolling_shutter", Vector3(center, 0, z + 7.15))
			CATALOGUE.prop(level, "air_conditioner", Vector3(center, 3, z - 7.2), PI)


static func _interior(level: Node3D, street: Node3D, building: Node3D, index: int) -> void:
	var front := building.to_global(Vector3(0, 0, 7.1))
	var local := street.to_local(front)
	var name := "Shop" if index == 1 else "Workshop"
	KIT._socket(street, name + "Entry", local, -street.rotation.y, KIT.WALK)
	var room := ROOMS.room(name + "Front", 5.36, 6, 3.3)
	level.add_child(room)
	room.set_meta("building", building)
	_join(level, street, name + "Entry", room, "In")
	var back := ROOMS.room(name + "Back", 5.36, 7.96, 3.3)
	level.add_child(back)
	back.set_meta("building", building)
	_join(level, room, "Out", back, "In")
	var counter := COUNTER.instantiate() as Node3D
	room.add_child(counter)
	counter.position = Vector3(-1.9, 0, 3)
	counter.rotation.y = PI / 2
	CATALOGUE.prop(room, "street_bench", Vector3(2.1, 0, 3), -PI / 2)
	CATALOGUE.prop(back, "wooden_crate", Vector3(-2.0, 0, 3))
	CATALOGUE.prop(back, "electrical_cabinet", Vector3(2.1, 0, 5))
	for interior: Node3D in [room, back]:
		var light := OmniLight3D.new()
		light.position = Vector3(0, 2.8, 3)
		light.omni_range = 8
		light.light_color = Color("e6d8b5")
		light.light_energy = 1.3
		interior.add_child(light)


static func _outer_buildings(level: Node3D) -> void:
	var closed := [0, 2, 3, 4, 5, 7, 8, 9]
	for i: int in range(5):
		for side: int in [-1, 1]:
			var building := CATALOGUE.BUILDINGS[closed[i % 8]].instantiate() as Node3D
			level.add_child(building)
			building.position = Vector3(side * 39, 0, i * 14)
			building.scale = Vector3(14.0 / 6.0, 1.0, 8.0 / 14.2)
			building.rotation.y = -side * PI / 2
			var frontage := CATALOGUE.BUILDINGS[closed[(i + 3) % 8]].instantiate() as Node3D
			level.add_child(frontage)
			frontage.position = Vector3(i * 14 - 28, 0, -14 if side < 0 else 70)
			frontage.scale = Vector3(2.34, .8, 1.0)
			frontage.rotation.y = 0 if side < 0 else PI


static func _furnish_street(street: Node3D, shelter: bool) -> void:
	for side: int in [-1, 1]:
		# The lamp arm runs along authored +X; the other front-facing props use +Z.
		CATALOGUE.prop(street, "street_lamp", Vector3(side * 5.4, 0, 3), PI if side > 0 else 0)
		CATALOGUE.prop(street, "parking_meter", Vector3(side * 4.6, 0, 12), -side * PI / 2)
		var light := OmniLight3D.new()
		light.position = Vector3(side * 4.3, 4.8, 3)
		light.light_color = Color("e8c28a")
		light.light_energy = 1.3
		light.omni_range = 9
		street.add_child(light)
	if shelter:
		CATALOGUE.prop(street, "bus_shelter", Vector3(5.1, 0, 12), -PI / 2)
	else:
		CATALOGUE.prop(street, "street_bench", Vector3(5.4, 0, 12), -PI / 2)
	CATALOGUE.prop(street, "street_trash_can", Vector3(5.3, 0, 14.5))
	CATALOGUE.prop(street, "fire_hydrant", Vector3(-4.8, 0, 13.8), PI / 2)


static func _furnish_alley(alley: Node3D) -> void:
	# Preserve a central 1.7 m walking lane and the entire socket approach.
	CATALOGUE.prop(alley, "garbage_bag", Vector3(1.13, 0, 4))
	CATALOGUE.prop(alley, "steel_barrel", Vector3(1.15, 0, 11))
	CATALOGUE.prop(alley, "wooden_crate", Vector3(-1.12, 0, 12.5), PI)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 3.8, 8)
	light.light_color = Color("a7c1c8")
	light.light_energy = .65
	light.omni_range = 11
	alley.add_child(light)


static func _casino_frontage(level: Node3D) -> void:
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color("a78136")
	gold.roughness = .9
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("18282a")
	dark.roughness = 1
	var pieces: Array[Array] = [
		[Vector3(18.75, 4.25, 34.65), Vector3(5.8, 1.6, .25), dark],
		[Vector3(18.75, 3.1, 34.4), Vector3(5.8, .25, 1.4), gold],
		[Vector3(16.35, 1.5, 34.65), Vector3(.22, 3, .22), gold],
		[Vector3(21.15, 1.5, 34.65), Vector3(.22, 3, .22), gold],
	]
	for piece: Array in pieces:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = piece[1]
		mesh.mesh = box
		mesh.material_override = piece[2]
		mesh.position = piece[0]
		level.add_child(mesh)
	var sign := MARQUEE.instantiate() as Node3D
	sign.name = "CasinoSign"
	sign.position = Vector3(18.75, 4.25, 34.49)
	sign.rotation.y = PI
	level.add_child(sign)
	var light := OmniLight3D.new()
	light.position = Vector3(18.75, 3.3, 33.5)
	light.light_color = Color("ffd17e")
	light.light_energy = 1.4
	light.omni_range = 6
	level.add_child(light)
