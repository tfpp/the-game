extends GutTest
## Exercise the actual CSG collision bake, including ramps, doors and ferry clearance.

const ROOM := preload("res://world/room.tscn")
var _room: Node3D


func before_each() -> void:
	_room = ROOM.instantiate() as Node3D
	add_child_autofree(_room)
	await wait_physics_frames(3)


func test_both_ramps_connect_gaming_floor_to_promenade() -> void:
	_assert_floor(Vector3(0, 3, 0), -1.5)
	for direction: float in [-1.0, 1.0]:
		for distance: float in [6.1, 8.0, 10.0, 11.9]:
			_assert_floor(Vector3(0, 3, direction * distance), (distance - 12.0) / 4.0)
		_assert_floor(Vector3(0, 3, direction * 13.0), 0.0)
	for x: float in [-16.5, 16.5]:
		_assert_floor(Vector3(x, 3, 0), 0.0)


func test_side_room_doorways_are_walkable() -> void:
	for direction: float in [-1.0, 1.0]:
		var hit := _ray(Vector3(direction * 16, 1, 0), Vector3(direction * 22, 1, 0))
		assert_true(hit.is_empty(), "Door opening must allow a standing player through")


func test_ferry_hull_route_is_clear_and_both_landings_are_solid() -> void:
	for x: float in [23.5, 26.0, 28.5]:
		var hit := _ray(Vector3(x, 0.08, -19.5), Vector3(x, 0.08, 19.5))
		assert_true(hit.is_empty(), "Ferry must fit along its entire 30m route")
	for z: float in [-20.05, 20.05]:
		_assert_floor(Vector3(26, 3, z), 0.2)


func test_hub_and_attraction_rooms_have_solid_ceilings() -> void:
	for x: float in [-26.0, 0.0, 26.0]:
		var hit := _ray(Vector3(x, 4, 2), Vector3(x, 10, 2))
		assert_false(hit.is_empty(), "Interior must be covered")


func test_skylights_open_the_ceiling_but_glass_keeps_players_in() -> void:
	for x: float in [-9.5, 5.5]:
		var hit := _ray(Vector3(x, 4, 2), Vector3(x, 10, 2))
		assert_false(hit.is_empty(), "Skylight glass must be solid")
		if not hit.is_empty():
			var point: Vector3 = hit["position"]
			# The ceiling slab's underside is y 8; the glass sits above it, in the opening.
			assert_gt(point.y, 8.2, "The ceiling is cut open under the skylight")


func _assert_floor(from: Vector3, expected_y: float) -> void:
	var hit := _ray(from, from - Vector3(0, 8, 0))
	assert_false(hit.is_empty(), "Walkable floor at %s" % from)
	if not hit.is_empty():
		var point: Vector3 = hit["position"]
		assert_almost_eq(point.y, expected_y, 0.03, "Floor height at %s" % from)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	return _room.get_world_3d().direct_space_state.intersect_ray(query)
