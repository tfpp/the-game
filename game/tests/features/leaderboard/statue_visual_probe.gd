extends Node
## Opt-in native rendered review: xvfb-run godot --path game <this scene>.
## Saves actual live-room views to /tmp/statue-*.png; not a headless GUT test.


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(0.5).timeout
	var statue := $Game/Features/leaderboard/OnlineStatue as OnlineStatue
	statue.set_process(false)
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	Controls.select_device(Controls.Device.GAMEPAD)
	Controls.start()
	player.set_physics_process(false)
	player.visible = false
	($Game/Features/third_person as Node).set_process(false)
	for layer: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	var portrait := OnlineStatue.portrait_for(get_tree(), 1)
	for body: String in ["default", "girl", "penguin"]:
		portrait["body"] = body
		statue.champion = {"name": "CrownGuest", "seconds": 98765, "portrait": portrait}
		camera.position = Vector3(0, 1.65, -16)
		camera.look_at(statue.global_position + Vector3.UP * 1.3)
		await _capture("/tmp/statue-%s-spawn.png" % body)
		camera.position = Vector3(8.5, 2.0, -17.5)
		camera.look_at(statue.global_position + Vector3.UP * 1.3)
		await _capture("/tmp/statue-%s-rear.png" % body)
	portrait["head"] = "frog"
	portrait["tail"] = "fin"
	portrait["body"] = "girl"
	statue.champion = {"name": "CrownGuest", "seconds": 98765, "portrait": portrait}
	camera.position = Vector3(1.5, 1.8, -13.8)
	camera.look_at(statue.global_position + Vector3.UP * 1.4)
	await _capture("/tmp/statue-creature.png")
	print("STATUE_VISUAL_PROBE PASS")
	get_tree().quit()


func _capture(path: String) -> void:
	for i: int in 4:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
