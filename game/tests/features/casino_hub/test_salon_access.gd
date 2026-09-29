extends GutTest
## Standing-player clearance through the furnished salon, its ramps and gallery.

const ROOM := preload("res://world/room.tscn")
const SLOTS := preload("res://features/slot_machine/feature.tscn")
const ROULETTE := preload("res://features/roulette/feature.tscn")
var _world: Node3D
var _hull: CapsuleShape3D


func before_all() -> void:
	_world = Node3D.new()
	add_child(_world)
	_world.add_child(ROOM.instantiate())
	_world.add_child(SLOTS.instantiate())
	_world.add_child(ROULETTE.instantiate())
	_hull = CapsuleShape3D.new()
	_hull.radius = 0.4064
	_hull.height = 1.8288
	await wait_physics_frames(4)


func after_all() -> void:
	_world.free()


func test_central_aisle_and_each_machine_remain_accessible() -> void:
	_sweep(Vector3(0, -0.55, -5.9), Vector3(0, -0.55, 5.9))
	_sweep(Vector3(0, -0.55, 5.9), Vector3(4.8, -0.55, 5.9))
	for machine: Node3D in _world.get_child(1).get_children():
		var approach := machine.to_global(Vector3(0, 0.95, 2.6))
		_sweep(Vector3(approach.x, approach.y, 5.9), approach)
		assert_lt(approach.distance_to(machine.interaction_point()), SlotMachine.USE_RANGE)


func test_entire_six_metre_spawn_jitter_area_is_clear() -> void:
	var spawn := _world.get_child(0).get_node("Spawn") as Marker3D
	for x: int in range(-3, 4):
		for z: int in range(-3, 4):
			var query := PhysicsShapeQueryParameters3D.new()
			query.collision_mask = 1  # Match player movement; layer 2 is weapon-only.
			query.shape = _hull
			query.transform.origin = spawn.global_position + Vector3(x, 0, z)
			var hits := _world.get_world_3d().direct_space_state.intersect_shape(query)
			assert_true(hits.is_empty(), "Spawn hull is clear at %s" % query.transform.origin)


func test_gallery_staircase_has_support_and_standing_clearance() -> void:
	_sweep(Vector3(0, -0.55, 5.9), Vector3(-10.5, -0.55, 5.9))
	_sweep(Vector3(-10.5, -0.55, 5.9), Vector3(-10.5, -0.55, 5.2))
	_sweep(Vector3(-10.5, -0.55, 5.2), Vector3(-12.8, -0.55, 5.2))
	# Extra 0.12 m accounts for a vertical capsule's rounded base on the 21-degree ramp.
	var bottom := Vector3(-12.8, -0.40, 3.7)
	var top := Vector3(-12.8, 4.12, -7.8)
	_sweep(bottom, top)
	_sweep(top, Vector3(-12.8, 4.15, -9))
	_sweep(Vector3(-12.8, 4.15, -9), Vector3(12.8, 4.15, -9))
	for z: float in [3.0, 0.0, -3.0, -6.0, -9.0]:
		var expected_y := 3.2 if z < -8 else -1.5 + (4.0 - z) * 4.7 / 12.0
		var ray := PhysicsRayQueryParameters3D.create(
			Vector3(-12.8, expected_y + 0.5, z), Vector3(-12.8, expected_y - 0.5, z)
		)
		var hit := _world.get_world_3d().direct_space_state.intersect_ray(ray)
		assert_false(hit.is_empty(), "Stair/gallery floor support at z=%s" % z)
		if not hit.is_empty():
			assert_almost_eq((hit["position"] as Vector3).y, expected_y, 0.08)


func _sweep(start: Vector3, end: Vector3) -> void:
	for reverse: bool in [false, true]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.collision_mask = 1  # Match player movement; layer 2 is weapon-only.
		query.shape = _hull
		query.transform.origin = end if reverse else start
		query.motion = start - end if reverse else end - start
		var result := _world.get_world_3d().direct_space_state.cast_motion(query)
		assert_almost_eq(result[0], 1.0, 0.001, "Standing route %s -> %s" % [start, end])
