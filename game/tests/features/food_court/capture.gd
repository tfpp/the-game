extends Node
## Native seated-player review. Run with a display; writes /tmp/casino-seat-*.png.

@onready var root: Window = get_tree().root


func _ready() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var casino := (
		(load("res://features/casino_hub/casino_gridmap.tscn") as PackedScene).instantiate()
	)
	world.add_child(casino)
	var court := (
		(load("res://features/food_court/feature.tscn") as PackedScene).instantiate() as FoodCourt
	)
	world.add_child(court)
	var player := (load("res://core/player/player.tscn") as PackedScene).instantiate() as Player
	world.add_child(player)
	var models := (load("res://features/player_models/feature.tscn") as PackedScene).instantiate()
	world.add_child(models)
	models.call("_process", 0.0)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	root.size = Vector2i(960, 540)
	for spec: Array in [
		["lounge", "Furnishings/BundleFurnishings/Chair/Seat", Vector3(2.2, 1.7, 2.5)],
		["balcony", "MariachiBalcony/Stool_1/Seat", Vector3(2.5, 1.8, 2.5)],
		["cards", "Furnishings/PlayerSeat0_1", Vector3(2.5, 1.8, 2.5)]
	]:
		var anchor := casino.get_node(str(spec[1])) as Node3D
		var index: int = anchor.get("index")
		player.global_position = anchor.global_position + Vector3(0.9, 0, 0)
		player.net_position = player.global_position
		court.request_sit(index)
		court.call("_update_local_pin", 0.016)
		# The live third_person feature supplies this local body yaw.
		var body := player.get_node("Body") as Node3D
		body.visible = true
		body.rotation.y = player.yaw
		camera.global_position = anchor.global_position + (spec[2] as Vector3)
		camera.look_at(anchor.global_position + Vector3.UP * 0.5)
		for frame: int in 30:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/casino-seat-%s.png" % spec[0])
		court.request_stand()
		await get_tree().process_frame
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit()
