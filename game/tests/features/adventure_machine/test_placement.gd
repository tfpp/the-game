extends GutTest

const ROOM := preload("res://features/casino_hub/gridmap/playable.tscn")
const FEATURE := preload("res://features/adventure_machine/feature.tscn")
const SLOTS := preload("res://features/slot_machine/feature.tscn")
var _world: Node3D
var _machine: AdventureMachine
var _hull: CapsuleShape3D


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)
	_world.add_child(ROOM.instantiate())
	_machine = FEATURE.instantiate() as AdventureMachine
	_world.add_child(_machine)
	_world.add_child(SLOTS.instantiate())
	_hull = CapsuleShape3D.new()
	_hull.radius = .4064
	_hull.height = 1.8288
	await wait_physics_frames(4)


func _clear(at: Vector3, to: Vector3) -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = 1
	query.shape = _hull
	query.transform.origin = at
	query.motion = to - at
	assert_true(_world.get_world_3d().direct_space_state.intersect_shape(query).is_empty(), str(at))
	var result := _world.get_world_3d().direct_space_state.cast_motion(query)
	assert_almost_eq(result[0], 1.0, .001, "%s to %s" % [at, to])


func test_cabinet_base_matches_saved_promenade_and_faces_the_walking_aisle() -> void:
	assert_eq(_machine.global_position, Vector3(17, 0, -18.8))
	assert_eq(_machine.global_basis.z, Vector3.BACK, "This cabinet's front is +Z")
	var mesh := _machine.get_node("Model") as MeshInstance3D
	assert_almost_eq(mesh.mesh.get_aabb().position.y, 0.0, .001)
	var collider := _machine.get_node("Collider") as CollisionShape3D
	var box := collider.shape as BoxShape3D
	assert_almost_eq(collider.global_position.y - box.size.y * .5, 0.0, .001)
	for x: float in [-.3, .3]:
		for z: float in [-.25, .35]:
			var base := _machine.global_position + Vector3(x, 0, z)
			var ray := PhysicsRayQueryParameters3D.create(
				base + Vector3.UP * .1, base - Vector3.UP * .2, 1, [_machine.get_rid()]
			)
			var hit := _world.get_world_3d().direct_space_state.intersect_ray(ray)
			assert_false(hit.is_empty(), str(base))
			if not hit.is_empty():
				assert_almost_eq((hit["position"] as Vector3).y, 0.0, .001)
	assert_gt(_machine.position.x - box.size.x * .5, 15.4, "Not on the pit or rim")
	assert_gt(collider.global_position.z - box.size.z * .5, -19.5, "Clear of the north wall")
	assert_gt(_machine.position.distance_to(Vector3(4.6, 0, -15.8)), 10.0, "Open PR #510")


func test_spawn_jitter_portal_approaches_and_route_to_machine_stay_clear() -> void:
	for x: int in range(-3, 4):
		for z: int in range(-19, -12):
			_clear(Vector3(x, 1, z), Vector3(x, 1, z))
	_clear(Vector3(0, 1, -16), Vector3(0, 1, -14))
	_clear(Vector3(0, 1, -14), Vector3(17, 1, -14))
	_clear(Vector3(17, 1, -14), Vector3(17, 1, -17.2))
	for x: float in [7.0, 10.0, 22.7]:
		_clear(Vector3(x, 1, -14), Vector3(x, 1, -17.2))
	for x: float in [16.5, 17.0, 17.5]:
		_clear(Vector3(x, 1, -17.2), Vector3(x, 1, -17.2))


func test_existing_slot_bank_approaches_and_ramp_mouth_remain_clear() -> void:
	for machine: Node3D in _world.get_node("SlotMachines").get_children():
		var approach := machine.to_global(Vector3(0, .95, 2.6))
		_clear(Vector3(approach.x, approach.y, 5.9), approach)
	_clear(Vector3(-2, 1, -14), Vector3(2, 1, -14))
	# Existing painted asset and collider are reused, rather than a duplicate model.
	var source := (
		preload("res://features/casino_props/props/video_poker_machine.tscn").instantiate()
	)
	assert_same(
		(_machine.get_node("Model") as MeshInstance3D).mesh,
		(source.get_node("Model") as MeshInstance3D).mesh
	)
	source.free()
