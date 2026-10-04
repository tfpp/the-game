extends Node
## Review the shipped stretch settings and actual gameplay overlays at phone sizes.


func _ready() -> void:
	capture.call_deferred()


func capture() -> void:
	var game := (load("res://main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(game)
	for frame: int in 12:
		await get_tree().process_frame
	var login := game.get_node("LoginScreen") as CanvasLayer
	login.hide()
	login.set_process(false)
	login.remove_from_group(&"modal_ui")
	Controls.touch_available = true
	Controls.device = Controls.Device.TOUCH
	Controls.start()
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	player.set_physics_process(false)
	var hand := Hand.for_peer(get_tree(), 1)
	var inventory := hand.inventory()
	var output := ProjectSettings.globalize_path(
		"res://../docs/design/previews/phase-one-phone-hud"
	)
	DirAccess.make_dir_recursive_absolute(output)
	for size: Vector2i in [Vector2i(360, 780), Vector2i(780, 360)]:
		get_tree().root.size = size
		for occupied: bool in [false, true]:
			inventory.backpack = PackedStringArray(["", "", "", "", "", "", "", ""])
			hand.net_item_id = "pistol" if occupied else ""
			if occupied:
				inventory.backpack[0] = "smg"
				inventory.backpack[1] = "m4a4"
				inventory.backpack[2] = "ammo:pistol:20"
				inventory.backpack[3] = "watch"
				inventory.backpack[4] = "jewelry"
				inventory.backpack[5] = "electronics"
				inventory.backpack[6] = "stolen_wallet"
				inventory.backpack[7] = "scrap"
			for frame: int in 20:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_tree().root.get_texture().get_image().save_png(
				output.path_join(
					"%dx%d-%s.png" % [size.x, size.y, "occupied" if occupied else "empty"]
				)
			)
	get_tree().quit()
