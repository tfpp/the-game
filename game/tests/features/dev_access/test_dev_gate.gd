extends GutTest
## Development entrances stay hidden and unusable until sv_cheats 1 (features/dev_access).

const Cheats := preload("res://tests/features/dev_access/cheats_fixture.gd")
const PLAYER := preload("res://core/player/player.tscn")
const STREET := preload("res://features/street_district/feature.tscn")
const PROPS := preload("res://features/hotel_props/feature.tscn")
const GARAGE := preload("res://features/procedural_rooms/feature.tscn")
const GPS := preload("res://features/gps/feature.tscn")
const HIDDEN_PLACES: Array[String] = [
	"Garage Teleporter",
	"Hotel Prop Room",
	"Hotel Props Teleport",
	"Street Casino Entrance",
	"Street District",
	"Street District Teleporter",
]


func _player_at(pos: Vector3) -> Player:
	var player := PLAYER.instantiate() as Player
	player.set_multiplayer_authority(1)
	player.position = pos
	player.net_position = pos
	add_child_autofree(player)
	player.set_physics_process(false)
	return player


func _labels(gps: Gps) -> Array[String]:
	var result: Array[String] = []
	for destination: GpsDestination in gps.destinations():
		result.append(destination.label)
	return result


func test_cheats_follow_the_noclip_switch() -> void:
	assert_false(DevGate.cheats_enabled(get_tree()), "No noclip feature means locked")
	assert_false(DevGate.cheats_enabled(null))
	var noclip := Cheats.enable(self)
	assert_true(DevGate.cheats_enabled(get_tree()))
	noclip.set(&"cheats_enabled", false)
	assert_false(DevGate.cheats_enabled(get_tree()))


func test_networked_portals_deny_use_until_cheats() -> void:
	for scene: PackedScene in [STREET, PROPS, GARAGE]:
		add_child_autofree(scene.instantiate())
	var doors: Array[GarageDoor] = [
		get_node("StreetDistrict/CasinoStreetEntrance") as GarageDoor,
		get_node("StreetDistrict/Entrance") as GarageDoor,
		get_node("HotelProps/Entrance") as GarageDoor,
		get_node("ProceduralRooms/Entrance") as GarageDoor,
	]
	var player := _player_at(Vector3.ZERO)
	for door: GarageDoor in doors:
		player.net_position = door.global_position
		var entity := door.get_node("NetworkedEntity") as NetworkedInteraction
		assert_false(door.visible, "%s hidden" % door.get_path())
		assert_eq(entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
		assert_false(door.can_use(player))
	Cheats.enable(self)
	for door: GarageDoor in doors:
		player.net_position = door.global_position
		var entity := door.get_node("NetworkedEntity") as NetworkedInteraction
		assert_true(door.visible, "%s shown" % door.get_path())
		assert_eq(entity._evaluate(1, &"use", {}), NetworkedEntity.Result.ACCEPTED)


func test_gps_lists_and_routes_dev_places_only_with_cheats() -> void:
	var gps := GPS.instantiate() as Gps
	add_child_autofree(gps)
	for scene: PackedScene in [STREET, PROPS, GARAGE]:
		add_child_autofree(scene.instantiate())
	var labels := _labels(gps)
	for place: String in HIDDEN_PLACES:
		assert_false(labels.has(place), "%s hidden without cheats" % place)
	assert_true(labels.has("Procedural Garage"), "The physical service lift stays listed")
	for link: Dictionary in gps.links():
		assert_ne(link["label"], "Visit the old casino", "Locked doors are not routed")
	Cheats.enable(self)
	labels = _labels(gps)
	for place: String in HIDDEN_PLACES:
		assert_true(labels.has(place), "%s listed with cheats" % place)
