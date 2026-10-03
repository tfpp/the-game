extends RefCounted
## Remove the vacant former mall/trampoline wing, keeping its travel corridor.


static func trim(level: Node3D) -> void:
	for name: String in ["Floors", "Ceiling", "ShopWallsNorthSouth", "ShopWallsEastWest"]:
		var grid := level.get_node(name) as GridMap
		for cell: Vector3i in grid.get_used_cells():
			if cell.x >= 2 and cell.z >= 20:
				grid.set_cell_item(cell, GridMap.INVALID_CELL_ITEM)
	# The live mall portal sits on this wall and teleports from the corridor.
	var sides := level.get_node("ShopWallsEastWest") as GridMap
	for z: int in range(20, 30, 2):
		sides.set_cell_item(
			Vector3i(1, 0, z), 3, sides.get_orthogonal_index_from_basis(Basis(Vector3.UP, -PI / 2))
		)
	var roof := level.get_node_or_null("FoodRoof")
	if roof != null:
		roof.free()
	var decor := level.get_node("Decor") as GridMap
	for cell: Vector3i in decor.get_used_cells():
		# Keep inward-facing fixtures on the casino's south wall.
		if (
			cell.x > 2
			and (cell.z > 20 or (cell.z == 20 and decor.get_cell_item_orientation(cell) == 0))
		):
			decor.set_cell_item(cell, GridMap.INVALID_CELL_ITEM)
