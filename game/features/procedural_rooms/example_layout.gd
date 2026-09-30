extends RefCounted
## Three socket-assembled examples. This is a join prototype, not a general solver.

const Kit := preload("res://features/procedural_rooms/example_kit.gd")
const Shell := preload("res://features/procedural_rooms/shell_mesh.gd")


static func build(parent: Node) -> Node3D:
	var root := Node3D.new()
	root.name = "SocketExamples"
	parent.add_child(root)
	var routes := Node3D.new()
	routes.name = "Routes"
	root.add_child(routes)
	for index: int in 3:
		var kind: String = ["ramp", "stairs", "sewer"][index]
		var lane := Node3D.new()
		lane.name = kind.capitalize()
		lane.position.x = (index - 1) * 20
		routes.add_child(lane)
		var start := Kit.room("Arrival")
		lane.add_child(start)
		var connector := Kit.connector(kind.capitalize(), kind)
		_join(lane, start.get_node("Out"), connector)
		var finish := Kit.room("Destination", kind == "sewer")
		_join(lane, connector.get_node("Out"), finish)
		if kind == "sewer":
			var turn := Kit.connector("SideTunnel", "sewer")
			_join(lane, finish.get_node("Out"), turn)
			_join(lane, turn.get_node("Out"), Kit.room("PumpRoom"))
		_label(start, kind.to_upper() + " / SOCKET LAB", Vector3(0, 2.4, 7.85))
		_label(finish, "FLUSH JOIN / " + kind.to_upper(), Vector3(-2.7, 2.4, 4))
	Shell.rebuild(root)
	return root


static func _join(root: Node3D, from: ProceduralSocketAttachment, module: Node3D) -> void:
	root.add_child(module)
	var to := module.get_node("In") as ProceduralSocketAttachment
	var id := str(from.get_parent().name) + "_" + str(module.name)
	var errors := ProceduralSocketAttachment.attach(from, to, id)
	assert(errors.is_empty(), str(errors))


static func _label(root: Node3D, text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.font_size = 32
	label.pixel_size = 0.0025
	label.modulate = Color("fff0d0")
	label.no_depth_test = false
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)
