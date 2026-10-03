extends SceneTree
## Offline recipe. The runtime scene preserves hand-editable GridMap cells.

const LIBRARY := preload("res://features/strip_mall/tiles.tres")


func _initialize() -> void:
	var root := Node3D.new()
	root.name = "MallStructure"
	var floors := _grid(root, "Paving")
	var parking := _grid(root, "Parking")
	var walls := _grid(root, "ShopWalls")
	var partitions := _grid(root, "Partitions")
	var roof := _grid(root, "ShopRoof")
	var fascia := _grid(root, "Fascia")
	fascia.position.y = 4.25
	fascia.scale.y = .25
	var canopies := _grid(root, "Awnings")
	var posts := _grid(root, "Posts")
	var windows := _grid(root, "Windows")
	var planters := _grid(root, "Planters")
	var west := walls.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI / 2))
	for x: int in range(2, 34):
		for z: int in range(18, 40):
			floors.set_cell_item(Vector3i(x, 0, z), 0)
	for x: int in range(-8, 2):
		for z: int in range(18, 40):
			parking.set_cell_item(Vector3i(x, 0, z), 1)
	for z: int in [20, 24, 28, 32, 36]:
		for x: int in range(-7, -1):
			parking.set_cell_item(
				Vector3i(x, 0, z),
				8,
				parking.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI / 2))
			)
	for z: int in range(18, 40):
		walls.set_cell_item(Vector3i(33, 0, z), 2, west)
		fascia.set_cell_item(Vector3i(33, 0, z), 2, west)
		canopies.set_cell_item(Vector3i(29, 0, z), 4)
		for x: int in range(29, 34):
			roof.set_cell_item(Vector3i(x, 16, z), 3)
	for z: int in [18, 25, 32, 39]:
		for x: int in range(29, 34):
			partitions.set_cell_item(Vector3i(x, 0, z), 2)
		posts.set_cell_item(Vector3i(27, 0, z), 6)
	for z: int in [19, 24, 26, 31, 33, 38]:
		windows.set_cell_item(Vector3i(29, 0, z), 5, west)
	for x: int in [5, 11, 17, 23]:
		planters.set_cell_item(Vector3i(x, 0, 19), 7)
		planters.set_cell_item(Vector3i(x, 0, 38), 7)
	# Brick site boundaries guard the remote scene edges without a ceiling.
	var border := _grid(root, "Boundary")
	for x: int in range(-8, 34):
		for z: int in [18, 39]:
			border.set_cell_item(Vector3i(x, 0, z), 9)
	for z: int in range(18, 40):
		border.set_cell_item(Vector3i(-8, 0, z), 9, west)
	# Solid return kiosk supports the modeled portal; it is not a floating door.
	var kiosk := _grid(root, "ReturnKiosk")
	for z: int in range(26, 31):
		kiosk.set_cell_item(Vector3i(2, 0, z), 2, west)
	for x: int in range(0, 2):
		for z: int in [26, 30]:
			kiosk.set_cell_item(Vector3i(x, 0, z), 2)
	for x: int in range(0, 3):
		for z: int in range(26, 31):
			roof.set_cell_item(Vector3i(x, 16, z), 3)
	var packed := PackedScene.new()
	assert(packed.pack(root) == OK)
	assert(ResourceSaver.save(packed, "res://features/strip_mall/structure.tscn") == OK)
	root.free()
	quit()


func _grid(root: Node3D, label: String) -> GridMap:
	var grid := GridMap.new()
	grid.name = label
	grid.mesh_library = LIBRARY
	grid.cell_size = Vector3(1, .25, 1)
	grid.cell_center_x = false
	grid.cell_center_y = false
	grid.cell_center_z = false
	grid.cell_octant_size = 8
	root.add_child(grid)
	grid.owner = root
	return grid
