extends Node
## Render private-run arrival, return and lower deck presentation.


func _ready() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var instance := SlumInstance.new()
	instance.members = [1]
	instance.enemy_plan = GarageRunPlan.enemies(73021)
	add_child(instance)
	var enemies := instance.get_node("Map/CrownGarage/Enemies")
	for enemy: Node in enemies.get_children():
		enemy.set_physics_process(false)
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	get_tree().root.size = Vector2i(960, 720)
	var output := ProjectSettings.globalize_path("res://../docs/design/previews/phase-one-garage")
	DirAccess.make_dir_recursive_absolute(output)
	var views: Array[Array] = [
		["arrival", Vector3(0, 17.65, 1.2), Vector3(0, 17.3, 9)],
		["return", Vector3(4, 17.65, 7), Vector3(0, 17.6, 0)],
		["b5", Vector3(-8, 1.65, 5), Vector3(4, 1, 10)],
		["shaft", Vector3(-13, 17.65, 20), Vector3(0, 8, 22)],
	]
	for index: int in [0, enemies.get_child_count() - 1]:
		var enemy := enemies.get_child(index) as Node3D
		var target := enemy.global_position + Vector3.UP
		var direction := Vector3(-target.x, 0, 21 - target.z).normalized()
		views.append(["enemy-%d" % index, target + direction * 5 + Vector3.UP * .65, target])
	for view: Array in views:
		camera.position = view[1]
		camera.look_at(view[2])
		for frame: int in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output.path_join(str(view[0]) + ".png"))
	get_tree().quit()
