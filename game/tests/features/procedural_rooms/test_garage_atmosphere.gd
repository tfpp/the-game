extends GutTest

const Layout := preload("res://features/procedural_rooms/world_layout.gd")
const Lights := preload("res://features/procedural_rooms/garage_lights.gd")
const Atmosphere := preload("res://features/procedural_rooms/garage_atmosphere.gd")
const FEATURE := preload("res://features/procedural_rooms/prototype.tscn")


func test_tube_plan_is_seeded_and_keeps_lit_tubes_working() -> void:
	assert_eq(Lights.plan(2, 73021), Lights.plan(2, 73021))
	var dead_top := 0
	var dead_bottom := 0
	for seed_value: int in 40:
		for index: int in 5:
			var states := Lights.plan(index, seed_value)
			assert_eq(states.size(), Lights.SLOTS.size())
			for slot: int in Lights.LIT_SLOTS:
				assert_ne(states[slot], "dead", "Lit tubes keep a readable pool of light")
		dead_top += Lights.plan(4, seed_value).count("dead")
		dead_bottom += Lights.plan(0, seed_value).count("dead")
	assert_gt(dead_bottom, dead_top, "Lighting deteriorates towards B5")


func test_flicker_is_mostly_on_with_short_dips() -> void:
	var dark := 0
	for step: int in 1200:
		var level := Lights.flicker_level(step * 0.05, 0.3)
		assert_true(level in [0.06, 1.0])
		if level < 0.5:
			dark += 1
	assert_gt(dark, 0, "Tubes occasionally flicker off")
	assert_lt(dark, 240, "Tubes stay on most of the time")


func test_every_deck_hangs_tubes_under_its_ceiling_away_from_the_atrium() -> void:
	var root := Node3D.new()
	add_child(root)
	var world := Layout.build(root)
	for index: int in 5:
		var lights := world.get_node("Deck%d/Fluorescents" % index)
		assert_eq(lights.tubes.size(), Lights.SLOTS.size())
		assert_eq(lights.lights.size(), Lights.LIT_SLOTS.size())
		for tube: MeshInstance3D in lights.tubes:
			var top := tube.position.y + (tube.mesh as BoxMesh).size.y / 2
			assert_almost_eq(top, 3.47, 0.01, "Tube is flush under the 3.5 m ceiling")
			var over_atrium := absf(tube.position.x) < 10 and tube.position.z > 12
			assert_false(over_atrium and tube.position.z < 30, "No tube floats over the atrium")
		for light: OmniLight3D in lights.lights:
			assert_lte(light.omni_range, 12.0)
	root.free()


func test_deck_lights_skip_distant_floors_and_keep_nearby_decks_readable() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var lights := Lights.new()
	root.add_child(lights)
	lights.position.y = 12
	lights.build(3, 73021)
	assert_true(lights.camera_is_near(Vector3(0, 13.7, 21)))
	assert_true(lights.camera_is_near(Vector3(0, 17.7, 21)), "Adjacent floor remains lit")
	assert_false(lights.camera_is_near(Vector3(0, 5.7, 21)), "Distant floors do not need lights")
	assert_false(lights.camera_is_near(Vector3(80, 13.7, 21)), "Other districts skip flicker")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	camera.position = Vector3(80, 13.7, 21)
	lights._process(0.05)
	assert_false(lights.lights[0].visible)
	camera.position = Vector3(0, 13.7, 21)
	lights._process(0.05)
	assert_true(lights.lights[0].visible)


func test_flickering_tube_dims_its_light() -> void:
	var root := Node3D.new()
	add_child(root)
	var lights := Lights.new()
	root.add_child(lights)
	lights.build(0, 1)
	lights.states[Lights.LIT_SLOTS[0]] = "flicker"
	lights.phases[Lights.LIT_SLOTS[0]] = 0.3
	var dips := 0
	for step: int in 400:
		lights.apply_time(step * 0.05)
		if lights.lights[0].light_energy < lights.light_energy * 0.5:
			dips += 1
	assert_gt(dips, 0)
	root.free()


func test_live_garage_uses_weathered_textures_rain_and_dark_ambience() -> void:
	var feature := FEATURE.instantiate() as Node3D
	add_child(feature)
	var garage := feature.get_node("Garage") as Node3D
	for surface: String in ["Floor", "Wall", "Roof", "Grey"]:
		var mesh := garage.get_node("CrownGarage/Structure/" + surface) as MeshInstance3D
		var material := mesh.material_override as StandardMaterial3D
		assert_string_starts_with(material.resource_name, "Garage")
		assert_lte(material.albedo_texture.get_width(), 128)
	var atmosphere := garage.get_node("Atmosphere")
	var rain := atmosphere.rain as CPUParticles3D
	assert_almost_eq(rain.position, Vector3(0, 20, 21), Vector3.ONE * 0.01)
	assert_lte(rain.amount, 120, "Bound CPU simulation and transparent overdraw on mobile")
	assert_eq(rain.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_lte(rain.emission_box_extents.x, 10.0, "Rain stays inside the atrium")
	assert_lte(rain.emission_box_extents.z, 9.0)
	var camera := Camera3D.new()
	feature.add_child(camera)
	camera.global_position = garage.to_global(Vector3(0, 17.7, 5))
	atmosphere.update_camera(camera)
	assert_true(rain.emitting)
	assert_not_null(camera.environment)
	assert_true(camera.environment.fog_enabled)
	assert_almost_eq(camera.environment.ambient_light_energy, Atmosphere.AMBIENT_ENERGY, 0.001)
	camera.global_position = Vector3(12, 1.7, -13.5)
	atmosphere.update_camera(camera)
	assert_false(rain.emitting)
	assert_null(camera.environment, "Leaving the garage restores the casino environment")
	feature.free()
