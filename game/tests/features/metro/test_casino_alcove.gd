extends GutTest
## Real saved geometry and paired travel must follow the wall-mounted casino marker.

const CASINO := preload("res://features/casino_hub/casino_gridmap.tscn")
const METRO := preload("res://features/metro/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const RECIPE := preload("res://features/casino_hub/gridmap/metro_alcove.gd")
var casino: Node3D
var metro: MetroService
var access: MetroAccess


func before_each() -> void:
	metro = METRO.instantiate() as MetroService
	add_child_autofree(metro)
	metro.set_physics_process(false)
	metro.transfers.set_physics_process(false)
	casino = CASINO.instantiate() as Node3D
	add_child_autofree(casino)
	access = casino.get_node("MetroAccess") as MetroAccess
	await wait_physics_frames(4)
	access.source.set_physics_process(false)
	access.source.net_aperture = 1
	access.source._update_doors()
	await wait_physics_frames(4)


func test_cab_is_recessed_with_gps_and_original_station_identity() -> void:
	assert_eq(access.position, Vector3(-12, 0, 19.8))
	assert_almost_eq(access.global_basis.z, Vector3.FORWARD, Vector3.ONE * 0.001)
	assert_eq(access.zone_id, "crown")
	assert_eq(access.station, 0)
	assert_eq(access.slot, 0)
	assert_same(access.source.partner, access.destination)
	assert_same(access.destination.partner, access.source)
	assert_same(access.destination.get_parent(), metro.stations[0])
	var gps := access.get_node("MetroDestination") as GpsDestination
	assert_almost_eq(gps.global_position, Vector3(-12, 0.1, 18.8), Vector3.ONE * 0.001)
	# The original cabin's entire depth is behind the south wall, not in the aisle.
	var cabin := access.source.get_node("Shell3") as GridMap
	var library := cabin.mesh_library
	var bounds := (
		cabin.global_transform
		* library.get_item_mesh_transform(0)
		* library.get_item_mesh(0).get_aabb()
	)
	assert_gte(bounds.position.z, 19.79)
	assert_lte(bounds.end.z, 23.01)


func test_approach_and_freed_promenade_have_capsule_clearance_and_floor() -> void:
	for x: float in [-0.6, 0.0, 0.6]:
		for z: float in [-2.4, -1.5, -0.7, 0.0, 0.8, 2.0]:
			_assert_walkable(access.to_global(Vector3(x, 0.94, z)))
	for x: float in [-17, -16, -15, -14, -13, -12, -11, -10]:
		for z: float in [15.5, 16.5, 17.5, 18.5]:
			_assert_walkable(Vector3(x, 0.94, z))


func _assert_walkable(at: Vector3) -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4064
	capsule.height = 1.8288
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform.origin = at
	query.collision_mask = 1
	var space := casino.get_world_3d().direct_space_state
	assert_true(space.intersect_shape(query).is_empty(), "Clear standing capsule at " + str(at))
	var ray := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 1.2, 1)
	var hit := space.intersect_ray(ray)
	assert_false(hit.is_empty(), "Supported floor at " + str(at))
	if not hit.is_empty():
		assert_almost_eq((hit["position"] as Vector3).y, 0.0, 0.002)


func test_opening_keeps_headers_and_adjacent_wall_sealed() -> void:
	var space := casino.get_world_3d().direct_space_state
	for x: float in [-15, -13.85, -10.15, -9]:
		var ray := PhysicsRayQueryParameters3D.create(Vector3(x, 1, 19), Vector3(x, 1, 21), 1)
		assert_false(space.intersect_ray(ray).is_empty(), "Adjacent wall remains sealed")
	for x: float in [-13, -11]:
		var ray := PhysicsRayQueryParameters3D.create(Vector3(x, 4, 19), Vector3(x, 4, 21), 1)
		assert_false(space.intersect_ray(ray).is_empty(), "Header closes the upper wall")
	var walls := casino.get_node("WallsNorthSouth") as GridMap
	var shops := casino.get_node("ShopWallsNorthSouth") as GridMap
	for x: int in [-14, -12]:
		assert_eq(walls.get_cell_item(Vector3i(x + 1, 0, 19)), 7)
		assert_eq(shops.get_cell_item(Vector3i(x, 0, 20)), 7)
	var decor := casino.get_node("Decor") as GridMap
	assert_eq(decor.get_cell_item(Vector3i(-12, 12, 20)), GridMap.INVALID_CELL_ITEM)
	assert_eq(decor.get_cell_item(Vector3i(-20, 12, 20)), 0, "Keep the painting clear of the sign")
	RECIPE.configure(casino)
	RECIPE.configure(casino)
	await wait_physics_frames(4)
	assert_eq(access.position, Vector3(-12, 0, 19.8), "Offline recipe preserves saved placement")
	assert_eq(casino.find_children("MetroAccess", "Node3D", false, false).size(), 1)


func test_recessed_elevator_round_trip_returns_to_the_actual_cabin() -> void:
	var player := PLAYER.instantiate() as Player
	player.name = "1"
	player.position = access.source.car.to_global(Vector3(0.4, 0.93, -0.3))
	player.net_position = player.position
	player.rotation.y = 0.4
	add_child_autofree(player)
	player.set_physics_process(false)
	var original := player.net_position
	metro.depart_elevator(access.source, [player])
	assert_true(metro.transfers.pending.has(1))
	await wait_physics_frames(8)
	assert_true(metro.transfers.pending[1]["ready"])
	metro.transfers._physics_process(1.1)
	assert_true(metro.stations[0].contains(player.net_position))
	access.source.net_state = ElevatorCab.State.CLOSED
	access.destination.net_state = ElevatorCab.State.CLOSED
	metro.depart_elevator(access.destination, [player])
	await wait_physics_frames(8)
	assert_true(metro.transfers.pending[1]["ready"])
	metro.transfers._physics_process(1.1)
	assert_lt(player.net_position.distance_to(original), 0.002)
	assert_true(metro.transfers.pending.is_empty())
