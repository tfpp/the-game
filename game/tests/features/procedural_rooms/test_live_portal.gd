extends GutTest

const Cheats := preload("res://tests/features/dev_access/cheats_fixture.gd")
const FEATURE := preload("res://features/procedural_rooms/prototype.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _feature: Node3D
var _player: Player


func before_each() -> void:
	_feature = FEATURE.instantiate()
	add_child(_feature)
	_player = PLAYER.instantiate()
	_player.name = "1"
	add_child(_player)
	_player.set_physics_process(false)
	Cheats.enable(self)


func after_each() -> void:
	_feature.free()
	_player.free()


func test_portal_round_trip_validates_identity_and_range_and_keeps_one_player() -> void:
	var entrance := _feature.get_node("Entrance") as GarageDoor
	var entity := entrance.get_node("NetworkedEntity") as NetworkedInteraction
	_player.net_position = Vector3.ZERO
	assert_eq(entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	_player.net_position = entrance.global_position
	_player.position = _player.net_position
	assert_eq(entity._evaluate(2, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_eq(entity._evaluate(1, &"use", {"peer": 1}), NetworkedEntity.Result.DENIED)
	assert_eq(entity._evaluate(1, &"use", {}), NetworkedEntity.Result.ACCEPTED)
	assert_eq(
		_player.net_position, (_feature.get_node("Garage/Arrival") as Marker3D).global_position
	)
	var returning := _feature.get_node("Garage/Return") as GarageDoor
	_player.net_position = returning.global_position
	_player.position = _player.net_position
	returning.use()
	assert_eq(
		_player.net_position, (_feature.get_node("CasinoArrival") as Marker3D).global_position
	)
	assert_true(_feature.find_children("*", "Player", true, false).is_empty())
	assert_true(_feature.find_children("*", "WorldEnvironment", true, false).is_empty())


func test_gps_routes_through_portal_and_arrival_has_clear_supported_floor() -> void:
	var goal := _feature.get_node("Destinations/Garage") as GpsDestination
	var entrance := _feature.get_node("Entrance") as GarageDoor
	var arrival := _feature.get_node("Garage/Arrival") as Marker3D
	var regions: Array[AABB] = [goal.area]
	var links: Array[Dictionary] = [
		{
			"from": entrance.global_position,
			"to": arrival.global_position,
			"label": entrance.door_label
		}
	]
	var next := GpsRoute.next_hop(regions, links, Vector3(2, .2, 5), arrival.global_position)
	assert_eq(next["position"], entrance.global_position)
	await wait_physics_frames(2)
	var query := PhysicsRayQueryParameters3D.create(
		arrival.global_position, arrival.global_position - Vector3.UP * 2
	)
	var hit := _feature.get_world_3d().direct_space_state.intersect_ray(query)
	assert_false(hit.is_empty())
	assert_almost_eq((hit["position"] as Vector3).y, -6.0, .001)
	var capsule := CapsuleShape3D.new()
	capsule.radius = .4064
	capsule.height = 1.8288
	var overlap := PhysicsShapeQueryParameters3D.new()
	overlap.shape = capsule
	overlap.transform.origin = arrival.global_position + Vector3.UP * .95
	assert_true(_feature.get_world_3d().direct_space_state.intersect_shape(overlap).is_empty())
	for node: Node in _feature.find_children("*", "Node3D", true, false):
		if node.is_in_group(&"world_lift_stops") or node.is_in_group(&"prototype_doors"):
			assert_true(node.is_in_group(&"interactables"))
			assert_true(node.has_method("can_use") and node.has_method("interaction_text"))


func test_standalone_teleporter_in_dev_room_has_clear_approach_and_supported_return() -> void:
	var dev_room := preload("res://features/dev_room/feature.tscn").instantiate() as Node3D
	add_child_autofree(dev_room)
	await wait_physics_frames(2)
	assert_false(_feature.has_node("TeleportRoom"))
	var entrance := _feature.get_node("Entrance") as GarageDoor
	var room := dev_room.get_node("Destination") as GpsDestination
	assert_true(room.area.has_point(entrance.global_position))
	assert_eq(
		(_feature.get_node("Destinations/Portal") as GpsDestination).label, "Garage Teleporter"
	)
	var space := _feature.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = .4064
	capsule.height = 1.8288
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform.origin = Vector3(294, .95, -305.1)
	query.motion = Vector3(0, 0, -1.8)
	assert_eq(space.cast_motion(query)[0], 1.0)
	var arrival := _feature.get_node("CasinoArrival") as Marker3D
	var ray := PhysicsRayQueryParameters3D.create(
		arrival.global_position, arrival.global_position - Vector3.UP
	)
	var hit := space.intersect_ray(ray)
	assert_false(hit.is_empty())
	assert_almost_eq((hit["position"] as Vector3).y, 0.0, .001)
