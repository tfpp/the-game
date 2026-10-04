extends Node


func _ready() -> void:
	capture.call_deferred()


func capture() -> void:
	get_tree().root.size = Vector2i(960, 720)
	var game := (load("res://main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(game)
	for frame: int in 8:
		await get_tree().process_frame
	for layer: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).hide()
	var camera := Camera3D.new()
	game.add_child(camera)
	camera.current = true
	var zones := get_tree().get_first_node_in_group(&"zone_instances") as ZoneInstances
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	player.set_physics_process(false)
	var marker := Marker3D.new()
	game.add_child(marker)
	var output := ProjectSettings.globalize_path(
		"res://../docs/design/previews/phase-one-live-slums"
	)
	DirAccess.make_dir_recursive_absolute(output)
	for destination: int in 2:
		var instance := zones.create_excursion(
			[1] as Array[int], marker, destination as SlumInstance.Destination, 73021
		)
		if destination == 0:
			_print_mesh_inventory(instance.get_node("Map/CrownGarage"))
			for enemy: Node in instance.get_node("Map/CrownGarage/Enemies").get_children():
				enemy.set_physics_process(false)
		player.global_position = instance.return_cab.car.to_global(Vector3(-.5, .95, -.4))
		player.net_position = player.global_position
		instance.return_cab.server_arrive()
		for frame: int in 90:
			await get_tree().physics_frame
		var cab := instance.return_cab
		camera.global_position = cab.car.to_global(Vector3(-.5, 1.65, -.4))
		camera.look_at(cab.car.to_global(Vector3(-.5, 1.65, 8)))
		for frame: int in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_tree().root.get_texture().get_image().save_png(
			output.path_join("arrival-%d.png" % destination)
		)
		camera.global_position = cab.car.to_global(Vector3(4, 1.65, 8))
		camera.look_at(cab.car.to_global(Vector3(0, 2, 0)))
		for frame: int in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_tree().root.get_texture().get_image().save_png(
			output.path_join("return-%d.png" % destination)
		)
		if destination == 0:
			for index: int in 5:
				var wet_center := instance.global_position + Vector3(7, index * 4, 8)
				camera.global_position = wet_center + Vector3(3, 1.65, 3)
				camera.look_at(wet_center)
				for frame: int in 10:
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				get_tree().root.get_texture().get_image().save_png(
					output.path_join("water-B%d.png" % (5 - index))
				)
			for index: int in range(1, 5):
				var x := -13.0 if index % 2 == 0 else 13.0
				var center := instance.global_position + Vector3(x, index * 4, 21)
				camera.global_position = center + Vector3(4, 2.6, -4)
				camera.look_at(center - Vector3.UP * .5)
				for frame: int in 10:
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				get_tree().root.get_texture().get_image().save_png(
					output.path_join("shortcut-B%d.png" % (5 - index))
				)
			for tier: int in [GarageEnemyTiers.Tier.LURKER, GarageEnemyTiers.Tier.GUNMAN]:
				for node: Node in instance.get_node("Map/CrownGarage/Enemies").get_children():
					var enemy := node as GarageEnemy
					if enemy.tier != tier:
						continue
					for distance: float in [5.0, 12.0]:
						var direction := -1.0 if enemy.position.z > 20.0 else 1.0
						camera.global_position = (
							enemy.global_position + Vector3(0, 1.65, direction * distance)
						)
						camera.look_at(enemy.global_position + Vector3.UP)
						for frame: int in 10:
							await get_tree().process_frame
						await RenderingServer.frame_post_draw
						get_tree().root.get_texture().get_image().save_png(
							output.path_join("enemy-%d-%dm.png" % [tier, int(distance)])
						)
					break
		zones.registry.leave(1)
		await get_tree().process_frame
		await get_tree().process_frame
	get_tree().quit()


func _print_mesh_inventory(world: Node) -> void:
	var groups: Dictionary[String, int] = {}
	for node: Node in world.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var path := String(world.get_path_to(mesh))
		var group := path.get_slice("/", 0)
		groups[group] = groups.get(group, 0) + mesh.mesh.get_surface_count()
	print("GARAGE_MESH_SURFACES ", JSON.stringify(groups))
