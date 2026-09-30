extends GutTest
## The dev room (features/dev_room) and the warp doors moved into it from the casino.

const FEATURE := preload("res://features/dev_room/feature.tscn")
const PlayerScene := preload("res://core/player/player.tscn")
const WARP_SCENES: Array[String] = [
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
	assert_eq(_room.get_node("CasinoBooth").position, Vector3(12, 0, 31))
	var door := _room.get_node("CasinoBooth/Door") as GarageDoor
	assert_eq(door.door_label, "Enter the dev room")


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
	var gallery_exit := load(WARP_SCENES[4]).instantiate() as Node3D
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


func test_dev_room_has_a_gps_area() -> void:
	var destination := _room.get_node("Destination") as GpsDestination
	assert_eq(destination.label, "Dev Room")
	assert_true(destination.area.encloses(INTERIOR))
	assert_true(destination.area.has_point(destination.global_position))
