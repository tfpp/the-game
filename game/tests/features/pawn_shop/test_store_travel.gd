extends GutTest
## Real feature order, streamed arrival, authenticated return and GPS route chain.

const SHOP := preload("res://features/pawn_shop/feature.tscn")
const STARTER := preload("res://features/starter_room/feature.tscn")
const GPS := preload("res://features/gps/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")


func test_van_shop_and_return_with_later_loaded_garage() -> void:
	var features := Node3D.new()
	add_child_autofree(features)
	# Matches alphabetical feature loading: the return target doesn't exist yet.
	var shop := SHOP.instantiate() as Node3D
	shop.name = "pawn_shop"
	features.add_child(shop)
	var starter := STARTER.instantiate() as Node3D
	starter.name = "starter_room"
	features.add_child(starter)
	var gps := GPS.instantiate() as Gps
	features.add_child(gps)
	var room := shop.get_node("Room") as StreamedRoom
	var van := starter.get_node("Room/Van") as OperationsVan
	van.set_physics_process(false)
	var player := PLAYER.instantiate() as Player
	add_child_autofree(player)
	player.set_physics_process(false)
	player.net_position = van.to_global(van.entity.interaction_offset)
	player.global_position = player.net_position
	assert_false(room.is_loaded())
	van.request_trip(3)
	assert_true(room.arrival_held(), "Shop floor preloads during the driving screen")
	van._physics_process(OperationsVan.TRAVEL_SECONDS)
	assert_eq(player.net_position, van.arrival(3).global_position)
	van.panel.close(false)
	var exit_door := shop.get_node("Room/Exit") as RoomDoor
	var garage := starter.get_node("Room") as StreamedRoom
	assert_eq(exit_door.destination_room(), garage, "Resolve a feature loaded after the shop")
	exit_door.use()
	assert_ne(
		player.net_position,
		(garage.get_node("Arrival") as Marker3D).global_position,
		"Return is rejected outside the door's interaction range"
	)
	player.net_position = exit_door.global_position - Vector3(0, 0, 1)
	player.global_position = player.net_position
	await preload("res://tests/fixtures/real_time.gd").wait(get_tree(), 0.55)
	exit_door.use()
	assert_true(garage.arrival_held(), "Return preloads the operations garage")
	assert_eq(player.net_position, (garage.get_node("Arrival") as Marker3D).global_position)
	var goal := (room.get_node("Destination") as GpsDestination).global_position
	var hop := GpsRoute.next_hop(gps.regions(), gps.links(), Vector3(0, 0, 16), goal)
	assert_eq(hop["position"], (starter.get_node("CasinoReturn") as Node3D).global_position)
	hop = GpsRoute.next_hop(gps.regions(), gps.links(), player.net_position, goal)
	assert_eq(hop["position"], van.to_global(van.entity.interaction_offset))
	assert_true(str(hop["door"]).contains("Gun Shop"))
	for path: String in ["GunWall/Pistol", "RustyHogg", "HatStand/TopHat"]:
		assert_true(room.contains((shop.get_node(path) as Node3D).global_position))
	var machine := preload("res://features/gun_machine/feature.tscn").instantiate() as Node3D
	features.add_child(machine)
	var runs := preload("res://features/slum_runs/feature.tscn").instantiate() as Node3D
	features.add_child(runs)
	assert_false(room.contains((machine.get_node("Kiosk") as Node3D).global_position))
	assert_false(room.contains((machine.get_node("TrashCan") as Node3D).global_position))
	assert_true(room.contains((runs.get_node("Fence") as Node3D).global_position))


func test_structure_uses_casino_tiles_and_no_public_street_exit() -> void:
	var interior := preload("res://features/pawn_shop/interior.tscn").instantiate() as Node3D
	add_child_autofree(interior)
	for grid: GridMap in interior.get_node("Structure").find_children("*", "GridMap", false):
		assert_eq(
			grid.mesh_library.resource_path, "res://features/casino_hub/gridmap/casino_tiles.tres"
		)
	assert_not_null(interior.get_node("Street/ParkedVan/Body"))
	assert_not_null(interior.get_node("Street/PublicRoad"))
	assert_true(interior.find_children("*", "GarageDoor", true).is_empty())
	var casino := preload("res://features/casino_hub/casino_gridmap.tscn").instantiate()
	add_child_autofree(casino)
	var walls := casino.get_node("ShopWallsEastWest") as GridMap
	for z: int in [25, 27]:
		assert_eq(walls.get_cell_item(Vector3i(-2, 0, z)), 3, "Old casino shop entrance closed")
