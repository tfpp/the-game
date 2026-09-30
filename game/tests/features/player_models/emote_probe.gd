extends Node3D
## Render the actual network-driven emote overlay in either camera mode.


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
	models.emotes = {1: {"name": str(Network.args.get("emote-name", "flip_off")), "started": 0.0}}
	models.emote_clock = float(Network.args.get("emote-elapsed", "1.0"))
	var avatar := player.get_node("Body/Avatar") as BlockPlayerModel
	avatar.set_process(false)
	avatar.set_clothing("shirt:1", "pants:1")
	avatar.animate(0.1, Vector3.ZERO, true, 8)
	var camera := player.get_node("Camera") as Camera3D
	var hand: Hand
	if Network.has_flag("first-person-emote"):
		camera.global_position = Vector3(0, 0.5, 0)
		camera.rotation = Vector3.ZERO
		hand = preload("res://features/holdables/hand.tscn").instantiate()
		hand.peer_id = 1
		hand.net_item_id = "shotgun"
		add_child(hand)
		hand.set_process(false)
		hand._process(0)
	else:
		(player.get_node("Body") as Node3D).show()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 2.4
		camera.global_position = Vector3(-0.7, 0.65, -3)
		camera.look_at(Vector3(0, 0, 0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -150, 0)
	light.light_energy = 1.2
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("202b38")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b7cde2")
	environment.environment.ambient_light_energy = 0.6
	add_child(environment)
	for frame: int in 12:
		avatar.animate(0.016, Vector3.ZERO, true, 8, 0, hand != null, hand != null)
		if hand != null:
			hand._process(0)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := str(Network.args.get("avatar-capture", ""))
	if not path.is_empty():
		get_viewport().get_texture().get_image().save_png(path)
		get_tree().quit()
