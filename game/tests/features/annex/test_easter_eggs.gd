extends GutTest

const ANNEX := preload("res://features/annex/feature.tscn")
var _annex: Node3D
var _secrets: Node3D


func before_each() -> void:
	_annex = ANNEX.instantiate() as Node3D
	add_child_autofree(_annex)
	_secrets = _annex.get_node("EasterEggs")
	await wait_physics_frames(3)


func test_six_distinct_secrets_are_spread_through_the_wings() -> void:
	assert_eq(_secrets.get_child_count(), 6)
	var messages: Array[String] = []
	for secret: Node3D in _secrets.get_children():
		var label := secret.get_node("Joke") as Label3D
		assert_false(messages.has(label.text))
		messages.append(label.text)
		for other: Node3D in _secrets.get_children():
			if secret != other:
				assert_gt(secret.position.distance_to(other.position), 25.0)


func test_all_plaques_mount_on_real_walls_and_face_clear_reading_space() -> void:
	var space := _annex.get_world_3d().direct_space_state
	for secret: Node3D in _secrets.get_children():
		var normal := secret.global_basis.z
		var face := secret.global_position
		var wall := space.intersect_ray(
			PhysicsRayQueryParameters3D.create(face + normal * 0.2, face - normal * 0.2)
		)
		assert_false(wall.is_empty(), secret.name)
		if not wall.is_empty():
			assert_almost_eq(wall.position.distance_to(face), 0.0, 0.01, secret.name)
			assert_gt(wall.normal.dot(normal), 0.99, "Text faces inward")
		var approach := face + normal * 1.5
		var sight := space.intersect_ray(
			PhysicsRayQueryParameters3D.create(approach, face + normal * 0.06)
		)
		assert_true(sight.is_empty(), "Readable from inside the room")
		var floor_hit := space.intersect_ray(
			PhysicsRayQueryParameters3D.create(approach, approach - Vector3(0, 2, 0))
		)
		assert_false(floor_hit.is_empty(), "Reading position has a floor")
		if not floor_hit.is_empty():
			assert_almost_eq(floor_hit.position.y, 0.0, 0.01)
		var shape := PhysicsShapeQueryParameters3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.4064
		capsule.height = 1.8288
		shape.shape = capsule
		shape.transform.origin = Vector3(approach.x, 0.94, approach.z)
		assert_true(space.intersect_shape(shape).is_empty(), "Standing reading clearance")


func test_static_budget_and_peer_independence() -> void:
	var second := ANNEX.instantiate() as Node3D
	add_child_autofree(second)
	var copy := second.get_node("EasterEggs")
	assert_eq(_secrets.find_children("*", "MeshInstance3D", true, false).size(), 6)
	assert_eq(_secrets.find_children("*", "Label3D", true, false).size(), 6)
	for node: Node in _secrets.find_children("*", "", true, false):
		assert_null(node.get_script(), "No runtime scripts or processing")
		assert_true(node is Node3D)
		assert_false(node is CollisionObject3D or node is Light3D)
		if node is GeometryInstance3D:
			assert_eq(node.visibility_range_end, 18.0)
			assert_eq(node.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	for secret: Node3D in _secrets.get_children():
		var other := copy.get_node(NodePath(secret.name)) as Node3D
		assert_eq(secret.transform, other.transform)
		var label := secret.get_node("Joke") as Label3D
		assert_eq(label.text, other.get_node("Joke").text)
		assert_false(label.no_depth_test)
		assert_false(label.double_sided)
