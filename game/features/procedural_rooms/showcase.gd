extends RefCounted
## Reusable modeled props, visible socket frames, and a separated assembly gallery.

const Kit := preload("res://features/procedural_rooms/example_kit.gd")
const DOOR := preload("res://features/procedural_rooms/sliding_door.tscn")
const ORANGE := preload("res://features/procedural_rooms/materials/orange.tres")
const GREY := preload("res://features/procedural_rooms/materials/grey.tres")
const COVER := preload("res://features/procedural_rooms/materials/cover.tres")
const WATER := preload("res://features/procedural_rooms/materials/water.tres")
const DARK := preload("res://features/procedural_rooms/materials/dark.tres")
const HAZARD := preload("res://features/procedural_rooms/materials/hazard.tres")
const CAR := preload("res://features/procedural_rooms/props/car.tscn")
const CRATE := preload("res://features/procedural_rooms/props/crate.tscn")
const BARREL := preload("res://features/procedural_rooms/props/barrel.tscn")
const CABINET := preload("res://features/procedural_rooms/service_cabinet.tscn")


static func decorate(world: Node3D) -> void:
	var doors := Node3D.new()
	doors.name = "Doors"
	world.add_child(doors)
	for kind: String in ["Ramp", "Stairs", "Sewer"]:
		var lane := world.get_node("Routes/" + kind)
		var arrival := lane.get_node("Arrival") as Node3D
		var destination := lane.get_node("Destination") as Node3D
		set_piece(arrival, {"Ramp": "garage", "Stairs": "utility", "Sewer": "pump"}[kind])
		set_piece(destination, "pump" if kind == "Sewer" else "storage")
		var socket := arrival.get_node("Out") as ProceduralSocketAttachment
		var door := DOOR.instantiate() as ProceduralSlidingDoor
		door.name = kind + "Door"
		doors.add_child(door)
		door.global_transform = socket.global_transform
		placard(arrival, kind.to_upper() + " / W03 DOOR", Vector3(-2.65, 2.75, 7.65))
	var seen: Dictionary[String, bool] = {}
	for socket: ProceduralSocketAttachment in world.find_children(
		"*", "ProceduralSocketAttachment", true, false
	):
		if socket.join_id.is_empty() or seen.has(socket.join_id):
			continue
		seen[socket.join_id] = true
		portal(socket, socket.join_id, Color("51dbcf"))


static func set_piece(root: Node3D, kind: String) -> void:
	var props := Node3D.new()
	props.name = "SetPieces"
	root.add_child(props)
	match kind:
		"garage":
			_prop(props, CAR, "Car", Vector3(-2.75, 0, 4))
			Kit.box(props, "Column", Vector3(0.7, 3.5, 0.7), Vector3(2.8, 1.75, 3.2), GREY)
			Kit.box(props, "Barrier", Vector3(0.5, 0.85, 2.6), Vector3(2.8, 0.425, 5.4), HAZARD)
		"utility":
			for z: float in [2.5, 4.0, 5.5]:
				var cabinet := CABINET.instantiate() as Node3D
				cabinet.name = "Cabinet%s" % z
				cabinet.position = Vector3(-3.5, 0, z)
				props.add_child(cabinet)
			Kit.box(props, "ServiceBench", Vector3(1.2, 0.85, 2.7), Vector3(2.8, 0.425, 4), ORANGE)
		"pump":
			for z: float in [2.0, 6.0]:
				var mesh := MeshInstance3D.new()
				mesh.name = "Tank%s" % z
				var cylinder := CylinderMesh.new()
				cylinder.radial_segments = 8
				cylinder.height = 2.6
				cylinder.top_radius = 0.65
				cylinder.bottom_radius = 0.65
				mesh.mesh = cylinder
				mesh.material_override = WATER
				mesh.position = Vector3(-2.75, 1.3, z)
				props.add_child(mesh)
				var body := StaticBody3D.new()
				var collider := CollisionShape3D.new()
				var shape := CylinderShape3D.new()
				shape.radius = 0.65
				shape.height = 2.6
				collider.shape = shape
				body.add_child(collider)
				mesh.add_child(body)
			_prop(props, BARREL, "BarrelA", Vector3(2.8, 0, 2.3))
			_prop(props, BARREL, "BarrelB", Vector3(2.8, 0, 3.4))
			Kit.box(props, "PumpMotor", Vector3(1.1, 0.7, 0.9), Vector3(2.8, 0.35, 6.7), COVER)
			Kit.box(props, "Pipe", Vector3(0.25, 0.25, 6), Vector3(-3.65, 2.65, 4), GREY, false)
		"storage":
			for side: float in [-1, 1]:
				for index: int in 3:
					_prop(
						props,
						CRATE,
						"Crate%s_%d" % [side, index],
						Vector3(side * 2.8, 0, 2.4 + index * 1.35)
					)
				_prop(props, CRATE, "StackedCrate%s" % side, Vector3(side * 2.8, 1, 3.75))
	placard(root, kind.to_upper() + " SET", Vector3(-2.7, 3.1, 1.6))


static func portal(socket: Node3D, id: String, color: Color) -> void:
	var marker := Node3D.new()
	marker.name = "SocketDisplay"
	socket.add_child(marker)
	marker.add_to_group(&"socket_displays")
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for side: float in [-1, 1]:
		Kit.box(
			marker,
			"Edge%s" % side,
			Vector3(0.055, 3, 0.055),
			Vector3(side * 1.54, 1.5, 0),
			material,
			false
		)
	Kit.box(marker, "Top", Vector3(3.13, 0.055, 0.055), Vector3(0, 3.04, 0), material, false)
	Kit.box(marker, "FloorEdge", Vector3(3, 0.005, 0.07), Vector3(0, 0.006, 0), material, false)
	placard(marker, "W03 / " + id, Vector3(0, 3.35, 0))


static func placard(root: Node3D, text: String, at: Vector3) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = 28
	label.pixel_size = 0.0035
	label.modulate = Color("f4ead8")
	label.outline_size = 4
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = at
	root.add_child(label)
	return label


static func gallery(world: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "AssemblyGallery"
	world.add_child(root)
	root.position = Vector3(-20, 0, -55)
	Kit.box(root, "Platform", Vector3(18, 0.2, 40), Vector3(0, -0.3, 16), DARK)
	var pieces := [
		Kit.room("GarageBay"), Kit.connector("HallConnector", "hall"), Kit.room("PumpChamber", true)
	]
	var positions := [Vector3.ZERO, Vector3(0, 0, 12), Vector3(0, 0, 26)]
	for index: int in pieces.size():
		var module := pieces[index] as Node3D
		root.add_child(module)
		module.position = positions[index]
		module.set_meta("display_only", true)
		if index != 1:
			set_piece(module, "garage" if index == 0 else "pump")
		for socket: ProceduralSocketAttachment in module.find_children(
			"*", "ProceduralSocketAttachment", true, false
		):
			if is_instance_valid(socket.cap):
				socket.cap.free()
				socket.cap = null
			portal(socket, "MATING FACE", Color("51dbcf"))
	var door := DOOR.instantiate() as ProceduralSlidingDoor
	door.name = "DoorAttachment"
	root.add_child(door)
	door.position = Vector3(0, 0, 10)
	for item: Array in [
		["01 GARAGE BAY", 4.0],
		["02 DOOR / W03", 10.0],
		["03 HALL / W03", 17.0],
		["04 PUMP CHAMBER", 30.0]
	]:
		placard(root, item[0], Vector3(0, 4.5, item[1])).add_to_group(&"catalogue_labels")
	for z: float in [8.9, 23.2]:
		placard(root, "SNAP W03 TO W03", Vector3(0, 0.15, z))
	return root


static func _prop(root: Node3D, scene: PackedScene, id: String, at: Vector3) -> void:
	var instance := scene.instantiate() as Node3D
	instance.name = id
	instance.position = at
	root.add_child(instance)
