extends Node
## Actual Compatibility renders. Test-only seeded collection, no production cheats.

var _output := "/tmp/prawn-skins"
var _menu: CanvasLayer
var _skins: PrawnSkins


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		_output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_output)
	get_tree().root.size = Vector2i(1280, 720)
	var game := preload("res://main.tscn").instantiate()
	get_tree().root.add_child(game)
	var shop := game.get_node("Features/pawn_shop") as Node3D
	(shop.get_node("Room") as StreamedRoom).load_room(60000)
	for frame: int in 10:
		await get_tree().process_frame
	game.get_node("LoginScreen").set_process(false)
	for overlay: CanvasLayer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		overlay.hide()
	var camera := Camera3D.new()
	game.add_child(camera)
	camera.current = true
	camera.position = shop.to_global(Vector3(-5.5, 1.65, 23.5))
	camera.look_at(shop.to_global(Vector3(-4, .8, 21.1)))
	await _save("crate-in-shop")
	_skins = shop.get_node("PrawnSkins") as PrawnSkins
	_skins.set_process(false)
	_menu = _skins.menu
	_menu.show()
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	if player != null:
		player.net_position = shop.to_global(Vector3(-4, .95, 22.5))
		player.set_physics_process(false)
	var document := PrawnSkinCatalog.empty_document()
	for id: String in PrawnSkinCatalog.SKINS:
		document["skins"][id] = 2
	document["crates"] = {"harbour": 2, "night": 1}
	document["equipped"] = {"pistol": "crown"}
	_skins._collections[_skins._key(1)] = {"revision": 1, "document": document}
	_menu.receive(&"show", _skins._snapshot(1))
	_menu._navigate("contents", "harbour")
	await _save("crate-contents")
	_menu._navigate("skin", "crown")
	await _save("skin-preview")
	_menu._navigate("collection", "")
	await _save("collection")
	var reward := _skins._snapshot(1, "", "crown")
	_menu.receive(&"update", reward)
	await get_tree().create_timer(.7).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_output.path_join("reveal.png"))
	await get_tree().create_timer(2.6).timeout
	get_tree().root.size = Vector2i(390, 844)
	get_tree().root.content_scale_size = Vector2i(390, 844)
	_menu._navigate("contents", "night")
	await _save("phone-contents")
	_menu._navigate("skin", "king")
	await _save("phone-preview")
	_menu.close(false)
	_menu.hide()
	get_tree().root.size = Vector2i(1280, 720)
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	# Render the identical painted geometry outside the menus.
	var view := PrawnSkinAppearance.create_view("crown")
	game.add_child(view)
	view.global_position = shop.to_global(Vector3(-4, 1.2, 23))
	camera.global_position = view.global_position + Vector3(.35, .2, .35)
	camera.look_at(view.global_position + Vector3(0, .05, -.05))
	await _save("painted-pistol")
	game.queue_free()
	for renderer: Node in get_tree().get_nodes_in_group(&"model_icon_renderers"):
		renderer.queue_free()
	PrawnSkinAppearance._materials.clear()
	for frame: int in 3:
		await get_tree().process_frame
	get_tree().quit()


func _save(label: String) -> void:
	for frame: int in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_output.path_join(label + ".png"))
