extends SceneTree
## Explicit offline recipe; saved GridMaps remain editable and never rebuild on load.

const CASINO := preload("res://features/casino_hub/gridmap/casino_tiles.tres")
const CONCRETE := preload("res://features/starter_room/garage_tiles.tres")


func _initialize() -> void:
	var area := Node3D.new()
	area.name = "Upstairs"
	var deck := _grid(area, "Deck", CONCRETE)
	for x: int in range(-8, -2):
		for z: int in range(-9, -4):
			deck.set_cell_item(Vector3i(x, 10, z), 0)
	var stairs := _grid(area, "Stairs", CASINO)
	stairs.position = Vector3(-5, 0, 0)
	stairs.rotation.y = PI
	for flight: int in 2:
		for x: int in 2:
			stairs.set_cell_item(Vector3i(x, flight * 5, flight * 2), 15)
	var slope := _grid(area, "StairRails", CASINO, true)
	slope.position = stairs.position
	slope.rotation.y = PI
	for x: int in [0, 2]:
		for flight: int in 2:
			slope.set_cell_item(Vector3i(x, flight * 5, flight * 2), 16)
	var rails := _grid(area, "Rails", CASINO, true)
	var turn := rails.get_orthogonal_index_from_basis(Basis(Vector3.UP, -PI / 2))
	for z: int in [-8, -6]:
		rails.set_cell_item(Vector3i(-2, 10, z), 9, turn)
	# Southern rail stops at the two-metre stair mouth (-7 .. -5).
	rails.set_cell_item(Vector3i(-5, 10, -4), 9)
	for edge: int in [-8, -3]:
		var short := _grid(area, "ShortRail%s" % absi(edge), CASINO, true)
		short.position = Vector3(edge, 0, -4)
		short.scale.x = .5
		short.set_cell_item(Vector3i(0, 10, 0), 9)
	var posts := _grid(area, "Posts", CASINO, true)
	for point: Vector3i in [
		Vector3i(-2, 10, -8),
		Vector3i(-2, 10, -6),
		Vector3i(-2, 10, -4),
		Vector3i(-5, 10, -4),
		Vector3i(-7, 10, -4)
	]:
		posts.set_cell_item(point, 10)
	var scene := PackedScene.new()
	scene.pack(area)
	ResourceSaver.save(scene, "res://features/starter_room/upstairs.tscn")
	area.free()
	quit()


func _grid(parent: Node3D, title: String, library: MeshLibrary, exact := false) -> GridMap:
	var grid := GridMap.new()
	grid.name = title
	grid.mesh_library = library
	grid.cell_size = Vector3(1, .25, 1)
	grid.cell_center_y = false
	grid.cell_center_x = not exact
	grid.cell_center_z = not exact
	parent.add_child(grid)
	grid.owner = parent
	return grid
