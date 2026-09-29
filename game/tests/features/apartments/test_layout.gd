extends GutTest

const FEATURE := preload("res://features/apartments/feature.tscn")
const CASINO := preload("res://world/room.tscn")
var _home: Apartments


func before_each() -> void:
	_home = FEATURE.instantiate() as Apartments
	add_child_autofree(_home)


func test_ten_units_have_clear_doorways_floors_and_furniture() -> void:
	var floor_node := _home._spawn_floor(1) as StreamedRoom
	_home.floors.add_child(floor_node)
	floor_node.load_room(10000)
	await wait_physics_frames(3)
	var signs := 0
	var beds := 0
	for child: Node in floor_node.get_node("Content").get_children():
		if child is Label3D and (child as Label3D).text.begins_with("UNIT"):
			signs += 1
			assert_eq((child as Label3D).billboard, BaseMaterial3D.BILLBOARD_DISABLED)
			var front := (child as Label3D).basis.z
			assert_lt(front.z * (child as Label3D).position.z, 0.0)
		if child is CSGBox3D and (child as CSGBox3D).size == Vector3(1.8, 0.6, 2.8):
			beds += 1
	assert_eq(signs, 10)
	assert_eq(beds, 10)
	for slot: int in 10:
		var x := -12.0 + (slot % 5) * 6.0
		var side := -1.0 if slot < 5 else 1.0
		for step: int in 13:
			var point := floor_node.to_global(Vector3(x, 1, side * step * 0.5))
			_assert_supported(point, floor_node.global_position.y)
			_assert_capsule_clear(point)
	for step: int in 57:
		var point := floor_node.to_global(Vector3(-14 + step * 0.5, 1, 0))
		_assert_supported(point, floor_node.global_position.y)
		_assert_capsule_clear(point)


func test_lobby_routes_and_arrivals_have_support() -> void:
	var lobby := _home.get_node("Lobby") as StreamedRoom
	lobby.load_room(10000)
	await wait_physics_frames(3)
	for point: Vector3 in [
		Vector3(-5, 1, 4), Vector3(0, 1, 0), Vector3(0, 1, -1), Vector3(5, 1, -4)
	]:
		_assert_supported(lobby.to_global(point), 0)
		_assert_capsule_clear(lobby.to_global(point))
	assert_true(lobby.contains(lobby.get_node("Arrival").global_position))
	assert_true(lobby.contains(lobby.get_node("EntranceArrival").global_position))


func test_casino_entrance_is_supported_and_approachable() -> void:
	add_child_autofree(CASINO.instantiate())
	await wait_physics_frames(3)
	for step: int in 13:
		var point := Vector3(-10, 1, 24 + step * 0.5)
		_assert_supported(point, 0)
		_assert_capsule_clear(point)
	assert_eq(_home.get_node("Entrance").position, Vector3(-10, 1.2, 31))


func _assert_supported(point: Vector3, height: float) -> void:
	var ray := PhysicsRayQueryParameters3D.create(point, point - Vector3(0, 2, 0))
	var hit := _home.get_world_3d().direct_space_state.intersect_ray(ray)
	assert_false(hit.is_empty(), "Floor at %s" % point)
	if not hit.is_empty():
		assert_almost_eq((hit["position"] as Vector3).y, height, 0.02)


func _assert_capsule_clear(point: Vector3) -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, point)
	var hits := _home.get_world_3d().direct_space_state.intersect_shape(query)
	assert_true(hits.is_empty(), "Standing clearance at %s" % point)
