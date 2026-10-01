extends GutTest

const FEATURE := preload("res://features/gps/feature.tscn")
const ROOM_SCENES: Array[String] = [
	"res://features/hotel_props/feature.tscn",
	"res://features/street_district/feature.tscn",
	"res://features/room_doors/feature.tscn",
	"res://features/hotel_annex/feature.tscn",
	"res://features/apartments/feature.tscn",
	"res://features/dev_room/feature.tscn",
]

var _gps: Gps


func before_each() -> void:
	_gps = FEATURE.instantiate()
	add_child_autofree(_gps)


func after_each() -> void:
	Controls.start()


func test_p_opens_the_phone_as_a_modal() -> void:
	assert_true(InputMap.has_action(Gps.ACTION))
	var key := InputMap.action_get_events(Gps.ACTION)[0] as InputEventKey
	assert_eq(key.physical_keycode, KEY_P)
	var phone: GpsPhone = _gps.get_node("Phone")
	_gps.esc_menu_open()
	assert_true(phone.is_open())
	assert_true(phone.is_in_group(&"modal_ui"))
	assert_eq(phone.shown().size(), _gps.destinations().size())
	phone.close()
	assert_false(phone.is_open())
	assert_false(phone.is_in_group(&"modal_ui"))


func test_destinations_are_sorted_and_unique() -> void:
	var labels: Array[String] = []
	for destination: GpsDestination in _gps.destinations():
		assert_false(labels.has(destination.label), destination.label)
		labels.append(destination.label)
	assert_gte(labels.size(), 10)
	var sorted := labels.duplicate()
	sorted.sort()
	assert_eq(labels, sorted)


func test_search_filters_by_name_and_hint() -> void:
	var phone: GpsPhone = _gps.get_node("Phone")
	_gps.esc_menu_open()
	phone._filter("cellar")
	assert_eq(phone.shown().size(), 1)
	assert_eq(phone.shown()[0].label, "Wine Cellar")
	phone._filter("FROGS")
	assert_eq(phone.shown()[0].label, "Petting Parlor")
	phone._filter("zzz")
	assert_eq(phone.shown().size(), 0)
	phone.choose(0)
	assert_null(_gps.target(), "Choosing from an empty list does nothing")


func test_choosing_a_place_starts_a_route_and_closes_the_phone() -> void:
	var phone: GpsPhone = _gps.get_node("Phone")
	_gps.esc_menu_open()
	phone._filter("kaaba")
	phone.choose(0)
	assert_eq(_gps.target().label, "Kaaba")
	assert_false(phone.is_open())
	_gps.clear_route()
	assert_null(_gps.target())


func test_every_streamed_room_has_a_gps_destination() -> void:
	# Future rooms must add a GpsDestination to features/gps/feature.tscn (see README).
	for path: String in ROOM_SCENES:
		add_child_autofree(load(path).instantiate())
	var rooms := get_tree().get_nodes_in_group(&"streamed_rooms")
	assert_gte(rooms.size(), 5)
	for room: StreamedRoom in rooms:
		var covered := false
		for destination: GpsDestination in _gps.destinations():
			covered = covered or room.global_bounds().has_point(destination.global_position)
		assert_true(covered, "%s needs a GpsDestination" % room.get_path())


func test_real_doors_route_from_the_casino_to_the_wine_cellar() -> void:
	for path: String in ROOM_SCENES:
		add_child_autofree(load(path).instantiate())
	var cellar := _find("Wine Cellar")
	var hop := GpsRoute.next_hop(
		_gps.regions(), _gps.links(), Vector3(0, -1.5, 0), cellar.global_position
	)
	assert_eq(hop["door"], "Enter the dev room")
	hop = GpsRoute.next_hop(
		_gps.regions(), _gps.links(), _find("Dev Room").global_position, cellar.global_position
	)
	assert_eq(hop["door"], "Enter the lounge")
	assert_null(_find("Parking Garage"), "The old garage mock-up has no door any more")


func test_heading_is_clockwise_from_facing() -> void:
	assert_almost_eq(Gps.relative_heading(0.0, Vector2(0, -1)), 0.0, 0.001)
	assert_almost_eq(Gps.relative_heading(0.0, Vector2(1, 0)), PI / 2.0, 0.001, "East is right")
	# Facing west (yaw +90 degrees turns forward from -Z to -X), north is to the right.
	assert_almost_eq(Gps.relative_heading(PI / 2.0, Vector2(0, -1)), PI / 2.0, 0.001)


func test_route_draws_on_the_radar() -> void:
	var radar := preload("res://features/radar/radar.gd").new()
	radar.size = Vector2(228, 228)
	add_child_autofree(radar)
	assert_true(radar.is_in_group(&"radar"))
	assert_eq(radar.walls().size(), 0)
	_gps.start_route(_find("Kaaba"))
	_gps._path = PackedVector2Array([Vector2.ZERO, Vector2(0, -10)])
	assert_true(_gps.is_in_group(&"radar_overlays"))
	radar.visible = true
	radar.queue_redraw()
	await wait_process_frames(2)
	pass_test("Drawing the overlay doesn't error")


func _find(label: String) -> GpsDestination:
	for destination: GpsDestination in _gps.destinations():
		if destination.label == label:
			return destination
	return null


func test_guidance_follows_the_local_player_and_arrives() -> void:
	var player: Player = preload("res://core/player/player.tscn").instantiate()
	player.name = "1"
	add_child_autofree(player)
	player.add_to_group(&"local_player")
	var kaaba := _find("Kaaba")
	player.global_position = kaaba.global_position + Vector3(0, 0, 20)
	_gps.start_route(kaaba)
	_gps._process(0.5)
	assert_eq(_gps.route()[0], Vector2(-24, -0.5))
	assert_eq(_gps._text, "Continue to Kaaba, 20 m")
	player.global_position = kaaba.global_position + Vector3(1, 0.1, 0)
	_gps._process(0.5)
	assert_eq(_gps._text, "Arrived at Kaaba")
	_gps._process(Gps.ARRIVED_HOLD_SEC + 0.1)
	assert_null(_gps.target(), "The route ends a moment after arriving")
