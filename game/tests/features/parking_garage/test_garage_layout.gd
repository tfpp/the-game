extends GutTest
## Exercises the actual CSG collision bake for the garage structure, the same
## way test_casino_layout.gd exercises the casino's.

const FeatureScene := preload("res://features/parking_garage/feature.tscn")
## The Garage sub-node sits far from the casino; every local coordinate below
## needs this added to become a world position.
const OFFSET := Vector3(0, 0, 600)

var _root: Node3D


func before_each() -> void:
	_root = FeatureScene.instantiate() as Node3D
	add_child_autofree(_root)
	await wait_physics_frames(3)


func test_each_floor_has_a_walkable_slab_clear_of_columns() -> void:
	_assert_floor(Vector3(16, 3, 1) + OFFSET, 0.0)
	_assert_floor(Vector3(16, 6, 1) + OFFSET, 3.3)
	_assert_floor(Vector3(16, 9, 1) + OFFSET, 6.6)


## Tolerance is wider than a flat slab's: a vertical ray through a sloped
## surface hits the slab's top face, which sits above the slope's centerline
## by roughly (thickness / 2) / cos(angle).
func test_ramp1_climbs_smoothly_from_floor0_to_floor1() -> void:
	for x: float in [11.0, 13.5, 16.0]:
		var expected_y: float = (x - 8.0) / 9.0 * 3.3
		_assert_floor(Vector3(x, 5, 11.5) + OFFSET, expected_y, 0.2)


func test_ramp2_climbs_smoothly_from_floor1_to_floor2() -> void:
	for x: float in [-16.5, -12.5, -8.5]:
		var expected_y: float = 3.3 + (-8.0 - x) / 9.0 * 3.3
		_assert_floor(Vector3(x, 8, 11.5) + OFFSET, expected_y, 0.2)


func test_stairwell_flight_a_is_a_walkable_climb_from_floor0() -> void:
	# Step 10 (0-indexed) treads from z = -8 - run*11 to -8 - run*10.
	var tread_z := -8.0 - 0.272727 * 10.5
	_assert_floor(Vector3(-16, 3, tread_z) + OFFSET, 0.15 * 11.0)


func test_stairwell_flight_b_continues_the_climb_from_floor1() -> void:
	var tread_z := -8.0 - 0.272727 * 10.5
	_assert_floor(Vector3(-16, 6, tread_z) + OFFSET, 3.3 + 0.15 * 11.0)


func test_every_floor_has_a_solid_ceiling() -> void:
	for y: float in [0.0, 3.3, 6.6]:
		var hit := _ray(Vector3(5, y + 1, -3) + OFFSET, Vector3(5, y + 4, -3) + OFFSET)
		assert_false(hit.is_empty(), "Floor at y=%s must be covered" % y)


func test_the_south_face_is_open_above_the_knee_wall() -> void:
	# Beyond this is the deliberately solid city backdrop (see CityBuilding* nodes).
	var hit := _ray(Vector3(0, 2, 13) + OFFSET, Vector3(0, 2, 18) + OFFSET)
	assert_true(hit.is_empty(), "Open facade must let a standing player see outside")


func test_the_entrance_door_and_garage_door_are_solid() -> void:
	for pos: Vector3 in [Vector3(12, 1.1, 32.15), Vector3(-10, 1.1, -5.6) + OFFSET]:
		var hit := _ray(pos + Vector3(0, 0, -0.5), pos + Vector3(0, 0, 0.5))
		assert_false(hit.is_empty(), "Door panel at %s must be solid" % pos)


func _assert_floor(from: Vector3, expected_y: float, tolerance: float = 0.05) -> void:
	var hit := _ray(from, from - Vector3(0, 8, 0))
	assert_false(hit.is_empty(), "Walkable floor at %s" % from)
	if not hit.is_empty():
		var point: Vector3 = hit["position"]
		assert_almost_eq(point.y, expected_y, tolerance, "Floor height at %s" % from)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	return _root.get_world_3d().direct_space_state.intersect_ray(query)
