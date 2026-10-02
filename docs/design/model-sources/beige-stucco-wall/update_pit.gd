extends SceneTree
## One-time migration of the current saved scene; retain all other editor cells.

const Build := preload("res://features/casino_hub/gridmap/build.gd")
const Layout := preload("res://features/casino_hub/gridmap/layout.gd")


func _initialize() -> void:
	assert(
		(
			ResourceSaver.save(
				Build._library(), "res://features/casino_hub/gridmap/casino_tiles.tres"
			)
			== OK
		)
	)
	var scene := load("res://features/casino_hub/casino_gridmap.tscn") as PackedScene
	var root := scene.instantiate() as Node3D
	for name: String in ["Floors", "WallsNorthSouth", "WallsEastWest"]:
		var grid := root.get_node(name) as GridMap
		for cell: Vector3i in grid.get_used_cells():
			if cell.y != -6:
				continue
			if cell.x < -15 or cell.x >= 15 or cell.z < -12 or cell.z >= 12:
				continue
			var item := grid.get_cell_item(cell)
			if item not in [Layout.FLOOR, Layout.RAMP, Layout.PIT_WALL]:
				continue
			var rotation := grid.get_cell_item_orientation(cell)
			var target := Vector3i(cell.x, Layout.PIT_LAYER, cell.z)
			assert(grid.get_cell_item(target) == -1, "Keep existing painted cells")
			grid.set_cell_item(cell, -1)
			grid.set_cell_item(target, item, rotation)
	(root.get_node("Destinations/GamingPit") as Marker3D).position.y = -Layout.PIT_HEIGHT
	var packed := PackedScene.new()
	assert(packed.pack(root) == OK)
	assert(ResourceSaver.save(packed, "res://features/casino_hub/casino_gridmap.tscn") == OK)
	print("PIT MIGRATED: retaining walls and floor raised to -1.25 m; saved editor layout retained")
	root.free()
	quit()
