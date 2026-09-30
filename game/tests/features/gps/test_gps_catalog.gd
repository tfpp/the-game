extends GutTest
const PLAYER := preload("res://core/player/player.tscn")
const FROG := preload("res://features/frogs/frog.tscn")

var _gps: Gps
var _phone: GpsPhone


func before_each() -> void:
	_gps = preload("res://features/gps/feature.tscn").instantiate()
	add_child_autofree(_gps)
	_gps.set_process(false)
	_phone = _gps.get_node("Phone")


func after_each() -> void:
	Controls.start()


func test_existing_entities_are_categorized_without_duplicates() -> void:
	var frog: Frog = FROG.instantiate()
	frog.name = "Frog1"
	add_child_autofree(frog)
	frog.set_physics_process(false)
	frog.add_to_group(&"interactables")
	var slot: Node = preload("res://features/slot_machine/machine.tscn").instantiate()
	add_child_autofree(slot)
	var player: Player = PLAYER.instantiate()
	player.name = "42"
	player.display_name = "Guest Ada"
	player.set_multiplayer_authority(42)
	add_child_autofree(player)
	var destinations := _gps.destinations()
	var frogs := 0
	for destination: GpsDestination in destinations:
		if destination.source == frog:
			frogs += 1
			assert_eq(destination.category, "Animals")
		if destination.source == slot:
			assert_eq(destination.category, "Objects")
			assert_true(destination.label.begins_with("Slot machine"))
		if destination.source == player:
			assert_eq(destination.category, "People")
			assert_eq(destination.label, "Guest Ada")
	assert_eq(frogs, 1, "Multiple discovery groups still produce one destination")
	assert_eq(destinations.size(), 17)
	player.add_to_group(&"local_player")
	assert_eq(_gps.destinations().size(), 16, "Never list yourself")


func test_target_tracks_world_position_and_clears_on_death_and_despawn() -> void:
	var frog: Frog = FROG.instantiate()
	add_child_autofree(frog)
	frog.set_physics_process(false)
	var destination: GpsDestination
	for entry: GpsDestination in _gps.destinations():
		if entry.source == frog:
			destination = entry
	assert_not_null(destination)
	frog.position = Vector3(12, 2, 3)
	assert_eq(destination.destination_position(), frog.global_position)
	_gps.start_route(destination)
	frog.net_alive = false
	_gps._process(0.5)
	assert_null(_gps.target())
	assert_false(_gps.destinations().has(destination))
	frog.net_alive = true
	assert_true(_gps.destinations().has(destination), "Respawn restores the same adapter")
	_gps.start_route(destination)
	remove_child(frog)
	_gps._process(0.5)
	assert_null(_gps.target(), "Disconnected or unloaded target clears guidance")


func test_sections_search_and_header_selection() -> void:
	var person := _marker("Ada", "People")
	var animal := _marker("Frog", "Animals")
	var object := _marker("Ferry", "Objects")
	_phone.open([object, person, animal], null)
	assert_eq(_phone._list.get_item_text(0), "People")
	assert_eq(_phone._list.get_item_text(2), "Animals")
	assert_eq(_phone._list.get_item_text(4), "Objects")
	_phone._choose_row(0)
	assert_null(_gps.target())
	assert_true(_phone.is_open())
	_phone._choose_row(3)
	assert_eq(_gps.target(), animal, "Row mapping accounts for every header")
	_phone.open([object, person, animal], null)
	_phone._filter("PEOPLE")
	assert_eq(_phone.shown(), [person])
	_phone._submit("")
	assert_eq(_gps.target(), person)


func test_stale_row_cannot_start_route() -> void:
	var source := Node3D.new()
	add_child(source)
	var marker := _marker("Temporary object", "Objects")
	marker.tracks_source = true
	marker.source = source
	_phone.open([marker], null)
	source.free()
	_phone.choose(0)
	assert_null(_gps.target())
	assert_true(_phone.shown().is_empty())


func test_wheel_scrolls_without_selecting_or_closing() -> void:
	var entries: Array[GpsDestination] = []
	for i: int in 60:
		entries.append(_marker("Object %d" % i, "Objects"))
	_phone.open(entries, null)
	await wait_process_frames(3)
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	_phone._input(wheel)
	assert_gt(_phone._list.get_v_scroll_bar().value, 0.0)
	assert_null(_gps.target())
	assert_true(_phone.is_open())
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	_phone._input(wheel)
	assert_eq(_phone._list.get_v_scroll_bar().value, 0.0)
	_phone.close()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	_phone._input(wheel)
	assert_eq(_phone._list.get_v_scroll_bar().value, 0.0)


func _marker(label: String, category: String) -> GpsDestination:
	var marker := GpsDestination.new()
	marker.label = label
	marker.category = category
	add_child_autofree(marker)
	return marker


func test_moving_target_replans_and_resumes_after_arrival() -> void:
	var player: Player = PLAYER.instantiate()
	player.name = "1"
	add_child_autofree(player)
	player.set_physics_process(false)
	var source := Node3D.new()
	add_child_autofree(source)
	source.position = Vector3(10, 0, 0)
	var marker := _marker("Moving object", "Objects")
	marker.source = source
	marker.tracks_source = true
	_gps.start_route(marker)
	_gps._process(0.5)
	assert_eq(_gps.route()[-1], Vector2(10, 0))
	source.position.x = 20
	_gps._process(0.5)
	assert_eq(_gps.route()[-1], Vector2(20, 0))
	source.position = player.position
	_gps._process(0.5)
	assert_gt(_gps._arrived_left, 0.0)
	source.position.x = 30
	_gps._process(0.5)
	assert_eq(_gps._arrived_left, 0.0)
	assert_eq(_gps.route()[-1], Vector2(30, 0))
	assert_eq(_gps.target(), marker)


func test_reopening_after_target_freed_and_new_spawn() -> void:
	var source := Node3D.new()
	source.name = "OldObject"
	add_child(source)
	source.add_to_group(&"interactables")
	_gps.esc_menu_open()
	_phone._filter("OldObject")
	# Generic names are humanized by the catalog.
	_phone._filter("Old Object")
	_phone.choose(0)
	assert_not_null(_gps.target())
	source.free()
	var replacement := Node3D.new()
	replacement.name = "NewObject"
	add_child_autofree(replacement)
	replacement.add_to_group(&"interactables")
	_gps.esc_menu_open()
	assert_null(_gps.target())
	_phone._filter("New Object")
	assert_eq(_phone.shown().size(), 1, "A late spawn appears on the next open")


func test_named_npcs_and_other_animals() -> void:
	var patron := CasinoPatron.new()
	autofree(patron)
	patron.look = PatronModel.MITCH_LOOK
	assert_eq(GpsCatalog.label_for(patron), "Mitch McConnell and intern")
	assert_eq(GpsCatalog.category_for(patron), "People")
	patron.look = PatronModel.MAMDANI_LOOK
	assert_eq(GpsCatalog.label_for(patron), "Zohran Mamdani")
	patron.look = PatronModel.TRUMP_LOOK
	assert_eq(GpsCatalog.label_for(patron), "Donald Trump")
	var penguin := Penguin.new()
	autofree(penguin)
	assert_eq(GpsCatalog.category_for(penguin), "Animals")
	var bird := Bird.new()
	autofree(bird)
	assert_eq(GpsCatalog.category_for(bird), "Animals")


func test_collected_pickup_and_coin_are_unavailable() -> void:
	var coin: CoinPickup = preload("res://features/coins/pickup.tscn").instantiate()
	add_child_autofree(coin)
	var marker := _marker("Coin", "Objects")
	marker.tracks_source = true
	marker.source = coin
	assert_true(marker.available())
	coin.available = false
	assert_false(marker.available())
	var pickup: ItemPickup = preload("res://features/holdables/item_pickup.tscn").instantiate()
	add_child_autofree(pickup)
	marker.source = pickup
	assert_true(marker.available())
	pickup.net_taken = true
	assert_false(marker.available())
