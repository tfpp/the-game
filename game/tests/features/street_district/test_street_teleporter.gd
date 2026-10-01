extends GutTest

const FEATURE := preload("res://features/street_district/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _feature: Node3D
var _room: StreamedRoom


func before_each() -> void:
	_feature = FEATURE.instantiate() as Node3D
	add_child_autofree(_feature)
	_room = _feature.get_node("Room") as StreamedRoom


func test_authenticated_round_trip_loads_geometry_before_arrival() -> void:
	assert_false(_room.is_loaded())
	var entrance := _feature.get_node("Entrance") as RoomDoor
	var player := PLAYER.instantiate() as Player
	player.set_multiplayer_authority(1)
	player.position = entrance.global_position
	player.net_position = player.position
	add_child_autofree(player)
	player.set_physics_process(false)
	var entity := entrance.get_node("NetworkedEntity") as NetworkedInteraction
	assert_eq(entity._evaluate(999, &"use", {}), NetworkedEntity.Result.DENIED)
	player.net_position += Vector3(10, 0, 0)
	assert_eq(entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	player.net_position = entrance.global_position
	entrance.use()
	assert_true(_room.is_loaded())
	assert_eq(player.net_position, (_room.get_node("Arrival") as Marker3D).global_position)
	assert_eq(entity._evaluate(1, &"use", {}), NetworkedEntity.Result.COOLDOWN)
	await wait_physics_frames(3)
	var arrival := player.net_position
	var space := _room.get_world_3d().direct_space_state
	var hit := space.intersect_ray(
		PhysicsRayQueryParameters3D.create(arrival, arrival + Vector3.DOWN * 2)
	)
	assert_false(hit.is_empty(), "Arrival has district collision before teleport")
	var returning := _room.get_node("Return") as RoomDoor
	player.net_position = returning.global_position
	returning.use()
	assert_eq(player.net_position, (_feature.get_node("CasinoArrival") as Marker3D).global_position)
	_room.unload_room()
	await wait_physics_frames(2)
	assert_not_null(_room.get_node("Return/NetworkedEntity"))


func test_gps_and_return_marker_are_in_their_regions() -> void:
	var dev := preload("res://features/dev_room/feature.tscn").instantiate() as Node3D
	add_child_autofree(dev)
	var region := (dev.get_node("Destination") as GpsDestination).area
	assert_true(region.has_point((_feature.get_node("CasinoArrival") as Marker3D).position))
	assert_true(region.has_point((_feature.get_node("Entrance") as RoomDoor).position))
	var goal := _feature.get_node("Destinations/District") as GpsDestination
	assert_true(_room.contains(goal.global_position))
	var gps := preload("res://features/gps/feature.tscn").instantiate() as Gps
	add_child_autofree(gps)
	var inbound := GpsRoute.next_hop(
		gps.regions(), gps.links(), Vector3(300, 1, -300), goal.global_position
	)
	assert_eq(inbound["position"], (_feature.get_node("Entrance") as RoomDoor).global_position)


func test_searchable_objects_persist_while_geometry_streams_and_keep_routes_clear() -> void:
	var objects := _room.get_node("StreetObjects")
	assert_eq(objects.get_child_count(), 12)
	for i: int in range(6):
		var bin := objects.get_node("Dumpster%d/Loot" % i) as LootContainer
		assert_eq(bin.noun, "dumpster")
		assert_not_null(bin.loot_table)
		assert_true(bin.get_node("NetworkedEntity") is NetworkedInteraction)
		assert_not_null(objects.get_node("Dumpster%d/Model/Hinge" % i))
	_room.load_room(3000)
	await wait_physics_frames(3)
	var space := _room.get_world_3d().direct_space_state
	var hull := CapsuleShape3D.new()
	hull.radius = .4064
	hull.height = 1.8288
	for row: int in range(3):
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = hull
		query.transform.origin = _room.to_global(Vector3(-27, .95, row * 28))
		query.motion = Vector3(54, 0, 0)
		assert_almost_eq(space.cast_motion(query)[0], 1.0, .001, "Street central lane")
	for x: float in [-14.0, 14.0]:
		for z: float in [6.0, 34.0]:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = hull
			query.transform.origin = _room.to_global(Vector3(x, .95, z))
			query.motion = Vector3(0, 0, 16)
			assert_almost_eq(space.cast_motion(query)[0], 1.0, .001, "Alley entrance and lane")
	_room.unload_room()
	await wait_physics_frames(2)
	assert_eq(objects.get_child_count(), 12, "Shared interaction paths survive streaming")


func test_casino_portals_connect_lobby_and_facade_in_both_directions() -> void:
	var entrance := _feature.get_node("CasinoStreetEntrance") as RoomDoor
	var player := PLAYER.instantiate() as Player
	player.set_multiplayer_authority(1)
	player.position = entrance.global_position
	player.net_position = player.position
	add_child_autofree(player)
	player.set_physics_process(false)
	entrance.use()
	assert_true(_room.is_loaded())
	assert_eq(player.net_position, (_room.get_node("CasinoArrival") as Marker3D).global_position)
	assert_not_null(_room.get_node("Content/District/CasinoSign"))
	await wait_physics_frames(3)
	var hull := CapsuleShape3D.new()
	hull.radius = .4064
	hull.height = 1.8288
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = hull
	query.transform.origin = player.net_position
	query.exclude = [player.get_rid()]
	var space := _room.get_world_3d().direct_space_state
	assert_true(space.intersect_shape(query).is_empty(), "Casino arrival is clear")
	query.transform.origin = _room.to_global(Vector3(18.75, .95, 32.6))
	query.motion = Vector3(0, 0, 1.3)
	assert_almost_eq(space.cast_motion(query)[0], 1.0, .001, "Casino doorway approach")
	var door := _room.get_node("CasinoEntrance") as RoomDoor
	player.net_position = door.global_position
	door.use()
	assert_eq(
		player.net_position, (_feature.get_node("MainCasinoArrival") as Marker3D).global_position
	)


func test_marquee_has_raised_uv_geometry_and_animated_emissive_bulbs() -> void:
	var sign := (
		preload("res://features/street_district/props/casino_marquee.tscn").instantiate() as Node3D
	)
	add_child_autofree(sign)
	sign.set_process(false)
	var panel := sign.get_node("PanelAndRaisedLetters") as MeshInstance3D
	assert_true(panel.mesh is ArrayMesh)
	var arrays := panel.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_eq(vertices.size(), uvs.size())
	assert_gt(panel.mesh.get_aabb().end.z, .2, "Lettering stands proud of backing")
	var material := panel.material_override as StandardMaterial3D
	assert_eq(material.albedo_texture.get_width(), 64)
	assert_eq(material.albedo_texture.get_height(), 64)
	assert_eq(sign.find_children("*", "Label3D", true, false).size(), 0)
	var bulb := sign.get_node("Bulb0Top") as MeshInstance3D
	var glow := bulb.material_override as StandardMaterial3D
	assert_true(glow.emission_enabled)
	sign.set("_time", 0.0)
	sign.call("_process", 0.0)
	var before := glow.emission_energy_multiplier
	sign.call("_process", .2)
	assert_lt(glow.emission_energy_multiplier, before, "Chase lights change brightness")
