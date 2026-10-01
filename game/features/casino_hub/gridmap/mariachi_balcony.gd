extends RefCounted
## Offline west extension, stair flight and furnished mezzanine above the mariachi.

const Layout := preload("res://features/casino_hub/gridmap/layout.gd")
const BAR := preload("res://assets/casino_hub/models/salon_bar.glb")
const FINISHES := preload("res://features/casino_hub/model_materials.gd")
const STOOL := preload("res://features/casino_hub/models/casino_stool.tscn")
const COLUMN := preload("res://features/room_kits/wooden_support_column.tscn")
const WEST := -32
const BALCONY_Y := 5.0


static func configure(level: Node3D) -> void:
	var previous := level.get_node_or_null("MariachiBalcony")
	if previous != null:
		level.remove_child(previous)
		previous.free()
	var area := Node3D.new()
	area.name = "MariachiBalcony"
	area.set_script(FINISHES)
	level.add_child(area)
	area.owner = level
	var floors := level.get_node("Floors") as GridMap
	for x: int in range(WEST, -24):
		for z: int in range(-14, 12):
			floors.set_cell_item(Vector3i(x, 0, z), 0)
	var sides := level.get_node("WallsEastWest") as GridMap
	for cell: Vector3i in sides.get_used_cells_by_item(3):
		if cell.x == -24 and cell.z >= -14 and cell.z < 12:
			sides.set_cell_item(cell, GridMap.INVALID_CELL_ITEM)
	var upper := level.get_node("PitStructure/UpperWallsEastWest") as GridMap
	for cell: Vector3i in upper.get_used_cells():
		if cell.x == -24 and cell.z >= -14 and cell.z < 12:
			upper.set_cell_item(cell, GridMap.INVALID_CELL_ITEM)
	var outer := _grid(area, level, "OuterWalls")
	var upper_outer := _grid(area, level, "UpperOuterWalls")
	upper_outer.position.y = 5.0
	var west := outer.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI / 2))
	var south := outer.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI))
	for z: int in range(-14, 12, 2):
		outer.set_cell_item(Vector3i(WEST, 0, z + 1), 3, west)
	for z: int in range(-14, 12):
		upper_outer.set_cell_item(Vector3i(WEST, 0, z), 14, west)
	for x: int in range(WEST, -24, 2):
		outer.set_cell_item(Vector3i(x, 0, -14), 3)
		outer.set_cell_item(Vector3i(x + 1, 0, 11), 3, south)
	for x: int in range(WEST, -24):
		upper_outer.set_cell_item(Vector3i(x, 0, -14), 14)
		upper_outer.set_cell_item(Vector3i(x, 0, 11), 14, south)
	var ceiling := level.get_node("Ceiling") as GridMap
	for x: int in range(WEST, -24):
		for z: int in range(-14, 12):
			ceiling.set_cell_item(Vector3i(x, 35, z), 8)
	var roof := StaticBody3D.new()
	roof.name = "ExtensionRoof"
	roof.position = Vector3(-28, 8.85, -1)
	area.add_child(roof)
	roof.owner = level
	var roof_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 0.2, 26)
	roof_shape.shape = box
	roof.add_child(roof_shape)
	roof_shape.owner = level
	var deck := _grid(area, level, "Deck")
	for x: int in range(WEST, -18):
		for z: int in range(-4, 6):
			deck.set_cell_item(Vector3i(x, 20, z), 6)
	var stairs := _grid(area, level, "Stairs")
	for story: int in 4:
		for x: int in range(-30, -26):
			stairs.set_cell_item(Vector3i(x, story * 5, -12 + story * 2), 15)
	var rails := _grid(area, level, "Rails", true)
	var posts := _grid(area, level, "Posts", true)
	var stair_rails := _grid(area, level, "StairRails", true)
	var turn := rails.get_orthogonal_index_from_basis(Basis(Vector3.UP, -PI / 2))
	for x: int in range(WEST, -18, 2):
		rails.set_cell_item(Vector3i(x, 20, 6), 9)
		posts.set_cell_item(Vector3i(x, 20, 6), 10)
		if x < -30 or x >= -26:
			rails.set_cell_item(Vector3i(x, 20, -4), 9)
			posts.set_cell_item(Vector3i(x, 20, -4), 10)
	for z: int in range(-4, 6, 2):
		rails.set_cell_item(Vector3i(-18, 20, z), 9, turn)
		posts.set_cell_item(Vector3i(-18, 20, z), 10)
	posts.set_cell_item(Vector3i(-18, 20, 6), 10)
	for x: int in [-30, -26]:
		for story: int in 4:
			stair_rails.set_cell_item(Vector3i(x, story * 5, -12 + story * 2), 16)
			posts.set_cell_item(Vector3i(x, story * 5, -12 + story * 2), 10)
		posts.set_cell_item(Vector3i(x, 20, -4), 10)
	for z: int in [-3, 5]:
		var column := COLUMN.instantiate() as Node3D
		column.name = "Support_%s" % z
		column.position = Vector3(-18.7, 0, z)
		area.add_child(column)
		column.owner = level
	var bar := BAR.instantiate() as Node3D
	bar.name = "Bar"
	bar.position = Vector3(-30.5, 5, 1)
	bar.rotation.y = PI / 2
	FINISHES.apply_finishes(bar)
	area.add_child(bar)
	bar.owner = level
	var counter := StaticBody3D.new()
	counter.name = "BarCounter"
	counter.position = Vector3(-29.4, 5.49, 1)
	area.add_child(counter)
	counter.owner = level
	var shape := CollisionShape3D.new()
	var counter_box := BoxShape3D.new()
	counter_box.size = Vector3(0.4, 0.98, 7)
	shape.shape = counter_box
	counter.add_child(shape)
	shape.owner = level
	for z: int in [-1, 1, 3]:
		var stool := STOOL.instantiate() as Node3D
		stool.name = "Stool_%s" % z
		stool.position = Vector3(-28.2, 5, z)
		area.add_child(stool)
		stool.owner = level
	var destination := Marker3D.new()
	destination.name = "BalconyBar"
	destination.position = Vector3(-25, 5, 0)
	destination.set_script(load("res://features/gps/gps_destination.gd"))
	destination.set("label", "Mariachi Balcony Bar")
	destination.set("hint", "Above the mariachi stage; stairs in the west extension.")
	area.add_child(destination)
	destination.owner = level
	# Relocate existing west-wall decor into the extension rather than adding lights.
	var decor := level.get_node("Decor") as GridMap
	for cell: Vector3i in decor.get_used_cells():
		if cell.x == -24 and cell.z >= -14 and cell.z < 12:
			var item := decor.get_cell_item(cell)
			var orientation := decor.get_cell_item_orientation(cell)
			decor.set_cell_item(cell, GridMap.INVALID_CELL_ITEM)
			decor.set_cell_item(Vector3i(WEST, cell.y, cell.z), item, orientation)


static func _grid(area: Node3D, level: Node3D, name: String, exact := false) -> GridMap:
	var grid := GridMap.new()
	grid.name = name
	grid.mesh_library = (level.get_node("Floors") as GridMap).mesh_library
	grid.cell_size = Layout.CELL_SIZE
	grid.cell_octant_size = 4
	grid.cell_center_y = false
	grid.cell_center_x = not exact
	grid.cell_center_z = not exact
	area.add_child(grid)
	grid.owner = level
	return grid
