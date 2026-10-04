extends GutTest

const BOARD := preload("res://features/leaderboard/feature.tscn")
const ROOM := preload("res://features/casino_hub/gridmap/playable.tscn")


func test_pedestal_sits_on_live_floor_facing_spawn_without_blocking_routes() -> void:
	var room := ROOM.instantiate() as Node3D
	add_child_autofree(room)
	var board := BOARD.instantiate() as Leaderboard
	add_child_autofree(board)
	board.set_process(false)
	var statue := board.get_node("OnlineStatue") as OnlineStatue
	statue.set_process(false)
	var center := statue.global_position
	assert_eq(center, Vector3(4.6, 0, -15.8))
	assert_gt(center.x - 0.75, 3.0 + 0.4064, "Clear the entire jittered spawn square")
	assert_gt(center.z - 0.75, -19.0, "Keep the north door corridor clear")
	var toward_spawn := Vector3(0, 0, -16) - center
	assert_gt((-statue.global_basis.z).dot(toward_spawn.normalized()), 0.99)
	var cap := statue.get_node("Cap") as MeshInstance3D
	assert_almost_eq(cap.position.y + cap.get_aabb().end.y, 0.9, 0.001)
	await wait_physics_frames(3)
	var space := room.get_world_3d().direct_space_state
	for corner: Vector3 in [Vector3(-0.76, 0, -0.76), Vector3(0.76, 0, 0.76)]:
		var origin := center + corner + Vector3.UP
		var ray := PhysicsRayQueryParameters3D.create(origin, origin - Vector3.UP * 2, 1)
		var hit := space.intersect_ray(ray)
		assert_false(hit.is_empty())
		if not hit.is_empty():
			assert_almost_eq((hit["position"] as Vector3).y, 0.0, 0.02)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4064
	capsule.height = 1.8288
	# Spawn, elevator approach, both neighboring room door routes and pit-ramp approach.
	for x: float in [-3.0, 0.0, 3.0, 7.0]:
		for z: float in [-19.0, -17.8, -16.0, -13.0]:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.transform.origin = Vector3(x, 1.0, z)
			assert_true(space.intersect_shape(query).is_empty(), str(query.transform.origin))
