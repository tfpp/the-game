extends GutTest
## The railing is shared low-poly geometry; its guard collision leaves both ramps open.

const SCENE := preload("res://features/casino_hub/casino_gridmap.tscn")
const FINISH := preload("res://features/room_kits/brass_railing_material.tres")
var _room: Node3D


func before_each() -> void:
	_room = SCENE.instantiate() as Node3D
	add_child_autofree(_room)
	await wait_physics_frames(3)


func test_railings_share_small_meshes_and_one_wood_brass_material() -> void:
	var grid := _room.get_node("PitRailing/SpansNorthSouth") as GridMap
	var posts := _room.get_node("PitRailing/Posts") as GridMap
	assert_eq(grid.get_used_cells_by_item(9).size(), 24)
	assert_eq(
		(_room.get_node("PitRailing/SpansEastWest") as GridMap).get_used_cells_by_item(9).size(), 24
	)
	assert_eq(posts.get_used_cells_by_item(10).size(), 50)
	assert_same(grid.mesh_library, posts.mesh_library)
	for id: int in [9, 10]:
		var mesh := grid.mesh_library.get_item_mesh(id)
		assert_eq(mesh.get_surface_count(), 1)
		assert_eq(mesh.get_faces().size() / 3, 56 if id == 9 else 104)
		assert_same(mesh.surface_get_material(0), FINISH)
		var arrays := mesh.surface_get_arrays(0)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var wood := false
		var brass := false
		for uv: Vector2 in uvs:
			assert_between(uv.x, 0.0, 1.0)
			assert_between(uv.y, 0.0, 1.0)
			wood = wood or uv.x > 0.5
			brass = brass or uv.x < 0.5
		assert_true(wood and brass, "Both finishes are mapped on each shared mesh")
	var texture := FINISH.get_shader_parameter("albedo_texture") as Texture2D
	assert_eq(texture.get_size(), Vector2(32, 32))
	assert_almost_eq(grid.mesh_library.get_item_mesh(10).get_aabb().size.y, 1.105, 0.001)


func test_guard_collision_is_continuous_around_the_rim() -> void:
	for direction: float in [-1.0, 1.0]:
		for x: float in [-14.5, -10.5, -4.5, 4.5, 10.5, 14.5]:
			assert_false(
				_ray(Vector3(x, 0.6, direction * 13), Vector3(x, 0.6, direction * 11)).is_empty()
			)
		for z: float in [-11.5, -6.5, 0.5, 6.5, 11.5]:
			assert_false(
				_ray(Vector3(direction * 16, 0.6, z), Vector3(direction * 14, 0.6, z)).is_empty()
			)


func test_both_ramp_mouths_remain_clear_for_standing_players() -> void:
	var hull := CapsuleShape3D.new()
	hull.radius = 0.4064
	hull.height = 1.8288
	for direction: float in [-1.0, 1.0]:
		for x: float in [-2.4, 0.0, 2.4]:
			assert_true(
				_ray(Vector3(x, 0.6, direction * 13), Vector3(x, 0.6, direction * 11)).is_empty()
			)
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = hull
			query.collision_mask = 1
			query.transform.origin = Vector3(x, 0.95, direction * 12.5)
			query.motion = Vector3(0, 0, -direction)
			assert_almost_eq(
				_room.get_world_3d().direct_space_state.cast_motion(query)[0], 1.0, 0.001
			)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return _room.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to, 1)
	)
