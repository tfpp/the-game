extends "res://tests/features/food_court/wendys_probe.gd"
## Real-level offline purchases, menus and ordinary held food in both camera modes.


func _run() -> void:
	$Game/Features/character_memory.queue_free()
	await get_tree().create_timer(0.5).timeout
	_player = get_tree().get_first_node_in_group(&"local_player") as Player
	_player.set_physics_process(false)
	Controls.select_device(Controls.Device.GAMEPAD)
	Controls.start()
	for layer: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = layer is FirstPersonView
	var room := $Game/Features/strip_mall/Room as StreamedRoom
	room.load_room(60000)
	var hand := Hand.for_peer(get_tree(), 1)
	for path: String in ["CityWokShop", "CitySushiShop"]:
		var stand := room.get_node(path) as PokeStand
		$Game/Features/third_person.enabled = false
		_view(stand.to_global(Vector3(0, 1.65, 1.7)), stand.to_global(Vector3(0, 1.6, 0)))
		var menu: CanvasLayer = stand.get_node("Menu")
		menu.show()
		stand.use()
		assert(menu.is_in_group(&"modal_ui"))
		await _capture("/tmp/" + path + "-menu.png")
		menu._buttons[0].pressed.emit()
		assert(hand.net_item_id == "poke_bowl")
		menu._close()
		menu.hide()
		await _capture("/tmp/" + path + "-first-person.png")
		$Game/Features/third_person.enabled = true
		await _capture("/tmp/" + path + "-third-person.png")
		hand.request_primary_action()
		assert(hand.net_item_id.is_empty())
	print("CITY_FOOD_PROBE PASS: both purchases, menus and held first/third-person views")
	get_tree().quit()
