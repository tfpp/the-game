extends Node3D
## Native authoring review: actual car prefabs and gaze-driven boot opening.

const CAR := preload("res://features/procedural_rooms/props/car.tscn")
const WRECK := preload("res://features/parking_garage/car_wreck.tscn")
const PLAYER := preload("res://core/player/player.tscn")


func _ready() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("161c23")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("c3d1df")
	world.environment.ambient_light_energy = .65
	add_child(world)
	var lamp := DirectionalLight3D.new()
	lamp.rotation_degrees = Vector3(-55, -25, 0)
	lamp.light_energy = 1.8
	add_child(lamp)
	var camera := Camera3D.new()
	camera.position = Vector3(5, 2.6, 8)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.5
	add_child(camera)
	camera.look_at(Vector3(0, .6, 0))
	camera.current = true
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	floor_mesh.mesh = plane
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color("45494d")
	floor_mesh.material_override = concrete
	add_child(floor_mesh)
	var car := CAR.instantiate() as Node3D
	car.position.x = -2.5
	add_child(car)
	var wreck := WRECK.instantiate() as Node3D
	wreck.rotation.y = PI / 2
	wreck.position.x = 2.5
	add_child(wreck)
	var player := PLAYER.instantiate() as Player
	player.position = Vector3(-2.5, .95, 3.3)
	add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.get_node("Camera").queue_free()
	camera.current = true
	var output := ProjectSettings.globalize_path("res://../docs/design/previews/models")
	DirAccess.make_dir_recursive_absolute(output)
	player.yaw = 0
	await get_tree().create_timer(.6).timeout
	await _capture(output + "/car-boots-closed.png")
	for model: Node3D in [car, wreck]:
		player.global_position = model.global_position + Vector3(0, .95, 3.3)
		player.net_position = player.global_position
		var boot := model.get_node("Loot") as CarBoot
		var eye := (
			player.net_position
			+ Vector3.UP * (player.movement.eye_height_m() - player.movement.hull_height_m() * .5)
		)
		var ray := (boot.global_position - eye).normalized()
		player.yaw = atan2(-ray.x, -ray.z)
		player.pitch = asin(ray.y)
		await get_tree().create_timer(.6).timeout
		assert(boot.net_boot_open and not boot.net_searched)
		print(
			model.scene_file_path,
			" lid=",
			model.get_node("BootLid").rotation_degrees,
			" bounds=",
			model.get_node("BootLid").mesh.get_aabb()
		)
		boot.request_search()
		assert(boot.net_active_searchers == 1)
		# This review holds presence for both visible cars while staging the second gaze.
		boot.set_physics_process(false)
	print(
		"FINAL car lid ",
		car.get_node("BootLid").global_transform,
		" netopen ",
		car.get_node("Loot").net_boot_open
	)
	await _capture(output + "/car-boots-open.png")
	print("CAR_BOOT_NATIVE_CAPTURE PASS")
	get_tree().quit()


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(path) == OK)
