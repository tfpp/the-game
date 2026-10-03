extends SceneTree
## Offline recipe: saved editable cells, sharing the casino's actual MeshLibrary.

const LIBRARY := preload("res://features/casino_hub/gridmap/casino_tiles.tres")


func _initialize() -> void:
	var store := Node3D.new()
	store.name = "StoreStructure"
	var floor_grid := _grid(store, "Floor")
	var ceiling := _grid(store, "Ceiling")
	var walls := _grid(store, "WallsNorthSouth")
	var sides := _grid(store, "WallsEastWest")
	var sills := _grid(store, "WindowSills")
	var south := walls.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI))
	var west := sides.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI / 2))
	var east := sides.get_orthogonal_index_from_basis(Basis(Vector3.UP, -PI / 2))
	for x: int in range(-16, -2):
		for z: int in range(20, 30):
			floor_grid.set_cell_item(Vector3i(x, 0, z), 5)
			ceiling.set_cell_item(Vector3i(x, 20, z), 8)
	for x: int in range(-16, -2):
		walls.set_cell_item(Vector3i(x, 0, 20), 13)
	for x: int in range(-16, -2, 2):
		walls.set_cell_item(Vector3i(x + 1, 0, 29), 7, south)
	for x: int in range(-16, -4):
		# Low stucco sill beneath the storefront glass; door is the final 2 m bay.
		sills.set_cell_item(Vector3i(x, -3, 29), 12, south)
	for z: int in range(20, 30):
		sides.set_cell_item(Vector3i(-16, 0, z), 13, west)
		sides.set_cell_item(Vector3i(-3, 0, z), 13, east)
	var body := StaticBody3D.new()
	body.name = "RoofCollision"
	store.add_child(body)
	body.owner = store
	var shape := CollisionShape3D.new()
	shape.position = Vector3(-9, 5.125, 25)
	var box := BoxShape3D.new()
	box.size = Vector3(14, .25, 10)
	shape.shape = box
	body.add_child(shape)
	shape.owner = store
	var packed := PackedScene.new()
	assert(packed.pack(store) == OK)
	assert(ResourceSaver.save(packed, "res://features/pawn_shop/structure.tscn") == OK)
	store.free()
	quit()


func _grid(store: Node3D, grid_name: String) -> GridMap:
	var grid := GridMap.new()
	grid.name = grid_name
	grid.mesh_library = LIBRARY
	grid.cell_size = Vector3(1, .25, 1)
	grid.cell_center_y = false
	grid.cell_octant_size = 8
	store.add_child(grid)
	grid.owner = store
	return grid
