extends Node3D


func _ready() -> void:
	var room := $Feature/Room as StreamedRoom
	room.set_physics_process(false)
	room.load_room()
	var book := room.get_node("Book") as ChickenBettingBook
	book.set_process(false)
	book._rng.seed = 477
	book._prepare()
	$Camera.look_at(room.to_global(Vector3(0, 0.8, -1)))
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/chicken-preview.png")
	book._set_phase("fighting")
	book._round()
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/chicken-attack.png")
	var next := book.state.duplicate(true)
	next["health"] = [30, 0]
	next["winner"] = 0
	next["phase"] = "result"
	book.state = next
	await get_tree().create_timer(0.9).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/chicken-knockout.png")
	var menu := ChickenBettingMenu.new()
	menu.book = book
	add_child(menu)
	get_window().size = Vector2i(390, 720)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/chicken-phone.png")
	menu.close()
	get_window().size = Vector2i(1280, 720)
	var casino := preload("res://features/casino_hub/casino_gridmap.tscn").instantiate() as Node3D
	add_child(casino)
	$Camera.position = Vector3(-20, 1.6, -16.5)
	$Camera.look_at(Vector3(-20, 1.4, -19.65))
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/chicken-entrance.png")
	get_tree().quit()
