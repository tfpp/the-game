extends SceneTree
## Bake editable GridMap cells once. No runtime construction or CSG architecture.


func _initialize() -> void:
	var room := Node3D.new()
	room.name = "Backroom"
	var library := load("res://features/casino_hub/gridmap/casino_tiles.tres") as MeshLibrary
	var floors := _grid(room, "Floors", library)
	var north_south := _grid(room, "NorthSouth", library)
	var east_west := _grid(room, "EastWest", library)
	var ceilings := _grid(room, "Ceilings", library)
	var roof := _grid(room, "Roof", library)
	for x: int in range(-6, 6):
		for z: int in range(-5, 5):
			floors.set_cell_item(
				Vector3i(x, 0, z), 0 if x >= -3 and x < 3 and z >= -3 and z < 1 else 6
			)
			roof.set_cell_item(Vector3i(x, 20, z), 0)
			ceilings.set_cell_item(Vector3i(x, 19, z), 8)
	# Offset the ceiling finish below the slab, avoiding coplanar flicker.
	ceilings.position.y = -0.01
	for x: int in range(-6, 6, 2):
		north_south.set_cell_item(Vector3i(x, 0, -5), 3)
		north_south.set_cell_item(
			Vector3i(x + 1, 0, 4),
			3,
			north_south.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI))
		)
	for z: int in range(-5, 5, 2):
		east_west.set_cell_item(
			Vector3i(-6, 0, z + 1),
			3,
			east_west.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI / 2))
		)
		east_west.set_cell_item(
			Vector3i(5, 0, z),
			3,
			east_west.get_orthogonal_index_from_basis(Basis(Vector3.UP, -PI / 2))
		)
	var light := OmniLight3D.new()
	light.name = "WarmLamp"
	light.position = Vector3(0, 3.8, 0)
	light.light_color = Color(1, 0.8, 0.55)
	light.light_energy = 2.5
	light.omni_range = 10
	room.add_child(light)
	light.owner = room
	var sign := Label3D.new()
	sign.name = "Rules"
	sign.position = Vector3(0, 3, -4.7)
	sign.text = "THE BACKROOM\nTwo birds. One winner. No spectators harmed."
	sign.font_size = 48
	sign.pixel_size = 0.004
	room.add_child(sign)
	sign.owner = room
	var scene := PackedScene.new()
	scene.pack(room)
	ResourceSaver.save(scene, "res://features/chicken_betting/interior.tscn")
	room.free()
	quit()


func _grid(root: Node3D, title: String, library: MeshLibrary) -> GridMap:
	var grid := GridMap.new()
	grid.name = title
	grid.mesh_library = library
	grid.cell_size = Vector3(1, 0.25, 1)
	grid.cell_center_y = false
	root.add_child(grid)
	grid.owner = root
	return grid
