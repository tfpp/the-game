extends RefCounted
## Initial layout recipe. Cells are saved in the scene, not regenerated at runtime.

const CELL_SIZE := Vector3(1, 0.25, 1)
const FLOOR := 0
const WALL := 1
const RAMP := 2
const WOOD_WALL := 3
const PIT_WALL := 4
const DOOR_HEADER := 7
const STANDARD_WALL_HEIGHT := 5.0
const PIT_HEIGHT := STANDARD_WALL_HEIGHT / 4.0
const PIT_LAYER := -5
const WEST := -24
const EAST := 24
const NORTH := -20
const SOUTH := 20


static func populate(floors: GridMap, walls: GridMap, side_walls: GridMap) -> void:
	for grid: GridMap in [floors, walls, side_walls]:
		grid.clear()
		grid.cell_size = CELL_SIZE
		grid.cell_center_y = false
	for x: int in range(WEST, EAST):
		for z: int in range(NORTH, SOUTH):
			var pit := x >= -15 and x < 15 and z >= -12 and z < 12
			var ramp := x >= -3 and x < 3 and ((z >= -12 and z < -6) or (z >= 6 and z < 12))
			if not ramp:
				floors.set_cell_item(Vector3i(x, PIT_LAYER if pit else 0, z), FLOOR)
	# Six solid wedge strips span each 6 m run, rising one quarter-wall height.
	var reverse := floors.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI))
	for x: int in range(-3, 3):
		floors.set_cell_item(Vector3i(x, PIT_LAYER, -9), RAMP)
		floors.set_cell_item(Vector3i(x, PIT_LAYER, 8), RAMP, reverse)
	_build_walls(walls, side_walls)


static func _build_walls(walls: GridMap, side_walls: GridMap) -> void:
	var south := walls.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI))
	var west := walls.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI / 2))
	var east := walls.get_orthogonal_index_from_basis(Basis(Vector3.UP, -PI / 2))
	for x: int in range(WEST, EAST, 2):
		if x < -4 or x >= 4:
			walls.set_cell_item(Vector3i(x, 0, NORTH), WOOD_WALL)
		walls.set_cell_item(
			Vector3i(x + 1, 0, SOUTH - 1), DOOR_HEADER if x >= -2 and x < 2 else WOOD_WALL, south
		)
	for z: int in range(NORTH, SOUTH, 2):
		side_walls.set_cell_item(Vector3i(WEST, 0, z + 1), WOOD_WALL, west)
		side_walls.set_cell_item(Vector3i(EAST - 1, 0, z), WOOD_WALL, east)
	for x: int in range(-15, 15):
		if x >= -3 and x < 3:
			continue
		walls.set_cell_item(Vector3i(x, PIT_LAYER, -12), PIT_WALL)
		walls.set_cell_item(Vector3i(x, PIT_LAYER, 11), PIT_WALL, south)
	for z: int in range(-12, 12):
		side_walls.set_cell_item(Vector3i(-15, PIT_LAYER, z), PIT_WALL, west)
		side_walls.set_cell_item(Vector3i(14, PIT_LAYER, z), PIT_WALL, east)
