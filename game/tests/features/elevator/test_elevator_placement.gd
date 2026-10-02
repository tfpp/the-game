extends GutTest
## Probe the current casino, rather than the retired CSG room.

const ROOM := preload("res://features/casino_hub/gridmap/playable.tscn")
const KIT := preload("res://features/elevator/elevator.tscn")
var _room: Node3D
var _cab: ElevatorCab
var _bay: GridMap


func before_each() -> void:
	_room = ROOM.instantiate() as Node3D
	add_child_autofree(_room)
	_cab = _room.get_node("Casino/Elevator/Cab") as ElevatorCab
	_bay = _room.get_node("Casino/Elevator/Bay") as GridMap
	_cab.set_physics_process(false)
	await wait_physics_frames(3)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return _room.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to)
	)


func test_single_stationary_elevator_centers_on_wall_opposite_spawn() -> void:
	assert_eq(
		(
			_room
			. find_children("*", "Node3D", true, false)
			. filter(func(node: Node) -> bool: return node is ElevatorCab)
			. size()
		),
		1
	)
	assert_eq(_bay.global_position, Vector3(0, 0, -20))
	assert_gt((_room.get_node("Spawn") as Node3D).global_position.z, 0.0)
	assert_almost_eq(_cab.global_basis.z, Vector3.BACK, Vector3.ONE * 0.0001)
	assert_false(_cab.travel_enabled)
	assert_true(_cab.destination.is_empty())
	assert_eq(_room.find_children("*", "CSGShape3D", true, false).size(), 0)
	var gps := _room.get_node("Casino/Destinations/Elevator") as GpsDestination
	assert_eq(gps.label, "Golden Crown Elevator")


func test_module_fits_grid_dimensions_and_has_solid_floor_sides_and_back() -> void:
	assert_eq(_bay.cell_size, Vector3(8, 5, 4))
	assert_eq(_bay.get_used_cells().size(), 1)
	assert_eq(_bay.mesh_library.get_item_name(0), "ElevatorBay")
	assert_eq(_bay.mesh_library.get_item_shapes(0).size(), 14)
	var bounds := _bay.mesh_library.get_item_mesh(0).get_aabb()
	assert_lte(bounds.size.x, 8.01)
	assert_lte(bounds.size.y, 5.01)
	assert_lte(bounds.size.z, 4.2, "Front trim may project slightly")
	var floor_hit := _ray(
		_cab.car.global_position + Vector3.UP, _cab.car.global_position + Vector3.DOWN
	)
	assert_false(floor_hit.is_empty())
	assert_almost_eq((floor_hit["position"] as Vector3).y, 0.0, 0.001)
	for direction: Vector3 in [Vector3.LEFT * 3, Vector3.RIGHT * 3, Vector3.FORWARD * 3]:
		assert_false(
			(
				_ray(
					_cab.car.global_position + Vector3.UP,
					_cab.car.global_position + Vector3.UP + direction
				)
				. is_empty()
			)
		)
	# The removed perimeter cells are filled by the module, including both flanks.
	for x: float in [-3.5, 3.5]:
		assert_false(_ray(Vector3(x, 1, -18), Vector3(x, 1, -22)).is_empty())


func test_doors_block_when_closed_and_leave_walking_clearance_when_open() -> void:
	var outside := Vector3(0.3, 1, -18)
	var inside := _cab.car.to_global(Vector3(0.3, 1, -0.5))
	assert_false(_ray(outside, inside).is_empty())
	_cab.net_state = ElevatorCab.State.OPEN
	_cab.net_aperture = 1.0
	_cab._update_doors()
	await wait_physics_frames(2)
	for x: float in [-1.0, 0, 1.0]:
		assert_true(_ray(Vector3(x, 1, -18), _cab.car.to_global(Vector3(x, 1, 0))).is_empty())
	var hull := CapsuleShape3D.new()
	hull.radius = 0.4064
	hull.height = 1.8288
	for z: float in [-18, -19.5, -20.5, -21.5, -22]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = hull
		query.transform.origin = Vector3(0, 0.96, z)
		assert_true(
			_room.get_world_3d().direct_space_state.intersect_shape(query).is_empty(), str(z)
		)


func test_standalone_kit_has_same_cell_origin_and_controller_offset() -> void:
	var kit := KIT.instantiate() as Node3D
	add_child_autofree(kit)
	assert_eq((kit.get_node("Bay") as GridMap).cell_size, _bay.cell_size)
	assert_eq((kit.get_node("Cab") as Node3D).position, Vector3.ZERO)
	assert_eq(_cab.position, Vector3.ZERO)
	assert_eq((_cab.get_node("Car") as Node3D).position, Vector3(0, 0, -1.55))
	assert_same((kit.get_node("Bay") as GridMap).mesh_library, _bay.mesh_library)
	assert_eq((kit.get_node("Bay") as GridMap).get_used_cells().size(), 1)
