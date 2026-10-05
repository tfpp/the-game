extends GutTest
## Pin the web-client light budget for the Crown and both private slums, and the
## census rules used to measure it (docs/profiling-web.md).

const MAIN := preload("res://main.tscn")
## Garage tubes can flicker off; the ceiling counts every tube as lit.
const SLUM_LIGHT_LIMITS: Array[int] = [18, 8]


func test_census_counts_visible_lights_shadows_and_processing() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var omni := OmniLight3D.new()
	omni.shadow_enabled = true
	omni.omni_range = 12.0
	root.add_child(omni)
	var spot := SpotLight3D.new()
	spot.spot_range = 2.0
	spot.position = Vector3(10, 0, 0)
	root.add_child(spot)
	var hidden := OmniLight3D.new()
	hidden.visible = false
	root.add_child(hidden)
	root.add_child(MeshInstance3D.new())
	var census := SceneCensus.count(root)
	assert_eq(census["lights"], 2)
	assert_eq(census["shadowed_lights"], 1)
	assert_eq(census["omni"], 1)
	assert_eq(census["spot"], 1)
	assert_eq(census["meshes"], 1)
	assert_eq(SceneCensus.lights_reaching(root, Vector3(-1, 0, 0)), 1)
	assert_eq(SceneCensus.lights_reaching(root, Vector3(9, 0, 0)), 2)


func test_crown_and_slum_instances_stay_within_light_budget() -> void:
	var game := MAIN.instantiate()
	add_child_autofree(game)
	await wait_process_frames(4)
	var crown := SceneCensus.count(game)
	gut.p("crown census %s" % crown)
	assert_lte(crown["shadowed_lights"], 2, "Crown shadowed lights")
	assert_lte(crown["lights"], 40, "Crown dynamic lights")
	var zones := get_tree().get_first_node_in_group(&"zone_instances") as ZoneInstances
	var marker := Marker3D.new()
	game.add_child(marker)
	for destination: int in 2:
		var instance := zones.create_excursion(
			[1] as Array[int], marker, destination as SlumInstance.Destination, 73021
		)
		await wait_process_frames(2)
		var slum := SceneCensus.count(instance)
		gut.p("slum %d census %s" % [destination, slum])
		assert_eq(slum["shadowed_lights"], 0, "slum %d shadowed lights" % destination)
		assert_lte(
			slum["lights"], SLUM_LIGHT_LIMITS[destination], "slum %d dynamic lights" % destination
		)
		assert_eq(slum["directional"], 0, "slum %d directional lights" % destination)
		zones.registry.leave(1)
		await wait_process_frames(2)
