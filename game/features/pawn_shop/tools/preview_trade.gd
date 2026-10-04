extends Node


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var output := ProjectSettings.globalize_path("res://../docs/design/previews/trading")
	DirAccess.make_dir_recursive_absolute(output)
	get_window().size = Vector2i(1280, 800)
	var game := preload("res://main.tscn").instantiate()
	get_tree().root.add_child(game)
	var shop := game.get_node("Features/pawn_shop") as Node3D
	(shop.get_node("Room") as StreamedRoom).load_room(60000)
	for frame: int in 20:
		await get_tree().process_frame
	game.get_node("LoginScreen").set_process(false)
	for overlay: CanvasLayer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		overlay.hide()
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	player.set_physics_process(false)
	var fence := get_tree().get_first_node_in_group(&"pawn_counter") as LootFence
	player.global_position = fence.global_position + Vector3(1, .4, 0)
	player.net_position = player.global_position
	var hand := Hand.for_peer(get_tree(), 1)
	hand.net_item_id = "pistol"
	hand.inventory().backpack = PackedStringArray(
		["scrap", "electronics", "watch", "jewelry", "stolen_wallet", "ammo:pistol:20", "", ""]
	)
	var money := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	money.balances[1] = 2000000
	var menu := fence.get_node("TradeMenu") as CanvasLayer
	menu.show()
	menu.call("open_menu")
	if "--empty-sell" in OS.get_cmdline_user_args():
		hand.inventory().backpack = PackedStringArray(["", "", "", "", "", "", "", ""])
		for frame: int in 15:
			await get_tree().process_frame
		await _save(output, "nothing-to-sell")
		hand.net_item_id = ""
		for frame: int in 5:
			await get_tree().process_frame
		await _save(output, "empty-inventory")
		game.queue_free()
		for renderer: Node in get_tree().get_nodes_in_group(&"model_icon_renderers"):
			renderer.queue_free()
		for frame: int in 3:
			await get_tree().process_frame
		get_tree().quit()
		return
	for frame: int in 80:
		await get_tree().process_frame
	await _save(output, "guns")
	menu.set("_ammo", true)
	for frame: int in 5:
		await get_tree().process_frame
	await _save(output, "ammo")
	menu.call("_request", &"sell", {"slot": 0, "id": "scrap"})
	for frame: int in 5:
		await get_tree().process_frame
	assert(hand.inventory().item_at(0).is_empty())
	assert(int(money.balances[1]) > 2000000)
	print("PAWN SALE: ", menu.get("_status").text)
	menu.call("_request", &"buy", {"id": "ammo:m4a4:60"})
	await get_tree().create_timer(.6).timeout
	print("PAWN BUY: ", menu.get("_status").text, " rounds=", hand.inventory().ammo_for("m4a4"))
	assert(hand.inventory().ammo_for("m4a4") == 60)
	await _save(output, "receipt")
	menu.call("close_menu")
	(game.get_node("Features/gun_machine/StatsPanel") as CanvasLayer).show()
	player.global_position = shop.to_global(Vector3(-9, .95, 31.5))
	player.net_position = player.global_position
	player.yaw = PI
	player.net_yaw = PI
	(player.get_node("FirstPersonView") as CanvasLayer).show()
	for id: String in ["smg", "m4a4", "ak47"]:
		hand.net_item_id = id
		hand.inventory().backpack = PackedStringArray(
			[ItemCatalog.ammo_id(id, 40 if id == "smg" else 60), "", "", "", "", "", "", ""]
		)
		for frame: int in 15:
			await get_tree().process_frame
		await _save(output, id + "-first-person")
		hand._fire_cooldown = 0
		hand.request_primary_action()
		hand.magazine_for(id).entity.request_action(&"reload")
		await get_tree().create_timer(.8).timeout
		await _save(output, id + "-reload")
		await get_tree().create_timer(1.5).timeout
		print(
			id, " loaded=", hand.magazine_for(id).loaded(), " total=", hand.inventory().ammo_for(id)
		)
	game.queue_free()
	for renderer: Node in get_tree().get_nodes_in_group(&"model_icon_renderers"):
		renderer.queue_free()
	for frame: int in 3:
		await get_tree().process_frame
	get_tree().quit()


func _save(output: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(label + ".png"))
