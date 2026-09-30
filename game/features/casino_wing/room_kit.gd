extends RefCounted
## Variable room dimensions and four genuine W03 boundaries; unused doors stay capped.

const KIT := preload("res://features/procedural_rooms/example_kit.gd")


static func room(id: String, width: float, length: float, height: float = 3.5) -> Node3D:
	var node := Node3D.new()
	node.name = id
	node.set_meta("dimensions", Vector3(width, height, length))
	KIT._plane(node, width, length, 0, "floor", Vector3.UP)
	KIT._plane(node, width, length, height, "roof", Vector3.DOWN)
	KIT._end(node, "In", Vector3.ZERO, PI, width, height)
	KIT._end(node, "Out", Vector3(0, 0, length), 0, width, height)
	KIT._end(node, "West", Vector3(-width / 2, 0, length / 2), -PI / 2, length, height)
	KIT._end(node, "East", Vector3(width / 2, 0, length / 2), PI / 2, length, height)
	return node
