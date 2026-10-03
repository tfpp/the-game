extends GutTest
## Decor meshes are non-colliding tiles; local lights follow saved fixture cells.

const ROOM := preload("res://features/casino_hub/gridmap/playable.tscn")
const CYCLE := preload("res://features/day_night/feature.tscn")
const Decor := preload("res://features/casino_hub/gridmap/decor.gd")
var _room: Node3D
var _decor: GridMap


func before_each() -> void:
	_room = ROOM.instantiate() as Node3D
	add_child_autofree(_room)
	_decor = _room.get_node("Casino/Decor") as GridMap
	await wait_frames(1)


func test_decor_library_reuses_painting_and_fixtures_without_collision() -> void:
	assert_eq(_decor.mesh_library.get_item_list().size(), 3)
	for id: int in _decor.mesh_library.get_item_list():
		assert_gt(_decor.mesh_library.get_item_mesh(id).get_faces().size(), 0)
		assert_eq(_decor.mesh_library.get_item_shapes(id).size(), 0)
	assert_eq(_decor.mesh_library.get_item_name(Decor.PAINTING), "FramedLandscape")
	assert_eq(_decor.mesh_library.get_item_mesh(Decor.PAINTING).get_surface_count(), 2)
	assert_gt(_decor.get_used_cells_by_item(Decor.PAINTING).size(), 8)
	assert_eq(_decor.get_used_cells_by_item(Decor.WALL_LIGHT).size(), 17)
	assert_eq(_decor.get_cell_item(Vector3i(-9, 12, 30)), Decor.PAINTING)
	assert_eq(_decor.get_cell_item(Vector3i(13, 12, 38)), GridMap.INVALID_CELL_ITEM)


func test_saved_fixture_cells_have_local_lights_and_only_two_shadow_pools() -> void:
	var lights := _decor.get_node("FixtureLights")
	var fixture_count := _decor.get_used_cells_by_item(Decor.WALL_LIGHT).size()
	fixture_count += _decor.get_used_cells_by_item(Decor.PENDANT).size()
	assert_eq(lights.find_children("*", "OmniLight3D", false, false).size(), fixture_count)
	var shadow_count := 0
	for node: Node in lights.get_children():
		var light := node as Light3D
		assert_gt(light.light_energy, 0.0)
		assert_gt(light.light_color.r, light.light_color.b)
		if light.shadow_enabled:
			shadow_count += 1
		if light is OmniLight3D:
			assert_false(light.shadow_enabled)
	assert_eq(shadow_count, 2)
	assert_lte(lights.get_child_count(), 31, "Leave room below the 32-light frame limit")
	assert_false(_decor.is_processing(), "Runtime lights need no polling")


func test_editing_a_sconce_cell_repositions_its_light() -> void:
	var cell := Vector3i(-16, 12, -20)
	_decor.set_cell_item(cell, -1)
	var new_cell := Vector3i(-18, 12, -20)
	_decor.set_cell_item(new_cell, Decor.WALL_LIGHT)
	_decor.call("_update_lights")
	assert_null(_decor.get_node_or_null("FixtureLights/Lamp_-16_12_-20"))
	var lamp := _decor.get_node("FixtureLights/Lamp_-18_12_-20") as OmniLight3D
	assert_almost_eq(lamp.position, Vector3(-18, 3.1, -19.2), Vector3.ONE * 0.001)


func test_indoor_lighting_stays_fixed_when_the_clock_changes() -> void:
	var environment := (_room.get_node("Casino/Environment") as WorldEnvironment).environment
	var energy := environment.ambient_light_energy
	assert_lt(energy, 0.55)
	var cycle := CYCLE.instantiate() as DayNight
	add_child_autofree(cycle)
	cycle._apply(0.0)
	assert_eq(environment.ambient_light_energy, energy)
	cycle._apply(0.5)
	assert_eq(environment.ambient_light_energy, energy)
	assert_false((cycle.get_node("Sun") as DirectionalLight3D).visible)
	assert_false(cycle.is_processing())


func test_gridmap_batches_stay_within_compatibility_light_budget() -> void:
	var lamps := _room.find_children("*", "OmniLight3D", true, false)
	for node: Node in _room.find_children("*", "GridMap", true, false):
		if not node is GridMap:
			continue
		var grid := node as GridMap
		var batches: Dictionary[String, AABB] = {}
		for cell: Vector3i in grid.get_used_cells():
			var item := grid.get_cell_item(cell)
			var octant := Vector3i(
				floori(float(cell.x) / grid.cell_octant_size),
				floori(float(cell.y) / grid.cell_octant_size),
				floori(float(cell.z) / grid.cell_octant_size)
			)
			var key := "%s/%d" % [octant, item]
			var transform := Transform3D(grid.get_cell_item_basis(cell), grid.map_to_local(cell))
			transform *= grid.mesh_library.get_item_mesh_transform(item)
			var bounds := transform * grid.mesh_library.get_item_mesh(item).get_aabb()
			batches[key] = batches[key].merge(bounds) if batches.has(key) else bounds
		for key: String in batches:
			var count := 0
			var bounds := batches[key]
			for node_light: Node in lamps:
				var light := node_light as OmniLight3D
				var center := grid.to_local(light.global_position)
				var nearest := center.clamp(bounds.position, bounds.end)
				if center.distance_squared_to(nearest) <= light.omni_range * light.omni_range:
					count += 1
			assert_lte(count, 8, "%s batch %s overlaps %d omni lights" % [grid.name, key, count])
