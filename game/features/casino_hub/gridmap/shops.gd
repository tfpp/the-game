extends RefCounted
## Ground-level shops adjoining the south promenade; saved as native GridMap cells.

const Layout := preload("res://features/casino_hub/gridmap/layout.gd")
const TILE_FLOOR := 5
const WOOD_FLOOR := 6
const HEADER := 7


static func populate(floors: GridMap, walls: GridMap, sides: GridMap) -> void:
	for grid: GridMap in [walls, sides]:
		grid.clear()
		grid.cell_size = Layout.CELL_SIZE
		grid.cell_center_y = false
	_floor(floors, Rect2i(-16, 20, 14, 10), WOOD_FLOOR)
	_floor(floors, Rect2i(-2, 20, 4, 10), Layout.FLOOR)
	_floor(floors, Rect2i(2, 20, 32, 18), TILE_FLOOR)
	var south := walls.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI))
	var west := sides.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI / 2))
	var east := sides.get_orthogonal_index_from_basis(Basis(Vector3.UP, -PI / 2))
	for x: int in range(-16, -2, 2):
		walls.set_cell_item(Vector3i(x, 0, 20), Layout.WOOD_WALL)
		walls.set_cell_item(Vector3i(x + 1, 0, 29), Layout.WOOD_WALL, south)
	for x: int in range(2, 34, 2):
		walls.set_cell_item(Vector3i(x, 0, 20), Layout.WOOD_WALL)
		walls.set_cell_item(Vector3i(x + 1, 0, 37), Layout.WOOD_WALL, south)
	for x: int in range(-2, 2, 2):
		walls.set_cell_item(Vector3i(x + 1, 0, 29), Layout.WOOD_WALL, south)
	for z: int in range(20, 30, 2):
		sides.set_cell_item(Vector3i(-16, 0, z + 1), Layout.WOOD_WALL, west)
		sides.set_cell_item(Vector3i(-3, 0, z), Layout.WOOD_WALL, east)
	for z: int in range(20, 38, 2):
		sides.set_cell_item(Vector3i(33, 0, z), Layout.WOOD_WALL, east)
		var item := HEADER if z >= 24 and z < 28 else Layout.WOOD_WALL
		sides.set_cell_item(Vector3i(2, 0, z + 1), item, west)
	# The corridor faces need the decorated back of each shop partition too.
	for z: int in range(20, 30, 2):
		var item := HEADER if z >= 24 and z < 28 else Layout.WOOD_WALL
		sides.set_cell_item(Vector3i(-2, 0, z + 1), Layout.WOOD_WALL, west)
		sides.set_cell_item(Vector3i(1, 0, z), item, east)


static func _floor(grid: GridMap, bounds: Rect2i, item: int) -> void:
	for x: int in range(bounds.position.x, bounds.end.x):
		for z: int in range(bounds.position.y, bounds.end.y):
			grid.set_cell_item(Vector3i(x, 0, z), item)
