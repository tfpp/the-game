extends RefCounted
## Configure the existing garage lift; the hotel only owns its shaft and landing layout.

const SPEC := preload("res://features/street_hotel/spec.gd")
const LIFT := preload("res://features/procedural_rooms/moving_lift.tscn")
const GATE := preload("res://features/procedural_rooms/sliding_door.tscn")
const STOP := preload("res://features/procedural_rooms/lift_stop.tscn")
const PANEL := preload("res://features/street_hotel/elevator_panel.tscn")
const KIT := preload("res://features/street_hotel/room_kit.gd")
const SHELL := preload("res://features/procedural_rooms/shell_mesh.gd")
const WOOD := preload("res://assets/casino_hub/textures/walnut_albedo.png")


static func build(parent: Node3D, floors: Array[StreamedRoom]) -> ProceduralMovingLift:
	var lift := LIFT.instantiate() as ProceduralMovingLift
	lift.name = "Lift"
	lift.position = SPEC.LIFT_CENTER + Vector3(0, 0, 9.5)
	lift.initial_floor = 0
	lift.control_panel = PANEL
	for index: int in SPEC.FLOORS:
		lift.stop_heights.append(index * SPEC.STOREY)
		lift.stop_labels.append(str(index + 1))
	parent.add_child(lift)
	var shaft := Node3D.new()
	shaft.name = "LiftShaft"
	parent.add_child(shaft)
	var walls := Node3D.new()
	walls.name = "ShaftGeometry"
	shaft.add_child(walls)
	var top := SPEC.FLOORS * SPEC.STOREY
	KIT._wall(walls, Vector3(4, 0, 3.85), -PI / 2, -1.65, 1.65, 0, top, "steel")
	KIT._wall(walls, Vector3(8, 0, 3.85), PI / 2, -1.65, 1.65, 0, top, "steel")
	KIT._wall(walls, Vector3(6, 0, 2.2), PI, -2, 2, 0, top, "steel")
	for index: int in SPEC.FLOORS:
		var y := index * SPEC.STOREY
		KIT._wall(walls, Vector3(6, y, 5.5), 0, -2, -1.5, 0, SPEC.STOREY, "steel")
		KIT._wall(walls, Vector3(6, y, 5.5), 0, 1.5, 2, 0, SPEC.STOREY, "steel")
		KIT._wall(walls, Vector3(6, y, 5.5), 0, -1.5, 1.5, 3, SPEC.STOREY, "steel")
		# A narrow threshold joins the cab; the remaining shaft stays hollow.
		(
			SHELL
			. face(
				walls,
				PackedVector3Array(
					[
						Vector3(4.5, y, 5.28),
						Vector3(7.5, y, 5.28),
						Vector3(7.5, y, 5.5),
						Vector3(4.5, y, 5.5),
					]
				),
				Vector3.UP,
				"steel"
			)
		)
		var gate := GATE.instantiate() as ProceduralSlidingDoor
		gate.name = "LiftGate"
		gate.managed_by_lift = true
		gate.position = Vector3(6, 0, 5.5)
		floors[index].add_child(gate)
		lift.gates.append(gate)
		var button := STOP.instantiate() as Node3D
		button.name = "LiftCall"
		button.position = Vector3(8.55, 0, 5.9)
		button.set("floor_index", index)
		button.set("lift_path", NodePath("../../Lift"))
		floors[index].add_child(button)
		for sign: Label3D in button.find_children("*", "Label3D", true, false):
			sign.rotation.y = 0
			sign.position.z = .06
		var label := Label3D.new()
		label.text = "CROWN HOTEL · %d" % (index + 1)
		label.position = Vector3(6, 3.23, 5.6)
		label.font_size = 24
		label.pixel_size = .003
		floors[index].add_child(label)
	var material := StandardMaterial3D.new()
	material.albedo_texture = WOOD
	material.albedo_color = Color("957956")
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(.5, .5, .5)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	SHELL.rebuild(shaft, {"steel": material})
	var collider := shaft.get_node("Structure/ShellCollision").get_child(0) as CollisionShape3D
	(collider.shape as ConcavePolygonShape3D).backface_collision = true
	lift._update_doors()
	return lift
