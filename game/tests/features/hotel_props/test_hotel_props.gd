extends GutTest

const FEATURE := preload("res://features/hotel_props/feature.tscn")
const INTERIOR := preload("res://features/hotel_props/interior.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const GPS := preload("res://features/gps/feature.tscn")

var _feature: Node3D
var _room: StreamedRoom


func before_each() -> void:
	_feature = FEATURE.instantiate() as Node3D
	add_child_autofree(_feature)
	_room = _feature.get_node("Room") as StreamedRoom


func _player_at(at: Vector3) -> Player:
	var player := PLAYER.instantiate() as Player
	player.set_multiplayer_authority(1)
	player.position = at
	player.net_position = at
	add_child_autofree(player)
	player.set_physics_process(false)
	return player


func test_fifty_individual_textured_uv_meshes_and_collisions() -> void:
	var interior := INTERIOR.instantiate() as Node3D
	add_child_autofree(interior)
	var props := interior.get_node("Props")
	assert_eq(props.get_child_count(), 50)
	var textures: Array[String] = []
	var counts := {32: 0, 64: 0, 128: 0}
	for prop: StaticBody3D in props.get_children():
		var model := prop.get_node("Model") as MeshInstance3D
		assert_true(model.mesh is ArrayMesh)
		var arrays := model.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		assert_eq(uvs.size(), vertices.size())
		assert_gte(vertices.size(), 36)
		for uv: Vector2 in uvs:
			assert_true(uv.x >= 0 and uv.x <= 1 and uv.y >= 0 and uv.y <= 1)
		var material := model.material_override as StandardMaterial3D
		assert_eq(material.texture_filter, BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS)
		var texture := material.albedo_texture
		assert_false(textures.has(texture.resource_path), str(prop.get_meta("prop_id")))
		textures.append(texture.resource_path)
		assert_true(counts.has(texture.get_width()))
		assert_eq(texture.get_width(), texture.get_height())
		counts[texture.get_width()] += 1
		assert_not_null((prop.get_node("Collider") as CollisionShape3D).shape)
	assert_eq(counts, {32: 10, 64: 17, 128: 23})
	var letter := props.get_node("MailEnvelope/Model") as MeshInstance3D
	assert_eq((letter.material_override as StandardMaterial3D).albedo_texture.get_width(), 32)


func test_no_visitors_leaves_room_unloaded_and_endpoints_present() -> void:
	await wait_physics_frames(3)
	assert_false(_room.is_loaded())
	for path: String in ["Entrance", "Room/Return"]:
		var door := _feature.get_node(path) as RoomDoor
		assert_true(door.is_in_group(&"interactables"))
		assert_not_null(door.get_node("NetworkedEntity") as NetworkedInteraction)


func test_validated_round_trip_preloads_floor() -> void:
	var entrance := _feature.get_node("Entrance") as RoomDoor
	var entity := entrance.get_node("NetworkedEntity") as NetworkedInteraction
	var player := _player_at(entrance.global_position + Vector3(20, 0, 0))
	assert_eq(entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_eq(entity._evaluate(999, &"use", {}), NetworkedEntity.Result.DENIED)
	player.global_position = entrance.global_position
	player.net_position = player.global_position
	assert_eq(entity._evaluate(1, &"use", {"peer_id": 1}), NetworkedEntity.Result.DENIED)
	assert_false(_room.is_loaded())
	entrance.use()
	assert_true(_room.is_loaded(), "Collision built before travel")
	assert_eq(player.net_position, (_room.get_node("Arrival") as Marker3D).global_position)
	assert_eq(entity._evaluate(1, &"use", {}), NetworkedEntity.Result.COOLDOWN)
	var returning := _room.get_node("Return") as RoomDoor
	player.global_position = returning.global_position
	player.net_position = player.global_position
	returning.use()
	assert_eq(player.net_position, (_feature.get_node("CasinoArrival") as Marker3D).global_position)


func test_arrival_floor_hull_and_central_aisle_are_clear() -> void:
	_room.load_room(3000)
	await wait_physics_frames(5)
	var space := _room.get_world_3d().direct_space_state
	var arrival := (_room.get_node("Arrival") as Marker3D).global_position
	var hit := space.intersect_ray(
		PhysicsRayQueryParameters3D.create(arrival, arrival + Vector3.DOWN * 2)
	)
	assert_false(hit.is_empty())
	if not hit.is_empty():
		assert_almost_eq((hit["position"] as Vector3).y, 0.0, 0.002)
	var hull := CapsuleShape3D.new()
	hull.radius = 0.4064
	hull.height = 1.8288
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = hull
	query.transform.origin = _room.to_global(Vector3(0, 0.95, 6))
	query.motion = Vector3(0, 0, -12)
	assert_true(space.intersect_shape(query).is_empty(), "Clear standing arrival")
	assert_almost_eq(space.cast_motion(query)[0], 1.0, 0.001, "Open central aisle")


func test_gps_routes_through_dev_room_and_back() -> void:
	var dev := preload("res://features/dev_room/feature.tscn").instantiate() as Node3D
	add_child_autofree(dev)
	var gps := GPS.instantiate() as Gps
	add_child_autofree(gps)
	var goal := _feature.get_node("Destinations/Room") as GpsDestination
	assert_true(_room.contains(goal.global_position))
	var entrance := _feature.get_node("Entrance") as RoomDoor
	var returning := _room.get_node("Return") as RoomDoor
	var arrival := _feature.get_node("CasinoArrival") as Marker3D
	assert_true((dev.get_node("Destination") as GpsDestination).area.has_point(arrival.position))
	var inbound := GpsRoute.next_hop(
		gps.regions(), gps.links(), Vector3(300, 1, -300), goal.global_position
	)
	assert_eq(inbound["position"], entrance.global_position)
	var outbound := GpsRoute.next_hop(
		gps.regions(), gps.links(), goal.global_position, arrival.global_position
	)
	assert_eq(outbound["position"], returning.global_position)


func test_unload_frees_props_without_removing_portals() -> void:
	_room.load_room(3000)
	assert_eq(_room.get_node("Content/Props").get_child_count(), 50)
	_room.unload_room()
	await wait_physics_frames(2)
	assert_false(_room.is_loaded())
	assert_null(_room.get_node_or_null("Content"))
	assert_not_null(_room.get_node("Return/NetworkedEntity"))
