extends GutTest
## Where the two cabs stand: built into the casino's south lobby wall and the B1 garage
## front wall, on real floors, with a clear approach. Geometry is probed with the
## actual room/garage collision, the way test_casino_layout.gd and test_garage_layout.gd do.

const FeatureScene := preload("res://features/elevator/feature.tscn")
const RoomScene := preload("res://world/room.tscn")
const GarageFeature := preload("res://features/procedural_rooms/feature.tscn")
const SPAWN := Vector3(2, 0.2, 5)
const SOUTH_WALL_FACE_Z := 34.0
const BACK := Vector3(0, 1, -1.7)
const GNOME_HOLE_XS: Array[float] = [-24.0, -6.0, 12.0, 30.0]

var _feature: Node3D


func before_each() -> void:
	_feature = FeatureScene.instantiate() as Node3D
	add_child_autofree(_feature)


func _casino_cab() -> ElevatorCab:
	return _feature.get_node("CasinoCab") as ElevatorCab


func _garage_cab() -> ElevatorCab:
	return _feature.get_node("GarageZone/GarageCab") as ElevatorCab


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	return _feature.get_world_3d().direct_space_state.intersect_ray(query)


## Take a cab out of ray queries so they probe the wall and floor it is built against.
func _ghost(cab: ElevatorCab) -> void:
	(cab.get_node("Shell") as CSGShape3D).collision_layer = 0
	for body: Node in cab.find_children("*", "CollisionObject3D", true, false):
		(body as CollisionObject3D).collision_layer = 0


func test_casino_cab_is_built_into_the_south_lobby_wall_facing_the_casino() -> void:
	var room := RoomScene.instantiate() as Node3D
	add_child_autofree(room)
	await wait_physics_frames(3)
	var cab := _casino_cab()
	_ghost(cab)
	await wait_physics_frames(2)
	var back := cab.to_global(BACK)
	var wall := _ray(Vector3(back.x, 1, 30), Vector3(back.x, 1, 40))
	assert_false(wall.is_empty(), "South wall must be behind the cab")
	assert_almost_eq((wall["position"] as Vector3).z, SOUTH_WALL_FACE_Z, 0.01)
	assert_almost_eq(back.z, SOUTH_WALL_FACE_Z, 0.01, "Cab block sits flush on the wall")
	var floor_hit := _ray(cab.global_position + Vector3.UP, cab.global_position + Vector3.DOWN)
	assert_almost_eq((floor_hit["position"] as Vector3).y, cab.global_position.y, 0.01)
	# Doors face north, into the lobby and back toward the gaming floor and spawn.
	var facing := cab.global_basis.z
	assert_almost_eq(facing.z, -1.0, 0.001)
	assert_lt(cab.global_position.distance_to(SPAWN), 32.0)
	for x: float in [-1.2, 0.0, 1.2]:
		var from := cab.to_global(Vector3(x, 1, 1.6))
		assert_true(_ray(from, from + facing * 4.0).is_empty(), "Approach must stay clear")


func test_casino_cab_block_leaves_the_gnome_holes_open() -> void:
	var cab := _casino_cab()
	var ends := [cab.to_global(Vector3(-3.1, 0, 0)).x, cab.to_global(Vector3(3.1, 0, 0)).x]
	for hole_x: float in GNOME_HOLE_XS:
		assert_false(
			hole_x > minf(ends[0], ends[1]) - 0.5 and hole_x < maxf(ends[0], ends[1]) + 0.5,
			"Gnome hole at x %s must stay open" % hole_x
		)


func test_garage_cab_is_built_into_the_b1_front_wall() -> void:
	var garage_feature := GarageFeature.instantiate() as Node3D
	add_child_autofree(garage_feature)
	await wait_physics_frames(3)
	var garage := garage_feature.get_node("Garage") as Node3D
	var zone := _feature.get_node("GarageZone") as Node3D
	assert_true(
		zone.global_transform.is_equal_approx(garage.global_transform),
		"The render zone shares the B1–B5 garage's frame"
	)
	var cab := _garage_cab()
	_ghost(cab)
	await wait_physics_frames(2)
	var local := garage.to_local(cab.global_position)
	var wall := _ray(
		garage.to_global(local + Vector3(0, 1.5, 3)), garage.to_global(local + Vector3(0, 1.5, -6))
	)
	assert_false(wall.is_empty(), "Garage wall must be behind the cab")
	assert_almost_eq(garage.to_local(wall["position"]).z, local.z - 1.7, 0.01)
	var floor_hit := _ray(cab.global_position + Vector3.UP, cab.global_position + Vector3.DOWN)
	assert_almost_eq((floor_hit["position"] as Vector3).y, cab.global_position.y, 0.01)
	var roof := _ray(cab.to_global(Vector3(2.5, 1, 1)), cab.to_global(Vector3(2.5, 6, 1)))
	assert_almost_eq(
		(roof["position"] as Vector3).y - cab.global_position.y, 3.5, 0.05, "B1 is 3.5 m tall"
	)
	var facing := cab.global_basis.z
	for x: float in [-1.2, 0.0, 1.2]:
		var from := cab.to_global(Vector3(x, 1, 1.6))
		assert_true(_ray(from, from + facing * 4.0).is_empty(), "Exit must stay clear")
	var zone_node := zone as RenderZone
	assert_true(zone_node.contains(cab.to_global(Vector3(0, 1.6, 0))))
	assert_true(zone_node.contains(cab.to_global(Vector3(0, 1.6, 2.5))))


func test_doors_block_when_closed_and_open_for_boarding() -> void:
	await wait_physics_frames(2)
	var cab := _casino_cab()
	var outside := cab.to_global(Vector3(0.3, 1, 2.5))
	var inside := cab.to_global(Vector3(0.3, 1, -0.5))
	assert_false(_ray(outside, inside).is_empty(), "Closed doors block the doorway")
	cab.net_state = ElevatorCab.State.OPEN
	cab._process(0.0)
	await wait_physics_frames(2)
	assert_true(_ray(outside, inside).is_empty(), "Open doors leave the doorway clear")
	for x: float in [-1.1, 1.1]:
		var side := cab.to_global(Vector3(x, 1, 2.5))
		assert_true(_ray(side, cab.to_global(Vector3(x, 1, 0))).is_empty())
