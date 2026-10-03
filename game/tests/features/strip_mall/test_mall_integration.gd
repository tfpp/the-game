extends GutTest
## Actual feature loading, authenticated travel, destination preload and GPS.

const MALL := preload("res://features/strip_mall/feature.tscn")
const COURT := preload("res://features/food_court/feature.tscn")
const KEBAB := preload("res://features/kebab_shop/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")

var _mall: Node3D
var _room: StreamedRoom
var _entrance: RoomDoor
var _exit: RoomDoor
var _player: Player


func before_each() -> void:
	# Shop RPC owners load independently before the mall, as the feature loader does.
	var features := Node3D.new()
	add_child_autofree(features)
	var court := COURT.instantiate()
	court.name = "food_court"
	features.add_child(court)
	var kebab := KEBAB.instantiate()
	kebab.name = "kebab_shop"
	features.add_child(kebab)
	_mall = MALL.instantiate() as Node3D
	_mall.name = "strip_mall"
	features.add_child(_mall)
	_room = _mall.get_node("Room") as StreamedRoom
	_entrance = _mall.get_node("Entrance") as RoomDoor
	_exit = _room.get_node("Exit") as RoomDoor
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_at(Vector3(0, 1, 25))


func test_visit_preloads_floor_then_return_uses_existing_authority_path() -> void:
	assert_false(_room.is_loaded())
	assert_eq(_entrance.destination_room(), _room)
	_entrance.use()
	assert_true(_room.arrival_held())
	assert_eq(_player.net_position, (_room.get_node("Arrival") as Marker3D).global_position)
	assert_true(_room.contains(_player.net_position))
	await wait_physics_frames(3)
	var query := PhysicsRayQueryParameters3D.create(
		_player.net_position, _player.net_position - Vector3(0, 4, 0)
	)
	var hit := _room.get_world_3d().direct_space_state.intersect_ray(query)
	assert_false(hit.is_empty(), "Floor exists before arrival")
	if not hit.is_empty():
		assert_almost_eq((hit["position"] as Vector3).y, 0.0, .02)
	_exit.use()
	assert_eq(_player.net_position, (_mall.get_node("CasinoArrival") as Marker3D).global_position)


func test_casino_approach_stays_walkable_on_the_unchanged_gridmap() -> void:
	var casino := preload("res://features/casino_hub/gridmap/playable.tscn").instantiate()
	add_child_autofree(casino)
	await wait_physics_frames(3)
	var shape := CapsuleShape3D.new()
	shape.radius = .4064
	shape.height = 1.8288
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = 1
	query.shape = shape
	query.exclude = [_player.get_rid()]
	query.transform.origin = Vector3(0, .95, 17)
	query.motion = Vector3(0, 0, 8)
	var space := _mall.get_world_3d().direct_space_state
	assert_almost_eq(space.cast_motion(query)[0], 1.0, .001)
	for z: float in [17.0, 21.0, 25.0]:
		var ray := PhysicsRayQueryParameters3D.create(Vector3(0, 1, z), Vector3(0, -1, z))
		ray.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(ray)
		assert_false(hit.is_empty(), "Casino approach floor")
		if not hit.is_empty():
			assert_almost_eq((hit["position"] as Vector3).y, 0.0, .02)


func test_portals_reject_unknown_sender_payload_and_remote_position() -> void:
	var entity := _entrance.get_node("NetworkedEntity") as NetworkedInteraction
	var denied := NetworkedEntity.Result.DENIED
	assert_eq(entity._evaluate(7, &"use", {}), denied)
	assert_eq(entity._evaluate(1, &"use", {"peer": 2}), denied)
	_at(Vector3(0, 1, 0))
	assert_eq(entity._evaluate(1, &"use", {}), denied)
	assert_eq(_player.net_position, Vector3(0, 1, 0))
	var exit_entity := _exit.get_node("NetworkedEntity") as NetworkedInteraction
	assert_eq(exit_entity._evaluate(1, &"use", {}), denied)


func test_two_customers_travel_without_moving_each_other() -> void:
	var other := PLAYER.instantiate() as Player
	other.name = "2"
	other.set_multiplayer_authority(2)
	add_child_autofree(other)
	other.set_physics_process(false)
	other.net_position = _player.net_position
	var entity := _entrance.get_node("NetworkedEntity") as NetworkedInteraction
	assert_eq(entity._evaluate(1, &"use", {}), NetworkedEntity.Result.ACCEPTED)
	assert_eq(other.net_position, Vector3(0, 1, 25))
	# The inherited shared 0.5 second cooldown serializes entrance use.
	assert_eq(entity._evaluate(2, &"use", {}), NetworkedEntity.Result.COOLDOWN)


func test_streaming_never_removes_food_rpc_owners_or_duplicates_seats() -> void:
	var court := _mall.get_parent().get_node("food_court") as FoodCourt
	var kebab := _mall.get_parent().get_node("kebab_shop") as KebabShop
	var entity := kebab.entity
	for repeat: int in 2:
		_room.load_room(3000)
		assert_true(_room.contains(kebab.global_position))
		for path: String in ["PokeStand", "WendysStand", "Booths"]:
			assert_true(
				(
					_room.contains((court.get_node(path) as Node3D).global_position)
					if path != "Booths"
					else _room.contains(court.seats[0].global_position)
				)
			)
		assert_eq(court.seats.size(), 32)
		assert_true(
			(
				_room
				. get_node("Content")
				. find_children("*", "MultiplayerSynchronizer", true, false)
				. is_empty()
			)
		)
		_room.unload_room()
		await wait_physics_frames(1)
		assert_true(is_instance_valid(entity))
		assert_eq(kebab.entity, entity)
		assert_eq(court.seats.size(), 32)


func test_gps_routes_old_food_markers_and_new_shop_places_through_mall_door() -> void:
	var gps := preload("res://features/gps/feature.tscn").instantiate() as Gps
	add_child_autofree(gps)
	for path: String in ["Destinations/FoodCourt", "Destinations/KebabShop"]:
		var goal := gps.get_node(path) as GpsDestination
		assert_true(_room.contains(goal.global_position))
		var hop := GpsRoute.next_hop(
			gps.regions(), gps.links(), Vector3(0, 0, 16), goal.global_position
		)
		assert_eq(hop["position"], _entrance.global_position)
	for path: String in ["Destination", "PokeDestination", "WendysDestination", "ZabkaDestination"]:
		assert_true(_room.contains((_room.get_node(path) as Node3D).global_position))


func test_late_loaded_mall_has_identical_static_links_and_no_persistent_state() -> void:
	var late := MALL.instantiate() as Node3D
	add_child_autofree(late)
	assert_eq((late.get_node("Room") as StreamedRoom).global_bounds(), _room.global_bounds())
	assert_eq(
		(late.get_node("Entrance") as RoomDoor).destination_room().global_bounds(),
		_room.global_bounds()
	)
	assert_false((late.get_node("Room") as StreamedRoom).is_loaded())


func _at(point: Vector3) -> void:
	_player.global_position = point
	_player.net_position = point
