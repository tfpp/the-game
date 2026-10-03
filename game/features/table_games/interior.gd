extends Node3D
## Three furnished chambers share the casino's native GridMap kit.
const LIBRARY := preload("res://features/casino_hub/gridmap/casino_tiles.tres")


func _ready() -> void:
	var grid := GridMap.new()
	grid.name = "CasinoTiles"
	grid.mesh_library = LIBRARY
	grid.cell_size = Vector3(1, .25, 1)
	grid.cell_center_y = false
	grid.cell_octant_size = 8
	add_child(grid)
	var south := grid.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI))
	var west := grid.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI / 2))
	var east := grid.get_orthogonal_index_from_basis(Basis(Vector3.UP, -PI / 2))
	for x: int in range(-18, 18):
		for z: int in range(-6, 6):
			grid.set_cell_item(Vector3i(x, 0, z), 0)
			grid.set_cell_item(Vector3i(x, 16, z), 8)
	for x: int in range(-18, 18, 2):
		grid.set_cell_item(Vector3i(x, 0, -6), 3)
		grid.set_cell_item(Vector3i(x + 1, 0, 5), 3, south)
	var sides := GridMap.new()
	sides.mesh_library = LIBRARY
	sides.cell_size = grid.cell_size
	sides.cell_center_y = false
	add_child(sides)
	var reverse_sides := GridMap.new()
	reverse_sides.mesh_library = LIBRARY
	reverse_sides.cell_size = grid.cell_size
	reverse_sides.cell_center_y = false
	add_child(reverse_sides)
	for x: int in [-18, -6, 6, 18]:
		for z: int in range(-6, 6, 2):
			if abs(x) == 6 and z == 0:
				sides.set_cell_item(Vector3i(x, 0, z + 1), 7, west)
				continue
			if x == 18:
				sides.set_cell_item(Vector3i(x - 1, 0, z), 3, east)
			else:
				sides.set_cell_item(Vector3i(x, 0, z + 1), 3, west)
				if abs(x) == 6:
					reverse_sides.set_cell_item(Vector3i(x - 1, 0, z), 3, east)
	for x: int in [-12, 0, 12]:
		var light := OmniLight3D.new()
		light.position = Vector3(x, 3.4, 0)
		light.light_color = Color("ffd3a0")
		light.omni_range = 10
		light.light_energy = 1.8
		add_child(light)
