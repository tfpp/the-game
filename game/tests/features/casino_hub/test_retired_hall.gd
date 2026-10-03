extends GutTest
## Retire only the old empty hall, not the live mall or its corridor.


func test_old_hall_is_removed_but_corridor_and_travel_remain() -> void:
	var scene := load("res://features/casino_hub/casino_gridmap.tscn") as PackedScene
	var casino := scene.instantiate()
	add_child_autofree(casino)
	assert_null(casino.get_node_or_null("FoodRoof"))
	for name: String in ["Floors", "Ceiling", "ShopWallsNorthSouth", "ShopWallsEastWest"]:
		var grid := casino.get_node(name) as GridMap
		for cell: Vector3i in grid.get_used_cells():
			assert_false(cell.x >= 2 and cell.z >= 20, "No former hall cells in " + name)
	var floor_grid := casino.get_node("Floors") as GridMap
	assert_eq(floor_grid.get_cell_item(Vector3i(0, 0, 25)), 0)
	var sides := casino.get_node("ShopWallsEastWest") as GridMap
	assert_eq(sides.get_cell_item(Vector3i(1, 0, 24)), 3, "Sealed wall behind mall portal")
	var mall := (load("res://features/strip_mall/feature.tscn") as PackedScene).instantiate()
	add_child_autofree(mall)
	assert_almost_eq(
		(mall.get_node("Entrance") as Node3D).position, Vector3(1.8, 1.25, 25), Vector3.ONE * 0.001
	)
	assert_not_null(mall.get_node("Room/FrogDisplay"))
	assert_not_null(mall.get_node("Room/Exit"))
