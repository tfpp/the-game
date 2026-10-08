extends RefCounted
## Offline recipe: recess the casino's existing metro cab behind the south wall.


static func configure(level: Node3D) -> void:
	var walls := level.get_node("WallsNorthSouth") as GridMap
	var shops := level.get_node("ShopWallsNorthSouth") as GridMap
	var south := walls.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI))
	# Both decorated faces share z=20. Retain their upper panels over the doorway.
	for x: int in [-14, -12]:
		walls.set_cell_item(Vector3i(x + 1, 0, 19), 7, south)
		shops.set_cell_item(Vector3i(x, 0, 20), 7)
	# Keep the existing painting, but not across the elevator sign and entrance globes.
	var decor := level.get_node("Decor") as GridMap
	var painting := Vector3i(-12, 12, 20)
	if decor.get_cell_item(painting) != GridMap.INVALID_CELL_ITEM:
		var item := decor.get_cell_item(painting)
		var orientation := decor.get_cell_item_orientation(painting)
		decor.set_cell_item(painting, GridMap.INVALID_CELL_ITEM)
		decor.set_cell_item(Vector3i(-20, 12, 20), item, orientation)
	# Close the 0.3 m seams beside the 3.4 m entrance in the four-metre panel opening.
	# Reuse the wood wall tile; these saved GridMaps introduce no new mesh/material.
	for side: String in ["Left", "Right"]:
		var name := "MetroAlcove" + side
		var trim := level.get_node_or_null(name) as GridMap
		if trim == null:
			trim = GridMap.new()
			trim.name = name
			level.add_child(trim)
			trim.owner = level
		trim.mesh_library = walls.mesh_library
		trim.cell_size = walls.cell_size
		trim.cell_center_x = false
		trim.cell_center_y = false
		trim.cell_center_z = false
		trim.scale = Vector3(0.15, 1, 1)
		trim.position = Vector3(-13.775 if side == "Left" else -10.075, 0, 19.5)
		trim.set_cell_item(Vector3i.ZERO, 3, south)
	var access := level.get_node_or_null("MetroAccess") as Node3D
	if access == null:
		access = Node3D.new()
		access.set_script(load("res://features/metro/metro_access.gd"))
		access.name = "MetroAccess"
		level.add_child(access)
		access.owner = level
		access.set("zone_id", "crown")
		access.set("label", "Golden Crown")
		access.set("station", 0)
		access.set("slot", 0)
	# Cab depth is 3.2 m along local -Z; the door plane is 0.2 m behind the marker.
	# Existing former-shop floor and ceiling support the entire recessed footprint.
	access.position = Vector3(-12, 0, 19.8)
	access.rotation.y = PI
