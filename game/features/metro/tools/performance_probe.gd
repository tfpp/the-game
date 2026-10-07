extends Node
## Fixed-camera native rendering census, not a browser FPS benchmark.


func _ready() -> void:
	run.call_deferred()


func run() -> void:
	var scene := Node3D.new()
	get_tree().root.add_child(scene)
	var metro := (
		(load("res://features/metro/feature.tscn") as PackedScene).instantiate() as MetroService
	)
	scene.add_child(metro)
	metro.set_physics_process(false)
	metro.net_time = 5.0
	var camera := Camera3D.new()
	camera.far = 190
	scene.add_child(camera)
	camera.current = true
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_energy = 0.45
	scene.add_child(env)
	var report: Dictionary = {}
	for zone: MetroZone in [metro.stations[0], metro.rides[0]]:
		zone.load_room(60000)
		camera.position = (
			zone.position + (Vector3(8, 3.2, 58) if zone.station_index >= 0 else Vector3(0, 2.8, 8))
		)
		camera.look_at(
			(
				zone.position
				+ (Vector3(0, 2.3, 28) if zone.station_index >= 0 else Vector3(0, 2.5, -8))
			)
		)
		for frame: int in 40:
			await get_tree().process_frame
		for frame: int in 90:
			await get_tree().process_frame
		report[str(zone.name)] = {
			"draw_calls":
			RenderingServer.get_rendering_info(
				RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
			),
			"objects":
			RenderingServer.get_rendering_info(
				RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME
			),
			"primitives":
			RenderingServer.get_rendering_info(
				RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME
			),
			"content_nodes": zone._content.find_children("*", "", true, false).size(),
			"train_meshes": zone.train.find_children("*", "MeshInstance3D", true, false).size(),
		}
		zone.unload_room()
		await get_tree().process_frame
	print("METRO_BENCH " + JSON.stringify(report))
	get_tree().quit()
