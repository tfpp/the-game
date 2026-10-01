extends GutTest

const FEATURE := preload("res://features/casino_legacy/feature.tscn")
const ROOM := preload("res://features/casino_hub/gridmap/playable.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _access: Node3D


func before_each() -> void:
	add_child_autofree(ROOM.instantiate())
	_access = FEATURE.instantiate() as Node3D
	add_child_autofree(_access)
	await wait_physics_frames(4)


func test_door_round_trip_uses_server_teleport_and_rejects_distant_use() -> void:
	var player := PLAYER.instantiate() as Player
	player.set_multiplayer_authority(1)
	add_child_autofree(player)
	var door := _access.get_node("Entrance") as GarageDoor
	var back := _access.get_node("Legacy/ReturnDoor") as GarageDoor
	player.net_position = door.global_position + Vector3(20, 0, 0)
	var before := player.net_position
	door.request_enter()
	assert_eq(player.net_position, before)
	player.net_position = door.global_position
	door.request_enter()
	assert_eq(player.net_position, (_access.get_node("Legacy/Arrival") as Marker3D).global_position)
	player.net_position = back.global_position
	back.request_enter()
	assert_eq(player.net_position, (_access.get_node("CasinoArrival") as Marker3D).global_position)


func test_both_arrivals_have_floor_clearance_and_legacy_gambling_is_present() -> void:
	var space := _access.get_world_3d().direct_space_state
	var hull := CapsuleShape3D.new()
	hull.radius = 0.4064
	hull.height = 1.8288
	for name: String in ["CasinoArrival", "Legacy/Arrival"]:
		var marker := _access.get_node(name) as Marker3D
		var ray := PhysicsRayQueryParameters3D.create(
			marker.global_position, marker.global_position - Vector3(0, 3, 0), 1
		)
		var hit := space.intersect_ray(ray)
		assert_false(hit.is_empty())
		if not hit.is_empty():
			assert_almost_eq((hit["position"] as Vector3).y, 0.0, 0.01)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = hull
		query.collision_mask = 1
		query.transform.origin = marker.global_position
		assert_true(space.intersect_shape(query).is_empty())
	assert_eq(_access.get_node("Legacy/Slots").get_child_count(), 8)
	assert_true(_access.get_node("Legacy/Roulette/Table") is RouletteTable)
	assert_null((_access.get_node("Legacy/Environment") as WorldEnvironment).environment)
