extends Node3D
const SCENE := preload("res://features/table_games/feature.tscn")
var _world: Node3D


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	ThemeDB.fallback_font = load("res://assets/fonts/inter/Inter-Regular.ttf")
	_world = SCENE.instantiate() as Node3D
	add_child(_world)
	(_world.get_node("Room") as StreamedRoom).load_room(60000)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("272321")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("b4a092")
	settings.ambient_light_energy = .55
	environment.environment = settings
	_world.add_child(environment)
	var camera := Camera3D.new()
	_world.add_child(camera)
	camera.make_current()
	get_tree().root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute("res://../docs/design/previews/crown-games")
	for x: int in [-12, 0, 12]:
		camera.position = Vector3(x + 2, 2.2, -5995)
		camera.look_at(Vector3(x, 1, -6001))
		for i: int in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_tree().root.get_texture().get_image().save_png(
			"res://../docs/design/previews/crown-games/room-%d.png" % x
		)
	await _dealer_review(camera)
	var wallet := PlayerMoney.new()
	add_child(wallet)
	wallet.set_process(false)
	wallet.balances = {1: 2000}
	var player := preload("res://core/player/player.tscn").instantiate() as Player
	player.display_name = "Crown Guest"
	add_child(player)
	player.set_physics_process(false)
	var table := _world.get_node("Room/VideoPoker") as CrownGameTable
	player.global_position = table.to_global(Vector3(0, .9144, 2))
	player.net_position = player.global_position
	table._join(player)
	table._start()
	table.set_process(false)
	table.open_screen()
	camera.make_current()
	for i: int in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(
		"res://../docs/design/previews/crown-games/draw-poker-controls.png"
	)
	_world.free()
	get_tree().quit()


func _dealer_review(camera: Camera3D) -> void:
	var table := _world.get_node("Room/Poker") as CrownGameTable
	table.set_process(false)
	(table.get_node("Sign") as Label3D).visible = false
	var dealer := table.get_node("Dealer") as CrownDealer
	dealer.set_process(false)
	get_tree().root.size = Vector2i(768, 432)
	camera.global_position = table.to_global(Vector3(1.9, 1.9, 2.8))
	camera.look_at(table.to_global(Vector3(0, 1.0, -.45)))
	DirAccess.make_dir_recursive_absolute("/tmp/crown-dealer-frames")
	var frame := 0
	for motion: String in [
		"idle", "greet", "shuffle", "deal", "reveal", "collect", "payout", "roll"
	]:
		if motion == "roll":
			table = _world.get_node("Room/Craps") as CrownGameTable
			table.set_process(false)
			dealer = table.get_node("Dealer") as CrownDealer
			dealer.set_process(false)
			camera.global_position = table.to_global(Vector3(1.9, 1.9, 2.8))
			camera.look_at(table.to_global(Vector3(0, 1, -.45)))
		var length := CrownDealer.CLIPS.get_animation(StringName(motion)).length
		var count := ceili(length * 12)
		for sample: int in count:
			var next := table.state.duplicate(true)
			next["dealer_animation"] = {
				"serial": frame + 1, "queue": [motion], "elapsed": sample * length / count
			}
			table.state = next
			dealer._idle_time = sample * length / count
			dealer._process(0)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var picture := get_tree().root.get_texture().get_image()
			picture.save_png("/tmp/crown-dealer-frames/frame-%04d.png" % frame)
			if sample == count / 2:
				picture.save_png(
					"res://../docs/design/previews/crown-games/dealer-" + motion + ".png"
				)
			frame += 1
	get_tree().root.size = Vector2i(1280, 720)
