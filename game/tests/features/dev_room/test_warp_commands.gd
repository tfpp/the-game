extends GutTest

const FEATURE := preload("res://features/dev_room/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const Chat := preload("res://features/chat_box/chat_box.gd")
const Cheats := preload("res://tests/features/dev_access/cheats_fixture.gd")
var _room: Node3D
var _player: Player


func before_each() -> void:
	_room = FEATURE.instantiate() as Node3D
	_room.name = "dev_room"
	add_child_autofree(_room)
	_player = PLAYER.instantiate() as Player
	_player.set_multiplayer_authority(1)
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.net_position = Vector3(0, 1.2, 0)


func test_warp_parser_preserves_only_warp_arguments() -> void:
	assert_true(Chat.is_command("!WARP dev"))
	assert_true(Chat.is_command("!warp"))
	assert_false(Chat.is_command("!warping"))
	assert_eq(Chat.parse_command("!WARP   DEV"), "warp dev")
	assert_eq(Chat.parse_command("/warp lounge"), "warp lounge")
	assert_eq(Chat.parse_command("/suicide please"), "suicide")
	assert_eq(Chat.parse_command("!guns"), "guns")


func test_invalid_commands_missing_player_and_cooldown_do_not_move() -> void:
	var start := _player.net_position
	for command: String in ["warp", "warp unknown", "warp dev extra", "warp ../../Room"]:
		_room.handle_chat_command(1, command)
		assert_eq(_player.net_position, start)
	_room.handle_chat_command(999, "warp dev")
	assert_eq(_player.net_position, start)
	_room.handle_chat_command(1, "warp dev")
	var arrival := _player.net_position
	assert_ne(arrival, start)
	_room.handle_chat_command(1, "warp casino")
	assert_eq(_player.net_position, arrival)
	_room._reset(Network.Mode.OFFLINE)
	_room.handle_chat_command(1, "warp casino")
	assert_eq(_player.net_position, (_room.get_node("CasinoArrival") as Marker3D).global_position)


func test_named_rooms_reuse_arrivals_and_preload_streamed_floor() -> void:
	var scenes := {
		"room_doors": preload("res://features/room_doors/feature.tscn"),
		"hotel_annex": preload("res://features/hotel_annex/feature.tscn"),
		"apartments": preload("res://features/apartments/feature.tscn"),
		"hotel_props": preload("res://features/hotel_props/feature.tscn"),
		"procedural_rooms": preload("res://features/procedural_rooms/feature.tscn"),
		"street_district": preload("res://features/street_district/feature.tscn"),
	}
	for name: String in scenes:
		var feature := (scenes[name] as PackedScene).instantiate()
		feature.name = name
		add_child_autofree(feature)
	for place: String in ["props", "garage", "street"]:
		_room.handle_chat_command(1, "warp " + place)
		assert_eq(_player.net_position, Vector3(0, 1.2, 0), "Cheat gate retained")
	Cheats.enable(self)
	for place: String in _room.ARRIVALS:
		_room._reset(Network.Mode.OFFLINE)
		_room.handle_chat_command(1, "warp " + place)
		var arrival := get_node(NodePath(_room.ARRIVALS[place])) as Marker3D
		assert_eq(_player.net_position, arrival.global_position, place)
		if arrival.get_parent() is StreamedRoom:
			var room := arrival.get_parent() as StreamedRoom
			assert_true(room.is_loaded(), "Floor preloaded before owner teleport")
			assert_true(room.arrival_held())
