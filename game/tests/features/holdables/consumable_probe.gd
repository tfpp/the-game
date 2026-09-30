extends Node3D
## Actual rig capture. --item=beer|cigarette --first-person --capture=/tmp/use.png


func _ready() -> void:
	var player: Player = preload("res://core/player/player.tscn").instantiate()
	player.name = "1"
	add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	var models: PlayerModels = preload("res://features/player_models/feature.tscn").instantiate()
	add_child(models)
	models.set_process(false)
	models._process(0)
	var avatar := player.get_node("Body/Avatar") as BlockPlayerModel
	avatar.set_process(false)
	avatar.set_clothing("shirt:1", "pants:1")
	avatar.set_body_type(str(Network.args.get("body", "default")))
	avatar.animate(0.1, Vector3.ZERO, true, 8)
	var camera := player.get_node("Camera") as Camera3D
	if Network.has_flag("first-person"):
		camera.position = Vector3(0, 0.5, 0)
	else:
		(player.get_node("Body") as Node3D).show()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 1.8
		camera.position = Vector3(1.7, 0.7, -2.5)
		camera.look_at(Vector3(0, 0.25, 0))
	var hand: Hand = preload("res://features/holdables/hand.tscn").instantiate()
	hand.peer_id = 1
	hand.net_item_id = str(Network.args.get("item", "beer"))
	add_child(hand)
	hand.set_process(false)
	hand.request_primary_action()
	hand.consumption.state = {"item": hand.net_item_id, "left": 1.5}
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -150, 0)
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("202b38")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b7cde2")
	environment.environment.ambient_light_energy = 0.6
	add_child(environment)
	for frame: int in 20:
		avatar.animate(0.016, Vector3.ZERO, true, 8, 0, false, true)
		hand._process(0)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		str(Network.args.get("capture", "/tmp/use.png"))
	)
	get_tree().quit()
