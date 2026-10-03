extends Node3D
## Native renderer review scene; see the feature README for its command.


func _ready() -> void:
	var race := $Race as HorseBetting
	race.set_process(false)
	race.state = {
		"phase": "racing",
		"round": 1,
		"winner": -1,
		"results": {},
		"bets": {2: {"name": "Guest", "horse": 0, "stake": 500}}
	}
	race.progress = [0.65, 0.5, 0.58, 0.42]
	$Camera.look_at(race.to_global(Vector3(0, 2.8, 0)))
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/horse-display.png")
	var menu := HorseBettingMenu.new()
	menu.race = race
	add_child(menu)
	get_window().size = Vector2i(390, 720)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/horse-phone.png")
	menu.close()
	get_tree().quit()
