extends GutTest
## Verify the live room's furnishings, spawn and existing slot-machine approaches.

const ROOM := preload("res://features/casino_hub/gridmap/playable.tscn")
const MAIN := preload("res://main.tscn")
const SLOTS := preload("res://features/slot_machine/feature.tscn")
var _world: Node3D
var _room: Node3D
var _slots: Node3D
var _hull: CapsuleShape3D


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)
	_room = ROOM.instantiate() as Node3D
	_world.add_child(_room)
	_slots = SLOTS.instantiate() as Node3D
	_world.add_child(_slots)
	_hull = CapsuleShape3D.new()
	_hull.radius = 0.4064
	_hull.height = 1.8288
	await wait_physics_frames(4)


func test_main_uses_gridmap_room_and_player_camera() -> void:
	var state := MAIN.get_state()
	for index: int in state.get_node_count():
		if state.get_node_name(index) == &"Room":
			assert_same(state.get_node_instance(index), ROOM)
			return
	fail_test("Main game must instance the playable GridMap room")


func test_bar_and_stationary_npcs_are_restored_on_supported_floors() -> void:
	var furniture := _room.get_node("Casino/Furnishings")
	assert_not_null(furniture.get_node("Bar"))
	assert_not_null(furniture.get_node("BarCounter/Shape"))
	for name: String in [
		"Bartender",
		"GuestAtBar",
		"GuestTalking",
		"GuestGallery",
		"GuestGallery2",
		"Dealer0",
		"Dealer1",
		"Dealer2"
	]:
		var npc := furniture.get_node(name) as Node3D
		var point := npc.global_position
		var query := PhysicsRayQueryParameters3D.create(
			point + Vector3(0, 0.1, 0), point - Vector3(0, 0.2, 0), 1
		)
		assert_false(_world.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), name)


func test_live_map_omits_old_attractions_and_overlapping_annexes() -> void:
	var excluded := PackedStringArray()
	var state := MAIN.get_state()
	for index: int in state.get_node_count():
		if state.get_node_name(index) == &"Features":
			for property: int in state.get_node_property_count(index):
				if state.get_node_property_name(index, property) == &"metadata/excluded_features":
					excluded = state.get_node_property_value(index, property)
	var available := FeatureLoader.find_features()
	for name: String in [
		"annex", "casino_wing", "frogs", "penguin", "water", "nyc_ferry", "gnomes", "wall_sconces"
	]:
		assert_true(name in excluded, name)
		assert_true(name in available, "Keep %s available for other maps" % name)
	for name: String in [
		"slot_machine", "casino_patrons", "bar_companion", "food_court", "pawn_shop", "kebab_shop"
	]:
		assert_false(name in excluded, name)


func test_five_metre_perimeter_and_ceiling_have_matching_collision() -> void:
	var library := (_room.get_node("Casino/WallsNorthSouth") as GridMap).mesh_library
	var bounds := library.get_item_mesh(3).get_aabb()
	var wall_bounds := library.get_item_mesh_transform(3) * bounds
	assert_almost_eq(wall_bounds.size.x, 2.0, 0.001)
	assert_almost_eq(wall_bounds.size.y, 5.0, 0.001)
	assert_almost_eq(wall_bounds.size.y / wall_bounds.size.x, 2.5, 0.001)
	assert_almost_eq(wall_bounds.position.y, 0.0, 0.001)
	for end: Vector3 in [
		Vector3(-36, 4.5, 0), Vector3(36, 4.5, 0), Vector3(0, 4.5, -37), Vector3(0, 4.5, 37)
	]:
		var ray := PhysicsRayQueryParameters3D.create(Vector3(0.5, 4.5, 0.5), end, 1)
		assert_false(
			_world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), str(end)
		)
	for x: float in [-23.0, 0.0, 23.0]:
		for z: float in [-19.0, 0.0, 19.0]:
			var ray := PhysicsRayQueryParameters3D.create(Vector3(x, 4.5, z), Vector3(x, 6, z), 1)
			var hit := _world.get_world_3d().direct_space_state.intersect_ray(ray)
			assert_false(hit.is_empty(), "Ceiling covers %s, %s" % [x, z])
			if not hit.is_empty():
				assert_almost_eq((hit["position"] as Vector3).y, 5.0, 0.001)


func test_double_width_panels_join_without_gaps_on_all_four_sides() -> void:
	var walls := _room.get_node("Casino/WallsNorthSouth") as GridMap
	var sides := _room.get_node("Casino/WallsEastWest") as GridMap
	assert_eq(walls.get_used_cells_by_item(3).size(), 46)
	assert_eq(sides.get_used_cells_by_item(3).size(), 40)
	for x: int in range(-24, 24):
		for sign_z: float in [-1.0, 1.0]:
			var ray := PhysicsRayQueryParameters3D.create(
				Vector3(x + 0.5, 4.5, sign_z * 19), Vector3(x + 0.5, 4.5, sign_z * 21), 1
			)
			assert_false(_world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty())
	for z: int in range(-20, 20):
		for sign_x: float in [-1.0, 1.0]:
			var ray := PhysicsRayQueryParameters3D.create(
				Vector3(sign_x * 23, 4.5, z + 0.5), Vector3(sign_x * 25, 4.5, z + 0.5), 1
			)
			assert_false(_world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty())


func test_spawn_jitter_and_each_slot_machine_approach_are_clear() -> void:
	var spawn := _room.get_node("Spawn") as Marker3D
	for x: int in range(-3, 4):
		for z: int in range(-3, 4):
			var query := PhysicsShapeQueryParameters3D.new()
			query.collision_mask = 1
			query.shape = _hull
			query.transform.origin = spawn.global_position + Vector3(x, 0, z)
			assert_true(_world.get_world_3d().direct_space_state.intersect_shape(query).is_empty())
	assert_eq(_slots.get_child_count(), 8)
	for machine: Node3D in _slots.get_children():
		var approach := machine.to_global(Vector3(0, 0.95, 2.6))
		var query := PhysicsShapeQueryParameters3D.new()
		query.collision_mask = 1
		query.shape = _hull
		query.transform.origin = Vector3(approach.x, approach.y, 5.9)
		query.motion = approach - query.transform.origin
		var result := _world.get_world_3d().direct_space_state.cast_motion(query)
		assert_almost_eq(result[0], 1.0, 0.001, str(machine.name))
		assert_lt(approach.distance_to(machine.interaction_point()), SlotMachine.USE_RANGE)
