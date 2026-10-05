extends Node
## Prints a light/process census and native frame times at the Crown spawn and both
## slum arrivals. Run under a display (see docs/profiling-web.md); not part of GUT.

const SAMPLE_FRAMES := 240


func _ready() -> void:
	measure.call_deferred()


func measure() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	var game := (load("res://main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(game)
	for frame: int in 30:
		await get_tree().process_frame
	var zones := get_tree().get_first_node_in_group(&"zone_instances") as ZoneInstances
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	var spawn := (get_tree().get_first_node_in_group(&"player_spawn") as Node3D).global_position
	_report("crown", game, spawn)
	await _sample("crown")
	var marker := Marker3D.new()
	game.add_child(marker)
	for destination: int in 2:
		var instance := zones.create_excursion(
			[1] as Array[int], marker, destination as SlumInstance.Destination, 73021
		)
		var arrival := instance.return_cab.car.to_global(Vector3(-.5, .95, -.4))
		player.global_position = arrival
		player.net_position = arrival
		instance.return_cab.server_arrive()
		for frame: int in 90:
			await get_tree().physics_frame
		var label := "garage" if destination == 0 else "alley"
		_report(label, instance, arrival)
		await _sample(label)
		zones.registry.leave(1)
		for frame: int in 3:
			await get_tree().process_frame
	get_tree().quit()


func _report(label: String, root: Node, point: Vector3) -> void:
	var census := SceneCensus.count(root)
	census["lights_at_view"] = SceneCensus.lights_reaching(get_tree().root, point)
	census["whole_tree"] = SceneCensus.count(get_tree().root)
	print("WEB_BUDGET_CENSUS ", label, " ", JSON.stringify(census))


func _sample(label: String) -> void:
	var times: Array[float] = []
	var last := Time.get_ticks_usec()
	for frame: int in SAMPLE_FRAMES:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
	times.sort()
	print(
		"WEB_BUDGET_FRAMES ",
		label,
		" ",
		(
			JSON
			. stringify(
				{
					"median_ms": snappedf(times[times.size() / 2], .01),
					"p95_ms": snappedf(times[int(times.size() * .95)], .01),
					"draw_calls":
					RenderingServer.get_rendering_info(
						RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
					),
					"objects":
					RenderingServer.get_rendering_info(
						RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME
					),
				}
			)
		)
	)
