extends GutTest
## The dev room (features/dev_room) and the warp doors moved into it from the casino.

const FEATURE := preload("res://features/dev_room/feature.tscn")
const PlayerScene := preload("res://core/player/player.tscn")
const WARP_SCENES: Array[String] = [
	"res://features/hotel_props/feature.tscn",
	"res://features/apartments/feature.tscn",
	"res://features/room_doors/feature.tscn",
	"res://features/hotel_annex/feature.tscn",
	"res://features/procedural_rooms/feature.tscn",
	"res://features/shooting_gallery/feature.tscn",
]
## Walkable interior of the room, in world space.
const INTERIOR := AABB(Vector3(286, 0, -308), Vector3(28, 4, 16.4))

var _room: Node3D


func before_each() -> void:
	_room = FEATURE.instantiate() as Node3D
	add_child_autofree(_room)


func _player_at(global_pos: Vector3) -> Player:
	var player := PlayerScene.instantiate() as Player
	player.set_multiplayer_authority(1)
	player.position = global_pos
	player.net_position = global_pos
	add_child_autofree(player)
	return player


func test_casino_booth_replaces_the_old_staff_door() -> void:
	assert_eq(_room.get_node("CasinoBooth").position, Vector3(12, 0, -18.4))
	var door := _room.get_node("CasinoBooth/Door") as GarageDoor
	assert_eq(door.door_label, "Enter the dev room")


func test_casino_development_doors_and_return_landings_clear_shops_and_walls() -> void:
	var casino := load("res://features/casino_hub/gridmap/playable.tscn") as PackedScene
	add_child_autofree(casino.instantiate())
	var street_scene := load("res://features/street_district/feature.tscn") as PackedScene
	var street := add_child_autofree(street_scene.instantiate()) as Node3D
	await wait_physics_frames(3)
	var space := _room.get_world_3d().direct_space_state
	var hull := CapsuleShape3D.new()
	hull.radius = 0.4064
	hull.height = 1.8288
	for pair: Array in [
		[_room.get_node("CasinoBooth/Door"), _room.get_node("CasinoBooth/Arrival")],
		[street.get_node("CasinoStreetEntrance"), street.get_node("MainCasinoArrival")]
	]:
		var door := pair[0] as Node3D
		var arrival := pair[1] as Marker3D
		assert_lt(door.global_position.z, -12.0, "Door is on north promenade, clear of shops")
		assert_gt(arrival.global_basis.z.dot(Vector3.FORWARD), 0.99, "Return faces into casino")
		var point := arrival.global_position
		var ray := PhysicsRayQueryParameters3D.create(point, point - Vector3(0, 3, 0), 1)
		var hit := space.intersect_ray(ray)
		assert_false(hit.is_empty(), "Landing has a floor")
		if not hit.is_empty():
			assert_almost_eq((hit["position"] as Vector3).y, 0.0, 0.01)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = hull
		query.collision_mask = 1
		query.transform.origin = point
		assert_true(space.intersect_shape(query).is_empty(), "Return hull clears walls")
		query.transform.origin = (
			door.global_position + (point - door.global_position).normalized() * 0.8
		)
		assert_true(space.intersect_shape(query).is_empty(), "Door can be approached")


func test_booth_and_return_door_round_trip() -> void:
	var door := _room.get_node("CasinoBooth/Door") as GarageDoor
	var back := _room.get_node("Room/ReturnDoor") as GarageDoor
	var player := _player_at(door.global_position)
	door.request_enter()
	var arrival := (_room.get_node("Room/Arrival") as Marker3D).global_position
	assert_true(player.net_position.is_equal_approx(arrival))
	assert_true(INTERIOR.has_point(arrival))
	player.net_position = back.global_position
	back.request_enter()
	var casino := (_room.get_node("CasinoBooth/Arrival") as Marker3D).global_position
	assert_true(player.net_position.is_equal_approx(casino))


func test_distant_player_cannot_use_the_booth() -> void:
	var door := _room.get_node("CasinoBooth/Door") as GarageDoor
	var player := _player_at(door.global_position + Vector3(20, 0, 0))
	var start := player.net_position
	door.request_enter()
	assert_true(player.net_position.is_equal_approx(start))


func test_every_warp_door_and_its_return_marker_is_in_the_room() -> void:
	var doors := {
		"hotel_props": ["Entrance", "CasinoArrival"],
		"apartments": ["Entrance", "CasinoArrival"],
		"room_doors": ["Lobby/Door", "Lobby/LobbyArrival"],
		"hotel_annex": ["Entrance", "CasinoArrival"],
		"procedural_rooms": ["Entrance", "CasinoArrival"],
		"shooting_gallery": ["Entrance", ""],
	}
	for path: String in WARP_SCENES:
		var feature := load(path).instantiate() as Node3D
		add_child_autofree(feature)
		var nodes: Array = doors[path.get_base_dir().get_file()]
		var door := feature.get_node(nodes[0]) as Node3D
		assert_true(INTERIOR.has_point(door.global_position), "%s door" % path)
		if nodes[1] != "":
			var marker := feature.get_node(nodes[1]) as Node3D
			assert_true(INTERIOR.has_point(marker.global_position), "%s return" % path)
	var gallery_exit := load("res://features/shooting_gallery/feature.tscn").instantiate() as Node3D
	add_child_autofree(gallery_exit)
	assert_true(INTERIOR.has_point(gallery_exit.get_node("Arena/Exit").destination))


func test_warp_doors_are_spread_along_the_walls() -> void:
	var spots: Array[Vector3] = [
		(_room.get_node("Room/ReturnDoor") as Node3D).global_position,
	]
	for path: String in WARP_SCENES:
		var feature := load(path).instantiate() as Node3D
		add_child_autofree(feature)
		var node_name := "Lobby" if path.contains("room_doors") else "Entrance"
		spots.append((feature.get_node(node_name) as Node3D).global_position)
	for i in spots.size():
		for j in range(i + 1, spots.size()):
			var a := Vector2(spots[i].x, spots[i].z)
			var b := Vector2(spots[j].x, spots[j].z)
			assert_gt(a.distance_to(b), 4.0, "%s vs %s" % [spots[i], spots[j]])


func test_gun_o_matic_and_can_have_floor_clear_approaches_and_work_in_range() -> void:
	var machine := preload("res://features/gun_machine/feature.tscn").instantiate() as GunMachine
	add_child_autofree(machine)
	var kiosk := machine.get_node("Kiosk") as GunMachineKiosk
	var can := machine.get_node("TrashCan") as GunMachineTrashCan
	assert_eq(kiosk.global_position, Vector3(313, 0, -300))
	assert_eq(can.global_position, Vector3(313, 0, -298.2))
	var player := _player_at(Vector3(311.5, 0.95, -300))
	player.set_physics_process(false)
	var rig := preload("res://features/gun_machine/gun_rig.tscn").instantiate() as GunRig
	rig.peer_id = 1
	add_child_autofree(rig)
	rig.set_process(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 460
	rig.equip(GunGenerator.generate(rng))
	await wait_physics_frames(3)
	var space := _room.get_world_3d().direct_space_state
	var hull := CapsuleShape3D.new()
	hull.radius = 0.4064
	hull.height = 1.8288
	for prop: Node3D in [kiosk, can]:
		assert_true(INTERIOR.has_point(prop.global_position))
		var spot := prop.global_position + Vector3(-1.5, 0.95, 0)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = hull
		query.collision_mask = 1
		query.exclude = [player.get_rid()]
		query.transform.origin = spot
		assert_true(space.intersect_shape(query).is_empty(), "Approach clears walls/props")
		query.transform.origin = Vector3(300, 0.95, -294)
		query.motion = spot - query.transform.origin
		assert_almost_eq(space.cast_motion(query)[0], 1.0, 0.001, "Arrival route is clear")
		var ray := PhysicsRayQueryParameters3D.create(spot, spot - Vector3(0, 3, 0), 1)
		var hit := space.intersect_ray(ray)
		assert_false(hit.is_empty(), "Approach has a floor")
		if not hit.is_empty():
			assert_almost_eq((hit["position"] as Vector3).y, 0.0, 0.001)
		player.net_position = spot
		assert_true(prop.can_use(player))
	player.net_position = Vector3(-6.5, 0.95, -3971.6)
	assert_false(kiosk.can_use(player), "Old shop position cannot buy from kiosk")
	assert_false(can.can_use(player), "Old shop position cannot discard")
	var sign := kiosk.get_node("Sign") as Label3D
	assert_false(sign.fixed_size)
	assert_lt(sign.font_size * sign.pixel_size, 0.25)


func test_dev_room_has_a_gps_area() -> void:
	var destination := _room.get_node("Destination") as GpsDestination
	assert_eq(destination.label, "Dev Room")
	assert_true(destination.area.encloses(INTERIOR))
	assert_true(destination.area.has_point(destination.global_position))
