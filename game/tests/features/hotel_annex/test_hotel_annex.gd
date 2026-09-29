extends GutTest

const Feature := preload("res://features/hotel_annex/feature.tscn")
const PlayerScene := preload("res://core/player/player.tscn")

var _feature: Node3D
var _hotel: StreamedRoom


func before_each() -> void:
	_feature = Feature.instantiate() as Node3D
	add_child_autofree(_feature)
	_hotel = _feature.get_node("Hotel") as StreamedRoom


func _player(at: Vector3) -> Player:
	var player := PlayerScene.instantiate() as Player
	player.set_multiplayer_authority(1)
	player.position = at
	player.net_position = at
	add_child_autofree(player)
	player.set_physics_process(false)
	return player


func test_dedicated_server_does_not_load_hotel_but_keeps_rpc_endpoints() -> void:
	await wait_physics_frames(2)
	assert_false(_hotel.is_loaded())
	assert_not_null(_feature.get_node("Entrance"))
	assert_not_null(_hotel.get_node("Return"))


func test_round_trip_preloads_room_and_preserves_links_after_unload() -> void:
	var casino := _feature.get_node("CasinoArrival") as Marker3D
	var arrival := _hotel.get_node("Arrival") as Marker3D
	var entrance := _feature.get_node("Entrance") as RoomDoor
	var exit := _hotel.get_node("Return") as RoomDoor
	var player := _player(casino.global_position)
	assert_true(entrance.can_use(player))
	entrance.use()
	assert_true(_hotel.is_loaded())
	assert_eq(player.net_position, arrival.global_position)
	assert_almost_eq(absf(player.net_yaw), PI, 0.001)
	assert_true(exit.can_use(player))
	exit.use()
	assert_eq(player.net_position, casino.global_position)
	assert_almost_eq(player.net_yaw, 0.0, 0.001)
	_hotel._hold_until_msec = 0
	await wait_physics_frames(2)
	assert_false(_hotel.is_loaded())
	assert_eq(exit.destination_room(), null)
	entrance.use()
	assert_true(_hotel.is_loaded())
	assert_eq(player.net_position, arrival.global_position)


func test_server_rejects_remote_use_from_casino_spawn() -> void:
	var player := _player(Vector3(2, 1, 5))
	(_feature.get_node("Entrance") as RoomDoor).request_enter()
	(_hotel.get_node("Return") as RoomDoor).request_enter()
	assert_eq(player.net_position, Vector3(2, 1, 5))
	assert_false(_hotel.is_loaded())


func test_restored_player_inside_hotel_loads_it_without_using_door() -> void:
	var arrival := _hotel.get_node("Arrival") as Marker3D
	var player := _player(arrival.global_position)
	await wait_physics_frames(2)
	assert_true(_hotel.is_loaded())
	player.global_position = Vector3(5, 1, 27)
	await wait_physics_frames(2)
	assert_false(_hotel.is_loaded())


func test_arrival_has_floor_and_clear_player_hull() -> void:
	_hotel.load_room(3000)
	var marker := _hotel.get_node("Arrival") as Marker3D
	var player := _player(marker.global_position)
	await wait_physics_frames(3)
	var space := player.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(
		marker.global_position, marker.global_position + Vector3.DOWN * 2
	)
	ray.exclude = [player.get_rid()]
	var hit := space.intersect_ray(ray)
	assert_false(hit.is_empty(), "Hotel floor under arrival")
	if not hit.is_empty():
		assert_almost_eq((hit.position as Vector3).y, 0.0, 0.02)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = (player.get_node("Collider") as CollisionShape3D).shape
	query.transform = player.global_transform
	query.exclude = [player.get_rid()]
	assert_eq(space.intersect_shape(query).size(), 0, "Arrival clears walls, pillars and door")


func test_expanded_wing_has_six_rooms_and_clear_connecting_hallways() -> void:
	var Layout := preload("res://features/world_builder/layout.gd")
	var spec: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://features/hotel_annex/hotel.json")
	)
	var layout: Dictionary = Layout.compile(spec)
	assert_eq(layout["errors"], [])
	assert_eq(layout["rooms"].size(), 6)
	assert_eq(layout["paths"].size(), 5)
	_hotel.load_room(3000)
	await wait_physics_frames(3)
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4064
	capsule.height = 1.8288
	query.shape = capsule
	var space := _hotel.get_world_3d().direct_space_state
	for path: Array in layout["paths"]:
		for index: int in 2:
			var a: Vector2i = path[index]
			var b: Vector2i = path[index + 1]
			if a == b:
				continue
			query.transform = Transform3D(
				Basis.IDENTITY, _hotel.to_global(Vector3(a.x + 0.5, 0.94, a.y + 0.5))
			)
			query.motion = Vector3(b.x - a.x, 0, b.y - a.y)
			assert_true(space.intersect_shape(query).is_empty(), "Clear hallway entrance")
			assert_almost_eq(
				space.cast_motion(query)[0], 1.0, 0.001, "Walkable connection %s" % str(path)
			)


func test_saved_wing_uses_uv2_lightmaps_without_runtime_lamp_lights() -> void:
	var scene := preload("res://features/hotel_annex/hotel.scn").instantiate() as Node3D
	assert_true(scene.has_meta("baked_lighting"))
	assert_eq(scene.find_children("*", "OmniLight3D", true, false).size(), 0)
	var chunks := 0
	for node: Node in scene.get_children():
		if not node is MeshInstance3D or str(node.name).ends_with("_unshadowed"):
			continue
		var mesh := node as MeshInstance3D
		for index: int in mesh.mesh.get_surface_count():
			var material := mesh.get_surface_override_material(index) as ShaderMaterial
			assert_not_null(material, "Baked shader survives scene save")
			assert_eq(mesh.gi_mode, GeometryInstance3D.GI_MODE_STATIC)
			var arrays := mesh.mesh.surface_get_arrays(index)
			assert_eq(arrays[Mesh.ARRAY_TEX_UV2].size(), arrays[Mesh.ARRAY_VERTEX].size())
		chunks += 1
	assert_gt(chunks, 0)
	assert_eq(chunks, scene.get_meta("lightmap_chunks", 0))
	var lightmap := scene.get_node_or_null("LightmapGI") as LightmapGI
	assert_not_null(lightmap)
	if lightmap != null:
		assert_true(lightmap.interior)
		assert_not_null(lightmap.light_data)
		if lightmap.light_data != null:
			assert_eq(lightmap.light_data.get_user_count(), chunks)
			assert_gt(lightmap.light_data.get_lightmap_textures().size(), 0)
			for index: int in lightmap.light_data.get_user_count():
				assert_is(
					lightmap.get_node(lightmap.light_data.get_user_path(index)), MeshInstance3D
				)
	scene.free()


func test_saved_lighting_fits_one_megabyte_in_git_and_export() -> void:
	var files: Array[String] = []
	var folder := "res://features/hotel_annex/hotel_lightmaps"
	for name: String in DirAccess.get_files_at(folder):
		files.append(folder.path_join(name))
	var sizes := preload("res://features/world_builder/tools/bake_files.gd").lighting_sizes(files)
	assert_gt(sizes.x, 0, "Source lighting files exist")
	assert_gt(sizes.y, 0, "Imported runtime lighting files exist")
	assert_lt(sizes.x, 1000000, "Saved source lightmaps and probe data fit the budget")
	assert_lt(sizes.y, 1000000, "Imported texture arrays and probe data fit the budget")
