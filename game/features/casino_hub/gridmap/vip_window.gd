extends RefCounted
## Offline wall inset. The saved pane keeps the casino hull sealed in previews too.

const WINDOW := preload("res://features/vip_lounge/window.tscn")


static func configure(level: Node3D) -> void:
	var upper := level.get_node("PitStructure/UpperWallsEastWest") as GridMap
	for z: int in range(-12, 12):
		upper.set_cell_item(Vector3i(23, 0, z), GridMap.INVALID_CELL_ITEM)
	var previous := level.get_node_or_null("VipWindow")
	if previous != null:
		previous.free()
	var window := WINDOW.instantiate() as Node3D
	window.name = "VipWindow"
	window.position = Vector3(24, 6.875, 0)
	level.add_child(window)
	window.owner = level
