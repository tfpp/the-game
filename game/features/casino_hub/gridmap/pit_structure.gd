extends RefCounted
## Offline architecture recipe; the result is saved as editable scene nodes.

const Layout := preload("res://features/casino_hub/gridmap/layout.gd")
const COLUMN := preload("res://features/room_kits/wooden_support_column.tscn")
const BRASS := preload("res://features/casino_hub/materials/brass.tres")
const CEILING_HEIGHT := Layout.STANDARD_WALL_HEIGHT * 2.0 - Layout.PIT_HEIGHT
const CEILING_LAYER := 35


static func configure(level: Node3D) -> void:
	var previous := level.get_node_or_null("PitStructure")
	if previous != null:
		level.remove_child(previous)
		previous.free()
	var structure := Node3D.new()
	structure.name = "PitStructure"
	level.add_child(structure)
	structure.owner = level
	for x: int in [-13, 13]:
		for z: int in [-10, 10]:
			var tower := Node3D.new()
			tower.name = "Column_%s_%s" % [x, z]
			tower.position = Vector3(x, -Layout.PIT_HEIGHT, z)
			structure.add_child(tower)
			tower.owner = level
			for story: int in 2:
				var section := COLUMN.instantiate() as Node3D
				section.name = "Story%s" % (story + 1)
				section.position.y = story * Layout.STANDARD_WALL_HEIGHT
				tower.add_child(section)
				section.owner = level
	populate_upper_walls(level)
	var ceiling := level.get_node("Ceiling") as GridMap
	for cell: Vector3i in ceiling.get_used_cells():
		if cell.z >= Layout.NORTH and cell.z < Layout.SOUTH:
			var item := ceiling.get_cell_item(cell)
			var orientation := ceiling.get_cell_item_orientation(cell)
			ceiling.set_cell_item(cell, GridMap.INVALID_CELL_ITEM)
			ceiling.set_cell_item(Vector3i(cell.x, CEILING_LAYER, cell.z), item, orientation)
	(level.get_node("Ceiling/Body") as Node3D).position.y = CEILING_HEIGHT + 0.1
	# Keep the fixtures and their light pools at their established heights.
	var decor := level.get_node("Decor") as GridMap
	var chain := CylinderMesh.new()
	chain.top_radius = 0.025
	chain.bottom_radius = 0.025
	chain.height = CEILING_HEIGHT - Layout.STANDARD_WALL_HEIGHT
	chain.radial_segments = 6
	chain.rings = 1
	chain.material = BRASS
	for cell: Vector3i in decor.get_used_cells_by_item(2):
		if cell.z >= Layout.SOUTH:
			continue
		var suspension := MeshInstance3D.new()
		suspension.name = "Suspension_%s_%s" % [cell.x, cell.z]
		suspension.mesh = chain
		suspension.position = decor.map_to_local(cell) + Vector3(0, chain.height / 2.0, 0)
		structure.add_child(suspension)
		suspension.owner = level


static func populate_upper_walls(level: Node3D) -> void:
	var structure := level.get_node("PitStructure") as Node3D
	for name: String in ["UpperWallsNorthSouth", "UpperWallsEastWest"]:
		var previous := structure.get_node_or_null(name)
		if previous != null:
			structure.remove_child(previous)
			previous.free()
		var grid := GridMap.new()
		grid.name = name
		grid.mesh_library = (level.get_node("WallsNorthSouth") as GridMap).mesh_library
		grid.cell_size = Layout.CELL_SIZE
		grid.cell_center_y = false
		grid.cell_octant_size = 4
		grid.position.y = Layout.STANDARD_WALL_HEIGHT
		structure.add_child(grid)
		grid.owner = level
		var south := grid.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI))
		var west := grid.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI / 2))
		var east := grid.get_orthogonal_index_from_basis(Basis(Vector3.UP, -PI / 2))
		if name == "UpperWallsNorthSouth":
			for x: int in range(Layout.WEST, Layout.EAST):
				grid.set_cell_item(Vector3i(x, 0, Layout.NORTH), 14)
				grid.set_cell_item(Vector3i(x, 0, Layout.SOUTH - 1), 14, south)
		else:
			for z: int in range(Layout.NORTH, Layout.SOUTH):
				grid.set_cell_item(Vector3i(Layout.WEST, 0, z), 14, west)
				grid.set_cell_item(Vector3i(Layout.EAST - 1, 0, z), 14, east)
