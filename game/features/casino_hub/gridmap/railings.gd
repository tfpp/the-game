extends RefCounted
## Two-metre spans and shared posts, saved as editable cells around the pit rim.

const SPAN := 9
const POST := 10


static func populate(grid: GridMap, side_grid: GridMap, post_grid: GridMap) -> void:
	grid.clear()
	side_grid.clear()
	post_grid.clear()
	var posts: Dictionary[Vector3i, bool] = {}
	var turn := grid.get_orthogonal_index_from_basis(Basis(Vector3.UP, -PI / 2))
	for z: int in [-12, 12]:
		for start: int in [-15, 3]:
			for x: int in range(start, start + 12, 2):
				grid.set_cell_item(Vector3i(x, 0, z), SPAN)
			for x: int in range(start, start + 13, 2):
				posts[Vector3i(x, 0, z)] = true
	for x: int in [-15, 15]:
		for z: int in range(-12, 12, 2):
			side_grid.set_cell_item(Vector3i(x, 0, z), SPAN, turn)
		for z: int in range(-12, 13, 2):
			posts[Vector3i(x, 0, z)] = true
	for cell: Vector3i in posts:
		post_grid.set_cell_item(cell, POST)
