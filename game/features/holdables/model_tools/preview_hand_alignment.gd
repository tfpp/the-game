extends Node3D
## Actual hand/avatar rigs, with a neutral backdrop for reviewing grip alignment.

const PLAYER := preload("res://core/player/player.tscn")
const HAND := preload("res://features/holdables/hand.tscn")


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var folder := args[0] if not args.is_empty() else "res://../docs/design/previews/hand-alignment"
	var output := ProjectSettings.globalize_path(folder)
	DirAccess.make_dir_recursive_absolute(output)
	get_window().size = Vector2i(1000, 720)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("34414b")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = .7
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -25, 0)
	add_child(light)
	var player := PLAYER.instantiate() as Player
	player.name = "1"
	add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	var body := player.get_node("Body") as Node3D
	var avatar := BlockPlayerModel.new()
	avatar.name = "Avatar"
	body.add_child(avatar)
	for child: Node in body.get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).hide()
	avatar.set_process(false)
	var camera := player.get_node("Camera") as Camera3D
	camera.position = Vector3(0, .65, 0)
	camera.current = true
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	add_child(hand)
	hand.set_process(false)
	for suffix: String in ["R", "L"]:
		var human := hand._arms.human
		var bone := human.skeleton.find_bone("Hand" + suffix)
		print("Hand", suffix, " rest: ", human.skeleton.get_bone_global_rest(bone))
	for id: String in ["pistol", "smg", "m4a4", "ak47", "shotgun", "awp"]:
		body.hide()
		camera.current = true
		hand.net_item_id = id
		hand._process(0.0)
		await _save(output, id + "-first-person")
		var view := hand.held_view()
		var animation := view.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if animation:
			view.set_process(false)
			animation.play("reload")
			animation.pause()
			for phase: float in [.5, 1.0, 1.5]:
				animation.seek(phase, true)
				var support := view.get_node("SupportGrip") as Node3D
				support.transform = (
					(view.get_node("Pose") as Node3D).transform
					* (view.get_node("Pose/SupportGrip") as Node3D).transform
				)
				hand._pose_arms(player)
				await _save(output, id + "-reload-" + str(phase))
			animation.play("RESET")
			animation.advance(0.0)
			animation.stop()
			(view.get_node("SupportGrip") as Node3D).transform = (
				(view.get_node("Pose") as Node3D).transform
				* (view.get_node("Pose/SupportGrip") as Node3D).transform
			)
		body.show()
		hand._process(0.0)
		var outside := Camera3D.new()
		add_child(outside)
		outside.position = Vector3(.8, .65, -1.2)
		outside.look_at(Vector3(0, .24, -.25))
		outside.current = true
		await _save(output, id + "-world")
		outside.queue_free()
	for child: Node in get_children():
		child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()


func _save(folder: String, title: String) -> void:
	for frame: int in 5:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(folder.path_join(title + ".png"))
