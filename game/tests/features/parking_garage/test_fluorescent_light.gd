extends GutTest
## Fixture failure states (features/parking_garage/fluorescent_light.gd). Every
## peer decides its own flicker locally, so these just drive `_process()`
## directly instead of waiting out real seconds (see test_elevator_cab.gd).

const FixtureScene := preload("res://features/parking_garage/fluorescent_fixture.tscn")


func _spawn(mode: int, seed_value: int = 0) -> FluorescentLight:
	var fixture := FixtureScene.instantiate() as FluorescentLight
	fixture.mode = mode
	fixture.fixture_seed = seed_value
	add_child_autofree(fixture)
	return fixture


func test_steady_fixture_stays_at_base_energy() -> void:
	var fixture := _spawn(FluorescentLight.Mode.STEADY)
	var light := fixture.get_node("Light") as OmniLight3D
	assert_almost_eq(light.light_energy, fixture.base_energy, 0.001)


func test_dead_fixture_gives_no_light() -> void:
	var fixture := _spawn(FluorescentLight.Mode.DEAD)
	var light := fixture.get_node("Light") as OmniLight3D
	var tube := fixture.get_node("Tube") as MeshInstance3D
	assert_false(light.visible)
	assert_false(tube.visible)


func test_flicker_fixture_changes_energy_over_time() -> void:
	var fixture := _spawn(FluorescentLight.Mode.FLICKER, 5)
	var light := fixture.get_node("Light") as OmniLight3D
	var seen_on := false
	var seen_off := false
	for _i in 40:
		fixture._process(0.1)
		if light.light_energy > 0.1:
			seen_on = true
		else:
			seen_off = true
	assert_true(seen_on, "A flickering tube should be lit at least sometimes")
	assert_true(seen_off, "A flickering tube should also go dark sometimes")


func test_struggle_fixture_stays_dim() -> void:
	var fixture := _spawn(FluorescentLight.Mode.STRUGGLE, 9)
	var light := fixture.get_node("Light") as OmniLight3D
	for _i in 40:
		fixture._process(0.1)
		assert_true(light.light_energy <= fixture.base_energy * 0.5 + 0.01)
