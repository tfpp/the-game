extends GutTest

const Feature := preload("res://features/hotel_annex/feature.tscn")
const Lighting := preload("res://features/hotel_annex/interior_lighting.gd")

var _feature: Node3D
var _camera: Camera3D
var _outside: Environment


func before_each() -> void:
	_feature = Feature.instantiate()
	add_child_autofree(_feature)
	_feature.set_process(false)
	_camera = Camera3D.new()
	add_child_autofree(_camera)
	_outside = Environment.new()
	_outside.sky = Sky.new()
	_outside.ambient_light_color = Color(0.05, 0.07, 0.16)
	_outside.ambient_light_energy = 0.15
	_camera.environment = _outside


func test_all_wings_sewers_and_atrium_floors_have_night_fill() -> void:
	for point: Vector3 in [
		Vector3(8, 2, -1398),
		Vector3(84, 2, -1380),
		Vector3(-84, 2, -1380),
		Vector3(-18, -5, -1407),
		Vector3(8, 2, -1495),
		Vector3(8, 14, -1495)
	]:
		_camera.position = point
		_feature.update_camera(_camera)
		assert_ne(_camera.environment, _outside)
		assert_almost_eq(_camera.environment.ambient_light_energy, Lighting.AMBIENT_ENERGY, 0.001)
		assert_eq(_camera.environment.ambient_light_color, Lighting.AMBIENT_COLOR)
		assert_eq(_camera.environment.ambient_light_sky_contribution, 0.0)
	assert_almost_eq(_outside.ambient_light_energy, 0.15, 0.001, "Outdoor night remains dark")


func test_sky_tracks_day_night_and_exit_restores_previous_environment() -> void:
	_camera.position = Vector3(8, 2, -1398)
	for brightness: float in [1.0, 0.1]:
		_outside.background_energy_multiplier = brightness
		_feature.update_camera(_camera)
		assert_same(_camera.environment.sky, _outside.sky)
		assert_almost_eq(_camera.environment.background_energy_multiplier, brightness, 0.001)
	_camera.position = Vector3(2, 2, 5)
	_feature.update_camera(_camera)
	assert_same(_camera.environment, _outside)


func test_camera_switch_and_feature_removal_restore_overrides() -> void:
	_camera.position = Vector3(8, 2, -1398)
	_feature.update_camera(_camera)
	var third_person := Camera3D.new()
	add_child_autofree(third_person)
	third_person.position = _camera.position
	_feature.update_camera(third_person)
	assert_same(_camera.environment, _outside)
	assert_not_null(third_person.environment)
	_feature._exit_tree()
	assert_null(third_person.environment)


func test_losing_camera_restores_environment() -> void:
	_camera.position = Vector3(8, 2, -1398)
	_feature.update_camera(_camera)
	_feature.update_camera(null)
	assert_same(_camera.environment, _outside)


func test_default_camera_uses_world_sky_without_changing_world_environment() -> void:
	var world := _camera.get_world_3d()
	var original := world.environment
	world.environment = _outside
	_camera.environment = null
	_camera.position = Vector3(8, 2, -1398)
	_feature.update_camera(_camera)
	assert_same(_camera.environment.sky, _outside.sky)
	assert_same(world.environment, _outside)
	_camera.position = Vector3.ZERO
	_feature.update_camera(_camera)
	assert_null(_camera.environment)
	world.environment = original
